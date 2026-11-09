import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';
import '../../../database/audit_logger.dart';
import '../../../database/database_provider.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';

class ProductRepository {
  ProductRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditLogger _audit;

  static final _barcodePattern = RegExp(r'^\S{1,50}$');

  // ---------------------------------------------------------------- reads

  /// The scanner's hot path. `barcode` has a unique index, so this lookup
  /// stays instant even with 100,000 products.
  /// Returns null when nothing matches or the product is deactivated.
  Future<Product?> findByBarcode(String barcode) {
    return (_db.select(_db.products)
          ..where(
            (p) =>
                p.barcode.equals(barcode.trim()) & p.isActive.equals(true),
          ))
        .getSingleOrNull();
  }

  Future<Product?> getById(String id) {
    return (_db.select(_db.products)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// A live list for the products screen and the POS search box.
  /// Searches name and barcode. Deactivated products are hidden unless
  /// `includeInactive` is true (the management screen shows them).
  Stream<List<Product>> watch({
    String search = '',
    bool includeInactive = false,
  }) {
    final q = _cleanSearch(search);

    final query = _db.select(_db.products)
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    query.where((p) {
      Expression<bool> condition = const Constant(true);
      if (!includeInactive) {
        condition = condition & p.isActive.equals(true);
      }
      if (q.isNotEmpty) {
        condition =
            condition & (p.name.like('%$q%') | p.barcode.like('%$q%'));
      }
      return condition;
    });

    return query.watch();
  }

  // --------------------------------------------------------------- writes

  Future<Product> create({
    required AppUser actor,
    required String barcode,
    required String name,
    required Money price,
    required Money cost,
    String? categoryId,
    int taxBasisPoints = 0,
    int openingStock = 0,
    int reorderLevel = 5,
  }) async {
    Permissions.require(actor.role, Permission.manageProducts);

    final cleanBarcode = _validateBarcode(barcode);
    final cleanName = _validateName(name);
    _validatePrice(price);
    _validateCost(cost);
    _validateTax(taxBasisPoints);
    _validateNotNegative(openingStock, 'Opening stock');
    _validateNotNegative(reorderLevel, 'Reorder level');

    return _db.transaction(() async {
      await _ensureBarcodeFree(cleanBarcode);
      await _ensureCategoryExists(categoryId);

      final row = await _db.into(_db.products).insertReturning(
            ProductsCompanion.insert(
              barcode: cleanBarcode,
              name: cleanName,
              price: price,
              cost: cost,
              categoryId: Value(categoryId),
              taxBasisPoints: Value(taxBasisPoints),
              stockOnHand: Value(openingStock),
              reorderLevel: Value(reorderLevel),
            ),
          );

      // Stock must always be explainable by the ledger, so opening stock
      // gets a ledger entry too.
      if (openingStock > 0) {
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: row.id,
                type: StockMovementType.adjustment,
                quantityChange: openingStock,
                userId: actor.id,
                note: const Value('Opening stock'),
              ),
            );
      }

      await _audit.log(
        userId: actor.id,
        action: 'product.created',
        details: 'barcode=$cleanBarcode name=$cleanName '
            'price=${price.format()}',
      );
      return row;
    });
  }

  /// Edits product details. Stock is NOT editable here: it only changes
  /// through the stock repository, so every change lands in the ledger.
  Future<Product> update({
    required AppUser actor,
    required String id,
    required String barcode,
    required String name,
    required Money price,
    required Money cost,
    String? categoryId,
    int taxBasisPoints = 0,
    int reorderLevel = 5,
  }) async {
    Permissions.require(actor.role, Permission.manageProducts);

    final cleanBarcode = _validateBarcode(barcode);
    final cleanName = _validateName(name);
    _validatePrice(price);
    _validateCost(cost);
    _validateTax(taxBasisPoints);
    _validateNotNegative(reorderLevel, 'Reorder level');

    return _db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) {
        throw const NotFoundException('Product not found.');
      }

      // Changing money fields needs a stronger permission than editing a name.
      final moneyChanged = existing.price != price || existing.cost != cost;
      if (moneyChanged) {
        Permissions.require(actor.role, Permission.changePrices);
      }

      await _ensureBarcodeFree(cleanBarcode, exceptId: id);
      await _ensureCategoryExists(categoryId);

      await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          barcode: Value(cleanBarcode),
          name: Value(cleanName),
          price: Value(price),
          cost: Value(cost),
          categoryId: Value(categoryId),
          taxBasisPoints: Value(taxBasisPoints),
          reorderLevel: Value(reorderLevel),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _audit.log(
        userId: actor.id,
        action: moneyChanged ? 'product.price_change' : 'product.updated',
        details: moneyChanged
            ? 'id=$id price ${existing.price.format()} -> ${price.format()}, '
                'cost ${existing.cost.format()} -> ${cost.format()}'
            : 'id=$id name=$cleanName',
      );

      return (await getById(id))!;
    });
  }

  /// Products are deactivated, never deleted: old sales still point at them.
  Future<void> setActive({
    required AppUser actor,
    required String id,
    required bool isActive,
  }) async {
    Permissions.require(actor.role, Permission.manageProducts);

    await _db.transaction(() async {
      final updated =
          await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (updated == 0) {
        throw const NotFoundException('Product not found.');
      }
      await _audit.log(
        userId: actor.id,
        action: isActive ? 'product.activated' : 'product.deactivated',
        details: 'id=$id',
      );
    });
  }

  // ------------------------------------------------------------ internals

  Future<void> _ensureBarcodeFree(String barcode, {String? exceptId}) async {
    final clash = await (_db.select(_db.products)
          ..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
    if (clash != null && clash.id != exceptId) {
      throw DuplicateException(
        'Barcode $barcode is already used by "${clash.name}".',
      );
    }
  }

  Future<void> _ensureCategoryExists(String? categoryId) async {
    if (categoryId == null) return;
    final found = await (_db.select(_db.categories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingleOrNull();
    if (found == null) {
      throw const ValidationException('That category no longer exists.');
    }
  }

  /// Strips LIKE wildcards so typing "%" or "_" can't act as a pattern.
  String _cleanSearch(String input) =>
      input.trim().replaceAll(RegExp(r'[%_\\]'), '');

  String _validateBarcode(String input) {
    final value = input.trim();
    if (!_barcodePattern.hasMatch(value)) {
      throw const ValidationException(
        'Barcode must be 1 to 50 characters with no spaces.',
      );
    }
    return value;
  }

  String _validateName(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 120) {
      throw const ValidationException(
        'Product name must be 1 to 120 characters.',
      );
    }
    return value;
  }

  void _validatePrice(Money price) {
    if (price <= Money.zero) {
      throw const ValidationException('Price must be greater than zero.');
    }
  }

  void _validateCost(Money cost) {
    if (cost.isNegative) {
      throw const ValidationException("Cost can't be negative.");
    }
  }

  void _validateTax(int basisPoints) {
    if (basisPoints < 0 || basisPoints > 10000) {
      throw const ValidationException('Tax must be between 0% and 100%.');
    }
  }

  void _validateNotNegative(int value, String label) {
    if (value < 0) {
      throw ValidationException("$label can't be negative.");
    }
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    ref.watch(databaseProvider),
    ref.watch(auditLoggerProvider),
  );
});