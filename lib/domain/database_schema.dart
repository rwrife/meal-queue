import 'package:sqflite/sqflite.dart' show Database;

/// Database schema contract and migration logic.
///
/// Version 1:
/// - recipe (id, title, servings, steps, photo_path, created_at, updated_at)
/// - ingredient (id, recipe_id, item, quantity_num, quantity_den, unit_symbol, aisle, sort_order)
/// - recipe_tag (recipe_id, tag)
/// - planned_meal stub (id, plan_date, slot, kind, recipe_id, servings)
/// - stock_lot stub (id, item, quantity_num, quantity_den, unit_symbol, location, best_by_date)
/// - shopping_line stub (id, snapshot_id, item, quantity_num, quantity_den, unit_symbol, aisle, is_checked, sort_order)
/// - shopping_snapshot stub (id, created_at, label)
class AppDatabaseSchema {
  static const int currentVersion = 1;

  static Future<void> createSchema(Database db) async {
    final batch = db.batch();

    // Core recipe tables
    batch.execute('''
      CREATE TABLE recipes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        servings INTEGER NOT NULL CHECK (servings > 0),
        steps TEXT NOT NULL DEFAULT '',
        photo_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE ingredients (
        id TEXT PRIMARY KEY,
        recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        item TEXT NOT NULL,
        quantity_num INTEGER,
        quantity_den INTEGER,
        unit_symbol TEXT NOT NULL DEFAULT '',
        aisle TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');
    batch.execute(
      'CREATE INDEX idx_ingredients_recipe ON ingredients(recipe_id, sort_order);',
    );

    batch.execute('''
      CREATE TABLE recipe_tags (
        recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        tag TEXT NOT NULL,
        PRIMARY KEY (recipe_id, tag)
      );
    ''');
    batch.execute('CREATE INDEX idx_recipe_tags_tag ON recipe_tags(tag);');

    // Future-feature stubs required by Issue #3 acceptance criteria
    batch.execute('''
      CREATE TABLE planned_meals (
        id TEXT PRIMARY KEY,
        plan_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        kind TEXT NOT NULL,
        recipe_id TEXT REFERENCES recipes(id) ON DELETE SET NULL,
        servings INTEGER
      );
    ''');

    batch.execute('''
      CREATE TABLE stock_lots (
        id TEXT PRIMARY KEY,
        item TEXT NOT NULL,
        quantity_num INTEGER NOT NULL,
        quantity_den INTEGER NOT NULL,
        unit_symbol TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL,
        best_by_date TEXT
      );
    ''');

    batch.execute('''
      CREATE TABLE shopping_snapshots (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        label TEXT NOT NULL DEFAULT ''
      );
    ''');

    batch.execute('''
      CREATE TABLE shopping_lines (
        id TEXT PRIMARY KEY,
        snapshot_id TEXT NOT NULL REFERENCES shopping_snapshots(id) ON DELETE CASCADE,
        item TEXT NOT NULL,
        quantity_num INTEGER,
        quantity_den INTEGER,
        unit_symbol TEXT NOT NULL DEFAULT '',
        aisle TEXT NOT NULL DEFAULT '',
        is_checked INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await batch.commit(noResult: true);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Migration scaffolding: handle schema versions as app evolves.
    // When schema reaches v2, migrations from v1 -> v2 go here.
    if (oldVersion < 1) {
      await createSchema(db);
    }
  }
}
