import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../database/app_database.dart';
import '../data/category_repository.dart';
import '../data/product_repository.dart';

/// Every product, active and inactive. The screen filters in memory, so
/// typing in the search box never flickers.
final allProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watch(includeInactive: true);
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll();
});

/// Runs an action and reports the result (or the error) in a snackbar.
Future<void> runGuarded(
  BuildContext context,
  Future<void> Function() action,
  String doneMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Something went wrong. Try again.')),
    );
  }
}