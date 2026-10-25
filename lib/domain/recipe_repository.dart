import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'database_schema.dart';
import 'meal.dart';
import 'rational.dart';
import 'unit.dart';

/// On-device recipes. Caller owns DB lifecycle; photos live under [root]/photos.
class RecipeRepository {
  RecipeRepository(this.db, this.root);

  final Database db;
  final Directory root;
  static const _ids = Uuid();

  static Future<RecipeRepository> open() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }
    final db = await factory.openDatabase(
      p.join(root.path, 'meal_queue.db'),
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
        onUpgrade: AppDatabaseSchema.onUpgrade,
      ),
    );
    final repository = RecipeRepository(db, root);
    await repository.cleanOrphanPhotos();
    return repository;
  }

  Future<void> close() => db.close();

  /// Import only into app-owned storage. Never persist external absolute paths.
  Future<String> importPhoto(File source) async {
    final ext = p.extension(source.path).toLowerCase();
    if (!{'.png', '.jpg', '.jpeg', '.webp'}.contains(ext)) {
      throw ArgumentError.value(ext, 'photo extension', 'unsupported image');
    }
    final photos = Directory(p.join(root.path, 'photos'));
    await photos.create(recursive: true);
    final name = '${_ids.v4()}$ext';
    final relative = p.posix.join('photos', name);
    await source.copy(p.join(root.path, 'photos', name));
    return relative;
  }

  File? photoFile(Recipe recipe) => photoFileFor(recipe.photoPath);

  File? photoFileFor(String? relative) {
    if (relative == null) return null;
    // Persist POSIX separators on every OS; reject traversal and drive paths.
    final parts = p.posix.split(relative);
    if (p.posix.isAbsolute(relative) ||
        p.windows.isAbsolute(relative) ||
        relative.contains('\\') ||
        p.posix.normalize(relative) != relative ||
        parts.length != 2 ||
        parts.first != 'photos' ||
        parts.last == '.' ||
        parts.last == '..') {
      throw FormatException('invalid stored photo path', relative);
    }
    return File(p.join(root.path, 'photos', parts.last));
  }

  Future<void> _cleanPhoto(String? relative) async {
    if (relative == null) return;
    final file = photoFileFor(relative);
    if (file != null && await file.exists()) await file.delete();
  }

  /// Save recipe and children atomically. Old photo removed only after commit.
  /// Supplied [photoPath] must have been imported with [importPhoto].
  Future<void> save(Recipe recipe) async {
    if (recipe.photoPath != null) photoFileFor(recipe.photoPath);
    final previous = await db.query(
      'recipes',
      columns: ['photo_path', 'created_at'],
      where: 'id = ?',
      whereArgs: [recipe.id],
      limit: 1,
    );
    final oldPhoto = previous.isEmpty
        ? null
        : previous.first['photo_path'] as String?;
    final createdAt = previous.isEmpty
        ? DateTime.now().millisecondsSinceEpoch
        : previous.first['created_at'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final values = {
        'title': recipe.title.trim(),
        'servings': recipe.servings,
        'steps': recipe.steps,
        'photo_path': recipe.photoPath,
        'updated_at': now,
      };
      if (previous.isEmpty) {
        await txn.insert('recipes', {
          'id': recipe.id,
          'created_at': createdAt,
          ...values,
        });
      } else {
        // UPDATE keeps plan references; INSERT OR REPLACE would delete them.
        await txn.update(
          'recipes',
          values,
          where: 'id = ?',
          whereArgs: [recipe.id],
        );
      }
      await txn.delete(
        'ingredients',
        where: 'recipe_id = ?',
        whereArgs: [recipe.id],
      );
      await txn.delete(
        'recipe_tags',
        where: 'recipe_id = ?',
        whereArgs: [recipe.id],
      );
      for (var i = 0; i < recipe.ingredients.length; i++) {
        final line = recipe.ingredients[i];
        await txn.insert('ingredients', {
          'id': _ids.v4(),
          'recipe_id': recipe.id,
          'item': line.item,
          'quantity_num': line.quantity?.numerator,
          'quantity_den': line.quantity?.denominator,
          'unit_symbol': line.unit.symbol,
          'aisle': line.aisle,
          'sort_order': i,
        });
      }
      for (final tag
          in recipe.tags
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()) {
        await txn.insert('recipe_tags', {'recipe_id': recipe.id, 'tag': tag});
      }
    });
    if (oldPhoto != recipe.photoPath) await _cleanPhoto(oldPhoto);
  }

  Future<Recipe?> get(String id) async {
    final rows = await db.query(
      'recipes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first;
    final ingredients = await db.query(
      'ingredients',
      where: 'recipe_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC',
    );
    final tags = await db.query(
      'recipe_tags',
      where: 'recipe_id = ?',
      whereArgs: [id],
      orderBy: 'tag COLLATE NOCASE',
    );
    return Recipe(
      id: id,
      title: raw['title'] as String,
      servings: raw['servings'] as int,
      steps: raw['steps'] as String,
      photoPath: raw['photo_path'] as String?,
      tags: [for (final row in tags) row['tag'] as String],
      ingredients: [
        for (final row in ingredients)
          Ingredient(
            item: row['item'] as String,
            quantity: row['quantity_num'] == null
                ? null
                : Rational(
                    row['quantity_num'] as int,
                    row['quantity_den'] as int,
                  ),
            unit: Unit.parse(row['unit_symbol'] as String),
            aisle: row['aisle'] as String,
          ),
      ],
    );
  }

  Future<List<Recipe>> list({String query = '', String? tag}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add(
        '(LOWER(title) LIKE ? ESCAPE \'\\\' OR LOWER(steps) LIKE ? ESCAPE \'\\\')',
      );
      final q = query
          .trim()
          .toLowerCase()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      args.addAll(['%$q%', '%$q%']);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('id IN (SELECT recipe_id FROM recipe_tags WHERE tag = ?)');
      args.add(tag);
    }
    final rows = await db.query(
      'recipes',
      columns: ['id'],
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return [for (final row in rows) (await get(row['id'] as String))!];
  }

  Future<List<String>> tags() async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT tag FROM recipe_tags ORDER BY tag COLLATE NOCASE',
    );
    return [for (final row in rows) row['tag'] as String];
  }

  Future<void> delete(String id) async {
    final recipe = await get(id);
    if (recipe == null) return;
    await db.delete('recipes', where: 'id = ?', whereArgs: [id]);
    await _cleanPhoto(recipe.photoPath);
  }

  /// Repair stray imported files after interrupted saves/deletes.
  Future<int> cleanOrphanPhotos() async {
    final dir = Directory(p.join(root.path, 'photos'));
    if (!await dir.exists()) return 0;
    final rows = await db.query('recipes', columns: ['photo_path']);
    final referenced = {for (final row in rows) row['photo_path'] as String?};
    var removed = 0;
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      if (!referenced.contains(
        p.posix.join(
          'photos',
          p.posix.basename(entry.path.replaceAll('\\', '/')),
        ),
      )) {
        await entry.delete();
        removed++;
      }
    }
    return removed;
  }
}
