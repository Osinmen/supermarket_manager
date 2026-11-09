import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import 'users_table.dart';

class AuditLogs extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get userId => text().nullable().references(Users, #id)();
  TextColumn get action => text()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}