import 'rational.dart';
import 'unit.dart';

/// User-owned recipe. Ingredient lists are defensively copied and immutable.
class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.servings,
    required List<Ingredient> ingredients,
    this.steps = '',
    List<String> tags = const [],
    this.photoPath,
  }) : ingredients = List.unmodifiable(ingredients),
       tags = List.unmodifiable(tags) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('recipe id and title must not be empty');
    }
    if (servings <= 0) {
      throw ArgumentError.value(servings, 'servings', 'must be positive');
    }
  }

  final String id;
  final String title;
  final int servings;
  final List<Ingredient> ingredients;
  final String steps;
  final List<String> tags;
  final String? photoPath;
}

/// [quantity] == null means "to taste" / absent quantity: never pretend
/// it's zero. [quantity] == 0 is valid as input but omitted from shopping
/// merges. Display name stays as user typed; itemKey is for comparison only.
class Ingredient {
  Ingredient({
    required String item,
    required this.quantity,
    required this.unit,
    this.aisle = '',
  }) : item = item.trim(),
       itemKey = normalizeItemKey(item),
       aisleKey = aisle.trim().toLowerCase() {
    if (itemKey.isEmpty) {
      throw ArgumentError.value(item, 'item', 'must not be empty');
    }
    if (quantity?.isNegative ?? false) {
      throw ArgumentError.value(quantity, 'quantity', 'must not be negative');
    }
  }

  final String item;
  final String itemKey;
  final Rational? quantity;
  final Unit unit;
  final String aisle;
  final String aisleKey;
}

/// Separate slot type makes leftovers/eat-out explicit without recipe IDs.
enum MealKind { recipe, leftovers, eatOut }

class PlannedMeal {
  PlannedMeal({
    required this.date,
    required this.slot,
    required this.kind,
    this.recipeId,
    this.servings,
  }) {
    if (slot.trim().isEmpty) throw ArgumentError.value(slot, 'slot');
    if (kind == MealKind.recipe && (recipeId?.trim().isEmpty ?? true)) {
      throw ArgumentError('recipe slot needs recipeId');
    }
    if (kind != MealKind.recipe && recipeId != null) {
      throw ArgumentError('non-recipe slot cannot reference a recipe');
    }
    if (servings != null && servings! <= 0) {
      throw ArgumentError.value(servings, 'servings', 'must be positive');
    }
  }

  final DateTime date;
  final String slot;
  final MealKind kind;
  final String? recipeId;
  final int? servings;
}

enum StockLocation { pantry, freezer }

class StockLot {
  StockLot({
    required String item,
    required this.quantity,
    required this.unit,
    required this.location,
    this.date,
  }) : item = item.trim(),
       itemKey = normalizeItemKey(item) {
    if (itemKey.isEmpty) {
      throw ArgumentError.value(item, 'item', 'must not be empty');
    }
    if (quantity.isNegative) throw ArgumentError.value(quantity, 'quantity');
  }

  final String item;
  final String itemKey;
  final Rational quantity;
  final Unit unit;
  final StockLocation location;
  final DateTime? date;
}

/// Frozen result of merging one or more planned recipes. Never reads live
/// recipe state once constructed; checked state belongs to later persistence.
class ShoppingLine {
  const ShoppingLine({
    required this.item,
    required this.itemKey,
    required this.quantity,
    required this.unit,
    required this.aisle,
    required this.aisleKey,
  });

  final String item;
  final String itemKey;
  final Rational? quantity;
  final Unit unit;
  final String aisle;
  final String aisleKey;
}

/// Case-insensitive whitespace normalization only: no unreviewed synonyms,
/// singularization, or punctuation stripping that might merge distinct foods.
String normalizeItemKey(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Exact scaling; absent amounts stay absent.
List<Ingredient> scaleRecipe(Recipe recipe, int targetServings) {
  if (targetServings <= 0) {
    throw ArgumentError.value(
      targetServings,
      'targetServings',
      'must be positive',
    );
  }
  final ratio = Rational(targetServings, recipe.servings);
  return List.unmodifiable([
    for (final line in recipe.ingredients)
      Ingredient(
        item: line.item,
        quantity: line.quantity == null ? null : line.quantity! * ratio,
        unit: line.unit,
        aisle: line.aisle,
      ),
  ]);
}

/// Merge identical normalized items within exact-compatible unit families.
/// The first line's display name, aisle and unit win; later values are
/// converted to that unit. Absent amounts remain a *separate* unquantified
/// line, not silently added to a quantified line. Zero amounts are omitted.
/// Output is sorted by normalized aisle, item, family, and quantity presence;
/// Dart's List.sort isn't stable, so original encounter index breaks ties.
List<ShoppingLine> mergeIngredients(Iterable<Ingredient> lines) {
  final merged = <String, ShoppingLine>{};
  for (final line in lines) {
    if (line.quantity?.isZero ?? false) continue;
    final key =
        '${line.itemKey}\u0000${line.unit.family}\u0000${line.quantity == null ? 'unmeasured' : 'measured'}';
    final existing = merged[key];
    if (existing == null) {
      merged[key] = ShoppingLine(
        item: line.item,
        itemKey: line.itemKey,
        quantity: line.quantity,
        unit: line.unit,
        aisle: line.aisle,
        aisleKey: line.aisleKey,
      );
    } else if (existing.quantity != null && line.quantity != null) {
      merged[key] = ShoppingLine(
        item: existing.item,
        itemKey: existing.itemKey,
        quantity:
            existing.quantity! +
            line.unit.convert(line.quantity!, existing.unit),
        unit: existing.unit,
        aisle: existing.aisle,
        aisleKey: existing.aisleKey,
      );
    }
  }

  final entries = merged.values.toList();
  final indices = <ShoppingLine, int>{
    for (var i = 0; i < entries.length; i++) entries[i]: i,
  };
  entries.sort((a, b) {
    for (final n in [
      a.aisleKey.compareTo(b.aisleKey),
      a.itemKey.compareTo(b.itemKey),
      a.unit.family.compareTo(b.unit.family),
      (a.quantity == null ? 0 : 1).compareTo(b.quantity == null ? 0 : 1),
    ]) {
      if (n != 0) return n;
    }
    return indices[a]!.compareTo(indices[b]!);
  });
  return List.unmodifiable(entries);
}
