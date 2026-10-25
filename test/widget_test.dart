import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/recipe_repository.dart';
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS gets Cupertino, no Material Scaffold', (tester) async {
    await pumpFor(tester, TargetPlatform.iOS);
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
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
}
