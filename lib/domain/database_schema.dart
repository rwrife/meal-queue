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
/// Version 2: cooked events and unique day/slot constraint.
/// Version 3: frozen list metadata, manual lines and user aisle ordering.
class AppDatabaseSchema {
  static const int currentVersion = 3;

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
        label TEXT NOT NULL DEFAULT '',
        completed_at INTEGER
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
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_manual INTEGER NOT NULL DEFAULT 0
      );
    ''');

    batch.execute('''
      CREATE TABLE aisle_orders (
        aisle TEXT PRIMARY KEY,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');

    batch.execute(
      'CREATE UNIQUE INDEX idx_plan_slot ON planned_meals(plan_date, slot);',
    );
    batch.execute('''
      CREATE TABLE cook_events (
        id TEXT PRIMARY KEY,
        plan_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        recipe_id TEXT,
        recipe_title TEXT NOT NULL,
        cooked_at INTEGER NOT NULL
      );
    ''');
    await batch.commit(noResult: true);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await createSchema(db);
    } else if (oldVersion < 2) {
      // Existing v1 has no slot uniqueness; preserve newest row per slot.
      await db.execute('''
        DELETE FROM planned_meals WHERE rowid NOT IN
        (SELECT MAX(rowid) FROM planned_meals GROUP BY plan_date, slot)
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_plan_slot ON planned_meals(plan_date, slot)',
      );
      await db.execute('''
        CREATE TABLE cook_events (
          id TEXT PRIMARY KEY,
          plan_date TEXT NOT NULL,
          slot TEXT NOT NULL,
          recipe_id TEXT,
          recipe_title TEXT NOT NULL,
          cooked_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE shopping_snapshots ADD COLUMN completed_at INTEGER',
      );
      await db.execute(
        'ALTER TABLE shopping_lines ADD COLUMN is_manual INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'CREATE TABLE aisle_orders (aisle TEXT PRIMARY KEY, sort_order INTEGER NOT NULL DEFAULT 0)',
      );
    }
  }
}
