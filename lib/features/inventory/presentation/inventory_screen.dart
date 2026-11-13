import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/category_repository.dart';
import '../../products/data/product_repository.dart';
import '../data/sample_products.dart';
import '../data/stock_repository.dart';
import 'stock_adjustment_dialog.dart';
import 'stock_history_dialog.dart';

enum _View { all, low, out }

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _query = '';
  _View _view = _View.all;

  List<InventoryItem> _filter(List<InventoryItem> all) {
    final q = _query.trim().toLowerCase();
    return all.where((i) {
      if (_view == _View.low && i.level != StockLevel.low) return false;
      if (_view == _View.out && i.level != StockLevel.out) return false;
      if (q.isEmpty) return true;
      return i.product.name.toLowerCase().contains(q) ||
          i.product.barcode.toLowerCase().contains(q) ||
          (i.categoryName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _adjust(InventoryItem item, AppUser me) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StockAdjustmentDialog(item: item, actor: me),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Stock updated.')));
    }
  }

  Future<void> _loadSamples(AppUser me) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await loadSampleProducts(
        actor: me,
        products: ref.read(productRepositoryProvider),
        categories: ref.read(categoryRepositoryProvider),
      );
      messenger
          .showSnackBar(SnackBar(content: Text('Added $added sample products.')));
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider);
    final inventory = ref.watch(inventoryProvider);
    if (me == null) return const SizedBox.shrink();

    return inventory.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text("Couldn't load inventory.")),
      data: (all) {
        final lowCount = all.where((i) => i.level == StockLevel.low).length;
        final outCount = all.where((i) => i.level == StockLevel.out).length;
        final stockValue = all.fold<Money>(
          Money.zero,
          (sum, i) => i.product.stockOnHand > 0
              ? sum + i.product.cost * i.product.stockOnHand
              : sum,
        );
        final rows = _filter(all);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(label: 'PRODUCTS', value: '${all.length}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      label: 'LOW STOCK',
                      value: '$lowCount',
                      alert: lowCount > 0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      label: 'OUT OF STOCK',
                      value: '$outCount',
                      alert: outCount > 0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      label: 'STOCK VALUE (AT COST)',
                      value: stockValue.format(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search name, barcode or category',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton<_View>(
                    style: SegmentedButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppTheme.radius,
                      ),
                    ),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: _View.all,
                        label: Text('All (${all.length})'),
                      ),
                      ButtonSegment(
                        value: _View.low,
                        label: Text('Low ($lowCount)'),
                      ),
                      ButtonSegment(
                        value: _View.out,
                        label: Text('Out ($outCount)'),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: all.isEmpty
                      ? _EmptyState(
                          onLoadSamples: kDebugMode && me.can(Permission.manageProducts)
                              ? () => _loadSamples(me)
                              : null,
                        )
                      : Column(
                          children: [
                            const _HeaderRow(),
                            const Divider(),
                            Expanded(
                              child: rows.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No products match.',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: rows.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(),
                                      itemBuilder: (_, i) => _InventoryRow(
                                        item: rows[i],
                                        canAdjust:
                                            me.can(Permission.adjustStock),
                                        onAdjust: () => _adjust(rows[i], me),
                                        onHistory: () => showDialog<void>(
                                          context: context,
                                          builder: (_) =>
                                              StockHistoryDialog(item: rows[i]),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.alert = false,
  });

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
          Text(
            value,
            style: AppTheme.numeric.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: alert ? AppColors.danger : AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    return Container(
      color: AppColors.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 4, child: Text('PRODUCT', style: style)),
          Expanded(flex: 2, child: Text('CATEGORY', style: style)),
          Expanded(
            flex: 1,
            child: Text('IN STOCK', textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 1,
            child: Text('REORDER', textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text('COST', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: 16),
          Expanded(flex: 1, child: Text('STATUS', style: style)),
          SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.item,
    required this.canAdjust,
    required this.onAdjust,
    required this.onHistory,
  });

  final InventoryItem item;
  final bool canAdjust;
  final VoidCallback onAdjust;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final p = item.product;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  p.barcode,
                  style: AppTheme.numeric.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.categoryName ?? '-',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${p.stockOnHand}',
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(
                fontWeight: FontWeight.w700,
                color: item.level == StockLevel.ok
                    ? AppColors.navy
                    : AppColors.danger,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${p.reorderLevel}',
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              p.cost.format(),
              textAlign: TextAlign.right,
              style: AppTheme.numeric,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusChip(level: item.level),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canAdjust)
                  IconButton(
                    tooltip: 'Adjust stock',
                    onPressed: onAdjust,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                IconButton(
                  tooltip: 'Stock history',
                  onPressed: onHistory,
                  icon: const Icon(Icons.history, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.level});

  final StockLevel level;

  @override
  Widget build(BuildContext context) {
    final (label, text, background, bordered) = switch (level) {
      StockLevel.ok => ('OK', AppColors.navy, AppColors.canvas, true),
      StockLevel.low => ('Low', AppColors.danger, AppColors.dangerSoft, false),
      StockLevel.out => ('Out', Colors.white, AppColors.danger, false),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.radius,
        border: bordered ? Border.all(color: AppColors.border) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onLoadSamples});

  final VoidCallback? onLoadSamples;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          const Text('No products yet.'),
          const SizedBox(height: 4),
          const Text(
            'Products you add will show up here with their stock levels.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          if (onLoadSamples != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onLoadSamples,
              child: const Text('Load sample products (debug only)'),
            ),
          ],
        ],
      ),
    );
  }
}