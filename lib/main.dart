import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

import 'app/adaptive.dart';
import 'domain/recipe_repository.dart';
import 'ui/recipe_library_screen.dart';
import 'ui/shopping_screen.dart';
import 'ui/week_planner_screen.dart';
import 'domain/week_planner.dart';

void main() => runApp(const MealQueueApp());

class MealQueueApp extends StatefulWidget {
  const MealQueueApp({super.key, this.repository});

  /// Injection for widget tests; production opens app-owned SQLite storage.
  final RecipeRepository? repository;

  @override
  State<MealQueueApp> createState() => _MealQueueAppState();
}

class _MealQueueAppState extends State<MealQueueApp> {
  RecipeRepository? _repository;
  int _tab = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    if (_repository == null) _open();
  }

  Future<void> _open() async {
    try {
      final repository = await RecipeRepository.open();
      if (!mounted) {
        await repository.close();
        return;
      }
      setState(() => _repository = repository);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    if (widget.repository == null) _repository?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final home = repository == null
        ? Center(
            child: Text(
              _error == null
                  ? 'Opening recipe library…'
                  : 'Cannot open local recipes: $_error',
            ),
          )
        : Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Adaptively(
                    ios: (_) => cupertino.CupertinoButton(
                      key: const Key('nav-recipes'),
                      onPressed: () => setState(() => _tab = 0),
                      child: const Text('Recipes'),
                    ),
                    android: (_) => material.TextButton(
                      key: const Key('nav-recipes'),
                      onPressed: () => setState(() => _tab = 0),
                      child: const Text('Recipes'),
                    ),
                    windows: (_) => fluent.Button(
                      key: const Key('nav-recipes'),
                      onPressed: () => setState(() => _tab = 0),
                      child: const Text('Recipes'),
                    ),
                  ),
                  Adaptively(
                    ios: (_) => cupertino.CupertinoButton(
                      key: const Key('nav-planner'),
                      onPressed: () => setState(() => _tab = 1),
                      child: const Text('Planner'),
                    ),
                    android: (_) => material.TextButton(
                      key: const Key('nav-planner'),
                      onPressed: () => setState(() => _tab = 1),
                      child: const Text('Planner'),
                    ),
                    windows: (_) => fluent.Button(
                      key: const Key('nav-planner'),
                      onPressed: () => setState(() => _tab = 1),
                      child: const Text('Planner'),
                    ),
                  ),
                  Adaptively(
                    ios: (_) => cupertino.CupertinoButton(
                      key: const Key('nav-shopping'),
                      onPressed: () => setState(() => _tab = 2),
                      child: const Text('Shopping'),
                    ),
                    android: (_) => material.TextButton(
                      key: const Key('nav-shopping'),
                      onPressed: () => setState(() => _tab = 2),
                      child: const Text('Shopping'),
                    ),
                    windows: (_) => fluent.Button(
                      key: const Key('nav-shopping'),
                      onPressed: () => setState(() => _tab = 2),
                      child: const Text('Shopping'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: switch (_tab) {
                  1 => WeekPlannerScreen(
                    recipes: repository,
                    planner: WeekPlanner(repository),
                  ),
                  2 => ShoppingScreen(recipes: repository),
                  _ => RecipeLibraryScreen(repository: repository),
                },
              ),
            ],
          );
    return Adaptively(
      ios: (_) => cupertino.CupertinoApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        home: home,
      ),
      android: (_) => material.MaterialApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        theme: material.ThemeData(colorSchemeSeed: material.Colors.deepOrange),
        home: home,
      ),
      windows: (_) => fluent.FluentApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );
  }
}
