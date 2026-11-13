import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/sale_repository.dart';
import 'cart_controller.dart';
import 'cart_panel.dart';
import 'checkout_dialog.dart';
import 'receipt_dialog.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  List<Product> _filter(List<Product> all, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q),
        )
        .toList();
  }

  void _add(Product product) {
    try {
      ref.read(cartProvider.notifier).add(product);
    } on AppException catch (e) {
      _toast(e.message);
    }
    _focus.requestFocus();
  }

  void _setQuantity(String productId, int quantity) {
    try {
      ref.read(cartProvider.notifier).setQuantity(productId, quantity);
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  /// Enter in the search box: an exact barcode adds that product (this is
  /// what a scanner does). Otherwise, if exactly one product matches the text,
  /// that one is added.
  void _submitSearch(List<Product> all) {
    final text = _search.text.trim();
    if (text.isEmpty) return;

    Product? match;
    for (final p in all) {
      if (p.barcode == text) {
        match = p;
        break;
      }
    }

    if (match == null) {
      final results = _filter(all, text);
      if (results.length == 1) {
        match = results.first;
      } else if (results.isEmpty) {
        _toast('No product found for "$text".');
        return;
      } else {
        _toast('${results.length} matches. Pick one from the list.');
        return;
      }
    }

    _add(match);
    _search.clear();
    setState(() => _query = '');
  }

  Future<void> _pay(AppUser me) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final receipt = await showDialog<SaleReceipt>(
      context: context,
      builder: (_) => CheckoutDialog(actor: me, cart: cart),
    );

    if (receipt != null && mounted) {
      ref.read(cartProvider.notifier).clear();
      await showDialog<void>(
        context: context,
        builder: (_) => ReceiptDialog(receipt: receipt),
      );
    }
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider);
    final cart = ref.watch(cartProvider);
    final all = ref.watch(posProductsProvider).when(
          data: (l) => l,
          loading: () => const <Product>[],
          error: (_, __) => const <Product>[],
        );
    if (me == null) return const SizedBox.shrink();

    final rows = _filter(all, _query);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): () => _pay(me),
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _search,
                    focusNode: _focus,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (_) => _submitSearch(all),
                    decoration: const InputDecoration(
                      hintText: 'Scan a barcode, or search then press Enter',
                      prefixIcon: Icon(Icons.qr_code_scanner, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: rows.isEmpty
                          ? Center(
                              child: Text(
                                all.isEmpty
                                    ? 'No products yet. Add some in Products.'
                                    : 'No products match.',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (_, i) => _ProductTile(
                                product: rows[i],
                                onAdd: () => _add(rows[i]),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 420,
              child: CartPanel(
                cart: cart,
                onQuantity: _setQuantity,
                onRemove: (id) => ref.read(cartProvider.notifier).remove(id),
                onClear: () => ref.read(cartProvider.notifier).clear(),
                onPay: () => _pay(me),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final out = p.stockOnHand <= 0;
    final low = !out && p.stockOnHand <= p.reorderLevel;

    return InkWell(
      onTap: out ? null : onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: out ? AppColors.textMuted : AppColors.navy,
                    ),
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
            if (out)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: AppTheme.radius,
                ),
                child: const Text(
                  'Out',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Text(
                '${p.stockOnHand} left',
                style: AppTheme.numeric.copyWith(
                  fontSize: 12,
                  color: low ? AppColors.danger : AppColors.textMuted,
                ),
              ),
            const SizedBox(width: 24),
            SizedBox(
              width: 110,
              child: Text(
                p.price.format(),
                textAlign: TextAlign.right,
                style: AppTheme.numeric.copyWith(
                  fontWeight: FontWeight.w700,
                  color: out ? AppColors.textMuted : AppColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.add_circle_outline,
              size: 20,
              color: out ? AppColors.border : AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}