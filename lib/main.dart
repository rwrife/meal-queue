import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app/adaptive.dart';

void main() => runApp(const MealQueueApp());

/// Empty shell. Feature controls arrive with their working feature slices.
class MealQueueApp extends StatelessWidget {
  const MealQueueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Adaptively(
      ios: (_) => const CupertinoApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        home: _HomeScreen(),
      ),
      android: (_) => MaterialApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
        home: const _HomeScreen(),
      ),
      windows: (_) => const fluent.FluentApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        home: _HomeScreen(),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  static const _empty = 'No recipes yet. Recipe library coming soon.';

  @override
  Widget build(BuildContext context) {
    return Adaptively(
      ios: (_) => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Meal Queue')),
        child: SafeArea(child: Center(child: Text(_empty))),
      ),
      android: (_) => Scaffold(
        appBar: AppBar(title: const Text('Meal Queue')),
        body: const Center(child: Text(_empty)),
      ),
      windows: (_) => const fluent.NavigationView(
        content: fluent.ScaffoldPage(
          header: fluent.PageHeader(title: Text('Meal Queue')),
          content: Center(child: Text(_empty)),
        ),
      ),
    );
  }
}
