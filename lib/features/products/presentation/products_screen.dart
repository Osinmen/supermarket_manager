import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/product_repository.dart';
import 'categories_dialog.dart';
import 'product_form_dialog.dart';
import 'products_controller.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _query = '';
  bool _showInactive = false;

  List<Product> _filter(List<Product> all, Map<String, String> categoryNames) {
    final q = _query.trim().toLowerCase();
    return all.where((p) {
      if (!_showInactive && !p.isActive) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          (categoryNames[p.categoryId]?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openForm(AppUser me, {Product? product}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductFormDialog(actor: me, product: product),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(product == null ? 'Product added.' : 'Product saved.'),
        ),
      );
    }
  }

  Future<void> _toggleActive(AppUser me, Product product) async {
    final repo = ref.read(productRepositoryProvider);

    if (product.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Deactivate ${product.name}?'),
          content: const Text(
            "It won't appear at the till any more. Past sales and stock "
            'history are kept, and you can activate it again anytime.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await runGuarded(
      context,
      () => repo.setActive(
        actor: me,
        id: product.id,
        isActive: !product.isActive,
      ),
      product.isActive ? 'Product deactivated.' : 'Product activated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider);
    final products = ref.watch(allProductsProvider);
    final categories = ref.watch(categoriesProvider).when(
          data: (l) => l,
          loading: () => const <Category>[],
          error: (_, __) => const <Category>[],
        );
    if (me == null) return const SizedBox.shrink();

    final categoryNames = {for (final c in categories) c.id: c.name};
    final canManage = me.can(Permission.manageProducts);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _showInactive,
                onSelected: (v) => setState(() => _showInactive = v),
              ),
              const Spacer(),
              if (canManage) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('Categories'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CategoriesDialog(actor: me),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add product'),
                  onPressed: () => _openForm(me),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: products.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text("Couldn't load products.")),
                data: (all) {
                  if (all.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sell_outlined,
                            size: 40,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: 12),
                          Text('No products yet.'),
                          SizedBox(height: 4),
                          Text(
                            'Click "Add product" to create your first one.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }

                  final rows = _filter(all, categoryNames);
                  return Column(
                    children: [
                      const _HeaderRow(),
                      const Divider(),
                      Expanded(
                        child: rows.isEmpty
                            ? const Center(
                                child: Text(
                                  'No products match.',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => const Divider(),
                                itemBuilder: (_, i) => _ProductRow(
                                  product: rows[i],
                                  categoryName: categoryNames[rows[i].categoryId],
                                  canManage: canManage,
                                  onEdit: () => _openForm(me, product: rows[i]),
                                  onToggle: () => _toggleActive(me, rows[i]),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
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
            flex: 2,
            child: Text('PRICE', textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text('COST', textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 1,
            child: Text('VAT', textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 1,
            child: Text('STOCK', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: 16),
          Expanded(flex: 1, child: Text('STATUS', style: style)),
          SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.categoryName,
    required this.canManage,
    required this.onEdit,
    required this.onToggle,
  });

  final Product product;
  final String? categoryName;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final dim = p.isActive ? AppColors.navy : AppColors.textMuted;

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
                  style: TextStyle(fontWeight: FontWeight.w600, color: dim),
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
              categoryName ?? '-',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              p.price.format(),
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(
                fontWeight: FontWeight.w700,
                color: dim,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              p.cost.format(),
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${formatPercent(p.taxBasisPoints)}%',
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${p.stockOnHand}',
              textAlign: TextAlign.right,
              style: AppTheme.numeric.copyWith(
                color: p.stockOnHand <= p.reorderLevel
                    ? AppColors.danger
                    : AppColors.navy,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.isActive ? AppColors.canvas : AppColors.dangerSoft,
                  borderRadius: AppTheme.radius,
                  border: p.isActive
                      ? Border.all(color: AppColors.border)
                      : null,
                ),
                child: Text(
                  p.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.isActive ? AppColors.navy : AppColors.danger,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: canManage
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: p.isActive ? 'Deactivate' : 'Activate',
                        onPressed: onToggle,
                        icon: Icon(
                          p.isActive
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}