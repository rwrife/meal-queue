import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:mealqueue/domain/week_planner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repo;
  late WeekPlanner planner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-planner-test-');
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
  });

  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });

  test('assign recipe, servings override, leftovers, and clear', () async {
    final recipe = Recipe(
      id: 'pasta',
      title: 'Pasta',
      servings: 2,
      ingredients: [
        Ingredient(item: 'Noodles', quantity: Rational(200), unit: Unit.g),
      ],
    );
    await repo.save(recipe);

    final monday = DateTime(2026, 10, 26); // Monday
    await planner.assign(
      PlannedMeal(
        date: monday,
        slot: 'Dinner',
        kind: MealKind.recipe,
        recipeId: 'pasta',
        servings: 4, // override
      ),
    );

    await planner.assign(
      PlannedMeal(date: monday, slot: 'Lunch', kind: MealKind.leftovers),
    );

    var weekMeals = await planner.week(monday);
    expect(weekMeals.length, 2);
    final dinner = weekMeals.firstWhere((m) => m.slot == 'Dinner');
    expect(dinner.recipeId, 'pasta');
    expect(dinner.servings, 4);

    final lunch = weekMeals.firstWhere((m) => m.slot == 'Lunch');
    expect(lunch.kind, MealKind.leftovers);
    expect(lunch.recipeId, null);

    await planner.clear(monday, 'Lunch');
    weekMeals = await planner.week(monday);
    expect(weekMeals.length, 1);
    expect(weekMeals.single.slot, 'Dinner');
  });

  test(
    'copy last week preserves slot layout and current recipe refs',
    () async {
      final recipe = Recipe(
        id: 'salad',
        title: 'Green Salad',
        servings: 1,
        ingredients: [
          Ingredient(item: 'Lettuce', quantity: Rational(1), unit: Unit.none),
        ],
      );
      await repo.save(recipe);

      final monday1 = DateTime(2026, 10, 19);
      final monday2 = DateTime(2026, 10, 26);

      await planner.assign(
        PlannedMeal(
          date: monday1,
          slot: 'Lunch',
          kind: MealKind.recipe,
          recipeId: 'salad',
          servings: 3,
        ),
      );
      await planner.assign(
        PlannedMeal(
          date: monday1.add(const Duration(days: 2)), // Wednesday
          slot: 'Dinner',
          kind: MealKind.eatOut,
        ),
      );

      await planner.copyLastWeek(monday2);

      final week2 = await planner.week(monday2);
      expect(week2.length, 2);

      final wednesday2 = monday2.add(const Duration(days: 2));
      final copiedLunch = week2.firstWhere((m) => m.slot == 'Lunch');
      expect(copiedLunch.date, monday2);
      expect(copiedLunch.recipeId, 'salad');
      expect(copiedLunch.servings, 3);

      final copiedDinner = week2.firstWhere((m) => m.slot == 'Dinner');
      expect(copiedDinner.date, wednesday2);
      expect(copiedDinner.kind, MealKind.eatOut);
    },
  );

  test(
    'mark cooked writes CookEvent, can undo, and archivedWeeks works',
    () async {
      final recipe = Recipe(
        id: 'chili',
        title: 'Chili',
        servings: 4,
        ingredients: [
          Ingredient(
            item: 'Beans',
            quantity: Rational(1),
            unit: Unit.parse('can'),
          ),
        ],
      );
      await repo.save(recipe);

      final day = DateTime(2026, 10, 26);
      await planner.assign(
        PlannedMeal(
          date: day,
          slot: 'Dinner',
          kind: MealKind.recipe,
          recipeId: 'chili',
        ),
      );

      final event = await planner.markCooked(day, 'Dinner');
      expect(event.recipeId, 'chili');
      expect(event.recipeTitle, 'Chili');

      var history = await planner.history(recipeId: 'chili');
      expect(history.length, 1);
      expect(history.first.recipeTitle, 'Chili');

      await planner.undoCooked(event.id);
      history = await planner.history(recipeId: 'chili');
      expect(history, isEmpty);

      final pastDate = DateTime(2026, 10, 12);
      await planner.assign(
        PlannedMeal(
          date: pastDate,
          slot: 'Breakfast',
          kind: MealKind.leftovers,
        ),
      );
      final archived = await planner.archivedWeeks(DateTime(2026, 10, 26));
      expect(archived.isNotEmpty, true);
      expect(archived.first, weekStart(pastDate));
    },
  );
}
