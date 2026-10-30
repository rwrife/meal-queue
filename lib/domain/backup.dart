import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// JSON-only backup. Photos are deliberately excluded; restored recipes have
/// no photo path. Database replacement is one transaction, never partial.
class MealBackup {
  MealBackup(this.db);
  final Database db;

  static const maxBytes = 8 * 1024 * 1024;
  static const maxRows = 10000;
  static const tables = [
    'recipes',
    'ingredients',
    'recipe_tags',
    'planned_meals',
    'stock_lots',
    'shopping_snapshots',
    'shopping_lines',
    'aisle_orders',
    'cook_events',
  ];

  Future<String> exportJson() async {
    final data = await db.transaction(
      (txn) async => {
        for (final table in tables)
          table: [
            for (final row in await txn.query(table))
              {...row, if (table == 'recipes') 'photo_path': null},
          ],
      },
    );
    final json = jsonEncode({
      'format': 'meal-queue',
      'version': 1,
      'photos': 'excluded',
      'tables': data,
    });
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('Backup exceeds 8 MiB limit');
    }
    return json;
  }

  Future<void> importJson(String json) async {
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('Backup exceeds 8 MiB limit');
    }
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 4 ||
        decoded['format'] != 'meal-queue' ||
        decoded['version'] != 1 ||
        decoded['photos'] != 'excluded' ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported backup format');
    }
    final data = decoded['tables'] as Map<String, dynamic>;
    if (data.length != tables.length ||
        !data.keys.toSet().containsAll(tables)) {
      throw const FormatException('Invalid backup tables');
    }
    final columns = <String, Set<String>>{};
    final required = <String, Set<String>>{};
    for (final table in tables) {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      columns[table] = {for (final col in info) col['name'] as String};
      required[table] = {
        for (final col in info)
          if (col['notnull'] == 1 || col['pk'] == 1) col['name'] as String,
      };
    }
    var count = 0;
    for (final table in tables) {
      final rows = data[table];
      if (rows is! List) throw const FormatException('Invalid backup rows');
      count += rows.length;
      if (count > maxRows) throw const FormatException('Too many backup rows');
      for (final row in rows) {
        if (row is! Map<String, dynamic> ||
            row.isEmpty ||
            !columns[table]!.containsAll(row.keys) ||
            !row.keys.toSet().containsAll(required[table]!) ||
            row.values.any(
              (value) => value != null && value is! String && value is! int,
            ) ||
            (table == 'recipes' && row['photo_path'] != null)) {
          // Refuse paths rather than trusting an archive's claims about photos.
          throw const FormatException('Invalid backup row or photo path');
        }
      }
    }
    await db.transaction((txn) async {
      for (final table in tables.reversed) {
        await txn.delete(table);
      }
      for (final table in tables) {
        for (final raw in data[table] as List) {
          await txn.insert(table, Map<String, Object?>.from(raw as Map));
        }
      }
    });
  }
}
