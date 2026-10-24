import 'rational.dart';

/// A measurement unit. Units sharing a [family] convert exactly via [factor]
/// (rational multiple of the family base). Anything else - count words like
/// `clove`, `bunch`, `can`, or a mass vs. a volume - stays its own family, so
/// "1 bunch parsley" and "50 g parsley" are never silently converted.
///
/// ponytail: US<->metric (cup<->ml, oz<->g) is intentionally NOT exact, so it
/// is deliberately absent; add only with a user-visible approximation flag.
class Unit {
  const Unit._(this.symbol, this.family, this.factor);

  /// Unit with no known conversions; compatible only with the same symbol.
  factory Unit.custom(String name) {
    final key = name.trim().toLowerCase();
    return Unit._(key, 'custom:$key', Rational.one);
  }

  /// Maps common spellings to a known unit, otherwise [Unit.custom].
  /// Empty string means "no unit" (a bare count) -> [Unit.none].
  factory Unit.parse(String text) {
    final key = text.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (key.isEmpty) return none;
    return _aliases[key] ?? Unit.custom(key);
  }

  final String symbol;
  final String family;
  final Rational factor;

  static const Unit none = Unit._('', 'count', Rational.one);

  static const Unit tsp = Unit._('tsp', 'us-volume', Rational.one);
  static final Unit tbsp = Unit._('tbsp', 'us-volume', Rational(3));
  static final Unit cup = Unit._('cup', 'us-volume', Rational(48));

  static const Unit ml = Unit._('ml', 'metric-volume', Rational.one);
  static final Unit l = Unit._('l', 'metric-volume', Rational(1000));

  static const Unit g = Unit._('g', 'metric-mass', Rational.one);
  static final Unit kg = Unit._('kg', 'metric-mass', Rational(1000));

  static const Unit oz = Unit._('oz', 'us-mass', Rational.one);
  static final Unit lb = Unit._('lb', 'us-mass', Rational(16));

  static final Map<String, Unit> _aliases = {
    for (final u in [tsp, tbsp, cup, ml, l, g, kg, oz, lb]) u.symbol: u,
    'teaspoon': tsp,
    'teaspoons': tsp,
    'tablespoon': tbsp,
    'tablespoons': tbsp,
    'cups': cup,
    'c': cup,
    'milliliter': ml,
    'milliliters': ml,
    'liter': l,
    'liters': l,
    'litre': l,
    'litres': l,
    'gram': g,
    'grams': g,
    'kilogram': kg,
    'kilograms': kg,
    'ounce': oz,
    'ounces': oz,
    'pound': lb,
    'pounds': lb,
    'lbs': lb,
  };

  /// Whether quantities in [other] can be added to quantities in this unit
  /// with exact rational conversion.
  bool isCompatibleWith(Unit other) => family == other.family;

  /// Converts [quantity] expressed in this unit into [target]. Throws
  /// [ArgumentError] when units are incompatible.
  Rational convert(Rational quantity, Unit target) {
    if (!isCompatibleWith(target)) {
      throw ArgumentError('cannot convert $symbol to ${target.symbol}');
    }
    return quantity * factor / target.factor;
  }

  @override
  bool operator ==(Object other) =>
      other is Unit && symbol == other.symbol && family == other.family;

  @override
  int get hashCode => Object.hash(symbol, family);

  @override
  String toString() => symbol.isEmpty ? '(count)' : symbol;
}
