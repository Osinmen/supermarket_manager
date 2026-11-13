import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../database/enums.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_layout.dart';
import '../data/stock_repository.dart';

enum _Mode { receive, remove, count }

class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({
    super.key,
    required this.item,
    required this.actor,
  });

  final InventoryItem item;
  final AppUser actor;

  @override
  ConsumerState<StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends ConsumerState<StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _note = TextEditingController();

  _Mode _mode = _Mode.receive;
  bool _busy = false;
  String? _error;

  int get _current => widget.item.product.stockOnHand;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _newStock {
    final q = int.tryParse(_qty.text.trim());
    if (q == null) return null;
    return switch (_mode) {
      _Mode.receive => _current + q,
      _Mode.remove => _current - q,
      _Mode.count => q,
    };
  }

  String get _qtyLabel => switch (_mode) {
        _Mode.receive => 'Quantity received',
        _Mode.remove => 'Quantity to remove',
        _Mode.count => 'Counted quantity',
      };

  String get _noteLabel => switch (_mode) {
        _Mode.receive => 'Supplier / invoice no. (optional)',
        _Mode.remove => 'Reason (required): damaged, expired, lost...',
        _Mode.count => 'Note (optional)',
      };

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final qty = int.parse(_qty.text.trim());
    final (type, change) = switch (_mode) {
      _Mode.receive => (StockMovementType.purchase, qty),
      _Mode.remove => (StockMovementType.adjustment, -qty),
      _Mode.count => (StockMovementType.adjustment, qty - _current),
    };

    if (change == 0) {
      setState(() => _error = 'Nothing to change: the count matches the '
          'current stock.');
      return;
    }

    final note = _note.text.trim();
    final movementNote =
        note.isNotEmpty ? note : (_mode == _Mode.count ? 'Stock count' : null);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(stockRepositoryProvider).record(
            actor: widget.actor,
            productId: widget.item.product.id,
            type: type,
            quantityChange: change,
            note: movementNote,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _newStock;

    return AlertDialog(
      title: Text('Adjust stock: ${widget.item.product.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  AuthErrorBox(_error!),
                  const SizedBox(height: 12),
                ],
                SegmentedButton<_Mode>(
                  style: SegmentedButton.styleFrom(
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppTheme.radius,
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _Mode.receive,
                      label: Text('Receive'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment(
                      value: _Mode.remove,
                      label: Text('Remove'),
                      icon: Icon(Icons.remove),
                    ),
                    ButtonSegment(
                      value: _Mode.count,
                      label: Text('Count'),
                      icon: Icon(Icons.fact_check_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _qty,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: _qtyLabel),
                  validator: (v) {
                    final q = int.tryParse((v ?? '').trim());
                    if (q == null) return 'Enter a whole number';
                    if (_mode != _Mode.count && q <= 0) {
                      return 'Must be greater than zero';
                    }
                    if (_mode == _Mode.remove && q > _current) {
                      return 'Only $_current in stock';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: _noteLabel),
                  validator: (v) {
                    if (_mode == _Mode.remove && (v ?? '').trim().isEmpty) {
                      return 'Give a reason';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Current: ',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    Text(
                      '$_current',
                      style: AppTheme.numeric
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      '   →   New: ',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    Text(
                      next == null ? '-' : '$next',
                      style: AppTheme.numeric.copyWith(
                        fontWeight: FontWeight.w700,
                        color: (next != null && next < 0)
                            ? AppColors.danger
                            : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}