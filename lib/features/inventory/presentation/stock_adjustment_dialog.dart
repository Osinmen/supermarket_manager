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

//mmaking the enumn private 

enum _Mode {receive, remove, count}
class StockAdjustmentDialog extends ConsumerStatefulWidget{ 
  const StockAdjustmentDialog ({
    super.key, 
    required this.item, 
    required this.actor
  }); 
  final InventoryItem item;
  final AppUser actor;

  @override 
  ConsumerState<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends ConsumerState<StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _note = TextEditingController();

  _Mode _mode = _Mode.receive;
  bool _busy  = false;
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
    if(q == null) return null;
    return switch(_mode) {
      _Mode.receive => _current + q, 
      _Mode.remove => _current - q, 
      _Mode.count => q
    };
  }   

  String get _qtyLabel => switch(_mode) {
    _Mode.receive => 'Quantity Receieved', 
    _Mode.remove => 'Quantity to remove', 
    _Mode.count => 'Counted Quantity', 
  }; 

  String get _noteLable => switch(_mode) { 
    _Mode.receive => 'Supplier/ invoice no. (optional)',
_Mode.remove => 'Reason (required): damaged, expired lost..... ', 
_Mode.count => 'Note (optional)'
  };

  Future<void> submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final qty = int.parse(_qty.text.trim());
    final (type, change) = switch(_mode) {
      _Mode.receive => (StockMovementType.purchase, qty), 
      _Mode.remove => (StockMovementType.adjustment, -qty), 
      _Mode.count => (StockMovementType.adjustment, qty - _current)
    };
    if(change == 0) {
      setState(() => _error = "Nothing to change: the count matches the current stock ");
      return;
    }

    final note = _note.text.trim();
    final movementNote = note.isNotEmpty ? note: (_mode == _Mode.count ? 'Stock count ' : null);
 setState(() {
      _busy = true;
      _error = null;
    });
F
  }
  

}