import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/database_schema.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/stock_repository.dart';
import 'package:mealqueue/domain/unit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Database db;
  late StockRepository stock;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('meal-queue-stock-');
    db = await databaseFactoryFfi.openDatabase(
      '${root.path}/stock.db',
      options: OpenDatabaseOptions(
        version: AppDatabaseSchema.currentVersion,
        onCreate: (db, _) => AppDatabaseSchema.createSchema(db),
      ),
    );
    stock = StockRepository(db);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'exact normalized matching; no implicit conversion, empty and zero hidden',
    () {
      final ingredient = Ingredient(
        item: '  BLACK   beans ',
        quantity: Rational(2),
        unit: Unit.parse('can'),
      );
      StockLot lot(String item, Rational amount, Unit unit) => StockLot(
        id: 'a',
        item: item,
        quantity: amount,
        unit: unit,
        location: StockLocation.pantry,
      );
      expect(mayHaveIngredient(ingredient, []), isFalse);
      expect(
        mayHaveIngredient(ingredient, [
          lot('black beans', Rational(1), Unit.parse('can')),
        ]),
        isTrue,
      );
      expect(
        mayHaveIngredient(ingredient, [
          lot('beans', Rational(1), Unit.parse('can')),
        ]),
        isFalse,
      );
      expect(
        mayHaveIngredient(ingredient, [
          lot('black beans', Rational(1), Unit.none),
        ]),
        isFalse,
      );
      expect(
        mayHaveIngredient(ingredient, [
          lot('black beans', Rational.zero, Unit.parse('can')),
        ]),
        isFalse,
      );
      expect(
        mayHaveIngredient(
          Ingredient(item: 'flour', quantity: Rational(1), unit: Unit.g),
          [lot('flour', Rational(1000), Unit.kg)],
        ),
        isFalse,
      );
    },
  );

  test(
    'CRUD, exact decrement, shortage rollback and explicit restore',
    () async {
      final id = await stock.save(
        StockLot(
          item: ' Peas ',
          quantity: Rational(3, 2),
          unit: Unit.kg,
          location: StockLocation.freezer,
          date: DateTime(2026, 11, 2),
        ),
      );
      expect((await stock.get(id))!.date, DateTime(2026, 11, 2));
      expect((await stock.list()).single.itemKey, 'peas');
      final remaining = await stock.consume(id, Rational(1, 2));
      expect(remaining.quantity, Rational(1));
      await expectLater(stock.consume(id, Rational(2)), throwsStateError);
      expect((await stock.get(id))!.quantity, Rational(1));
      expect(
        (await stock.consume(id, Rational(-1, 2))).quantity,
        Rational(3, 2),
      );
      await expectLater(stock.consume(id, Rational.zero), throwsArgumentError);
      await stock.save(
        StockLot(
          id: id,
          item: 'Peas',
          quantity: Rational(1),
          unit: Unit.g,
          location: StockLocation.fridge,
        ),
      );
      expect((await stock.get(id))!.location, StockLocation.fridge);
      expect((await stock.get(id))!.date, null);
      await stock.delete(id);
      expect(await stock.list(), isEmpty);
      await expectLater(stock.delete(id), throwsStateError);
      await expectLater(stock.consume(id, Rational(1)), throwsStateError);
    },
  );

  test(
    'dated use-first is conservative and respects normalized item and unit',
    () {
      StockLot lot(String id, DateTime? date, {Rational? amount}) => StockLot(
        id: id,
        item: 'Peas',
        quantity: amount ?? Rational(1),
        unit: Unit.kg,
        location: StockLocation.freezer,
        date: date,
      );
      final early = lot('early', DateTime(2026, 1, 1));
      final late = lot('late', DateTime(2026, 2, 1));
      expect(useFirst(early, [early, late]), isTrue);
      expect(useFirst(late, [early, late]), isFalse);
      expect(useFirst(lot('unknown', null), [early]), isFalse);
      expect(
        useFirst(lot('gone', DateTime(2025), amount: Rational.zero), [late]),
        isFalse,
      );
    },
  );
}
