import 'package:intl/intl.dart';

import '../features/pos/data/sale_repository.dart';

abstract final class ReceiptService {
  /// Change this to the shop's real name.
  static const storeName = 'Supermarket';

  static const _width = 40;

  static String format(SaleReceipt receipt) {
    final s = receipt.sale;
    final line = '-' * _width;
    final b = StringBuffer();

    b.writeln(_center(storeName.toUpperCase()));
    b.writeln(_center('Receipt ${s.receiptNumber}'));
    b.writeln(_center(DateFormat('dd MMM yyyy, HH:mm').format(s.createdAt)));
    b.writeln(_center('Cashier: ${receipt.cashierName}'));
    b.writeln(line);

    for (final item in receipt.items) {
      b.writeln(item.productName);
      b.writeln(
        _pair(
          '  ${item.quantity} x ${item.unitPrice.format()}',
          item.lineTotal.format(),
        ),
      );
    }

    b.writeln(line);
    b.writeln(_pair('Subtotal (excl. VAT)', s.subtotal.format()));
    b.writeln(_pair('VAT', s.tax.format()));
    b.writeln(_pair('TOTAL', s.total.format()));
    b.writeln(line);

    final method = s.paymentMethod.name;
    b.writeln(
      _pair(
        'Paid (${method[0].toUpperCase()}${method.substring(1)})',
        s.amountPaid.format(),
      ),
    );
    b.writeln(_pair('Change', s.change.format()));
    b.writeln(line);
    b.writeln(_center('Thank you for shopping with us!'));

    return b.toString();
  }

  static String _center(String text) {
    if (text.length >= _width) return text;
    return text.padLeft((_width + text.length) ~/ 2);
  }

  static String _pair(String left, String right) {
    final room = _width - right.length - 1;
    final l = left.length > room ? left.substring(0, room) : left;
    return l.padRight(_width - right.length) + right;
  }
}