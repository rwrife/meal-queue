import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../app/adaptive.dart';
import '../domain/meal.dart';
import '../domain/rational.dart';
import '../domain/recipe_repository.dart';
import '../domain/unit.dart';
import '../domain/week_planner.dart';
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
    final confirmed = await confirmAdaptiveDelete(
      context,
      'Delete ${recipe.title}?',
    );
    if (confirmed != true) return;
    try {
      await widget.repository.delete(recipe.id);
      if (mounted && selected?.id == recipe.id) {
        setState(() {
          selected = null;
          viewing = false;
          editing = false;
        });
      }
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  bool get split => MediaQuery.sizeOf(context).width >= 720;

  void openEditor([Recipe? recipe]) {
    if (!split) {
      Navigator.of(context).push(
        adaptivePageRoute<void>(
          (ctx) => AdaptiveScaffold(
            title: recipe == null ? 'New Recipe' : 'Edit Recipe',
            onBack: () => Navigator.pop(ctx),
            body: RecipeEditorScreen(
              repository: widget.repository,
              recipe: recipe,
              onDone: (saved) {
                Navigator.pop(ctx);
                if (saved) reload();
              },
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      selected = recipe;
      editing = true;
      viewing = false;
    });
  }

  void openDetail(Recipe recipe) {
    if (!split) {
      Navigator.of(context)
          .push(
            adaptivePageRoute<void>(
              (ctx) => AdaptiveScaffold(
                title: recipe.title,
                onBack: () => Navigator.pop(ctx),
                actionLabel: 'Edit recipe',
                onAction: () {
                  Navigator.pop(ctx);
                  openEditor(recipe);
                },
                body: _detail(recipe),
              ),
            ),
          )
          .then((_) {
            if (mounted) reload();
          });
      return;
    }
    setState(() {
      selected = recipe;
      viewing = true;
      editing = false;
    });
  }

  void openStock() {
    Navigator.of(context)
        .push(
          adaptivePageRoute<void>(
            (ctx) => StockScreen(
              key: const Key('stock-screen'),
              repository: widget.repository.stock,
              onBack: () => Navigator.pop(ctx),
            ),
          ),
        )
        .then((_) {
          if (mounted) reload();
        });
  }

  void back() {
    setState(() {
      viewing = false;
    });
    reload();
  }

  void closeEditor(bool saved) {
    setState(() => editing = false);
    if (saved) reload();
  }

  @override
  Widget build(BuildContext context) {
    final content = editing
        ? RecipeEditorScreen(
            key: ValueKey(selected?.id ?? 'new'),
            repository: widget.repository,
            recipe: selected,
            onDone: closeEditor,
          )
        : viewing
        ? _detail(selected!)
        : _library();
    final heading = editing
        ? (selected == null ? 'New Recipe' : 'Edit Recipe')
        : viewing
        ? selected!.title
        : 'Recipe Library';
    final onBack = editing ? () => closeEditor(false) : back;
    final hasBack = editing || viewing;
    final onAdd = viewing ? () => openEditor(selected) : () => openEditor();
    final addLabel = viewing ? 'Edit recipe' : 'New recipe';
    return PopScope(
      canPop: !hasBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && hasBack) onBack();
      },
      child: AdaptiveScaffold(
        title: heading,
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (MediaQuery.sizeOf(context).width < 720) return content;
            return Row(
              key: const Key('recipe-split'),
              children: [
                SizedBox(width: constraints.maxWidth * .42, child: _library()),
                Expanded(
                  child: editing || viewing
                      ? content
                      : const Center(
                          child: Text('Select a recipe to view details'),
                        ),
                ),
              ],
            );
          },
        ),
        onBack: hasBack ? onBack : null,
        actionLabel: editing ? null : addLabel,
        onAction: editing ? null : onAdd,
        largeTitle: !hasBack,
      ),
    );
  }

  Widget _detail(Recipe recipe) => ListView(
    key: const Key('recipe-detail'),
    padding: const EdgeInsets.all(16),
    children: [
      Text('${recipe.servings} servings'),
      FutureBuilder<List<CookEvent>>(
        future: WeekPlanner(widget.repository).history(recipeId: recipe.id),
        builder: (_, snapshot) {
          final events = snapshot.data ?? [];
          return Text(
            'Cooked ${events.length} times${events.isEmpty ? '' : ' · Last cooked ${dayKey(events.first.cookedAt)}'}',
          );
        },
      ),
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
        child: _button('Stock', openStock),
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
          height: 48 * MediaQuery.textScalerOf(context).scale(1),
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
                    child: AdaptiveContextMenu(
                      onEdit: () => openEditor(recipe),
                      onDelete: () => remove(recipe),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (photo != null && photo.existsSync())
                            Image.file(
                              photo,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          _button(
                            '${recipe.title} · ${recipe.servings} servings · ${recipe.tags.join(', ')}',
                            () => openDetail(recipe),
                          ),
                          _button('Delete', () => remove(recipe)),
                        ],
                      ),
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
}) => AdaptiveField(
  key: key,
  label: label,
  controller: controller,
  onChanged: onChanged,
  maxLines: maxLines,
);

Widget _button(String label, VoidCallback onPressed, {bool selected = false}) =>
    AdaptiveButton(label: label, onPressed: onPressed, selected: selected);

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
    return AdaptiveSaveRegion(
      onSave: save,
      child: ListView(
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
                  SizedBox(
                    width: 180,
                    child: _field('Item', line.item, (_) {}),
                  ),
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
      ),
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
