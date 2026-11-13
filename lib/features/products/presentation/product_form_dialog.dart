import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_layout.dart';
import '../data/category_repository.dart';
import '../data/product_repository.dart';
import 'products_controller.dart';

/// 750 -> "7.5", 0 -> "0". Tax is stored in basis points (7.5% = 750).
String formatPercent(int basisPoints) {
  final value = basisPoints / 100;
  return value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}

/// "7.5" -> 750. Empty means 0. Returns null if it isn't a valid 0-100 value.
int? _parsePercent(String input) {
  final text = input.trim().replaceAll('%', '');
  if (text.isEmpty) return 0;
  final value = double.tryParse(text);
  if (value == null || value < 0 || value > 100) return null;
  return (value * 100).round();
}

int _parseWholeNumber(String input, int fallback) {
  final text = input.trim();
  return text.isEmpty ? fallback : int.parse(text);
}

class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key, required this.actor, this.product});

  final AppUser actor;

  /// Null means "add a new product".
  final Product? product;

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  static final _barcodePattern = RegExp(r'^\S{1,50}$');

  final _formKey = GlobalKey<FormState>();
  final _barcode = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _tax = TextEditingController();
  final _stock = TextEditingController();
  final _reorder = TextEditingController(text: '5');

  String? _categoryId;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.product != null;
  bool get _canChangePrices => widget.actor.can(Permission.changePrices);

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _barcode.text = p.barcode;
      _name.text = p.name;
      _price.text = p.price.format(symbol: false).replaceAll(',', '');
      _cost.text = p.cost.format(symbol: false).replaceAll(',', '');
      _tax.text = formatPercent(p.taxBasisPoints);
      _reorder.text = '${p.reorderLevel}';
      _categoryId = p.categoryId;
    }
  }

  @override
  void dispose() {
    _barcode.dispose();
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _tax.dispose();
    _stock.dispose();
    _reorder.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CategoryNameDialog(title: 'New category'),
    );
    if (name == null) return;

    try {
      final created = await ref
          .read(categoryRepositoryProvider)
          .create(actor: widget.actor, name: name);
      if (mounted) setState(() => _categoryId = created.id);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final price = Money.tryParse(_price.text)!;
    final cost = Money.tryParse(_cost.text)!;
    final tax = _parsePercent(_tax.text)!;
    final reorder = _parseWholeNumber(_reorder.text, 5);

    try {
      final repo = ref.read(productRepositoryProvider);
      if (_editing) {
        await repo.update(
          actor: widget.actor,
          id: widget.product!.id,
          barcode: _barcode.text,
          name: _name.text,
          price: price,
          cost: cost,
          categoryId: _categoryId,
          taxBasisPoints: tax,
          reorderLevel: reorder,
        );
      } else {
        await repo.create(
          actor: widget.actor,
          barcode: _barcode.text,
          name: _name.text,
          price: price,
          cost: cost,
          categoryId: _categoryId,
          taxBasisPoints: tax,
          openingStock: _parseWholeNumber(_stock.text, 0),
          reorderLevel: reorder,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _profitPreview() {
    final price = Money.tryParse(_price.text);
    final cost = Money.tryParse(_cost.text);
    if (price == null || cost == null || price.minorUnits <= 0) {
      return const SizedBox.shrink();
    }

    final profit = price - cost;
    final margin = profit.minorUnits * 100 / price.minorUnits;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Text(
            'Profit per unit: ',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Text(
            '${profit.format()}  (${margin.toStringAsFixed(1)}%)',
            style: AppTheme.numeric.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: profit.isNegative ? AppColors.danger : AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).when(
          data: (l) => l,
          loading: () => const <Category>[],
          error: (_, __) => const <Category>[],
        );
    final priceEnabled = !_busy && (!_editing || _canChangePrices);

    return AlertDialog(
      title: Text(_editing ? 'Edit product' : 'Add product'),
      content: SizedBox(
        width: 520,
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
                // Scanners type the code and press Enter, which moves focus
                // to the next field.
                TextFormField(
                  controller: _barcode,
                  autofocus: !_editing,
                  enabled: !_busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Barcode',
                    helperText: 'Scan it here, or type it',
                    prefixIcon: Icon(Icons.qr_code_scanner, size: 18),
                  ),
                  validator: (v) => _barcodePattern.hasMatch(v?.trim() ?? '')
                      ? null
                      : '1 to 50 characters, no spaces',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter a name';
                    if (value.length > 120) return 'At most 120 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('${_categoryId}_${categories.length}'),
                        initialValue:
                            categories.any((c) => c.id == _categoryId)
                                ? _categoryId
                                : null,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final c in categories)
                            DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged:
                            _busy ? null : (v) => setState(() => _categoryId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        onPressed: _busy ? null : _newCategory,
                        child: const Text('New'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        enabled: priceEnabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Selling price',
                          prefixText: '${Money.currencySymbol} ',
                        ),
                        validator: (v) {
                          final m = Money.tryParse(v ?? '');
                          if (m == null) return 'e.g. 1250 or 1250.50';
                          if (m <= Money.zero) return 'Must be above zero';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        enabled: priceEnabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Cost price',
                          prefixText: '${Money.currencySymbol} ',
                        ),
                        validator: (v) =>
                            Money.tryParse(v ?? '') == null
                                ? 'e.g. 900 or 900.50'
                                : null,
                      ),
                    ),
                  ],
                ),
                _profitPreview(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _tax,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'VAT %',
                          helperText: '7.5 for VAT, 0 if exempt',
                          suffixText: '%',
                        ),
                        validator: (v) => _parsePercent(v ?? '') == null
                            ? 'Enter 0 to 100'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorder,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: _editing
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onFieldSubmitted: _editing ? (_) => _submit() : null,
                        decoration: const InputDecoration(
                          labelText: 'Reorder level',
                          helperText: 'Warn when stock falls to this',
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_editing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stock,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Opening stock',
                      helperText: 'How many you have on the shelf now',
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'To change the stock quantity, use Inventory.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_editing && !_canChangePrices)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "You don't have permission to change prices.",
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
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
              : Text(_editing ? 'Save changes' : 'Add product'),
        ),
      ],
    );
  }
}

/// A tiny dialog that asks for one category name and returns it.
class CategoryNameDialog extends StatefulWidget {
  const CategoryNameDialog({super.key, required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_name.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Category name'),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Enter a name';
              if (value.length > 60) return 'At most 60 characters';
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}