import 'package:flutter/widgets.dart';

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
    final confirmed = await confirmAdaptiveDelete(
      context,
      'Delete ${lot.item}?',
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
      (ctx) => AdaptiveDialog(
        title: '$action ${lot.item} (${lot.unit})',
        controllers: [controller],
        content: AdaptiveField(
          key: const Key('consume-amount'),
          label: 'Amount',
          controller: controller,
          onChanged: parse,
        ),
        actions: [
          AdaptiveButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AdaptiveButton(
            label: action,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    return ok == true ? submitted : null;
  }

  static Future<T?> _dialog<T>(BuildContext context, WidgetBuilder builder) =>
      showAdaptiveDialog<T>(context: context, builder: builder);

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
    return AdaptiveScaffold(
      title: 'Stock',
      body: body,
      onBack: widget.onBack,
      actionLabel: 'Add stock',
      onAction: () => edit(),
    );
  }

  Widget _button(String label, VoidCallback onPressed) =>
      AdaptiveButton(label: label, onPressed: onPressed);
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
      Wrap(
        spacing: 8,
        children: [
          for (final l in StockLocation.values)
            AdaptiveButton(
              label: l.name,
              selected: location == l,
              onPressed: () => _pickLocation(l),
            ),
        ],
      ),
      _button('Save', save),
      _button('Cancel', () => Navigator.pop(context, false)),
    ];
    return AdaptiveSaveRegion(
      onSave: save,
      child: AdaptiveDialog(
        title: 'Stock item',
        content: Column(mainAxisSize: MainAxisSize.min, children: fields),
        actions: const [],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, Key key) =>
      AdaptiveField(key: key, label: label, controller: controller);

  Widget _button(String label, VoidCallback onPressed) =>
      AdaptiveButton(label: label, onPressed: onPressed);
}
