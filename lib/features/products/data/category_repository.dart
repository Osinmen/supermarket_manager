import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../database/app_database.dart';
import '../../../database/audit_logger.dart';
import '../../../database/database_provider.dart';
import '../../auth/domain/app_user.dart';

class CategoryRepository {
  CategoryRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditLogger _audit;

  /// A live list: the screen rebuilds automatically when a category changes.
  Stream<List<Category>> watchAll() {
    return (_db.select(_db.categories)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<Category> create({
    required AppUser actor,
    required String name,
  }) async {
    Permissions.require(actor.role, Permission.manageProducts);
    final clean = _validate(name);

    return _db.transaction(() async {
      final existing = await (_db.select(_db.categories)
            ..where((c) => c.name.lower().equals(clean.toLowerCase())))
          .getSingleOrNull();
      if (existing != null) {
        throw const DuplicateException('That category already exists.');
      }

      final row = await _db
          .into(_db.categories)
          .insertReturning(CategoriesCompanion.insert(name: clean));

      await _audit.log(
        userId: actor.id,
        action: 'category.created',
        details: 'name=$clean',
      );
      return row;
    });
  }

  Future<void> rename({
    required AppUser actor,
    required String id,
    required String newName,
  }) async {
    Permissions.require(actor.role, Permission.manageProducts);
    final clean = _validate(newName);

    await _db.transaction(() async {
      final clash = await (_db.select(_db.categories)
            ..where(
              (c) =>
                  c.name.lower().equals(clean.toLowerCase()) &
                  c.id.equals(id).not(),
            ))
          .getSingleOrNull();
      if (clash != null) {
        throw const DuplicateException('That category already exists.');
      }

      final updated = await (_db.update(_db.categories)
            ..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(name: Value(clean)));
      if (updated == 0) {
        throw const NotFoundException('Category not found.');
      }

      await _audit.log(
        userId: actor.id,
        action: 'category.renamed',
        details: 'id=$id name=$clean',
      );
    });
  }

  String _validate(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 60) {
      throw const ValidationException(
        'Category name must be 1 to 60 characters.',
      );
    }
    return value;
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(
    ref.watch(databaseProvider),
    ref.watch(auditLoggerProvider),
  );
});