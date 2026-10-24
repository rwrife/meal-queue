import 'package:flutter_test/flutter_test.dart';
import 'package:mealqueue/domain/meal.dart';
import 'package:mealqueue/domain/rational.dart';
import 'package:mealqueue/domain/unit.dart';

Ingredient ing(
  String item,
  String? qty, [
  String unit = '',
  String aisle = '',
]) => Ingredient(
  item: item,
  quantity: qty == null ? null : Rational.parse(qty),
  unit: Unit.parse(unit),
  aisle: aisle,
);

void main() {
  group('Rational', () {
    test('normalizes and reduces', () {
      expect(Rational(2, 4), Rational(1, 2));
      expect(Rational(1, -2), Rational(-1, 2));
      expect(Rational(0, 5), Rational.zero);
      expect(() => Rational(1, 0), throwsArgumentError);
    });

    test('parses fractions, mixed numbers, decimals', () {
      expect(Rational.parse('1/2'), Rational(1, 2));
      expect(Rational.parse('2 1/2'), Rational(5, 2));
      expect(Rational.parse('-1 1/2'), Rational(-3, 2));
      expect(Rational.parse('0.25'), Rational(1, 4));
      expect(Rational.parse('3'), Rational(3));
      expect(() => Rational.parse('abc'), throwsFormatException);
      expect(() => Rational.parse('1/0'), throwsFormatException);
    });

    test('no float drift', () {
      final tenth = Rational.parse('0.1');
      var sum = Rational.zero;
      for (var i = 0; i < 10; i++) {
        sum += tenth;
      }
      expect(sum, Rational.one);
    });

    test('display as mixed numbers', () {
      expect(Rational(5, 2).toString(), '2 1/2');
      expect(Rational(1, 2).toString(), '1/2');
      expect(Rational(4).toString(), '4');
      expect(Rational(-3, 2).toString(), '-1 1/2');
    });

    test('arithmetic and ordering', () {
      expect(Rational(1, 3) + Rational(1, 6), Rational(1, 2));
      expect(Rational(1, 2) * Rational(2, 3), Rational(1, 3));
      expect(Rational(1, 2) / Rational(1, 4), Rational(2));
      expect(Rational(1, 3).compareTo(Rational(1, 2)), lessThan(0));
      expect(() => Rational.one / Rational.zero, throwsArgumentError);
    });
  });

  group('Unit', () {
    test('parses aliases and keeps unknown words custom', () {
      expect(Unit.parse('Tablespoons'), Unit.tbsp);
      expect(Unit.parse('lbs.'), Unit.lb);
      expect(Unit.parse(''), Unit.none);
      expect(Unit.parse('clove').family, 'custom:clove');
    });

    test('converts inside a family exactly', () {
      expect(Unit.cup.convert(Rational(1), Unit.tsp), Rational(48));
      expect(Unit.tsp.convert(Rational(3), Unit.tbsp), Rational.one);
      expect(Unit.kg.convert(Rational(1, 2), Unit.g), Rational(500));
    });

    test('refuses cross-family conversion', () {
      expect(Unit.cup.isCompatibleWith(Unit.ml), isFalse);
      expect(Unit.g.isCompatibleWith(Unit.oz), isFalse);
      expect(() => Unit.cup.convert(Rational.one, Unit.g), throwsArgumentError);
    });
  });

  group('scaleRecipe', () {
    final recipe = Recipe(
      id: 'r1',
      title: 'Pancakes',
      servings: 4,
      ingredients: [
        ing('flour', '2 1/2', 'cup'),
        ing('baking powder', '1/2', 'tsp'),
        ing('salt', null),
        ing('egg', '0'),
      ],
    );

    test('doubles exactly', () {
      final s = scaleRecipe(recipe, 8);
      expect(s[0].quantity, Rational(5));
      expect(s[1].quantity, Rational.one);
    });

    test('scales down to 1 serving exactly', () {
      final s = scaleRecipe(recipe, 1);
      expect(s[0].quantity, Rational(5, 8));
      expect(s[1].quantity, Rational(1, 8));
    });

    test('scales back up from 1 serving without drift', () {
      final one = Recipe(
        id: 'r1',
        title: 'Pancakes',
        servings: 1,
        ingredients: scaleRecipe(recipe, 1),
      );
      expect(scaleRecipe(one, 4)[0].quantity, Rational(5, 2));
    });

    test('absent and zero quantities survive scaling', () {
      final s = scaleRecipe(recipe, 3);
      expect(s[2].quantity, isNull);
      expect(s[3].quantity, Rational.zero);
    });

    test('rejects non-positive targets', () {
      expect(() => scaleRecipe(recipe, 0), throwsArgumentError);
    });
  });

  group('mergeIngredients', () {
    test('merges same item and unit, case-insensitively', () {
      final out = mergeIngredients([ing('Onion', '1'), ing('onion ', '1/2')]);
      expect(out, hasLength(1));
      expect(out.single.quantity, Rational(3, 2));
    });

    test('converts inside compatible unit family into first unit', () {
      final out = mergeIngredients([
        ing('olive oil', '1', 'tbsp'),
        ing('olive oil', '3', 'tsp'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.unit, Unit.tbsp);
      expect(out.single.quantity, Rational(2));
    });

    test('never merges incompatible units', () {
      final out = mergeIngredients([
        ing('parsley', '1', 'bunch'),
        ing('parsley', '50', 'g'),
        ing('flour', '1', 'cup'),
        ing('flour', '100', 'g'),
        ing('milk', '1', 'cup'),
        ing('milk', '250', 'ml'),
      ]);
      expect(out, hasLength(6));
    });

    test('unmeasured line stays separate from measured line', () {
      final out = mergeIngredients([
        ing('salt', null),
        ing('salt', '1', 'tsp'),
        ing('salt', null),
      ]);
      expect(out, hasLength(2));
      expect(out.where((l) => l.quantity == null), hasLength(1));
    });

    test('zero quantities are dropped', () {
      final out = mergeIngredients([ing('egg', '0'), ing('egg', '2')]);
      expect(out.single.quantity, Rational(2));
    });

    test('sort is deterministic for any input order, aisle first', () {
      final lines = [
        ing('yogurt', '1', 'cup', 'dairy'),
        ing('apple', '2', '', 'produce'),
        ing('butter', '1', 'tbsp', 'dairy'),
        ing('carrot', '3', '', 'produce'),
        ing('rice', '1', 'cup', ''),
      ];
      final forward = mergeIngredients(lines).map((l) => l.itemKey).toList();
      final reversed = mergeIngredients(lines.reversed)
          .map((l) => l.itemKey)
          .toList();
      expect(forward, ['rice', 'butter', 'yogurt', 'apple', 'carrot']);
      expect(reversed, forward);
    });

    test('equal sort keys keep first-seen order (stability)', () {
      final out = mergeIngredients([
        ing('salt', '1', 'tsp'),
        ing('salt', '1', 'kg'),
        ing('salt', '1', 'cup'),
      ]);
      // distinct families sort by family name, deterministic regardless of input
      final again = mergeIngredients([
        ing('salt', '1', 'cup'),
        ing('salt', '1', 'kg'),
        ing('salt', '1', 'tsp'),
      ]);
      expect(out.map((l) => l.unit.family), again.map((l) => l.unit.family));
    });

    test('result is unmodifiable', () {
      final out = mergeIngredients([ing('egg', '1')]);
      expect(() => out.add(out.first), throwsUnsupportedError);
    });
  });

  group('validation', () {
    test('rejects bad recipes, meals, stock', () {
      expect(
        () => Recipe(id: 'x', title: 'T', servings: 0, ingredients: const []),
        throwsArgumentError,
      );
      expect(() => ing('', '1'), throwsArgumentError);
      expect(
        () => PlannedMeal(
          date: DateTime(2026, 1, 1),
          slot: 'dinner',
          kind: MealKind.recipe,
        ),
        throwsArgumentError,
      );
      expect(
        () => PlannedMeal(
          date: DateTime(2026, 1, 1),
          slot: 'dinner',
          kind: MealKind.eatOut,
          recipeId: 'r1',
        ),
        throwsArgumentError,
      );
      expect(
        () => StockLot(
          item: 'peas',
          quantity: Rational(-1),
          unit: Unit.none,
          location: StockLocation.freezer,
        ),
        throwsArgumentError,
      );
    });
  });
}
