import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/main.dart';

void main() {
  Future<void> pumpFor(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(const MealQueueApp());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('iOS gets Cupertino, no Material Scaffold', (tester) async {
    await pumpFor(tester, TargetPlatform.iOS);
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.text('Meal Queue'), findsWidgets);
  });

  testWidgets('Android gets Material 3, no Cupertino app', (tester) async {
    await pumpFor(tester, TargetPlatform.android);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(CupertinoApp), findsNothing);
  });

  testWidgets('Windows gets Fluent, no Material/Cupertino app', (tester) async {
    await pumpFor(tester, TargetPlatform.windows);
    expect(find.byType(fluent.FluentApp), findsOneWidget);
    expect(find.byType(fluent.NavigationView), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byType(CupertinoApp), findsNothing);
  });
}
