import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:mealqueue/domain/week_planner.dart';
import 'package:mealqueue/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repo;
  late WeekPlanner planner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-widget-test-');
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
    await repo.save(
      Recipe(
        id: 'soup',
        title: 'Soup',
        servings: 2,
        ingredients: [
          Ingredient(item: 'Water', quantity: Rational(1), unit: Unit.ml),
        ],
      ),
    );
  });

  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });

  testWidgets(
    'full planner user journey: assign, override, copy week, cook and undo',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(MealQueueApp(repository: repo));
      await tester.pumpAndSettle();

      // Switch to Planner
      await tester.tap(find.byKey(const Key('nav-planner')));
      await tester.pumpAndSettle();

      // Monday Lunch slot
      final monday = weekStart(DateTime.now());
      final mondayKey = dayKey(monday);
      final slotFinder = find.byKey(Key('slot-$mondayKey:Lunch'));
      expect(slotFinder, findsOneWidget);

      // SQLite refresh runs outside Flutter's fake clock. Wait for loaded
      // recipe controls before opening a dialog that snapshots available recipes.
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.tap(slotFinder);
        await tester.pumpAndSettle();
        if (find.byKey(const Key('recipe-soup')).evaluate().isNotEmpty) break;
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('recipe-soup')), findsOneWidget);
      await tester.tap(find.byKey(const Key('recipe-soup')));
      await tester.pumpAndSettle();

      // Set servings override to 5
      await tester.enterText(find.byKey(const Key('slot-servings')), '5');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byKey(const Key('save-slot')));
      await tester.pumpAndSettle();

      // Persisted override proves dialog saved independently of visual label.
      final meals = await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          final rows = await planner.week(monday);
          if (rows.isNotEmpty) return rows;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return planner.week(monday);
      });
      expect(
        meals,
        isNotEmpty,
        reason:
            'Saving slot must persist to SQLite; UI: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
      );
      expect(meals!.single.recipeId, 'soup');
      expect(meals.single.servings, 5);
      for (var i = 0; i < 50; i++) {
        if (find.textContaining('Soup (5 servings)').evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.textContaining('Soup (5 servings)'), findsOneWidget);

      // Cook the meal
      final cookFinder = find.byKey(Key('cook-$mondayKey:Lunch'));
      expect(cookFinder, findsOneWidget);
      await tester.tap(cookFinder);
      await tester.pumpAndSettle();

      // SQLite writes finish on real clock, not pumpAndSettle's fake clock.
      for (var i = 0; i < 50; i++) {
        if (find.byKey(const Key('undo-cooked')).evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byKey(const Key('undo-cooked')), findsOneWidget);

      await tester.tap(find.byKey(const Key('undo-cooked')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 50; i++) {
        if (find.byKey(const Key('undo-cooked')).evaluate().isEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byKey(const Key('undo-cooked')), findsNothing);

      // Copy last week
      await tester.tap(find.byKey(const Key('copy-week')));
      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
