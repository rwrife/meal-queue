import 'package:flutter/widgets.dart';

import '../app/adaptive.dart';
import '../domain/meal.dart';
import '../domain/recipe_repository.dart';
import '../domain/week_planner.dart';

Widget _button(String label, VoidCallback action, {Key? key}) =>
    AdaptiveButton(key: key, label: label, onPressed: action);

class WeekPlannerScreen extends StatefulWidget {
  const WeekPlannerScreen({
    required this.recipes,
    required this.planner,
    this.initialMonday,
    super.key,
  });
  final RecipeRepository recipes;
  final WeekPlanner planner;
  final DateTime? initialMonday;

  @override
  State<WeekPlannerScreen> createState() => _WeekPlannerScreenState();
}

class _WeekPlannerScreenState extends State<WeekPlannerScreen> {
  late DateTime current = weekStart(widget.initialMonday ?? DateTime.now());
  Map<String, PlannedMeal> grid = {};
  List<Recipe> availableRecipes = [];
  CookEvent? lastEvent;
  String? banner;
  int revision = 0;
  bool archive = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final request = ++revision;
    final date = current;
    try {
      final list = await widget.planner.week(date);
      final all = await widget.recipes.list();
      if (!mounted || request != revision) return;
      setState(() {
        grid = {for (final m in list) '${dayKey(m.date)}:${m.slot}': m};
        availableRecipes = all;
        banner = null;
      });
    } catch (e) {
      if (mounted && request == revision) setState(() => banner = '$e');
    }
  }

  void changeWeek(int offset) {
    setState(() => current = current.add(Duration(days: offset * 7)));
    refresh();
  }

  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => banner = '$e');
    }
  }

  Future<void> cook(DateTime date, String slot) async {
    await run(() async {
      lastEvent = await widget.planner.markCooked(date, slot);
    });
  }

  Future<void> undo() async {
    final event = lastEvent;
    if (event == null) return;
    await run(() async {
      await widget.planner.undoCooked(event.id);
      lastEvent = null;
    });
  }

  Future<void> edit(DateTime date, String slot) async {
    final existing = grid['${dayKey(date)}:$slot'];
    final choice = await showAdaptiveDialog<_SlotChoice>(
      context: context,
      builder: (_) => _SlotDialog(
        slot: slot,
        existing: existing,
        recipes: availableRecipes,
      ),
    );
    if (choice == null) return;
    await run(
      () => choice.clear
          ? widget.planner.clear(date, slot)
          : widget.planner.assign(
              PlannedMeal(
                date: date,
                slot: slot,
                kind: choice.kind,
                recipeId: choice.recipeId,
                servings: choice.servings,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Week of ${dayKey(current)}';
    final body = Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _button(
              'Previous',
              () => changeWeek(-1),
              key: const Key('prev-week'),
            ),
            Text(dayKey(current)),
            _button('Next', () => changeWeek(1), key: const Key('next-week')),
            _button(
              'Copy last week',
              () => run(() => widget.planner.copyLastWeek(current)),
              key: const Key('copy-week'),
            ),
            _button('Week archive', () => setState(() => archive = !archive)),
            if (lastEvent != null)
              _button('Undo cooked', undo, key: const Key('undo-cooked')),
          ],
        ),
        if (banner != null) Text(banner!),
        Expanded(
          child: archive
              ? _archive()
              : ListView(
                  children: [
                    for (var i = 0; i < 7; i++)
                      _day(current.add(Duration(days: i))),
                  ],
                ),
        ),
      ],
    );
    return AdaptiveScaffold(title: title, body: body, largeTitle: true);
  }

  Widget _archive() => FutureBuilder<List<DateTime>>(
    future: widget.planner.archivedWeeks(DateTime.now()),
    builder: (context, snapshot) => ListView(
      children: [
        if (snapshot.hasError) Text('${snapshot.error}'),
        for (final date in snapshot.data ?? <DateTime>[])
          _button('Week of ${dayKey(date)}', () {
            setState(() {
              current = date;
              archive = false;
            });
            refresh();
          }),
      ],
    ),
  );

  Widget _day(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${days[date.weekday - 1]} ${date.month}/${date.day}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [for (final slot in mealSlots) _meal(date, slot)],
          ),
        ],
      ),
    );
  }

  Widget _meal(DateTime date, String slot) {
    final key = '${dayKey(date)}:$slot';
    final meal = grid[key];
    final recipe = availableRecipes
        .where((r) => r.id == meal?.recipeId)
        .firstOrNull;
    final name = switch (meal?.kind) {
      MealKind.recipe => recipe?.title ?? 'Deleted recipe',
      MealKind.leftovers => 'Leftovers',
      MealKind.eatOut => 'Eat out',
      null => 'Empty',
    };
    final count = meal?.kind == MealKind.recipe
        ? meal?.servings ?? recipe?.servings
        : null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _button(
          '$slot: $name${count == null ? '' : ' ($count servings)'}',
          () => edit(date, slot),
          key: Key('slot-$key'),
        ),
        if (meal?.kind == MealKind.recipe && recipe != null)
          _button('Cook $slot', () => cook(date, slot), key: Key('cook-$key')),
      ],
    );
  }
}

class _SlotChoice {
  const _SlotChoice(
    this.kind, {
    this.recipeId,
    this.servings,
    this.clear = false,
  });
  final MealKind kind;
  final String? recipeId;
  final int? servings;
  final bool clear;
}

class _SlotDialog extends StatefulWidget {
  const _SlotDialog({
    required this.slot,
    required this.existing,
    required this.recipes,
  });
  final String slot;
  final PlannedMeal? existing;
  final List<Recipe> recipes;
  @override
  State<_SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends State<_SlotDialog> {
  late MealKind kind = widget.existing?.kind ?? MealKind.recipe;
  late String? recipeId =
      widget.existing?.recipeId ??
      (widget.recipes.isEmpty ? null : widget.recipes.first.id);
  late final servings = TextEditingController(
    text: widget.existing?.servings?.toString(),
  );
  String? error;

  @override
  void dispose() {
    servings.dispose();
    super.dispose();
  }

  void save() {
    final text = servings.text.trim();
    final count = text.isEmpty ? null : int.tryParse(text);
    if (kind == MealKind.recipe && recipeId == null) {
      setState(() => error = 'Choose a recipe first');
    } else if (kind == MealKind.recipe &&
        text.isNotEmpty &&
        (count == null || count <= 0)) {
      setState(() => error = 'Servings must be a positive whole number');
    } else {
      Navigator.pop(
        context,
        _SlotChoice(
          kind,
          recipeId: kind == MealKind.recipe ? recipeId : null,
          servings: kind == MealKind.recipe ? count : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) Text(error!),
        Wrap(
          children: [
            for (final option in MealKind.values)
              _button(option.name, () => setState(() => kind = option)),
          ],
        ),
        if (kind == MealKind.recipe) ...[
          for (final recipe in widget.recipes)
            _button(
              '${recipe.id == recipeId ? '✓ ' : ''}${recipe.title}',
              () => setState(() => recipeId = recipe.id),
              key: Key('recipe-${recipe.id}'),
            ),
          AdaptiveField(
            key: const Key('slot-servings'),
            label: 'Servings override',
            controller: servings,
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
    final actions = <Widget>[
      if (widget.existing != null)
        _button(
          'Clear',
          () => Navigator.pop(context, _SlotChoice(kind, clear: true)),
          key: const Key('clear-slot'),
        ),
      _button('Cancel', () => Navigator.pop(context)),
      _button('Save', save, key: const Key('save-slot')),
    ];
    return AdaptiveDialog(
      title: widget.slot,
      content: choices,
      actions: actions,
    );
  }
}
