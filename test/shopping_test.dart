import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/shopping_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:mealqueue/domain/week_planner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repo;
  late WeekPlanner planner;
  late ShoppingRepository shopping;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-shopping-test-');
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
    planner = WeekPlanner(repo);
    shopping = ShoppingRepository(repo);
  });

  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });

  test(
    'generate list freezes snapshot independent of later recipe edits',
    () async {
      final recipe = Recipe(
        id: 'soup',
        title: 'Tomato Soup',
        servings: 2,
        ingredients: [
          Ingredient(
            item: 'Tomatoes',
            quantity: Rational(4),
            unit: Unit.none,
            aisle: 'Produce',
          ),
          Ingredient(
            item: 'Salt',
            quantity: Rational(1, 2),
            unit: Unit.tsp,
            aisle: 'Baking',
          ),
        ],
      );
      await repo.save(recipe);

      final monday = DateTime(2026, 10, 26);
      await planner.assign(
        PlannedMeal(
          date: monday,
          slot: 'Dinner',
          kind: MealKind.recipe,
          recipeId: 'soup',
          servings: 4, // 2x scale
        ),
      );

      final list = await shopping.generate(monday);
      expect(list.lines.length, 2);
      final tomatoLine = list.lines.firstWhere((l) => l.item == 'Tomatoes');
      expect(tomatoLine.quantity, Rational(8));

      // Later recipe edit must not mutate the active frozen list
      await repo.save(
        Recipe(
          id: 'soup',
          title: 'Tomato Soup Modified',
          servings: 2,
          ingredients: [
            Ingredient(
              item: 'Tomatoes',
              quantity: Rational(20),
              unit: Unit.none,
              aisle: 'Produce',
            ),
          ],
        ),
      );

      final freshRead = await shopping.get(list.id);
      expect(
        freshRead!.lines.firstWhere((l) => l.item == 'Tomatoes').quantity,
        Rational(8),
      );
    },
  );

  test('durable checkboxes survive reload and complete to history', () async {
    final recipe = Recipe(
      id: 'toast',
      title: 'Toast',
      servings: 1,
      ingredients: [
        Ingredient(
          item: 'Bread',
          quantity: Rational(2),
          unit: Unit.none,
          aisle: 'Bakery',
        ),
      ],
    );
    await repo.save(recipe);
    final monday = DateTime(2026, 10, 26);
    await planner.assign(
      PlannedMeal(
        date: monday,
        slot: 'Breakfast',
        kind: MealKind.recipe,
        recipeId: 'toast',
      ),
    );

    final list = await shopping.generate(monday);
    final line = list.lines.first;
    expect(line.checked, isFalse);

    await shopping.check(list.id, line.id, true);

    // Close and reopen same SQLite file: checkbox must survive process restart.
    await repo.close();
    final reopened = await databaseFactoryFfi.openDatabase(
      '${root.path}/recipes.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
        onUpgrade: AppDatabaseSchema.onUpgrade,
      ),
    );
    repo = RecipeRepository(reopened, root);
    shopping = ShoppingRepository(repo);
    final reloaded = (await shopping.active())!;
    expect(reloaded.lines.first.checked, isTrue);
    expect(reloaded.checkedCount, 1);

    await shopping.complete(list.id);
    expect(await shopping.active(), isNull);

    final history = await shopping.history();
    expect(history.length, 1);
    expect(history.first.id, list.id);
    expect(history.first.checkedCount, 1);
    expect(history.first.lines.length, 1);
  });

  test(
    'manual add/edit/remove lines and aisle order with unknown last',
    () async {
      final monday = DateTime(2026, 10, 26);
      final list = await shopping.generate(monday);

      await shopping.saveManual(
        list.id,
        item: 'Coffee Beans',
        quantity: Rational(1),
        unit: Unit.lb,
        aisle: 'Beverages',
      );
      await shopping.saveManual(
        list.id,
        item: 'Napkins',
        quantity: Rational(50),
        unit: Unit.none,
        aisle: 'Household',
      );

      var current = (await shopping.get(list.id))!;
      expect(current.lines.length, 2);

      final coffee = current.lines.firstWhere((l) => l.item == 'Coffee Beans');
      expect(coffee.manual, isTrue);

      // Edit manual item
      await shopping.saveManual(
        list.id,
        lineId: coffee.id,
        item: 'Espresso Beans',
        quantity: Rational(2),
        unit: Unit.lb,
        aisle: 'Beverages',
      );

      current = (await shopping.get(list.id))!;
      expect(
        current.lines.any(
          (l) => l.item == 'Espresso Beans' && l.quantity == Rational(2),
        ),
        isTrue,
      );

      // Custom aisle order: Household before Beverages; any unlisted aisle last
      await shopping.setAisleOrder(['household', 'beverages']);
      current = (await shopping.get(list.id))!;
      expect(current.lines.first.aisle, 'Household');
      expect(current.lines.last.aisle, 'Beverages');

      // Remove manual item
      final toRemove = current.lines.firstWhere((l) => l.item == 'Napkins');
      await shopping.removeManual(list.id, toRemove.id);

      current = (await shopping.get(list.id))!;
      expect(current.lines.length, 1);
      expect(current.lines.first.item, 'Espresso Beans');
    },
  );

  test(
    'already have stock hint shown when positive stock exists with exact unit',
    () async {
      await repo.stock.save(
        StockLot(
          item: 'Flour',
          quantity: Rational(500),
          unit: Unit.g,
          location: StockLocation.pantry,
        ),
      );

      final recipe = Recipe(
        id: 'bread',
        title: 'Bread',
        servings: 1,
        ingredients: [
          Ingredient(
            item: 'Flour',
            quantity: Rational(300),
            unit: Unit.g,
            aisle: 'Baking',
          ),
          Ingredient(
            item: 'Yeast',
            quantity: Rational(7),
            unit: Unit.g,
            aisle: 'Baking',
          ),
        ],
      );
      await repo.save(recipe);

      final monday = DateTime(2026, 10, 26);
      await planner.assign(
        PlannedMeal(
          date: monday,
          slot: 'Breakfast',
          kind: MealKind.recipe,
          recipeId: 'bread',
        ),
      );

      final list = await shopping.generate(monday);
      final flourLine = list.lines.firstWhere((l) => l.item == 'Flour');
      final yeastLine = list.lines.firstWhere((l) => l.item == 'Yeast');

      expect(flourLine.stockHint, isTrue);
      expect(flourLine.checked, isFalse); // Stock hint never auto-checks
      expect(yeastLine.stockHint, isFalse);
    },
  );

  test('generate returns existing active list if not completed', () async {
    final monday = DateTime(2026, 10, 26);
    final first = await shopping.generate(monday);
    final second = await shopping.generate(monday);
    expect(second.id, first.id);
  });
}
