import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/money.dart';
import 'converters/money_converter.dart';
import 'enums.dart';
import 'tables/audit_logs_table.dart';
import 'tables/catalog_tables.dart';
import 'tables/sales_tables.dart';
import 'tables/stock_movements_table.dart';
import 'tables/users_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Categories,
    Products,
    Sales,
    SaleItems,
    StockMovements,
    AuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {},
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'supermarket',
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode = WAL;');
      },
    ),
  );
}