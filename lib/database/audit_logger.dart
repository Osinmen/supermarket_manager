import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_provider.dart';

class AuditLogger {
  AuditLogger(this._db);

  final AppDatabase _db;

  Future<void> log({
    required String action,
    String? userId,
    String? details,
  }) async {
    await _db.into(_db.auditLogs).insert(
          AuditLogsCompanion.insert(
            action: action,
            userId: Value(userId),
            details: Value(details),
          ),
        );
  }
}

final auditLoggerProvider = Provider<AuditLogger>((ref) {
  return AuditLogger(ref.watch(databaseProvider));
});