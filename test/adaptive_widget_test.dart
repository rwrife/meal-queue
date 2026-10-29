import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/app/adaptive.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
import 'package:mealqueue/domain/shopping_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:mealqueue/domain/week_planner.dart';
import 'package:mealqueue/main.dart';
import 'package:mealqueue/ui/recipe_library_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late RecipeRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mq-adaptive-');
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
        id: 'soup',
        title: 'Vegetable soup with beans and rice',
        servings: 4,
        tags: ['Dinner'],
        ingredients: [
          Ingredient(
            item: 'Long grain rice',
            quantity: Rational(2),
            unit: Unit.g,
          ),
        ],
        steps: 'Simmer until ready.',
      ),
    );
    await repo.stock.save(
      StockLot(
        item: 'Long grain rice',
        quantity: Rational(1),
        unit: Unit.g,
        location: StockLocation.pantry,
      ),
    );
    await WeekPlanner(repo).assign(
      PlannedMeal(
        date: weekStart(DateTime.now()),
        slot: 'Lunch',
        kind: MealKind.recipe,
        recipeId: 'soup',
      ),
    );
    await ShoppingRepository(repo).generate(DateTime.now());
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await repo.close();
    await root.delete(recursive: true);
  });

  Future<void> ready(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> launch(
    WidgetTester tester,
    TargetPlatform platform,
    double width, {
    double scale = 1,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(highContrast: true);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    final handler = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      handler?.call(details);
    };
    try {
      await tester.pumpWidget(MealQueueApp(repository: repo));
      await ready(tester);
    } finally {
      FlutterError.onError = handler;
    }
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final width in [390.0, 768.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$platform $width ${scale}x all screens and dialogs', (
          tester,
        ) async {
          await launch(tester, platform, width, scale: scale);
          final semantics = tester.ensureSemantics();
          try {
            expect(find.byType(AdaptiveScaffold), findsOneWidget);
            expect(
              find.byKey(const Key('recipe-split')),
              width >= 720 ? findsOneWidget : findsNothing,
            );
            if (platform == TargetPlatform.iOS) {
              expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
              expect(find.byType(material.Scaffold), findsNothing);
              expect(find.byType(fluent.NavigationView), findsNothing);
            } else if (platform == TargetPlatform.android) {
              expect(
                material.Theme.of(
                  tester.element(find.byType(material.Scaffold)),
                ).useMaterial3,
                isTrue,
              );
              expect(find.byType(CupertinoPageScaffold), findsNothing);
              expect(find.byType(fluent.NavigationView), findsNothing);
            } else {
              expect(find.byType(fluent.NavigationView), findsOneWidget);
              expect(find.byType(material.NavigationBar), findsNothing);
              expect(find.byType(CupertinoTabBar), findsNothing);
              final nativeTheme = fluent.FluentTheme.of(
                tester.element(find.byType(fluent.NavigationView)),
              );
              expect(
                nativeTheme.resources.controlStrokeColorDefault,
                const Color(0xFF000000),
              );
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.textContaining('Vegetable soup').first);
            await ready(tester);
            expect(find.byKey(const Key('recipe-detail')), findsOneWidget);
            await tester.tap(find.byKey(const Key('page-action')));
            await ready(tester);
            expect(find.byKey(const Key('recipe-title')), findsOneWidget);
            await tester.scrollUntilVisible(
              find.text('Save recipe'),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(RecipeEditorScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const Key('page-back')));
            await ready(tester);
            await tester.tap(find.text('Stock'));
            await ready(tester);
            await tester.tap(
              platform == TargetPlatform.iOS
                  ? find.bySemanticsLabel('Add stock')
                  : find.byKey(const Key('page-action')),
            );
            await ready(tester);
            expect(find.byKey(const Key('stock-item')), findsOneWidget);
            expect(find.byType(AdaptiveDialog), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Cancel').last);
            await tester.tap(find.text('Cancel').last);
            await ready(tester);
            Navigator.of(tester.element(find.byKey(const Key('stock-screen'))))
                .pop();
            await ready(tester);
            await tester.tap(find.byKey(const Key('nav-planner')));
            await ready(tester);
            final slot = find.byKey(
              Key('slot-${dayKey(weekStart(DateTime.now()))}:Lunch'),
            );
            await tester.ensureVisible(slot);
            await tester.tap(slot);
            await ready(tester);
            expect(find.byKey(const Key('slot-servings')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancel'));
            await ready(tester);
            await tester.tap(find.byKey(const Key('nav-shopping')));
            await ready(tester);
            expect(
              find.bySemanticsLabel(RegExp('Check Long grain rice')),
              findsWidgets,
              reason: tester
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data)
                  .join(' | '),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byType(AdaptiveCheckbox));
            await ready(tester);
            final saved = await tester.runAsync(
              () => ShoppingRepository(repo).active(),
            );
            expect(saved!.lines.single.checked, isTrue);
            await tester.tap(find.text('Add item'));
            await ready(tester);
            expect(find.byType(AdaptiveDialog), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancel'));
            await ready(tester);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }

  testWidgets(
    'iOS compact detail supports edge swipe and delete action sheet',
    (tester) async {
      await launch(tester, TargetPlatform.iOS, 390);
      try {
        await tester.tap(find.textContaining('Vegetable soup').first);
        await ready(tester);
        expect(find.byKey(const Key('recipe-detail')), findsOneWidget);
        await tester.dragFrom(const Offset(1, 400), const Offset(350, 0));
        await ready(tester);
        expect(find.byKey(const Key('recipe-detail')), findsNothing);
        await tester.tap(find.text('Delete'));
        await ready(tester);
        expect(find.byType(CupertinoActionSheet), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await ready(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Windows keyboard traversal, Enter, Escape, shortcuts and context menu',
    (tester) async {
      await launch(tester, TargetPlatform.windows, 1280);
      try {
        Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
          await tester.sendKeyDownEvent(
            shift
                ? LogicalKeyboardKey.shiftLeft
                : LogicalKeyboardKey.controlLeft,
          );
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(
            shift
                ? LogicalKeyboardKey.shiftLeft
                : LogicalKeyboardKey.controlLeft,
          );
          await ready(tester);
        }

        await chord(LogicalKeyboardKey.digit2);
        expect(find.byKey(const Key('copy-week')), findsOneWidget);
        await chord(LogicalKeyboardKey.digit1);
        await chord(LogicalKeyboardKey.keyN);
        expect(find.byKey(const Key('recipe-title')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ready(tester);
        expect(find.byKey(const Key('recipe-title')), findsNothing);
        await chord(LogicalKeyboardKey.keyN);
        await tester.enterText(
          find.byKey(const Key('recipe-title')),
          'Keyboard recipe',
        );
        await chord(LogicalKeyboardKey.keyS);
        expect(find.byKey(const Key('recipe-title')), findsNothing);
        final saved = await tester.runAsync(
          () => repo.list(query: 'Keyboard recipe'),
        );
        expect(saved!.single.title, 'Keyboard recipe');
        final visited = <FocusNode>{};
        var activated = false;
        for (var i = 0; i < 40; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final focus = FocusManager.instance.primaryFocus;
          if (focus != null) visited.add(focus);
          final context = focus?.context;
          if (context != null &&
              context.findAncestorWidgetOfExactType<AdaptiveButton>()?.label ==
                  'Stock') {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await ready(tester);
            activated = true;
            break;
          }
        }
        expect(visited.length, greaterThan(1));
        expect(
          activated,
          isTrue,
          reason: 'Tab must reach Stock and Enter must activate it',
        );
        expect(find.byKey(const Key('stock-screen')), findsOneWidget);
        await chord(LogicalKeyboardKey.keyN);
        expect(find.byKey(const Key('stock-item')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ready(tester);
        expect(find.byType(AdaptiveDialog), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ready(tester);
        final recipe = find.textContaining('Vegetable soup').first;
        await tester.tap(recipe, buttons: kSecondaryMouseButton);
        await ready(tester);
        expect(find.byType(fluent.MenuFlyout), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await ready(tester);
        expect(find.byType(fluent.MenuFlyout), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
