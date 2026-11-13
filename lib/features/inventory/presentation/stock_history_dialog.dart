import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../database/enums.dart';
import '../data/stock_repository.dart';

final _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

String _typeLabel(StockMovementType type) => switch (type) {
      StockMovementType.purchase => 'Received',
      StockMovementType.sale => 'Sale',
      StockMovementType.saleReturn => 'Return',
      StockMovementType.adjustment => 'Adjustment',
    };

class StockHistoryDialog extends ConsumerWidget {
  const StockHistoryDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(stockMovementsProvider(item.product.id));

    const header = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    return AlertDialog(
      title: Text('Stock history: ${item.product.name}'),
      content: SizedBox(
        width: 680,
        height: 420,
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text("Couldn't load history.")),
          data: (list) {
            if (list.isEmpty) {
              return const Center(child: Text('No stock movements yet.'));
            }
            return Column(
              children: [
                Container(
                  color: AppColors.canvas,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: Text('DATE', style: header)),
                      Expanded(flex: 2, child: Text('TYPE', style: header)),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'CHANGE',
                          textAlign: TextAlign.right,
                          style: header,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(flex: 4, child: Text('NOTE', style: header)),
                      Expanded(flex: 2, child: Text('BY', style: header)),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final m = list[i].movement;
                      final change = m.quantityChange;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                _dateFormat.format(m.createdAt),
                                style: AppTheme.numeric.copyWith(fontSize: 12),
                              ),
                            ),
                            Expanded(flex: 2, child: Text(_typeLabel(m.type))),
                            Expanded(
                              flex: 1,
                              child: Text(
                                change > 0 ? '+$change' : '$change',
                                textAlign: TextAlign.right,
                                style: AppTheme.numeric.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: change < 0
                                      ? AppColors.danger
                                      : AppColors.navy,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 4,
                              child: Text(
                                m.note ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                list[i].userName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}