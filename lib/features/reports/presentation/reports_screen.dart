import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../database/enums.dart';
import '../../../services/receipt_service.dart';
import '../data/reports_repository.dart' show RecentSale;
import '../data/sales_report_repository.dart';

enum _Tab { summary, products, transactions }

String _label(PaymentMethod m) => m.name[0].toUpperCase() + m.name.substring(1);

String _rangeText(ReportFilter f) {
  final fmt = DateFormat('d MMM yyyy');
  if (f.start == f.end) return fmt.format(f.start);
  return '${fmt.format(f.start)} - ${fmt.format(f.end)}';
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Tab _tab = _Tab.summary;

  Future<void> _pickCustom(ReportFilter current) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
    );
    if (picked != null) {
      ref.read(reportFilterProvider.notifier).custom(picked.start, picked.end);
    }
  }

  Future<void> _openReceipt(RecentSale entry) async {
    final receipt =
        await ref.read(salesReportRepositoryProvider).receiptFor(entry);
    if (!mounted) return;
    final text = ReceiptService.format(receipt);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.sale.receiptNumber),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppTheme.radius,
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                text,
                style: AppTheme.numeric.copyWith(fontSize: 12, height: 1.4),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: text));
              messenger.showSnackBar(
                const SnackBar(content: Text('Receipt copied.')),
              );
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reportFilterProvider);
    final report = ref.watch(salesReportProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            filter: filter,
            onPreset: (p) =>
                ref.read(reportFilterProvider.notifier).choose(p),
            onCustom: () => _pickCustom(filter),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) {
                debugPrint('Reports failed: $e\n$st');
                return const Center(child: Text("Couldn't load the report."));
              },
              data: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Tiles(report: r),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<_Tab>(
                      style: SegmentedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppTheme.radius,
                        ),
                      ),
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(
                          value: _Tab.summary,
                          label: Text('Summary'),
                        ),
                        ButtonSegment(
                          value: _Tab.products,
                          label: Text('Products (${r.products.length})'),
                        ),
                        ButtonSegment(
                          value: _Tab.transactions,
                          label: Text('Transactions (${r.transactions.length})'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: switch (_tab) {
                      _Tab.summary => _SummaryTab(report: r),
                      _Tab.products => _ProductsTab(report: r),
                      _Tab.transactions => _TransactionsTab(
                          report: r,
                          onOpen: _openReceipt,
                        ),
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ filter

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onPreset,
    required this.onCustom,
  });

  final ReportFilter filter;
  final ValueChanged<RangePreset> onPreset;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Reports',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 16),
        Text(
          _rangeText(filter),
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const Spacer(),
        SegmentedButton<RangePreset>(
          style: SegmentedButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: AppTheme.radius),
          ),
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: RangePreset.today, label: Text('Today')),
            ButtonSegment(
              value: RangePreset.yesterday,
              label: Text('Yesterday'),
            ),
            ButtonSegment(value: RangePreset.last7, label: Text('7 days')),
            ButtonSegment(value: RangePreset.month, label: Text('This month')),
          ],
          selected: filter.preset == RangePreset.custom
              ? <RangePreset>{}
              : {filter.preset},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) onPreset(s.first);
          },
        ),
        const SizedBox(width: 8),
        filter.preset == RangePreset.custom
            ? FilledButton.icon(
                onPressed: onCustom,
                icon: const Icon(Icons.date_range, size: 18),
                label: const Text('Custom'),
              )
            : OutlinedButton.icon(
                onPressed: onCustom,
                icon: const Icon(Icons.date_range, size: 18),
                label: const Text('Custom'),
              ),
      ],
    );
  }
}

// ------------------------------------------------------------------- tiles

class _Tiles extends StatelessWidget {
  const _Tiles({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(label: 'REVENUE', value: report.revenue.format()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(label: 'TRANSACTIONS', value: '${report.count}'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(label: 'AVERAGE SALE', value: report.average.format()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(label: 'VAT INCLUDED', value: report.tax.format()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'EST. PROFIT',
            value: report.profit.format(),
            alert: report.profit.isNegative,
          ),
        ),
      ],
    );
  }
}

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
          Text(label, style: _headStyle),
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

const _headStyle = TextStyle(
  color: AppColors.textMuted,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
);

// ----------------------------------------------------------------- summary

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final total = report.revenue.minorUnits;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _TableCard(
            header: const Row(
              children: [
                Expanded(child: Text('DATE', style: _headStyle)),
                SizedBox(
                  width: 110,
                  child: Text('SALES', style: _headStyle, textAlign: TextAlign.right),
                ),
                SizedBox(
                  width: 140,
                  child: Text('REVENUE', style: _headStyle, textAlign: TextAlign.right),
                ),
              ],
            ),
            count: report.days.length,
            empty: 'No days in this range.',
            // Newest day first.
            builder: (i) {
              final d = report.days[report.days.length - 1 - i];
              final quiet = d.count == 0;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEE, d MMM yyyy').format(d.day),
                      style: TextStyle(
                        color: quiet ? AppColors.textMuted : AppColors.navy,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${d.count}',
                      textAlign: TextAlign.right,
                      style: AppTheme.numeric.copyWith(
                        color: quiet ? AppColors.textMuted : AppColors.navy,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      d.total.format(),
                      textAlign: TextAlign.right,
                      style: AppTheme.numeric.copyWith(
                        fontWeight: FontWeight.w700,
                        color: quiet ? AppColors.textMuted : AppColors.navy,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.topCenter,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'Payment methods',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (final m in PaymentMethod.values) ...[
                          _MethodRow(
                            label: _label(m),
                            amount: report.byMethod[m] ?? Money.zero,
                            fraction: total == 0
                                ? 0
                                : (report.byMethod[m]?.minorUnits ?? 0) / total,
                          ),
                          if (m != PaymentMethod.values.last)
                            const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        _KeyValue('Subtotal (before VAT)', report.subtotal.format()),
                        const SizedBox(height: 6),
                        _KeyValue('VAT included', report.tax.format()),
                        if (report.voidedCount > 0) ...[
                          const SizedBox(height: 6),
                          _KeyValue(
                            'Voided sales (not counted)',
                            '${report.voidedCount}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
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

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const Spacer(),
        Text(value, style: AppTheme.numeric.copyWith(fontSize: 13)),
      ],
    );
  }
}

// ---------------------------------------------------------------- products

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    return _TableCard(
      header: const Row(
        children: [
          SizedBox(width: 32, child: Text('#', style: _headStyle)),
          Expanded(child: Text('PRODUCT', style: _headStyle)),
          SizedBox(
            width: 90,
            child: Text('SOLD', style: _headStyle, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 140,
            child: Text('REVENUE', style: _headStyle, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 140,
            child: Text('EST. PROFIT', style: _headStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
      count: report.products.length,
      empty: 'No sales in this range.',
      builder: (i) {
        final p = report.products[i];
        return Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${i + 1}',
                style: AppTheme.numeric.copyWith(color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                '${p.quantity}',
                textAlign: TextAlign.right,
                style: AppTheme.numeric,
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                p.revenue.format(),
                textAlign: TextAlign.right,
                style: AppTheme.numeric.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                p.profit.format(),
                textAlign: TextAlign.right,
                style: AppTheme.numeric.copyWith(
                  color: p.profit.isNegative
                      ? AppColors.danger
                      : AppColors.textMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------ transactions

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab({required this.report, required this.onOpen});

  final SalesReport report;
  final ValueChanged<RecentSale> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TableCard(
      header: const Row(
        children: [
          SizedBox(width: 150, child: Text('RECEIPT', style: _headStyle)),
          SizedBox(width: 150, child: Text('DATE', style: _headStyle)),
          Expanded(child: Text('CASHIER', style: _headStyle)),
          SizedBox(width: 100, child: Text('PAYMENT', style: _headStyle)),
          SizedBox(width: 90, child: Text('STATUS', style: _headStyle)),
          SizedBox(
            width: 130,
            child: Text('TOTAL', style: _headStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
      count: report.transactions.length,
      empty: 'No sales in this range.',
      onTap: (i) => onOpen(report.transactions[i]),
      builder: (i) {
        final t = report.transactions[i];
        final voided = t.sale.status == SaleStatus.voided;
        final muted = voided ? AppColors.textMuted : AppColors.navy;

        return Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                t.sale.receiptNumber,
                style: AppTheme.numeric.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: muted,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                DateFormat('dd MMM, HH:mm').format(t.sale.createdAt),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                t.cashierName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(_label(t.sale.paymentMethod), style: TextStyle(color: muted)),
            ),
            SizedBox(
              width: 90,
              child: Align(
                alignment: Alignment.centerLeft,
                child: voided
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: AppTheme.radius,
                        ),
                        child: const Text(
                          'Voided',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const Text(
                        'Completed',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                t.sale.total.format(),
                textAlign: TextAlign.right,
                style: AppTheme.numeric.copyWith(
                  fontWeight: FontWeight.w700,
                  color: muted,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------ table helper

/// A card with a header row and a scrolling list of rows.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.header,
    required this.count,
    required this.builder,
    required this.empty,
    this.onTap,
  });

  final Widget header;
  final int count;
  final Widget Function(int index) builder;
  final String empty;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: header,
          ),
          const Divider(),
          Expanded(
            child: count == 0
                ? Center(
                    child: Text(
                      empty,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: count,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final row = Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: builder(i),
                      );
                      return onTap == null
                          ? row
                          : InkWell(onTap: () => onTap!(i), child: row);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}