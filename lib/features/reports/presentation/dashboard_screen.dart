import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/reports_repository.dart';

/// ₦1,250,000 -> ₦1.3M, ₦12,500 -> ₦12.5k
String _compact(Money m) {
  final naira = m.minorUnits / 100;
  if (naira >= 1000000) return '₦${(naira / 1000000).toStringAsFixed(1)}M';
  if (naira >= 1000) return '₦${(naira / 1000).toStringAsFixed(1)}k';
  return '₦${naira.round()}';
}

String _label(PaymentMethod m) => m.name[0].toUpperCase() + m.name.substring(1);

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider);
    final data = ref.watch(dashboardProvider);
    if (me == null) return const SizedBox.shrink();

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text("Couldn't load the dashboard.")),
      data: (d) => _Content(data: d, me: me),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.data, required this.me});

  final DashboardData data;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final isManager = d.stockValue != null;
    final firstName = me.fullName.split(' ').first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_greeting()}, $firstName',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: isManager ? "TODAY'S SALES" : 'MY SALES TODAY',
                  value: d.todayTotal.format(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: 'TRANSACTIONS', value: '${d.todayCount}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: 'AVERAGE SALE', value: d.average.format()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: isManager
                    ? _StatTile(
                        label: 'STOCK VALUE (AT COST)',
                        value: d.stockValue!.format(),
                      )
                    : _StatTile(
                        label: 'LOW / OUT OF STOCK',
                        value: '${d.lowCount + d.outCount}',
                        alert: d.lowCount + d.outCount > 0,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isManager) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _Panel(
                      title: 'Last 7 days',
                      child: _WeekChart(days: d.week),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _Panel(
                      title: 'Payments today',
                      child: _PaymentBreakdown(data: d),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _Panel(
                    title: isManager ? 'Recent sales' : 'My recent sales',
                    child: _RecentSales(sales: d.recent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: isManager
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Panel(
                              title: 'Top sellers today',
                              child: _TopSellers(products: d.topProducts),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _Panel(
                                title: 'Needs restocking',
                                trailing: _CountBadge(d.lowCount + d.outCount),
                                child: _Attention(products: d.attention),
                              ),
                            ),
                          ],
                        )
                      : _Panel(
                          title: 'Needs restocking',
                          trailing: _CountBadge(d.lowCount + d.outCount),
                          child: _Attention(products: d.attention),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pieces

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppTheme.radius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTheme.numeric.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: alert ? AppColors.danger : AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: AppTheme.radius,
      ),
      child: Text(
        '$count',
        style: AppTheme.numeric.copyWith(
          color: AppColors.danger,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(message, style: const TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<DayTotal> days;

  @override
  Widget build(BuildContext context) {
    var max = 0;
    for (final d in days) {
      if (d.total.minorUnits > max) max = d.total.minorUnits;
    }

    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        days[i].count == 0 ? '' : _compact(days[i].total),
                        style: AppTheme.numeric.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: max == 0
                            ? 2.0
                            : (120.0 * days[i].total.minorUnits / max)
                                .clamp(2.0, 120.0)
                                .toDouble(),
                        decoration: BoxDecoration(
                          // Today is the active bar, the rest are quiet.
                          color: i == days.length - 1
                              ? AppColors.accent
                              : const Color(0xFFCBD5E1),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        i == days.length - 1
                            ? 'Today'
                            : DateFormat('E').format(days[i].day),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == days.length - 1
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == days.length - 1
                              ? AppColors.navy
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final total = data.todayTotal.minorUnits;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final method in PaymentMethod.values) ...[
            _PaymentRow(
              label: _label(method),
              amount: data.byMethod[method] ?? Money.zero,
              fraction: total == 0
                  ? 0
                  : (data.byMethod[method]?.minorUnits ?? 0) / total,
            ),
            if (method != PaymentMethod.values.last) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final String label;
  final Money amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              amount.format(),
              style: AppTheme.numeric.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(height: 6, color: AppColors.border),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0).toDouble(),
                child: Container(height: 6, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentSales extends StatelessWidget {
  const _RecentSales({required this.sales});

  final List<RecentSale> sales;

  String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay
        ? 'Today, ${DateFormat('HH:mm').format(t)}'
        : DateFormat('dd MMM, HH:mm').format(t);
  }

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) return const _Empty('No sales yet.');

    return Column(
      children: [
        for (var i = 0; i < sales.length; i++) ...[
          if (i > 0) const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sales[i].sale.receiptNumber,
                        style: AppTheme.numeric.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sales[i].cashierName} · ${_when(sales[i].sale.createdAt)}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: AppTheme.radius,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    _label(sales[i].sale.paymentMethod),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 110,
                  child: Text(
                    sales[i].sale.total.format(),
                    textAlign: TextAlign.right,
                    style: AppTheme.numeric.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TopSellers extends StatelessWidget {
  const _TopSellers({required this.products});

  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const _Empty('No sales today yet.');

    return Column(
      children: [
        for (var i = 0; i < products.length; i++) ...[
          if (i > 0) const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: AppTheme.numeric.copyWith(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: Text(
                    products[i].name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${products[i].quantity} sold',
                  style: AppTheme.numeric.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  products[i].revenue.format(),
                  style: AppTheme.numeric.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({required this.products});

  final List<dynamic> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const _Empty('Everything is well stocked.');

    return Column(
      children: [
        for (var i = 0; i < products.length; i++) ...[
          if (i > 0) const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        products[i].name as String,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Reorder at ${products[i].reorderLevel}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StockChip(stock: products[i].stockOnHand as int),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StockChip extends StatelessWidget {
  const _StockChip({required this.stock});

  final int stock;

  @override
  Widget build(BuildContext context) {
    final out = stock <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: out ? AppColors.danger : AppColors.dangerSoft,
        borderRadius: AppTheme.radius,
      ),
      child: Text(
        out ? 'Out' : '$stock left',
        style: TextStyle(
          color: out ? Colors.white : AppColors.danger,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}