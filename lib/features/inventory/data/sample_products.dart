import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../auth/domain/app_user.dart';
import '../../products/data/category_repository.dart';
import '../../products/data/product_repository.dart';

// barcode, name, category, price (naira), cost (naira), opening stock, reorder
const _samples = [
  ('6000000000011', 'Instant Noodles 70g', 'Groceries', 400, 320, 120, 24),
  ('6000000000028', 'Spaghetti 500g', 'Groceries', 1100, 900, 60, 12),
  ('6000000000035', 'Rice 5kg', 'Groceries', 9500, 8200, 18, 5),
  ('6000000000042', 'Sugar 500g', 'Groceries', 1200, 1000, 4, 10),
  ('6000000000059', 'Vegetable Oil 1L', 'Groceries', 3200, 2800, 0, 8),
  ('6000000000066', 'Powdered Milk 400g', 'Groceries', 4500, 3900, 25, 6),
  ('6000000000073', 'Tomato Paste 70g', 'Groceries', 350, 270, 80, 20),
  ('6000000000080', 'Bottled Water 75cl', 'Drinks', 300, 200, 200, 48),
  ('6000000000097', 'Soft Drink 50cl', 'Drinks', 500, 380, 3, 24),
  ('6000000000103', 'Fruit Juice 1L', 'Drinks', 1800, 1450, 30, 10),
  ('6000000000110', 'Detergent 500g', 'Household', 1500, 1200, 40, 10),
  ('6000000000127', 'Toilet Tissue 4-pack', 'Household', 1600, 1300, 2, 8),
  ('6000000000134', 'Bath Soap', 'Personal care', 600, 450, 90, 20),
  ('6000000000141', 'Toothpaste 100ml', 'Personal care', 1100, 850, 35, 10),
  ('6000000000158', 'Eggs Crate (30)', 'Groceries', 4800, 4200, 0, 5),
];

/// Debug-only helper: fills an empty database with realistic products.
/// Skips any barcode that already exists. Returns how many were added.
Future<int> loadSampleProducts({
  required AppUser actor,
  required ProductRepository products,
  required CategoryRepository categories,
}) async {
  final categoryIds = <String, String>{
    for (final c in await categories.watchAll().first) c.name: c.id,
  };

  for (final name in _samples.map((s) => s.$3).toSet()) {
    if (categoryIds.containsKey(name)) continue;
    final created = await categories.create(actor: actor, name: name);
    categoryIds[name] = created.id;
  }

  var added = 0;
  for (final s in _samples) {
    try {
      await products.create(
        actor: actor,
        barcode: s.$1,
        name: s.$2,
        categoryId: categoryIds[s.$3],
        price: Money(s.$4 * 100),
        cost: Money(s.$5 * 100),
        openingStock: s.$6,
        reorderLevel: s.$7,
      );
      added++;
    } on DuplicateException {
      continue;
    }
  }
  return added;
}