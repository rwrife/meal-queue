import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
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
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mq-shopping-widget-');
    final db = await databaseFactoryFfi.openDatabase(
      '${root.path}/recipes.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
      ),
    );
    repo = RecipeRepository(db, root);
    await repo.save(
      Recipe(
        id: 'toast',
        title: 'Toast',
        servings: 1,
        ingredients: [
          Ingredient(item: 'Bread', quantity: Rational(2), unit: Unit.none),
        ],
      ),
    );
    await WeekPlanner(repo).assign(
      PlannedMeal(
        date: weekStart(DateTime.now()),
        slot: 'Breakfast',
        kind: MealKind.recipe,
        recipeId: 'toast',
      ),
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await repo.close();
    await root.delete(recursive: true);
  });
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform generates list, checks and completes', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(MealQueueApp(repository: repo));
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(finder, findsWidgets);
      }

      await waitFor(find.byKey(const Key('nav-shopping')));
      await tester.tap(find.byKey(const Key('nav-shopping')));
      await tester.pump();
      if (platform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      } else if (platform == TargetPlatform.android) {
        expect(find.byType(material.Scaffold), findsOneWidget);
      } else {
        expect(find.byType(fluent.NavigationView), findsOneWidget);
      }
      await waitFor(find.byKey(const Key('generate-list')));
      await tester.tap(find.byKey(const Key('generate-list')));
      await waitFor(find.textContaining('Bread'));
      if (platform == TargetPlatform.windows) {
        expect(find.byType(fluent.Checkbox), findsWidgets);
      } else if (platform == TargetPlatform.android) {
        expect(find.byType(material.Checkbox), findsWidgets);
      } else {
        expect(find.byType(CupertinoSwitch), findsWidgets);
      }
      expect(find.byKey(const Key('complete-list')), findsOneWidget);
      await tester.tap(find.byKey(const Key('complete-list')));
      await waitFor(find.textContaining('0/1 checked'));
      await tester.pump(const Duration(milliseconds: 300));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
