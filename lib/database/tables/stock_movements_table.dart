import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import '../enums.dart';
import 'catalog_tables.dart';
import 'users_table.dart';

@TableIndex(name: 'idx_stock_movements_product', columns: {#productId})
class StockMovements extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get type => textEnum<StockMovementType>()();
  IntColumn get quantityChange => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}