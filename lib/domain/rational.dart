/// Exact rational number with 64-bit int parts (no float drift).
///
/// ponytail: int overflow ceiling is far beyond recipe quantities; swap parts
/// to BigInt if imports ever need it.
class Rational implements Comparable<Rational> {
  factory Rational(int numerator, [int denominator = 1]) {
    if (denominator == 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must not be 0');
    }
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final g = _gcd(numerator.abs(), denominator);
    return Rational._(numerator ~/ g, denominator ~/ g);
  }

  const Rational._(this.numerator, this.denominator);

  static const Rational zero = Rational._(0, 1);
  static const Rational one = Rational._(1, 1);

  final int numerator;
  final int denominator;

  /// Parses `3`, `1/2`, `2 1/2`, `-1 1/2`, and plain decimals like `0.25`.
  /// Throws [FormatException] on anything else.
  factory Rational.parse(String input) {
    final s = input.trim();
    final mixed = RegExp(r'^(-?)(\d+)\s+(\d+)/(\d+)$').firstMatch(s);
    if (mixed != null) {
      final whole = int.parse(mixed[2]!);
      final den = int.parse(mixed[4]!);
      if (den == 0) throw FormatException('zero denominator', input);
      final value = Rational(whole * den + int.parse(mixed[3]!), den);
      return mixed[1] == '-' ? -value : value;
    }
    final frac = RegExp(r'^(-?\d+)/(\d+)$').firstMatch(s);
    if (frac != null) {
      final den = int.parse(frac[2]!);
      if (den == 0) throw FormatException('zero denominator', input);
      return Rational(int.parse(frac[1]!), den);
    }
    final dec = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(s);
    if (dec != null) {
      final digits = dec[3] ?? '';
      var den = 1;
      for (var i = 0; i < digits.length; i++) {
        den *= 10;
      }
      final n = int.parse('${dec[2]}$digits');
      return Rational(dec[1] == '-' ? -n : n, den);
    }
    throw FormatException('not a quantity', input);
  }

  bool get isZero => numerator == 0;
  bool get isNegative => numerator < 0;

  Rational operator +(Rational o) => Rational(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );

  Rational operator -(Rational o) => this + (-o);
  Rational operator -() => Rational._(-numerator, denominator);

  Rational operator *(Rational o) =>
      Rational(numerator * o.numerator, denominator * o.denominator);

  Rational operator /(Rational o) {
    if (o.isZero) throw ArgumentError.value(o, 'o', 'division by zero');
    return Rational(numerator * o.denominator, denominator * o.numerator);
  }

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  /// Display form: `3`, `1/2`, `2 1/2`, `-1 1/2`.
  @override
  String toString() {
    if (denominator == 1) return '$numerator';
    final abs = numerator.abs();
    final whole = abs ~/ denominator;
    final rem = abs % denominator;
    final sign = numerator < 0 ? '-' : '';
    return whole == 0
        ? '$sign$rem/$denominator'
        : '$sign$whole $rem/$denominator';
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a == 0 ? 1 : a;
  }
}
