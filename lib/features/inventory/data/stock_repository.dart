import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../database/app_database.dart';
import '../../../database/audit_logger.dart';
import '../../../database/database_provider.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';

enum StockLevel { ok, low, out }

/// A product plus its category name, for the inventory grid.
class InventoryItem {
  const InventoryItem(this.product, this.categoryName);

  final Product product;
  final String? categoryName;

  StockLevel get level {
    if (product.stockOnHand <= 0) return StockLevel.out;
    if (product.stockOnHand <= product.reorderLevel) return StockLevel.low;
    return StockLevel.ok;
  }
}

/// One row of a product's stock history.
class StockMovementEntry {
  const StockMovementEntry(this.movement, this.userName);

  final StockMovement movement;
  final String userName;
}

class StockRepository {
  StockRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditLogger _audit;

  /// Live list of every active product with its category name.
  Stream<List<InventoryItem>> watchInventory() {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.products.categoryId),
      ),
    ])
      ..where(_db.products.isActive.equals(true))
      ..orderBy([OrderingTerm.asc(_db.products.name)]);

    return query.watch().map(
          (rows) => rows
              .map(
                (r) => InventoryItem(
                  r.readTable(_db.products),
                  r.readTableOrNull(_db.categories)?.name,
                ),
              )
              .toList(),
        );
  }

  /// Newest first, with the name of the user who made each change.
  Stream<List<StockMovementEntry>> watchMovements(String productId) {
    final query = _db.select(_db.stockMovements).join([
      innerJoin(
        _db.users,
        _db.users.id.equalsExp(_db.stockMovements.userId),
      ),
    ])
      ..where(_db.stockMovements.productId.equals(productId))
      ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)])
      ..limit(200);

    return query.watch().map(
          (rows) => rows
              .map(
                (r) => StockMovementEntry(
                  r.readTable(_db.stockMovements),
                  r.readTable(_db.users).fullName,
                ),
              )
              .toList(),
        );
  }

  /// The only way stock is changed by hand. Updates the product and writes
  /// the ledger entry in one transaction, so the two can never disagree.
  /// Sales and returns go through the sale repository, not here.
  Future<void> record({
    required AppUser actor,
    required String productId,
    required StockMovementType type,
    required int quantityChange,
    String? note,
  }) async {
    Permissions.require(actor.role, Permission.adjustStock);

    if (type != StockMovementType.purchase &&
        type != StockMovementType.adjustment) {
      throw const ValidationException(
        'Sales and returns are recorded at the till, not here.',
      );
    }
    if (quantityChange == 0) {
      throw const ValidationException('Quantity must not be zero.');
    }
    if (type == StockMovementType.purchase && quantityChange < 0) {
      throw const ValidationException('Received stock must be positive.');
    }

    final cleanNote = note?.trim();
    if (quantityChange < 0 && (cleanNote == null || cleanNote.isEmpty)) {
      throw const ValidationException('Give a reason for removing stock.');
    }

    await _db.transaction(() async {
      final product = await (_db.select(_db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      if (product == null) {
        throw const NotFoundException('Product not found.');
      }

      final newStock = product.stockOnHand + quantityChange;
      if (newStock < 0) {
        throw ValidationException(
          'Only ${product.stockOnHand} in stock, '
          "you can't remove ${quantityChange.abs()}.",
        );
      }

      await (_db.update(_db.products)..where((p) => p.id.equals(productId)))
          .write(
        ProductsCompanion(
          stockOnHand: Value(newStock),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _db.into(_db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: productId,
              type: type,
              quantityChange: quantityChange,
              userId: actor.id,
              note: Value(
                (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote,
              ),
            ),
          );

      await _audit.log(
        userId: actor.id,
        action: 'stock.adjusted',
        details: 'product=${product.name} ${type.name} '
            'change=$quantityChange new=$newStock',
      );
    });
  }
}

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(
    ref.watch(databaseProvider),
    ref.watch(auditLoggerProvider),
  );
});

final inventoryProvider = StreamProvider<List<InventoryItem>>((ref) {
  return ref.watch(stockRepositoryProvider).watchInventory();
});

final stockMovementsProvider =
    StreamProvider.family<List<StockMovementEntry>, String>((ref, productId) {
  return ref.watch(stockRepositoryProvider).watchMovements(productId);
});