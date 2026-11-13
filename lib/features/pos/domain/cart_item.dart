import '../../../core/utils/money.dart';
import '../../../database/app_database.dart';

/// The VAT already inside a VAT-inclusive amount.
/// Example: 1,075.00 at 7.5% contains 75.00 VAT.
Money taxIncludedIn(Money amount, int basisPoints) {
  if (basisPoints <= 0) return Money.zero;
  final divisor = 10000 + basisPoints;
  return Money((amount.minorUnits * basisPoints + divisor ~/ 2) ~/ divisor);
}

class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.unitPrice,
    required this.taxBasisPoints,
    required this.quantity,
    required this.stockOnHand,
  });

  factory CartItem.fromProduct(Product p, {int quantity = 1}) => CartItem(
        productId: p.id,
        name: p.name,
        barcode: p.barcode,
        unitPrice: p.price,
        taxBasisPoints: p.taxBasisPoints,
        quantity: quantity,
        stockOnHand: p.stockOnHand,
      );

  final String productId;
  final String name;
  final String barcode;
  final Money unitPrice;
  final int taxBasisPoints;
  final int quantity;
  final int stockOnHand;

  Money get lineTotal => unitPrice * quantity;
  Money get tax => taxIncludedIn(lineTotal, taxBasisPoints);

  CartItem withQuantity(int quantity) => CartItem(
        productId: productId,
        name: name,
        barcode: barcode,
        unitPrice: unitPrice,
        taxBasisPoints: taxBasisPoints,
        quantity: quantity,
        stockOnHand: stockOnHand,
      );
}