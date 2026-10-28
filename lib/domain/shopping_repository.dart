import 'package:sqflite/sqflite.dart' show Database;
import 'package:uuid/uuid.dart';

import 'meal.dart';
import 'rational.dart';
import 'recipe_repository.dart';
import 'unit.dart';
import 'week_planner.dart';

class SavedLine {
  const SavedLine({
    required this.id,
    required this.item,
    required this.quantity,
    required this.unit,
    required this.aisle,
    required this.checked,
    required this.manual,
    required this.stockHint,
  });
  final String id, item, aisle;
  final Rational? quantity;
  final Unit unit;
  final bool checked, manual, stockHint;
}

class SavedList {
  const SavedList({
    required this.id,
    required this.label,
    required this.lines,
    required this.completedAt,
  });
  final String id, label;
  final List<SavedLine> lines;
  final DateTime? completedAt;
  int get checkedCount => lines.where((line) => line.checked).length;
}

/// Snapshots remain independent of recipe edits; stock hints are advisory.
class ShoppingRepository {
  ShoppingRepository(this.recipes);
  final RecipeRepository recipes;
  Database get db => recipes.db;
  static const _ids = Uuid();

  Future<SavedList> generate(DateTime monday) async {
    // One active trip at a time; repeated taps must not fork a frozen list.
    final existing = await active();
    if (existing != null) return existing;
    final meals = await WeekPlanner(recipes).week(monday);
    final ingredients = <Ingredient>[];
    for (final meal in meals) {
      if (meal.kind != MealKind.recipe || meal.recipeId == null) continue;
      final recipe = await recipes.get(meal.recipeId!);
      if (recipe != null) {
        ingredients.addAll(
          scaleRecipe(recipe, meal.servings ?? recipe.servings),
        );
      }
    }
    final merged = mergeIngredients(ingredients);
    final id = _ids.v4();
    await db.transaction((txn) async {
      await txn.insert('shopping_snapshots', {
        'id': id,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'label': 'Week of ${dayKey(weekStart(monday))}',
      });
      for (var i = 0; i < merged.length; i++) {
        final line = merged[i];
        await txn.insert('shopping_lines', {
          'id': _ids.v4(),
          'snapshot_id': id,
          'item': line.item,
          'quantity_num': line.quantity?.numerator,
          'quantity_den': line.quantity?.denominator,
          'unit_symbol': line.unit.symbol,
          'aisle': line.aisle,
          'sort_order': i,
        });
      }
    });
    return (await get(id))!;
  }

  Future<SavedList?> active() async {
    final rows = await db.query(
      'shopping_snapshots',
      where: 'completed_at IS NULL',
      orderBy: 'created_at DESC, rowid DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : get(rows.first['id'] as String);
  }

  Future<List<SavedList>> history() async {
    final rows = await db.query(
      'shopping_snapshots',
      where: 'completed_at IS NOT NULL',
      orderBy: 'completed_at DESC, rowid DESC',
    );
    return [for (final row in rows) (await get(row['id'] as String))!];
  }

  Future<SavedList?> get(String id) async {
    final rows = await db.query(
      'shopping_snapshots',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final orders = await db.query('aisle_orders', orderBy: 'sort_order, aisle');
    final ranks = {
      for (var i = 0; i < orders.length; i++)
        (orders[i]['aisle'] as String).toLowerCase(): i,
    };
    final stock = await recipes.stock.list();
    final raw = await db.query(
      'shopping_lines',
      where: 'snapshot_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order, rowid',
    );
    final lines = [
      for (final row in raw)
        SavedLine(
          id: row['id'] as String,
          item: row['item'] as String,
          quantity: row['quantity_num'] == null
              ? null
              : Rational(
                  row['quantity_num'] as int,
                  row['quantity_den'] as int,
                ),
          unit: Unit.parse(row['unit_symbol'] as String),
          aisle: row['aisle'] as String,
          checked: row['is_checked'] == 1,
          manual: row['is_manual'] == 1,
          stockHint: mayHaveIngredient(
            Ingredient(
              item: row['item'] as String,
              quantity: null,
              unit: Unit.parse(row['unit_symbol'] as String),
            ),
            stock,
          ),
        ),
    ];
    lines.sort((a, b) {
      final ar = ranks[a.aisle.toLowerCase()],
          br = ranks[b.aisle.toLowerCase()];
      final byRank = (ar ?? 0x7fffffff).compareTo(br ?? 0x7fffffff);
      if (byRank != 0) return byRank;
      final byAisle = a.aisle.toLowerCase().compareTo(b.aisle.toLowerCase());
      if (byAisle != 0) return byAisle;
      return raw
          .indexWhere((r) => r['id'] == a.id)
          .compareTo(raw.indexWhere((r) => r['id'] == b.id));
    });
    final snapshot = rows.first;
    return SavedList(
      id: id,
      label: snapshot['label'] as String,
      lines: lines,
      completedAt: snapshot['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              snapshot['completed_at'] as int,
            ),
    );
  }

  Future<void> setAisleOrder(List<String> aisles) async {
    if (aisles.map((s) => s.trim().toLowerCase()).toSet().length !=
            aisles.length ||
        aisles.any((s) => s.trim().isEmpty)) {
      throw ArgumentError('duplicate or blank aisle');
    }
    await db.transaction((txn) async {
      await txn.delete('aisle_orders');
      for (var i = 0; i < aisles.length; i++) {
        await txn.insert('aisle_orders', {
          'aisle': aisles[i].trim().toLowerCase(),
          'sort_order': i,
        });
      }
    });
  }

  Future<void> check(String snapshotId, String lineId, bool checked) async {
    await _editable(snapshotId);
    final count = await db.update(
      'shopping_lines',
      {'is_checked': checked ? 1 : 0},
      where: 'snapshot_id = ? AND id = ?',
      whereArgs: [snapshotId, lineId],
    );
    if (count != 1) throw StateError('Line not found');
  }

  Future<void> saveManual(
    String snapshotId, {
    String? lineId,
    required String item,
    Rational? quantity,
    required Unit unit,
    String aisle = '',
  }) async {
    await _editable(snapshotId);
    final ingredient = Ingredient(
      item: item,
      quantity: quantity,
      unit: unit,
      aisle: aisle,
    );
    if (lineId == null) {
      await db.insert('shopping_lines', {
        'id': _ids.v4(),
        'snapshot_id': snapshotId,
        'item': ingredient.item,
        'quantity_num': quantity?.numerator,
        'quantity_den': quantity?.denominator,
        'unit_symbol': unit.symbol,
        'aisle': aisle.trim(),
        'is_manual': 1,
        'sort_order': 0x7fffffff,
      });
    } else {
      final count = await db.update(
        'shopping_lines',
        {
          'item': ingredient.item,
          'quantity_num': quantity?.numerator,
          'quantity_den': quantity?.denominator,
          'unit_symbol': unit.symbol,
          'aisle': aisle.trim(),
          'is_manual': 1,
        },
        where: 'snapshot_id = ? AND id = ? AND is_manual = 1',
        whereArgs: [snapshotId, lineId],
      );
      if (count != 1) throw StateError('Manual line not found');
    }
  }

  Future<void> removeManual(String snapshotId, String lineId) async {
    await _editable(snapshotId);
    final count = await db.delete(
      'shopping_lines',
      where: 'snapshot_id = ? AND id = ? AND is_manual = 1',
      whereArgs: [snapshotId, lineId],
    );
    if (count != 1) throw StateError('Manual line not found');
  }

  Future<void> complete(String id) async {
    final count = await db.update(
      'shopping_snapshots',
      {'completed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND completed_at IS NULL',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Active list not found');
  }

  Future<void> _editable(String id) async {
    final rows = await db.query(
      'shopping_snapshots',
      columns: ['id'],
      where: 'id = ? AND completed_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Active list not found');
  }
}
