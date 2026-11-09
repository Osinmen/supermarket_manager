import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import '../converters/money_converter.dart';
import '../enums.dart';
import 'catalog_tables.dart';
import 'users_table.dart';

@TableIndex(name: 'idx_sales_created_at', columns: {#createdAt})
class Sales extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get receiptNumber => text().unique()();
  TextColumn get cashierId => text().references(Users, #id)();

  IntColumn get subtotal => integer().map(const MoneyConverter())();
  IntColumn get discount => integer().map(const MoneyConverter())();
  IntColumn get tax => integer().map(const MoneyConverter())();
  IntColumn get total => integer().map(const MoneyConverter())();
  IntColumn get amountPaid => integer().map(const MoneyConverter())();
  IntColumn get change => integer().map(const MoneyConverter())();

  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  TextColumn get status => textEnum<SaleStatus>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_sale_items_sale', columns: {#saleId})
class SaleItems extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();

  TextColumn get productName => text()();
  TextColumn get barcode => text()();
  IntColumn get unitPrice => integer().map(const MoneyConverter())();

  IntColumn get quantity => integer()();
  IntColumn get lineTotal => integer().map(const MoneyConverter())();

  @override
  Set<Column> get primaryKey => {id};
}