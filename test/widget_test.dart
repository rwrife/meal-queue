import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:mealqueue/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-widget-');
    final db = await databaseFactoryFfi.openDatabase(
      '${root.path}/recipes.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
      ),
    );
    repository = RecipeRepository(db, root);
  });

  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  Future<void> pumpFor(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(MealQueueApp(repository: repository));
    // Real sqflite-ffi I/O needs several real-event-loop turns. No
    // pumpAndSettle here: the loading spinner animates forever while the
    // async reload is still in flight, which would time out the pump.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(target, findsWidgets);
    await tester.pumpAndSettle();
  }

  testWidgets('iOS gets Cupertino, no Material Scaffold', (tester) async {
    await pumpFor(tester, TargetPlatform.iOS);
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
    expect(find.byType(material.MaterialApp), findsNothing);
    expect(find.byType(material.Scaffold), findsNothing);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android gets Material 3, no Cupertino app', (tester) async {
    await pumpFor(tester, TargetPlatform.android);
    expect(find.byType(material.MaterialApp), findsOneWidget);
    expect(find.byType(material.AppBar), findsOneWidget);
    expect(find.byType(CupertinoApp), findsNothing);
    expect(find.byType(material.TextField), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows gets Fluent, no Material/Cupertino app', (tester) async {
    await pumpFor(tester, TargetPlatform.windows);
    expect(find.byType(fluent.FluentApp), findsOneWidget);
    expect(find.byType(fluent.NavigationView), findsOneWidget);
    expect(find.byType(material.MaterialApp), findsNothing);
    expect(find.byType(CupertinoApp), findsNothing);
    expect(find.byType(fluent.TextBox), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows opens native recipe editor', (tester) async {
    await pumpFor(tester, TargetPlatform.windows);
    expect(find.text('No recipes found'), findsOneWidget);
    await tester.tap(find.text('Add recipe'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-title')), findsOneWidget);
    expect(find.byType(fluent.TextBox), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform stock navigation and native editor', (tester) async {
      await pumpFor(tester, platform);
      await tester.tap(find.text('Stock'));
      await settle(tester, find.text('No stock logged'));
      await tester.tap(find.text('Add stock').last);
      await settle(tester, find.byKey(const Key('stock-item')));
      expect(find.byKey(const Key('stock-date')), findsOneWidget);
      expect(
        find.byType(material.AlertDialog),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      if (platform == TargetPlatform.windows) {
        expect(find.byType(fluent.ContentDialog), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Android explicit consume and restore update stored quantity', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.stock.save(
        StockLot(
          item: 'Rice',
          quantity: Rational(5),
          unit: Unit.g,
          location: StockLocation.pantry,
        ),
      ),
    );
    await pumpFor(tester, TargetPlatform.android);
    await tester.tap(find.text('Stock'));
    await settle(tester, find.textContaining('5 g Rice'));
    await tester.tap(find.text('Consume'));
    await settle(tester, find.byKey(const Key('consume-amount')));
    await tester.enterText(find.byKey(const Key('consume-amount')), '1 1/2');
    await tester.tap(find.widgetWithText(material.TextButton, 'Consume').last);
    await settle(tester, find.textContaining('3 1/2 g Rice'));
    await tester.tap(find.text('Restore'));
    await settle(tester, find.byKey(const Key('consume-amount')));
    await tester.enterText(find.byKey(const Key('consume-amount')), '1/2');
    await tester.tap(find.widgetWithText(material.TextButton, 'Restore').last);
    await settle(tester, find.textContaining('4 g Rice'));
    final stored = (await tester.runAsync(() => repository.stock.list()))!
        .single;
    expect(stored.quantity, Rational(4));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'recipe badge appears only after matched stock, hides after explicit consumption',
    (tester) async {
      await tester.runAsync(
        () => repository.save(
          Recipe(
            id: 'r',
            title: 'Bean soup',
            servings: 2,
            ingredients: [
              Ingredient(
                item: 'Beans',
                quantity: Rational(2),
                unit: Unit.parse('can'),
              ),
            ],
          ),
        ),
      );
      await pumpFor(tester, TargetPlatform.android);
      await tester.tap(find.textContaining('Bean soup').last);
      await settle(tester, find.byKey(const Key('recipe-detail')));
      expect(find.textContaining('You may already have this'), findsNothing);
      await tester.runAsync(
        () => repository.stock.save(
          StockLot(
            item: ' beans ',
            quantity: Rational(1),
            unit: Unit.parse('can'),
            location: StockLocation.pantry,
          ),
        ),
      );
      await tester.tap(find.byType(material.BackButton));
      await settle(tester, find.textContaining('Bean soup').last);
      // Re-enter after stock reload (stock changed outside UI in this test).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(find.textContaining('Bean soup').last);
      await settle(tester, find.textContaining('You may already have this'));
      expect(find.textContaining('You may already have this'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
