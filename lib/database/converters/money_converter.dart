import 'package:drift/drift.dart';

import '../../core/utils/money.dart';

class MoneyConverter extends TypeConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromSql(int fromDb) => Money(fromDb);

  @override
  int toSql(Money value) => value.minorUnits;
}