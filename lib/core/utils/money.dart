import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

@immutable
class Money implements Comparable<Money> {
  const Money(this.minorUnits);

  static const zero = Money(0);
  static const currencySymbol = '₦';

  static final _thousands = NumberFormat('#,##0', 'en_US');
  static final _pattern = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');

  final int minorUnits;

  static Money? tryParse(String input) {
    final cleaned =
        input.replaceAll(currencySymbol, '').replaceAll(',', '').trim();
    final match = _pattern.firstMatch(cleaned);
    if (match == null) return null;

    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return Money(whole * 100 + int.parse(fraction));
  }

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);
  Money operator -() => Money(-minorUnits);
  Money operator *(int quantity) => Money(minorUnits * quantity);

  bool operator <(Money other) => minorUnits < other.minorUnits;
  bool operator <=(Money other) => minorUnits <= other.minorUnits;
  bool operator >(Money other) => minorUnits > other.minorUnits;
  bool operator >=(Money other) => minorUnits >= other.minorUnits;

  Money ofBasisPoints(int basisPoints) =>
      Money((minorUnits * basisPoints + 5000) ~/ 10000);

  String format({bool symbol = true}) {
    final abs = minorUnits.abs();
    final whole = _thousands.format(abs ~/ 100);
    final kobo = (abs % 100).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';
    return '$sign${symbol ? currencySymbol : ''}$whole.$kobo';
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => 'Money($minorUnits)';
}