import '../../../core/utils/money.dart';
import 'cart_item.dart';

class Cart {
  const Cart([this.items = const []]);

  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;

  int get units => items.fold(0, (sum, i) => sum + i.quantity);

  /// What the customer pays (prices already include VAT).
  Money get total => items.fold(Money.zero, (sum, i) => sum + i.lineTotal);

  /// The VAT portion of the total.
  Money get tax => items.fold(Money.zero, (sum, i) => sum + i.tax);

  /// The total without VAT.
  Money get subtotal => total - tax;
}