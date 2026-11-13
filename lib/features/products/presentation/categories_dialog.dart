import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/domain/app_user.dart';
import '../data/category_repository.dart';
import 'product_form_dialog.dart';
import 'products_controller.dart';

class CategoriesDialog extends ConsumerWidget {
  const CategoriesDialog({super.key, required this.actor});

  final AppUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final repo = ref.read(categoryRepositoryProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Categories')),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            onPressed: () async {
              final name = await showDialog<String>(
                context: context,
                builder: (_) => const CategoryNameDialog(title: 'New category'),
              );
              if (name != null && context.mounted) {
                await runGuarded(
                  context,
                  () => repo.create(actor: actor, name: name),
                  'Category added.',
                );
              }
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 340,
        child: categories.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) =>
              const Center(child: Text("Couldn't load categories.")),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: Text(
                  'No categories yet.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final category = list[i];
                return ListTile(
                  dense: true,
                  title: Text(category.name),
                  trailing: IconButton(
                    tooltip: 'Rename',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final name = await showDialog<String>(
                        context: context,
                        builder: (_) => CategoryNameDialog(
                          title: 'Rename category',
                          initial: category.name,
                        ),
                      );
                      if (name != null && context.mounted) {
                        await runGuarded(
                          context,
                          () => repo.rename(
                            actor: actor,
                            id: category.id,
                            newName: name,
                          ),
                          'Category renamed.',
                        );
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}