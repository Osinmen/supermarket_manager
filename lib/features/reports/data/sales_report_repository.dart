import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/permissions.dart';
import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../pos/data/sale_repository.dart';
import 'reports_repository.dart' show DayTotal, RecentSale;

// ------------------------------------------------------------------ filter

enum RangePreset { today, yesterday, last7, month, custom }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A date range picked on the Reports screen. [start] and [end] are whole
/// days and both are included.
class ReportFilter {
  const ReportFilter(this.preset, this.start, this.end);

  factory ReportFilter.of(RangePreset preset) {
    final today = _dateOnly(DateTime.now());
    switch (preset) {
      case RangePreset.today:
        return ReportFilter(preset, today, today);
      case RangePreset.yesterday:
        final y = DateTime(today.year, today.month, today.day - 1);
        return ReportFilter(preset, y, y);
      case RangePreset.last7:
        return ReportFilter(
          preset,
          DateTime(today.year, today.month, today.day - 6),
          today,
        );
      case RangePreset.month:
        return ReportFilter(preset, DateTime(today.year, today.month), today);
      case RangePreset.custom:
        return ReportFilter(preset, today, today);
    }
  }

  final RangePreset preset;
  final DateTime start;
  final DateTime end;

  DateTime get endExclusive => DateTime(end.year, end.month, end.day + 1);
}

class ReportFilterController extends Notifier<ReportFilter> {
  @override
  ReportFilter build() => ReportFilter.of(RangePreset.last7);

  void choose(RangePreset preset) => state = ReportFilter.of(preset);

  void custom(DateTime start, DateTime end) {
    state = ReportFilter(RangePreset.custom, _dateOnly(start), _dateOnly(end));
  }
}

final reportFilterProvider =
    NotifierProvider<ReportFilterController, ReportFilter>(
  ReportFilterController.new,
);

// -------------------------------------------------------------------- data

class ProductSales {
  const ProductSales({
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.profit,
  });

  final String name;
  final int quantity;
  final Money revenue;

  /// Revenue minus cost, using each product's current cost price.
  final Money profit;
}

class SalesReport {
  const SalesReport({
    required this.revenue,
    required this.tax,
    required this.count,
    required this.profit,
    required this.byMethod,
    required this.days,
    required this.products,
    required this.transactions,
    required this.voidedCount,
  });

  /// Completed sales only.
  final Money revenue;
  final Money tax;
  final int count;
  final Money profit;
  final Map<PaymentMethod, Money> byMethod;
  final List<DayTotal> days;

  /// Best sellers first.
  final List<ProductSales> products;

  /// Newest first. Includes voided sales.
  final List<RecentSale> transactions;
  final int voidedCount;

  Money get subtotal => revenue - tax;
  Money get average =>
      count == 0 ? Money.zero : Money(revenue.minorUnits ~/ count);
}

// -------------------------------------------------------------- repository

class SalesReportRepository {
  SalesReportRepository(this._db);

  final AppDatabase _db;

  /// Loads the report, then reloads whenever sales or products change.
  Stream<SalesReport> watch(AppUser actor, ReportFilter filter) async* {
    yield await _load(actor, filter);

    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.sales, _db.saleItems, _db.products]),
    );
    await for (final _ in updates) {
      yield await _load(actor, filter);
    }
  }

  Future<SalesReport> _load(AppUser actor, ReportFilter filter) async {
    Permissions.require(actor.role, Permission.viewReports);

    final start = filter.start;
    final end = filter.endExclusive;

    Expression<bool> inRange() =>
        _db.sales.createdAt.isBiggerOrEqualValue(start) &
        _db.sales.createdAt.isSmallerThanValue(end);

    // ---- every sale in the range (with cashier name) ----
    final saleRows = await (_db.select(_db.sales).join([
      innerJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
    ])
          ..where(inRange())
          ..orderBy([OrderingTerm.desc(_db.sales.createdAt)]))
        .get();

    final transactions = [
      for (final row in saleRows)
        RecentSale(row.readTable(_db.sales), row.readTable(_db.users).fullName),
    ];

    final completed = [
      for (final t in transactions)
        if (t.sale.status == SaleStatus.completed) t.sale,
    ];

    // ---- totals ----
    var revenue = Money.zero;
    var tax = Money.zero;
    final byMethod = {for (final m in PaymentMethod.values) m: Money.zero};
    for (final s in completed) {
      revenue = revenue + s.total;
      tax = tax + s.tax;
      byMethod[s.paymentMethod] = byMethod[s.paymentMethod]! + s.total;
    }

    // ---- one row per day (days with no sales show as zero) ----
    final days = <DayTotal>[];
    var day = start;
    while (day.isBefore(end) && days.length < 400) {
      final next = DateTime(day.year, day.month, day.day + 1);
      var total = Money.zero;
      var count = 0;
      for (final s in completed) {
        if (!s.createdAt.isBefore(day) && s.createdAt.isBefore(next)) {
          total = total + s.total;
          count++;
        }
      }
      days.add(DayTotal(day, total, count));
      day = next;
    }

    // ---- sales by product (completed sales only) ----
    final itemRows = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
      leftOuterJoin(
        _db.products,
        _db.products.id.equalsExp(_db.saleItems.productId),
      ),
    ])
          ..where(
            inRange() &
                _db.sales.status.equalsValue(SaleStatus.completed),
          ))
        .get();

    final names = <String, String>{};
    final qty = <String, int>{};
    final revenueBy = <String, Money>{};
    final profitBy = <String, Money>{};
    var profit = Money.zero;

    for (final row in itemRows) {
      final item = row.readTable(_db.saleItems);
      final product = row.readTableOrNull(_db.products);
      final cost = (product?.cost ?? Money.zero) * item.quantity;
      final lineProfit = item.lineTotal - cost;

      names[item.productId] = item.productName;
      qty[item.productId] = (qty[item.productId] ?? 0) + item.quantity;
      revenueBy[item.productId] =
          (revenueBy[item.productId] ?? Money.zero) + item.lineTotal;
      profitBy[item.productId] =
          (profitBy[item.productId] ?? Money.zero) + lineProfit;
      profit = profit + lineProfit;
    }

    final ids = qty.keys.toList()
      ..sort((a, b) => revenueBy[b]!.compareTo(revenueBy[a]!));
    final products = [
      for (final id in ids)
        ProductSales(
          name: names[id]!,
          quantity: qty[id]!,
          revenue: revenueBy[id]!,
          profit: profitBy[id]!,
        ),
    ];

    return SalesReport(
      revenue: revenue,
      tax: tax,
      count: completed.length,
      profit: profit,
      byMethod: byMethod,
      days: days,
      products: products,
      transactions: transactions,
      voidedCount: transactions.length - completed.length,
    );
  }

  /// Loads a sale's items so its receipt can be shown again.
  Future<SaleReceipt> receiptFor(RecentSale entry) async {
    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(entry.sale.id)))
        .get();
    return SaleReceipt(
      sale: entry.sale,
      items: items,
      cashierName: entry.cashierName,
    );
  }
}

final salesReportRepositoryProvider = Provider<SalesReportRepository>((ref) {
  return SalesReportRepository(ref.watch(databaseProvider));
});

final salesReportProvider = StreamProvider.autoDispose<SalesReport>((ref) {
  final user = ref.watch(authControllerProvider);
  final filter = ref.watch(reportFilterProvider);
  if (user == null) return const Stream.empty();
  return ref.watch(salesReportRepositoryProvider).watch(user, filter);
});