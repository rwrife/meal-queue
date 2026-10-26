import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;

import '../app/adaptive.dart';
import '../domain/meal.dart';
import '../domain/rational.dart';
import '../domain/stock_repository.dart';
import '../domain/unit.dart';

/// Loose pantry/freezer/fridge stock log. Decrement happens only through the
/// explicit Consume action; nothing is deducted automatically.
class StockScreen extends StatefulWidget {
  const StockScreen({required this.repository, this.onBack, super.key});
  final StockRepository repository;
  final VoidCallback? onBack;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<StockLot> lots = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final rows = await widget.repository.list();
      if (!mounted) return;
      setState(() {
        lots = rows;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> edit([StockLot? lot]) async {
    Widget builder(BuildContext ctx) =>
        _StockEditorSheet(repository: widget.repository, lot: lot);
    final saved = await _dialog<bool>(context, builder);
    if (saved == true) reload();
  }

  Future<void> remove(StockLot lot) async {
    final confirmed = await _dialog<bool>(
      context,
      (ctx) => Adaptively(
        ios: (_) => CupertinoAlertDialog(
          title: Text('Delete ${lot.item}?'),
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
        android: (_) => material.AlertDialog(
          title: Text('Delete ${lot.item}?'),
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
        windows: (_) => fluent.ContentDialog(
          title: Text('Delete ${lot.item}?'),
          actions: [
            fluent.Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            fluent.Button(
              child: const Text('Delete'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.delete(lot.id);
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> changeQuantity(StockLot lot, {required bool restore}) async {
    final amount = await _askQuantity(lot, restore: restore);
    if (amount == null) return;
    if (amount.compareTo(Rational.zero) <= 0) {
      if (mounted) setState(() => error = 'Enter a positive amount');
      return;
    }
    try {
      await widget.repository.consume(lot.id, restore ? -amount : amount);
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<Rational?> _askQuantity(StockLot lot, {required bool restore}) async {
    final action = restore ? 'Restore' : 'Consume';
    final controller = TextEditingController();
    var submitted = Rational.zero;
    void parse(String value) {
      try {
        submitted = Rational.parse(value);
      } on FormatException {
        submitted = Rational.zero;
      }
    }

    final ok = await _dialog<bool>(
      context,
      (ctx) => Adaptively(
        ios: (_) => CupertinoAlertDialog(
          title: Text('$action ${lot.item} (${lot.unit})'),
          content: Column(
            children: [
              CupertinoTextField(
                key: const Key('consume-amount'),
                controller: controller,
                placeholder: 'Amount',
                onChanged: parse,
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: Text(action),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
        android: (_) => material.AlertDialog(
          title: Text('$action ${lot.item} (${lot.unit})'),
          content: material.TextField(
            key: const Key('consume-amount'),
            controller: controller,
            decoration: const material.InputDecoration(labelText: 'Amount'),
            onChanged: parse,
          ),
          actions: [
            material.TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            material.TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
        windows: (_) => fluent.ContentDialog(
          title: Text('$action ${lot.item} (${lot.unit})'),
          content: fluent.TextBox(
            key: const Key('consume-amount'),
            controller: controller,
            placeholder: 'Amount',
            onChanged: parse,
          ),
          actions: [
            fluent.Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            fluent.FilledButton(
              child: Text(action),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    return ok == true ? submitted : null;
  }

  static Future<T?> _dialog<T>(BuildContext context, WidgetBuilder builder) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS || TargetPlatform.macOS:
        return showCupertinoDialog<T>(context: context, builder: builder);
      case TargetPlatform.android || TargetPlatform.fuchsia:
        return material.showDialog<T>(context: context, builder: builder);
      case TargetPlatform.windows || TargetPlatform.linux:
        return fluent.showDialog<T>(context: context, builder: builder);
    }
  }

  String _label(StockLot lot) {
    final parts = [
      lot.quantity.toString(),
      lot.unit.symbol.isEmpty ? null : lot.unit.symbol,
      lot.item,
      lot.location.name,
      if (lot.date != null)
        'best by ${lot.date!.toIso8601String().substring(0, 10)}',
      if (useFirst(lot, lots)) 'use first',
    ];
    return parts.whereType<String>().join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final content = loading
        ? const Center(child: Text('Loading stock…'))
        : lots.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No stock logged'),
                _button('Add stock', () => edit()),
              ],
            ),
          )
        : ListView(
            key: const Key('stock-list'),
            children: [
              for (final lot in lots)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(_label(lot), key: Key('stock-${lot.id}')),
                      _button(
                        'Consume',
                        () => changeQuantity(lot, restore: false),
                      ),
                      _button(
                        'Restore',
                        () => changeQuantity(lot, restore: true),
                      ),
                      _button('Edit', () => edit(lot)),
                      _button('Delete', () => remove(lot)),
                    ],
                  ),
                ),
            ],
          );
    final body = Column(
      children: [
        if (error != null) Text('Storage error: $error'),
        Expanded(child: content),
      ],
    );
    return Adaptively(
      ios: (_) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Stock'),
          leading: widget.onBack == null
              ? null
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: widget.onBack,
                  child: const Text('Back'),
                ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => edit(),
            child: const Icon(CupertinoIcons.add),
          ),
        ),
        child: SafeArea(child: body),
      ),
      android: (_) => material.Scaffold(
        appBar: material.AppBar(
          title: const Text('Stock'),
          leading: widget.onBack == null
              ? null
              : material.BackButton(onPressed: widget.onBack),
          actions: [
            material.IconButton(
              tooltip: 'Add stock',
              onPressed: () => edit(),
              icon: const Icon(material.Icons.add),
            ),
          ],
        ),
        body: body,
      ),
      windows: (_) => fluent.NavigationView(
        content: fluent.ScaffoldPage(
          header: fluent.PageHeader(
            title: const Text('Stock'),
            commandBar: fluent.CommandBar(
              primaryItems: [
                if (widget.onBack != null)
                  fluent.CommandBarButton(
                    icon: const Icon(fluent.FluentIcons.back),
                    label: const Text('Back'),
                    onPressed: widget.onBack,
                  ),
                fluent.CommandBarButton(
                  icon: const Icon(fluent.FluentIcons.add),
                  label: const Text('Add stock'),
                  onPressed: () => edit(),
                ),
              ],
            ),
          ),
          content: body,
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onPressed) => Adaptively(
    ios: (_) => CupertinoButton(onPressed: onPressed, child: Text(label)),
    android: (_) =>
        material.TextButton(onPressed: onPressed, child: Text(label)),
    windows: (_) => fluent.Button(onPressed: onPressed, child: Text(label)),
  );
}

class _StockEditorSheet extends StatefulWidget {
  const _StockEditorSheet({required this.repository, this.lot});
  final StockRepository repository;
  final StockLot? lot;

  @override
  State<_StockEditorSheet> createState() => _StockEditorSheetState();
}

class _StockEditorSheetState extends State<_StockEditorSheet> {
  late final item = TextEditingController(text: widget.lot?.item ?? '');
  late final quantity = TextEditingController(
    text: widget.lot?.quantity.toString() ?? '',
  );
  late final unit = TextEditingController(text: widget.lot?.unit.symbol ?? '');
  late final date = TextEditingController(
    text: widget.lot?.date?.toIso8601String().substring(0, 10) ?? '',
  );
  late StockLocation location = widget.lot?.location ?? StockLocation.pantry;
  String? error;

  @override
  void dispose() {
    item.dispose();
    quantity.dispose();
    unit.dispose();
    date.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      final inputDate = date.text.trim();
      final parsedDate = inputDate.isEmpty ? null : DateTime.parse(inputDate);
      if (parsedDate != null &&
          (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(inputDate) ||
              parsedDate.toIso8601String().substring(0, 10) != inputDate)) {
        throw const FormatException('Date must be a valid YYYY-MM-DD');
      }
      final lot = StockLot(
        id: widget.lot?.id ?? '',
        item: item.text,
        quantity: Rational.parse(quantity.text),
        unit: Unit.parse(unit.text),
        location: location,
        date: parsedDate,
      );
      await widget.repository.save(lot);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = 'Check item and amount: $e');
    }
  }

  void _pickLocation(StockLocation value) => setState(() => location = value);

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      if (error != null) Text(error!),
      _field('Item', item, const Key('stock-item')),
      _field('Amount', quantity, const Key('stock-quantity')),
      _field('Unit', unit, const Key('stock-unit')),
      _field(
        'Best-by date (YYYY-MM-DD, optional)',
        date,
        const Key('stock-date'),
      ),
      Adaptively(
        ios: (_) => CupertinoSegmentedControl<StockLocation>(
          children: {for (final l in StockLocation.values) l: Text(l.name)},
          groupValue: location,
          onValueChanged: _pickLocation,
        ),
        android: (_) => material.SegmentedButton<StockLocation>(
          segments: [
            for (final l in StockLocation.values)
              material.ButtonSegment(value: l, label: Text(l.name)),
          ],
          selected: {location},
          onSelectionChanged: (values) => _pickLocation(values.first),
        ),
        windows: (_) => Wrap(
          spacing: 8,
          children: [
            for (final l in StockLocation.values)
              fluent.ToggleButton(
                checked: location == l,
                onChanged: (_) => _pickLocation(l),
                child: Text(l.name),
              ),
          ],
        ),
      ),
      _button('Save', save),
      _button('Cancel', () => Navigator.pop(context, false)),
    ];
    return Adaptively(
      ios: (_) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Stock item')),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: fields),
        ),
      ),
      android: (_) => material.Scaffold(
        appBar: material.AppBar(title: const Text('Stock item')),
        body: ListView(padding: const EdgeInsets.all(16), children: fields),
      ),
      windows: (_) => fluent.ContentDialog(
        title: const Text('Stock item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: fields),
        actions: const [],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, Key key) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Adaptively(
          ios: (_) => CupertinoTextField(
            key: key,
            controller: controller,
            placeholder: label,
          ),
          android: (_) => material.TextField(
            key: key,
            controller: controller,
            decoration: material.InputDecoration(labelText: label),
          ),
          windows: (_) => fluent.TextBox(
            key: key,
            controller: controller,
            placeholder: label,
          ),
        ),
      );

  Widget _button(String label, VoidCallback onPressed) => Adaptively(
    ios: (_) => CupertinoButton(onPressed: onPressed, child: Text(label)),
    android: (_) =>
        material.FilledButton(onPressed: onPressed, child: Text(label)),
    windows: (_) =>
        fluent.FilledButton(onPressed: onPressed, child: Text(label)),
  );
}
