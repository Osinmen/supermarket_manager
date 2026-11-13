import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/permissions.dart';
import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';
import '../../../database/database_provider.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';

class DayTotal {
  const DayTotal(this.day, this.total, this.count);

  final DateTime day;
  final Money total;
  final int count;
}

class TopProduct {
  const TopProduct(this.name, this.quantity, this.revenue);

  final String name;
  final int quantity;
  final Money revenue;
}

class RecentSale {
  const RecentSale(this.sale, this.cashierName);

  final Sale sale;
  final String cashierName;
}

class DashboardData {
  const DashboardData({
    required this.todayTotal,
    required this.todayCount,
    required this.byMethod,
    required this.week,
    required this.topProducts,
    required this.recent,
    required this.attention,
    required this.lowCount,
    required this.outCount,
    required this.stockValue,
  });

  final Money todayTotal;
  final int todayCount;
  final Map<PaymentMethod, Money> byMethod;

  /// The last 7 days, oldest first, today last.
  final List<DayTotal> week;
  final List<TopProduct> topProducts;
  final List<RecentSale> recent;

  /// Low or out-of-stock products, emptiest first.
  final List<Product> attention;
  final int lowCount;
  final int outCount;

  /// Null when the user isn't allowed to see cost prices.
  final Money? stockValue;

  Money get average =>
      todayCount == 0 ? Money.zero : Money(todayTotal.minorUnits ~/ todayCount);
}

class ReportsRepository {
  ReportsRepository(this._db);

  final AppDatabase _db;

  /// Loads the dashboard, then reloads it whenever sales, sale items or
  /// products change.
  Stream<DashboardData> watchDashboard(AppUser actor) async* {
    yield await _load(actor);

    final updates = _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.sales, _db.saleItems, _db.products]),
    );
    await for (final _ in updates) {
      yield await _load(actor);
    }
  }

  Future<DashboardData> _load(AppUser actor) async {
    // People without report access only ever see their own sales.
    final canSeeAll = actor.can(Permission.viewReports);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = DateTime(now.year, now.month, now.day - 6);

    Expression<bool> inScope() {
      Expression<bool> condition =
          _db.sales.status.equalsValue(SaleStatus.completed);
      if (!canSeeAll) {
        condition = condition & _db.sales.cashierId.equals(actor.id);
      }
      return condition;
    }

    // ---- sales for the last 7 days (also gives us today) ----
    final weekSales = await (_db.select(_db.sales)
          ..where(
            (_) => inScope() & _db.sales.createdAt.isBiggerOrEqualValue(weekStart),
          ))
        .get();

    final week = <DayTotal>[];
    for (var i = 0; i < 7; i++) {
      final start = DateTime(now.year, now.month, now.day - 6 + i);
      final end = DateTime(now.year, now.month, now.day - 6 + i + 1);
      var total = Money.zero;
      var count = 0;
      for (final s in weekSales) {
        if (!s.createdAt.isBefore(start) && s.createdAt.isBefore(end)) {
          total = total + s.total;
          count++;
        }
      }
      week.add(DayTotal(start, total, count));
    }

    final today = weekSales.where((s) => !s.createdAt.isBefore(todayStart));
    var todayTotal = Money.zero;
    final byMethod = {for (final m in PaymentMethod.values) m: Money.zero};
    for (final s in today) {
      todayTotal = todayTotal + s.total;
      byMethod[s.paymentMethod] = byMethod[s.paymentMethod]! + s.total;
    }

    // ---- top sellers today (managers and admins) ----
    final topProducts = <TopProduct>[];
    if (canSeeAll) {
      final itemRows = await (_db.select(_db.saleItems).join([
        innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
      ])
            ..where(
              inScope() & _db.sales.createdAt.isBiggerOrEqualValue(todayStart),
            ))
          .get();

      final qty = <String, int>{};
      final revenue = <String, Money>{};
      final names = <String, String>{};
      for (final row in itemRows) {
        final item = row.readTable(_db.saleItems);
        names[item.productId] = item.productName;
        qty[item.productId] = (qty[item.productId] ?? 0) + item.quantity;
        revenue[item.productId] =
            (revenue[item.productId] ?? Money.zero) + item.lineTotal;
      }

      final ids = qty.keys.toList()
        ..sort((a, b) => revenue[b]!.compareTo(revenue[a]!));
      for (final id in ids.take(5)) {
        topProducts.add(TopProduct(names[id]!, qty[id]!, revenue[id]!));
      }
    }

    // ---- recent sales ----
    final recentRows = await (_db.select(_db.sales).join([
      innerJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
    ])
          ..where(inScope())
          ..orderBy([OrderingTerm.desc(_db.sales.createdAt)])
          ..limit(8))
        .get();
    final recent = [
      for (final row in recentRows)
        RecentSale(
          row.readTable(_db.sales),
          row.readTable(_db.users).fullName,
        ),
    ];

    // ---- stock ----
    final products = await (_db.select(_db.products)
          ..where((p) => p.isActive.equals(true)))
        .get();

    var lowCount = 0;
    var outCount = 0;
    var stockValue = Money.zero;
    final attention = <Product>[];
    for (final p in products) {
      if (p.stockOnHand > 0) stockValue = stockValue + p.cost * p.stockOnHand;
      if (p.stockOnHand <= 0) {
        outCount++;
        attention.add(p);
      } else if (p.stockOnHand <= p.reorderLevel) {
        lowCount++;
        attention.add(p);
      }
    }
    attention.sort((a, b) => a.stockOnHand.compareTo(b.stockOnHand));

    return DashboardData(
      todayTotal: todayTotal,
      todayCount: today.length,
      byMethod: byMethod,
      week: week,
      topProducts: topProducts,
      recent: recent,
      attention: attention.take(8).toList(),
      lowCount: lowCount,
      outCount: outCount,
      stockValue: canSeeAll ? stockValue : null,
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(databaseProvider));
});

final dashboardProvider = StreamProvider.autoDispose<DashboardData>((ref) {
  final user = ref.watch(authControllerProvider);
  if (user == null) return const Stream.empty();
  return ref.watch(reportsRepositoryProvider).watchDashboard(user);
});