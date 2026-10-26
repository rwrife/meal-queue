import 'package:sqflite/sqflite.dart' show Database;
import 'package:uuid/uuid.dart';

import 'meal.dart';
import 'rational.dart';
import 'unit.dart';

/// Uses the app's existing database; no network or automatic inventory changes.
class StockRepository {
  StockRepository(this.db);
  final Database db;
  static const _ids = Uuid();

  Future<List<StockLot>> list() async {
    final rows = await db.query(
      'stock_lots',
      orderBy: 'item COLLATE NOCASE, id',
    );
    return [for (final row in rows) _fromRow(row)];
  }

  Future<StockLot?> get(String id) async {
    final rows = await db.query(
      'stock_lots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<String> save(StockLot lot) async {
    final id = lot.id.isEmpty ? _ids.v4() : lot.id;
    final values = {
      'item': lot.item,
      'quantity_num': lot.quantity.numerator,
      'quantity_den': lot.quantity.denominator,
      'unit_symbol': lot.unit.symbol,
      'location': lot.location.name,
      'best_by_date': lot.date?.toIso8601String(),
    };
    if (lot.id.isEmpty) {
      await db.insert('stock_lots', {'id': id, ...values});
    } else {
      final count = await db.update(
        'stock_lots',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) throw StateError('Stock lot not found');
    }
    return id;
  }

  Future<void> delete(String id) async {
    final count = await db.delete(
      'stock_lots',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Stock lot not found');
  }

  /// Explicit consumption only. Reject shortages; preserve exact fractions.
  /// A negative delta restores previously consumed quantity on user request.
  Future<StockLot> consume(String id, Rational amount) async {
    if (amount.isZero) {
      throw ArgumentError.value(amount, 'amount', 'must not be zero');
    }
    return db.transaction((txn) async {
      final rows = await txn.query(
        'stock_lots',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Stock lot not found');
      final lot = _fromRow(rows.first);
      final remaining = lot.quantity - amount;
      if (remaining.isNegative) throw StateError('Not enough stock');
      await txn.update(
        'stock_lots',
        {
          'quantity_num': remaining.numerator,
          'quantity_den': remaining.denominator,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return StockLot(
        id: lot.id,
        item: lot.item,
        quantity: remaining,
        unit: lot.unit,
        location: lot.location,
        date: lot.date,
      );
    });
  }

  StockLot _fromRow(Map<String, Object?> row) => StockLot(
    id: row['id'] as String,
    item: row['item'] as String,
    quantity: Rational(row['quantity_num'] as int, row['quantity_den'] as int),
    unit: Unit.parse(row['unit_symbol'] as String),
    location: StockLocation.values.byName(row['location'] as String),
    date: row['best_by_date'] == null
        ? null
        : DateTime.parse(row['best_by_date'] as String),
  );
}
