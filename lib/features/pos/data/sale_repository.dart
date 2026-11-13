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
import '../domain/cart_item.dart';

typedef SaleLine = ({String productId, int quantity});

class SaleReceipt {
  const SaleReceipt({
    required this.sale,
    required this.items,
    required this.cashierName,
  });

  final Sale sale;
  final List<SaleItem> items;
  final String cashierName;
}

class SaleRepository {
  SaleRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditLogger _audit;

  /// Saves a sale. Everything happens in one transaction: the sale, its
  /// items, the stock changes and the ledger entries all succeed together
  /// or not at all.
  ///
  /// Prices and VAT are read from the database here, never trusted from the
  /// screen. [expectedTotal] is what the cashier saw; if it no longer matches
  /// (a price changed mid-sale) the sale is refused.
  Future<SaleReceipt> completeSale({
    required AppUser actor,
    required List<SaleLine> lines,
    required PaymentMethod method,
    required Money amountPaid,
    required Money expectedTotal,
  }) async {
    Permissions.require(actor.role, Permission.makeSale);

    if (lines.isEmpty) {
      throw const ValidationException('The cart is empty.');
    }
    if (lines.any((l) => l.quantity <= 0)) {
      throw const ValidationException('Quantities must be at least 1.');
    }
    final ids = lines.map((l) => l.productId).toSet().toList();
    if (ids.length != lines.length) {
      throw const ValidationException('A product appears twice in the cart.');
    }

    return _db.transaction(() async {
      final rows = await (_db.select(_db.products)
            ..where((p) => p.id.isIn(ids)))
          .get();
      final byId = {for (final p in rows) p.id: p};

      var total = Money.zero;
      var tax = Money.zero;
      final priced = <({
        Product product,
        int quantity,
        Money lineTotal,
        Money lineTax,
      })>[];

      for (final line in lines) {
        final product = byId[line.productId];
        if (product == null || !product.isActive) {
          throw const NotFoundException(
            'A product in this sale is no longer available.',
          );
        }
        if (product.stockOnHand < line.quantity) {
          throw ValidationException(
            'Only ${product.stockOnHand} of "${product.name}" in stock.',
          );
        }

        final lineTotal = product.price * line.quantity;
        final lineTax = taxIncludedIn(lineTotal, product.taxBasisPoints);
        total = total + lineTotal;
        tax = tax + lineTax;
        priced.add((
          product: product,
          quantity: line.quantity,
          lineTotal: lineTotal,
          lineTax: lineTax,
        ));
      }

      if (total != expectedTotal) {
        throw const ValidationException(
          'A price changed while you were selling. '
          'Review the cart and try again.',
        );
      }

      // Cash can be more than the total (change is given back). Card and
      // transfer always pay the exact total.
      final paid = method == PaymentMethod.cash ? amountPaid : total;
      if (paid < total) {
        throw const ValidationException(
          'The amount received is less than the total.',
        );
      }
      final change = paid - total;

      final receiptNumber = await _nextReceiptNumber();

      final sale = await _db.into(_db.sales).insertReturning(
            SalesCompanion.insert(
              receiptNumber: receiptNumber,
              cashierId: actor.id,
              subtotal: total - tax,
              discount: Money.zero,
              tax: tax,
              total: total,
              amountPaid: paid,
              change: change,
              paymentMethod: method,
              status: SaleStatus.completed,
            ),
          );

      final items = <SaleItem>[];
      for (final line in priced) {
        final product = line.product;

        items.add(
          await _db.into(_db.saleItems).insertReturning(
                SaleItemsCompanion.insert(
                  saleId: sale.id,
                  productId: product.id,
                  productName: product.name,
                  barcode: product.barcode,
                  unitPrice: product.price,
                  quantity: line.quantity,
                  lineTotal: line.lineTotal,
                  taxBasisPoints: product.taxBasisPoints,
                  tax: line.lineTax,
                ),
              ),
        );

        await (_db.update(_db.products)..where((p) => p.id.equals(product.id)))
            .write(
          ProductsCompanion(
            stockOnHand: Value(product.stockOnHand - line.quantity),
            updatedAt: Value(DateTime.now()),
          ),
        );

        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: product.id,
                type: StockMovementType.sale,
                quantityChange: -line.quantity,
                userId: actor.id,
                referenceId: Value(sale.id),
                note: Value('Sale $receiptNumber'),
              ),
            );
      }

      await _audit.log(
        userId: actor.id,
        action: 'sale.completed',
        details: 'receipt=$receiptNumber total=${total.format()} '
            'method=${method.name}',
      );

      return SaleReceipt(
        sale: sale,
        items: items,
        cashierName: actor.fullName,
      );
    });
  }

  /// R261113-0007 = 7th sale on 13 Nov 2026. The count includes voided
  /// sales, so a number is never reused.
  Future<String> _nextReceiptNumber() async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);

    final count = countAll();
    final query = _db.selectOnly(_db.sales)
      ..addColumns([count])
      ..where(_db.sales.createdAt.isBiggerOrEqualValue(dayStart));
    final soFar = await query.map((row) => row.read(count)).getSingle();

    String two(int n) => n.toString().padLeft(2, '0');
    final sequence = ((soFar ?? 0) + 1).toString().padLeft(4, '0');
    return 'R${two(now.year % 100)}${two(now.month)}${two(now.day)}-$sequence';
  }
}

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository(
    ref.watch(databaseProvider),
    ref.watch(auditLoggerProvider),
  );
});