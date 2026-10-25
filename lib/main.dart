import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app/adaptive.dart';
import 'domain/recipe_repository.dart';
import 'ui/recipe_library_screen.dart';

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
        : RecipeLibraryScreen(repository: repository);
    return Adaptively(
      ios: (_) => CupertinoApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        home: home,
      ),
      android: (_) => MaterialApp(
        title: 'Meal Queue',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
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
