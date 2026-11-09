import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import '../enums.dart';

class Users extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get username => text().withLength(min: 3, max: 40).unique()();
  TextColumn get fullName => text().withLength(min: 1, max: 80)();
  TextColumn get passwordHash => text()();
  TextColumn get role => textEnum<UserRole>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}