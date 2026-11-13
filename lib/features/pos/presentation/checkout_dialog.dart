import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_layout.dart';
import '../data/sale_repository.dart';
import '../domain/cart.dart';

String _plain(Money m) => m.format(symbol: false).replaceAll(',', '');

class CheckoutDialog extends ConsumerStatefulWidget {
  const CheckoutDialog({super.key, required this.actor, required this.cart});

  final AppUser actor;
  final Cart cart;

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  PaymentMethod _method = PaymentMethod.cash;
  late final _received = TextEditingController(text: _plain(_total));
  bool _busy = false;
  String? _error;

  Money get _total => widget.cart.total;

  Money? get _receivedMoney =>
      _method == PaymentMethod.cash ? Money.tryParse(_received.text) : _total;

  bool get _canPay {
    final r = _receivedMoney;
    return r != null && r >= _total;
  }

  /// A few useful "customer gave me..." amounts above the total.
  List<Money> get _quickAmounts {
    final options = <Money>[];
    for (final naira in [500, 1000, 2000, 5000, 10000]) {
      final m = Money(naira * 100);
      if (m > _total && options.length < 3) options.add(m);
    }
    return options;
  }

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_busy || !_canPay) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final receipt = await ref.read(saleRepositoryProvider).completeSale(
            actor: widget.actor,
            lines: [
              for (final i in widget.cart.items)
                (productId: i.productId, quantity: i.quantity),
            ],
            method: _method,
            amountPaid: _receivedMoney!,
            expectedTotal: _total,
          );
      if (mounted) Navigator.of(context).pop(receipt);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      // Show the real cause in the console so it can be fixed.
      debugPrint('Checkout failed: $e\n$st');
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final received = _receivedMoney;
    final change = received == null ? null : received - _total;
    final isCash = _method == PaymentMethod.cash;

    return AlertDialog(
      title: const Text('Payment'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                AuthErrorBox(_error!),
                const SizedBox(height: 12),
              ],
              const Text(
                'AMOUNT DUE',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _total.format(),
                style: AppTheme.numeric
                    .copyWith(fontSize: 34, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              SegmentedButton<PaymentMethod>(
                style: SegmentedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppTheme.radius,
                  ),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: PaymentMethod.cash,
                    label: Text('Cash'),
                    icon: Icon(Icons.payments_outlined),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.card,
                    label: Text('Card'),
                    icon: Icon(Icons.credit_card),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.transfer,
                    label: Text('Transfer'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                ],
                selected: {_method},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() {
                          _method = s.first;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 16),
              if (isCash) ...[
                TextField(
                  controller: _received,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _complete(),
                  decoration: const InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '${Money.currencySymbol} ',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Exact'),
                      onPressed: () => setState(
                        () => _received.text = _plain(_total),
                      ),
                    ),
                    for (final m in _quickAmounts)
                      ActionChip(
                        label: Text(m.format()),
                        onPressed: () =>
                            setState(() => _received.text = _plain(m)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      (change != null && change.isNegative) ? 'SHORT BY' : 'CHANGE',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      change == null
                          ? '-'
                          : (change.isNegative ? -change : change).format(),
                      style: AppTheme.numeric.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: (change != null && change.isNegative)
                            ? AppColors.danger
                            : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  'Confirm the ${_method.name} payment went through, then '
                  'complete the sale.',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || !_canPay) ? null : _complete,
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Complete sale'),
        ),
      ],
    );
  }
}