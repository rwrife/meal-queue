import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-test-');
    final db = await databaseFactoryFfi.openDatabase(
      '${root.path}/recipes.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
        onUpgrade: AppDatabaseSchema.onUpgrade,
      ),
    );
    repo = RecipeRepository(db, root);
  });

  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });

  test('schema version, tables, migration scaffold and foreign keys', () async {
    expect(await repo.db.getVersion(), 1);
    final tables = await repo.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll([
        'recipes',
        'ingredients',
        'recipe_tags',
        'planned_meals',
        'stock_lots',
        'shopping_snapshots',
        'shopping_lines',
      ]),
    );
    await AppDatabaseSchema.onUpgrade(repo.db, 1, 1); // no-op
    expect(await repo.db.rawQuery('PRAGMA foreign_keys'), [
      {'foreign_keys': 1},
    ]);
  });

  test('insert, search, tag filter, edit, delete, and children', () async {
    final recipe = Recipe(
      id: 'soup',
      title: 'Tomato Soup',
      servings: 4,
      tags: ['Quick', ' Dinner ', 'Quick'],
      steps: 'Simmer',
      ingredients: [
        Ingredient(
          item: 'Tomato',
          quantity: Rational(3, 2),
          unit: Unit.kg,
          aisle: 'Produce',
        ),
        Ingredient(item: 'Salt', quantity: null, unit: Unit.none),
      ],
    );
    await repo.save(recipe);
    final loaded = (await repo.get('soup'))!;
    expect(loaded.title, 'Tomato Soup');
    expect(loaded.steps, 'Simmer');
    expect(loaded.ingredients.length, 2);
    expect(loaded.ingredients.first.quantity, Rational(3, 2));
    expect(loaded.ingredients.last.quantity, null);
    expect(loaded.tags, ['Dinner', 'Quick']);
    expect((await repo.list(query: 'TOMATO')).length, 1);
    expect((await repo.list(query: '%')).length, 0); // literal search
    expect((await repo.list(tag: 'Quick')).length, 1);
    expect((await repo.list(tag: 'Other')).length, 0);

    await repo.save(
      Recipe(
        id: 'soup',
        title: 'Bean Soup',
        servings: 2,
        ingredients: [
          Ingredient(item: 'Beans', quantity: Rational(1), unit: Unit.g),
        ],
      ),
    );
    expect((await repo.get('soup'))!.ingredients.single.item, 'Beans');
    expect((await repo.list(query: 'Tomato')).length, 0);
    expect(await repo.tags(), isEmpty);
    await repo.delete('soup');
    expect(await repo.get('soup'), null);
    expect(await repo.db.query('ingredients'), isEmpty);
    expect(await repo.db.query('recipe_tags'), isEmpty);
  });

  test(
    'photos stay relative, get replaced, removed and orphan cleanup',
    () async {
      final source = File('${root.path}/source.jpg');
      await source.writeAsBytes([0xff, 0xd8, 0xff]);
      final first = await repo.importPhoto(source);
      expect(first, startsWith('photos/'));
      expect(repo.photoFileFor(first)!.existsSync(), true);
      expect(() => repo.photoFileFor('../other.jpg'), throwsFormatException);
      expect(() => repo.photoFileFor(r'photos\x.jpg'), throwsFormatException);
      await repo.save(
        Recipe(
          id: 'r',
          title: 'Rice',
          servings: 1,
          ingredients: [],
          photoPath: first,
        ),
      );
      expect((await repo.get('r'))!.photoPath, first);
      final second = await repo.importPhoto(source);
      await repo.save(
        Recipe(
          id: 'r',
          title: 'Rice',
          servings: 1,
          ingredients: [],
          photoPath: second,
        ),
      );
      expect(repo.photoFileFor(first)!.existsSync(), false);
      expect(repo.photoFileFor(second)!.existsSync(), true);
      final orphan = await repo.importPhoto(source);
      expect(await repo.cleanOrphanPhotos(), 1);
      expect(repo.photoFileFor(orphan)!.existsSync(), false);
      await repo.delete('r');
      expect(repo.photoFileFor(second)!.existsSync(), false);
    },
  );
}
