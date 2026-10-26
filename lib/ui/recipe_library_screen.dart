import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:uuid/uuid.dart';

import '../app/adaptive.dart';
import '../domain/meal.dart';
import '../domain/rational.dart';
import '../domain/recipe_repository.dart';
import '../domain/unit.dart';
import 'stock_screen.dart';

class RecipeLibraryScreen extends StatefulWidget {
  const RecipeLibraryScreen({required this.repository, super.key});
  final RecipeRepository repository;

  @override
  State<RecipeLibraryScreen> createState() => _RecipeLibraryScreenState();
}

class _RecipeLibraryScreenState extends State<RecipeLibraryScreen> {
  String query = '';
  String? tag;
  List<Recipe> recipes = [];
  List<String> tags = [];
  List<StockLot> stockLots = [];
  bool loading = true;
  int revision = 0;
  bool editing = false;
  bool viewing = false;
  bool showingStock = false;
  Recipe? selected;
  String? error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final request = ++revision;
    try {
      final results = await widget.repository.list(query: query, tag: tag);
      final available = await widget.repository.tags();
      final stock = await widget.repository.stock.list();
      if (!mounted || request != revision) return;
      setState(() {
        recipes = results;
        tags = available;
        stockLots = stock;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted || request != revision) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> remove(Recipe recipe) async {
    final bool? confirmed;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Delete recipe?'),
          content: Text(recipe.title),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Delete'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      confirmed = await fluent.showDialog<bool>(
        context: context,
        builder: (ctx) => fluent.ContentDialog(
          title: const Text('Delete recipe?'),
          content: Text(recipe.title),
          actions: [
            fluent.Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            fluent.FilledButton(
              child: const Text('Delete'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
    } else {
      confirmed = await material.showDialog<bool>(
        context: context,
        builder: (ctx) => material.AlertDialog(
          title: const Text('Delete recipe?'),
          content: Text(recipe.title),
          actions: [
            material.TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            material.TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
    if (confirmed != true) return;
    try {
      await widget.repository.delete(recipe.id);
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void openEditor([Recipe? recipe]) => setState(() {
    selected = recipe;
    editing = true;
    viewing = false;
    showingStock = false;
  });

  void openDetail(Recipe recipe) => setState(() {
    selected = recipe;
    viewing = true;
    editing = false;
    showingStock = false;
  });

  void back() {
    setState(() {
      viewing = false;
      showingStock = false;
    });
    reload();
  }

  void closeEditor(bool saved) {
    setState(() => editing = false);
    if (saved) reload();
  }

  @override
  Widget build(BuildContext context) {
    final content = showingStock
        ? StockScreen(
            repository: widget.repository.stock,
            onBack: back,
            key: const Key('stock-screen'),
          )
        : editing
        ? RecipeEditorScreen(
            key: ValueKey(selected?.id ?? 'new'),
            repository: widget.repository,
            recipe: selected,
            onDone: closeEditor,
          )
        : viewing
        ? _detail(selected!)
        : _library();
    if (showingStock) return content;
    final heading = editing
        ? (selected == null ? 'New Recipe' : 'Edit Recipe')
        : viewing
        ? selected!.title
        : 'Recipe Library';
    final onBack = editing ? () => closeEditor(false) : back;
    final hasBack = editing || viewing;
    final onAdd = viewing ? () => openEditor(selected) : () => openEditor();
    final addLabel = viewing ? 'Edit recipe' : 'New recipe';
    final addIcon = viewing ? fluent.FluentIcons.edit : fluent.FluentIcons.add;
    return Adaptively(
      ios: (_) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(heading),
          leading: hasBack
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onBack,
                  child: Text(editing ? 'Cancel' : 'Back'),
                )
              : null,
          trailing: editing
              ? null
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onAdd,
                  child: Icon(
                    viewing ? CupertinoIcons.pencil : CupertinoIcons.add,
                  ),
                ),
        ),
        child: SafeArea(child: content),
      ),
      android: (_) => material.Scaffold(
        appBar: material.AppBar(
          title: Text(heading),
          leading: hasBack ? material.BackButton(onPressed: onBack) : null,
          actions: editing
              ? null
              : [
                  material.IconButton(
                    tooltip: addLabel,
                    onPressed: onAdd,
                    icon: Icon(
                      viewing ? material.Icons.edit : material.Icons.add,
                    ),
                  ),
                ],
        ),
        body: content,
      ),
      windows: (_) => fluent.NavigationView(
        content: fluent.ScaffoldPage(
          header: fluent.PageHeader(
            title: Text(heading),
            commandBar: fluent.CommandBar(
              primaryItems: [
                if (hasBack)
                  fluent.CommandBarButton(
                    icon: const Icon(fluent.FluentIcons.back),
                    label: Text(editing ? 'Cancel' : 'Back'),
                    onPressed: onBack,
                  ),
                if (!editing)
                  fluent.CommandBarButton(
                    icon: Icon(addIcon),
                    label: Text(addLabel),
                    onPressed: onAdd,
                  ),
              ],
            ),
          ),
          content: content,
        ),
      ),
    );
  }

  Widget _detail(Recipe recipe) => ListView(
    key: const Key('recipe-detail'),
    padding: const EdgeInsets.all(16),
    children: [
      Text('${recipe.servings} servings'),
      for (final ingredient in recipe.ingredients)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '${ingredient.quantity ?? ''} ${ingredient.unit.symbol} ${ingredient.item}'
            '${stockLots.isNotEmpty && mayHaveIngredient(ingredient, stockLots) ? ' · You may already have this' : ''}',
          ),
        ),
      if (recipe.steps.isNotEmpty) Text(recipe.steps),
    ],
  );

  Widget _library() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: _button('Stock', () => setState(() => showingStock = true)),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: _field('Search recipes', null, (value) {
          query = value;
          reload();
        }, key: const Key('recipe-search')),
      ),
      if (tags.isNotEmpty)
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final value in <String?>[null, ...tags])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _button(value ?? 'All', () {
                    setState(() => tag = value);
                    reload();
                  }, selected: tag == value),
                ),
            ],
          ),
        ),
      if (error != null) Text('Storage error: $error'),
      Expanded(
        child: loading
            ? const Center(child: Text('Loading recipes…'))
            : recipes.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No recipes found'),
                    _button('Add recipe', () => openEditor()),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  final photo = widget.repository.photoFile(recipe);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        if (photo != null && photo.existsSync())
                          Image.file(
                            photo,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        Expanded(
                          child: _button(
                            '${recipe.title} · ${recipe.servings} servings · ${recipe.tags.join(', ')}',
                            () => openDetail(recipe),
                          ),
                        ),
                        _button('Delete', () => remove(recipe)),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

/// Native controls only. No Material field/button leaks into Cupertino or Fluent.
Widget _field(
  String label,
  TextEditingController? controller,
  ValueChanged<String> onChanged, {
  Key? key,
  int maxLines = 1,
}) => Adaptively(
  ios: (_) => CupertinoTextField(
    key: key,
    controller: controller,
    placeholder: label,
    maxLines: maxLines,
    onChanged: onChanged,
  ),
  android: (_) => material.TextField(
    key: key,
    controller: controller,
    decoration: material.InputDecoration(labelText: label),
    maxLines: maxLines,
    onChanged: onChanged,
  ),
  windows: (_) => fluent.TextBox(
    key: key,
    controller: controller,
    placeholder: label,
    maxLines: maxLines,
    onChanged: onChanged,
  ),
);

Widget _button(String label, VoidCallback onPressed, {bool selected = false}) =>
    Adaptively(
      ios: (_) => CupertinoButton(onPressed: onPressed, child: Text(label)),
      android: (_) => selected
          ? material.FilledButton(onPressed: onPressed, child: Text(label))
          : material.TextButton(onPressed: onPressed, child: Text(label)),
      windows: (_) => selected
          ? fluent.FilledButton(onPressed: onPressed, child: Text(label))
          : fluent.Button(onPressed: onPressed, child: Text(label)),
    );

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen({
    required this.repository,
    required this.onDone,
    this.recipe,
    super.key,
  });
  final RecipeRepository repository;
  final Recipe? recipe;
  final ValueChanged<bool> onDone;

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  late final title = TextEditingController(text: widget.recipe?.title ?? '');
  late final servings = TextEditingController(
    text: '${widget.recipe?.servings ?? 4}',
  );
  late final steps = TextEditingController(text: widget.recipe?.steps ?? '');
  late final tags = TextEditingController(
    text: widget.recipe?.tags.join(', ') ?? '',
  );
  late final List<_Line> lines = [
    for (final ingredient in widget.recipe?.ingredients ?? <Ingredient>[])
      _Line(ingredient: ingredient),
    if (widget.recipe == null) _Line(),
  ];
  late String? photoPath = widget.recipe?.photoPath;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    servings.dispose();
    steps.dispose();
    tags.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> pickPhoto() async {
    try {
      const images = XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      final choice = await openFile(acceptedTypeGroups: [images]);
      if (choice == null) return;
      final imported = await widget.repository.importPhoto(File(choice.path));
      if (mounted) setState(() => photoPath = imported);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    if (saving) return;
    try {
      final count = int.parse(servings.text.trim());
      final parsed = <Ingredient>[];
      for (final line in lines) {
        if (line.item.text.trim().isEmpty) {
          if (line.quantity.text.trim().isNotEmpty ||
              line.unit.text.trim().isNotEmpty) {
            throw const FormatException('Ingredient item required');
          }
          continue;
        }
        final amount = line.quantity.text.trim();
        parsed.add(
          Ingredient(
            item: line.item.text,
            quantity: amount.isEmpty ? null : Rational.parse(amount),
            unit: Unit.parse(line.unit.text),
            aisle: line.aisle.text,
          ),
        );
      }
      final recipe = Recipe(
        id: widget.recipe?.id ?? const Uuid().v4(),
        title: title.text,
        servings: count,
        steps: steps.text,
        tags: tags.text.split(','),
        ingredients: parsed,
        photoPath: photoPath,
      );
      setState(() {
        saving = true;
        error = null;
      });
      await widget.repository.save(recipe);
      if (mounted) widget.onDone(true);
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Check title, servings and amounts: $e');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.repository.photoFileFor(photoPath);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) Text(error!),
        if (photo != null && photo.existsSync())
          Image.file(photo, height: 120, fit: BoxFit.contain),
        Wrap(
          spacing: 8,
          children: [
            _button('Choose photo', pickPhoto),
            if (photoPath != null)
              _button('Remove photo', () => setState(() => photoPath = null)),
          ],
        ),
        _field('Title', title, (_) {}, key: const Key('recipe-title')),
        _field(
          'Base servings',
          servings,
          (_) {},
          key: const Key('recipe-servings'),
        ),
        _field('Tags (comma separated)', tags, (_) {}),
        const SizedBox(height: 12),
        const Text('Ingredients'),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SizedBox(
                  width: 90,
                  child: _field('Amount', line.quantity, (_) {}),
                ),
                SizedBox(width: 90, child: _field('Unit', line.unit, (_) {})),
                SizedBox(width: 180, child: _field('Item', line.item, (_) {})),
                SizedBox(
                  width: 110,
                  child: _field('Aisle', line.aisle, (_) {}),
                ),
                _button(
                  'Remove line',
                  () => setState(() {
                    lines.remove(line);
                    line.dispose();
                  }),
                ),
              ],
            ),
          ),
        _button('Add ingredient', () => setState(() => lines.add(_Line()))),
        _field('Steps', steps, (_) {}, maxLines: 5),
        const SizedBox(height: 20),
        _button(saving ? 'Saving…' : 'Save recipe', save),
      ],
    );
  }
}

class _Line {
  _Line({Ingredient? ingredient})
    : item = TextEditingController(text: ingredient?.item ?? ''),
      quantity = TextEditingController(
        text: ingredient?.quantity?.toString() ?? '',
      ),
      unit = TextEditingController(text: ingredient?.unit.symbol ?? ''),
      aisle = TextEditingController(text: ingredient?.aisle ?? '');
  final TextEditingController item, quantity, unit, aisle;

  void dispose() {
    item.dispose();
    quantity.dispose();
    unit.dispose();
    aisle.dispose();
  }
}
