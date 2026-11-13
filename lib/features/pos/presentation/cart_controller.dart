import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/product_repository.dart';
import '../domain/cart.dart';
import '../domain/cart_item.dart';

class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    // A new cart whenever someone signs in or out.
    ref.watch(authControllerProvider);
    return const Cart();
  }

  /// Adds one unit. Throws a [ValidationException] if there isn't enough stock.
  void add(Product product) {
    if (product.stockOnHand <= 0) {
      throw ValidationException('${product.name} is out of stock.');
    }

    final items = [...state.items];
    final index = items.indexWhere((i) => i.productId == product.id);

    if (index == -1) {
      items.add(CartItem.fromProduct(product));
    } else {
      final next = items[index].quantity + 1;
      if (next > product.stockOnHand) {
        throw ValidationException(
          'Only ${product.stockOnHand} of ${product.name} in stock.',
        );
      }
      // Refresh price and stock from the latest product data.
      items[index] = CartItem.fromProduct(product, quantity: next);
    }
    state = Cart(items);
  }

  void setQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      remove(productId);
      return;
    }

    final items = [...state.items];
    final index = items.indexWhere((i) => i.productId == productId);
    if (index == -1) return;

    final item = items[index];
    if (quantity > item.stockOnHand) {
      throw ValidationException(
        'Only ${item.stockOnHand} of ${item.name} in stock.',
      );
    }
    items[index] = item.withQuantity(quantity);
    state = Cart(items);
  }

  void remove(String productId) {
    state = Cart(state.items.where((i) => i.productId != productId).toList());
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(
  CartController.new,
);

/// Active products only, for the till's search list.
final posProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watch();
});