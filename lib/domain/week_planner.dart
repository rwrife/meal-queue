import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import 'meal.dart';
import 'recipe_repository.dart';

const mealSlots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

DateTime weekStart(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class CookEvent {
  const CookEvent({
    required this.id,
    required this.date,
    required this.slot,
    required this.recipeTitle,
    required this.cookedAt,
    this.recipeId,
  });
  final String id;
  final DateTime date;
  final String slot;
  final String? recipeId;
  final String recipeTitle;
  final DateTime cookedAt;
}

/// Single-slot writes, copy and cook history use SQLite transactions.
class WeekPlanner {
  WeekPlanner(this.recipes);
  final RecipeRepository recipes;
  Database get db => recipes.db;
  static const _ids = Uuid();

  Future<List<PlannedMeal>> week(DateTime monday) async {
    final start = weekStart(monday);
    final end = start.add(const Duration(days: 6));
    final rows = await db.query(
      'planned_meals',
      where: 'plan_date BETWEEN ? AND ?',
      whereArgs: [dayKey(start), dayKey(end)],
      orderBy: 'plan_date, slot',
    );
    return rows
        .map(
          (row) => PlannedMeal(
            date: DateTime.parse(row['plan_date'] as String),
            slot: row['slot'] as String,
            kind: MealKind.values.byName(row['kind'] as String),
            recipeId: row['recipe_id'] as String?,
            servings: row['servings'] as int?,
          ),
        )
        .toList();
  }

  Future<void> assign(PlannedMeal meal) async {
    if (!mealSlots.contains(meal.slot)) {
      throw ArgumentError.value(meal.slot, 'slot');
    }
    if (meal.kind == MealKind.recipe &&
        await recipes.get(meal.recipeId!) == null) {
      throw StateError('Recipe no longer exists');
    }
    await db.insert('planned_meals', {
      'id': _ids.v4(),
      'plan_date': dayKey(meal.date),
      'slot': meal.slot,
      'kind': meal.kind.name,
      'recipe_id': meal.recipeId,
      'servings': meal.servings,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clear(DateTime date, String slot) async {
    await db.delete(
      'planned_meals',
      where: 'plan_date = ? AND slot = ?',
      whereArgs: [dayKey(date), slot],
    );
  }

  Future<void> copyLastWeek(DateTime monday) async {
    final start = weekStart(monday);
    final prior = await week(start.subtract(const Duration(days: 7)));
    await db.transaction((txn) async {
      for (final meal in prior) {
        // Missing/deleted recipes become empty slots, not misleading leftovers.
        if (meal.kind == MealKind.recipe && meal.recipeId == null) continue;
        await txn.insert('planned_meals', {
          'id': _ids.v4(),
          'plan_date': dayKey(meal.date.add(const Duration(days: 7))),
          'slot': meal.slot,
          'kind': meal.kind.name,
          'recipe_id': meal.recipeId,
          'servings': meal.servings,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<CookEvent> markCooked(DateTime date, String slot) async {
    final rows = await db.query(
      'planned_meals',
      where: 'plan_date = ? AND slot = ?',
      whereArgs: [dayKey(date), slot],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first['kind'] != MealKind.recipe.name ||
        rows.first['recipe_id'] == null) {
      throw StateError('No recipe in slot');
    }
    final id = rows.first['recipe_id'] as String;
    final recipe = await recipes.get(id);
    if (recipe == null) throw StateError('Recipe no longer exists');
    final event = CookEvent(
      id: _ids.v4(),
      date: date,
      slot: slot,
      recipeId: id,
      recipeTitle: recipe.title,
      cookedAt: DateTime.now(),
    );
    await db.insert('cook_events', {
      'id': event.id,
      'plan_date': dayKey(date),
      'slot': slot,
      'recipe_id': id,
      'recipe_title': recipe.title,
      'cooked_at': event.cookedAt.millisecondsSinceEpoch,
    });
    return event;
  }

  Future<void> undoCooked(String eventId) => db
      .delete('cook_events', where: 'id = ?', whereArgs: [eventId])
      .then((_) {});

  Future<List<CookEvent>> history({String? recipeId}) async {
    final rows = await db.query(
      'cook_events',
      where: recipeId == null ? null : 'recipe_id = ?',
      whereArgs: recipeId == null ? null : [recipeId],
      orderBy: 'cooked_at DESC, rowid DESC',
    );
    return [
      for (final row in rows)
        CookEvent(
          id: row['id'] as String,
          date: DateTime.parse(row['plan_date'] as String),
          slot: row['slot'] as String,
          recipeId: row['recipe_id'] as String?,
          recipeTitle: row['recipe_title'] as String,
          cookedAt: DateTime.fromMillisecondsSinceEpoch(
            row['cooked_at'] as int,
          ),
        ),
    ];
  }

  Future<List<DateTime>> archivedWeeks(DateTime currentWeek) async {
    final rows = await db.query(
      'planned_meals',
      columns: ['plan_date'],
      where: 'plan_date < ?',
      whereArgs: [dayKey(weekStart(currentWeek))],
      distinct: true,
      orderBy: 'plan_date DESC',
    );
    final keys = <String, DateTime>{};
    for (final row in rows) {
      final start = weekStart(DateTime.parse(row['plan_date'] as String));
      keys[dayKey(start)] = start;
    }
    return keys.values.toList()..sort((a, b) => b.compareTo(a));
  }
}
