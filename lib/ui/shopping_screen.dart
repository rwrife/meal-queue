import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;

import '../app/adaptive.dart';
import '../domain/rational.dart';
import '../domain/recipe_repository.dart';
import '../domain/shopping_repository.dart';
import '../domain/unit.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({required this.recipes, super.key});
  final RecipeRepository recipes;
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  late final store = ShoppingRepository(widget.recipes);
  SavedList? list;
  List<SavedList> history = [];
  String? error;
  DateTime week = DateTime.now();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final current = await store.active();
      final past = await store.history();
      if (mounted) {
        setState(() {
          list = current;
          history = past;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Widget button(String label, VoidCallback action, {Key? key}) => Adaptively(
    ios: (_) =>
        CupertinoButton(key: key, onPressed: action, child: Text(label)),
    android: (_) =>
        material.TextButton(key: key, onPressed: action, child: Text(label)),
    windows: (_) =>
        fluent.Button(key: key, onPressed: action, child: Text(label)),
  );

  Future<void> edit([SavedLine? line]) async {
    final item = TextEditingController(text: line?.item ?? '');
    final amount = TextEditingController(
      text: line?.quantity?.toString() ?? '',
    );
    final unit = TextEditingController(text: line?.unit.symbol ?? '');
    final aisle = TextEditingController(text: line?.aisle ?? '');
    Widget field(TextEditingController controller, String name) => Adaptively(
      ios: (_) => CupertinoTextField(controller: controller, placeholder: name),
      android: (_) => material.TextField(
        controller: controller,
        decoration: material.InputDecoration(labelText: name),
      ),
      windows: (_) => fluent.TextBox(controller: controller, placeholder: name),
    );
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) {
        final form = SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(item, 'Item'),
              field(amount, 'Amount (optional)'),
              field(unit, 'Unit (optional)'),
              field(aisle, 'Aisle (optional)'),
            ],
          ),
        );
        void done() => Navigator.pop(ctx, true);
        return Adaptively(
          ios: (_) => CupertinoAlertDialog(
            title: const Text('Manual item'),
            content: form,
            actions: [
              CupertinoDialogAction(onPressed: done, child: const Text('Save')),
            ],
          ),
          android: (_) => material.AlertDialog(
            title: const Text('Manual item'),
            content: form,
            actions: [
              material.TextButton(onPressed: done, child: const Text('Save')),
            ],
          ),
          windows: (_) => fluent.ContentDialog(
            title: const Text('Manual item'),
            content: form,
            actions: [
              fluent.FilledButton(onPressed: done, child: const Text('Save')),
            ],
          ),
        );
      },
    );
    if (confirmed == true && list != null) {
      await run(() async {
        final quantity = amount.text.trim().isEmpty
            ? null
            : Rational.parse(amount.text);
        await store.saveManual(
          list!.id,
          lineId: line?.id,
          item: item.text,
          quantity: quantity,
          unit: Unit.parse(unit.text.trim()),
          aisle: aisle.text,
        );
      });
    }
    item.dispose();
    amount.dispose();
    unit.dispose();
    aisle.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = list;
    final content = ListView(
      children: [
        if (error != null) Text('Shopping error: $error'),
        Wrap(
          children: [
            button(
              'Previous week',
              () =>
                  setState(() => week = week.subtract(const Duration(days: 7))),
            ),
            Text('Week of ${week.year}-${week.month}-${week.day}'),
            button(
              'Next week',
              () => setState(() => week = week.add(const Duration(days: 7))),
            ),
            button(
              'Generate list',
              () => run(() async {
                await store.generate(week);
              }),
              key: const Key('generate-list'),
            ),
          ],
        ),
        if (current == null) const Text('No active shopping list'),
        if (current != null) ...[
          Text(current.label),
          button('Add item', () => edit()),
          // ponytail: ordering uses a comma-separated aisle list; upgrade to drag handles when needed.
          button('Set aisle order', () async {
            final input = TextEditingController();
            final ok = await showAdaptiveDialog<bool>(
              context: context,
              builder: (ctx) {
                void save() => Navigator.pop(ctx, true);
                return Adaptively(
                  ios: (_) => CupertinoAlertDialog(
                    title: const Text('Aisles, comma separated'),
                    content: CupertinoTextField(controller: input),
                    actions: [
                      CupertinoDialogAction(
                        onPressed: save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  android: (_) => material.AlertDialog(
                    title: const Text('Aisles, comma separated'),
                    content: material.TextField(controller: input),
                    actions: [
                      material.TextButton(
                        onPressed: save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  windows: (_) => fluent.ContentDialog(
                    title: const Text('Aisles, comma separated'),
                    content: fluent.TextBox(controller: input),
                    actions: [
                      fluent.FilledButton(
                        onPressed: save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              },
            );
            if (ok == true) {
              await run(() => store.setAisleOrder(input.text.split(',')));
            }
            input.dispose();
          }),
          for (final line in current.lines)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Adaptively(
                    ios: (_) => CupertinoSwitch(
                      value: line.checked,
                      onChanged: (v) =>
                          run(() => store.check(current.id, line.id, v)),
                    ),
                    android: (_) => material.Checkbox(
                      value: line.checked,
                      onChanged: (v) =>
                          run(() => store.check(current.id, line.id, v!)),
                    ),
                    windows: (_) => fluent.Checkbox(
                      checked: line.checked,
                      onChanged: (v) => run(
                        () => store.check(current.id, line.id, v ?? false),
                      ),
                    ),
                  ),
                  Text(
                    '${line.quantity ?? ''} ${line.unit.symbol} ${line.item} (${line.aisle.isEmpty ? 'Other' : line.aisle})'
                    '${line.stockHint ? ' · Already have stock?' : ''}',
                    key: Key('shopping-${line.id}'),
                  ),
                  if (line.manual) ...[
                    button('Edit ${line.item}', () => edit(line)),
                    button(
                      'Remove ${line.item}',
                      () => run(() => store.removeManual(current.id, line.id)),
                    ),
                  ],
                ],
              ),
            ),
          button(
            'Complete list',
            () => run(() => store.complete(current.id)),
            key: const Key('complete-list'),
          ),
        ],
        const Text('Completed lists'),
        for (final past in history)
          Text(
            '${past.label}: ${past.checkedCount}/${past.lines.length} checked',
          ),
      ],
    );
    return Adaptively(
      ios: (_) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Shopping')),
        child: SafeArea(child: content),
      ),
      android: (_) => material.Scaffold(
        appBar: material.AppBar(title: const Text('Shopping')),
        body: content,
      ),
      windows: (_) => fluent.NavigationView(
        content: fluent.ScaffoldPage(
          header: const fluent.PageHeader(title: Text('Shopping')),
          content: content,
        ),
      ),
    );
  }
}
