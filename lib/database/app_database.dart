import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../core/utils/ids.dart';
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          // v2: older database files were missing some columns/tables.
          if (from < 2) await _repairSchema(migrator);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

extension on AppDatabase {
  /// Adds any table or column that exists in the code but not in the file.
  /// Never deletes or changes existing data. New NOT NULL columns get a
  /// default (0 or empty text) so existing rows stay valid.
  Future<void> _repairSchema(Migrator migrator) async {
    for (final table in allTables) {
      final name = table.actualTableName;
      final rows = await customSelect('PRAGMA table_info("$name")').get();

      if (rows.isEmpty) {
        await migrator.createTable(table);
        continue;
      }

      final existing = rows.map((r) => r.read<String>('name')).toSet();
      for (final column in table.$columns) {
        if (existing.contains(column.name)) continue;

        final isText = column.type == DriftSqlType.string;
        final sqlType = isText ? 'TEXT' : 'INTEGER';
        final rule = column.$nullable
            ? ''
            : (isText ? " NOT NULL DEFAULT ''" : ' NOT NULL DEFAULT 0');
        await customStatement(
          'ALTER TABLE "$name" ADD COLUMN "${column.name}" $sqlType$rule',
        );
      }
    }
  }
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