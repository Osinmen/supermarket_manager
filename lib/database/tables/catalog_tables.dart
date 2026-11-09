import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import '../converters/money_converter.dart';

class Categories extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get name => text().withLength(min: 1, max: 60).unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_products_name', columns: {#name})
class Products extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get barcode => text().unique()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();

  IntColumn get price => integer().map(const MoneyConverter())();
  IntColumn get cost => integer().map(const MoneyConverter())();

  IntColumn get taxBasisPoints => integer().withDefault(const Constant(0))();
  IntColumn get stockOnHand => integer().withDefault(const Constant(0))();
  IntColumn get reorderLevel => integer().withDefault(const Constant(5))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}