// lib/features/pos/presentation/widgets/pos_categories_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ⬇️ استيراد مزودات التصنيفات من ميزة المنتجات
import '../../../products/presentation/providers/category_providers.dart';
import '../../../products/domain/entities/category.dart';

class PosCategoriesBar extends ConsumerWidget {
  const PosCategoriesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProductCategory>> categoriesAsync = ref.watch(categoriesProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // سنستخدم StateProvider بسيط لتتبع التصنيف المختار حالياً
    // (يمكنك نقله إلى pos_providers.dart لاحقاً)
    final selectedCategory = ref.watch(StateProvider<String?>((ref) => null));

    return SizedBox(
      height: 50,
      child: categoriesAsync.when(
        loading: () => const Center(child: LinearProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
        data: (categories) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              // زر "الكل"
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: const Text('الكل'),
                  selected: selectedCategory == null,
                  onSelected: (_) {
                    ref.read(StateProvider<String?>((ref) => null).notifier).state = null;
                  },
                ),
              ),
              // باقي التصنيفات
              ...categories.map((cat) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: selectedCategory == cat.id,
                      onSelected: (_) {
                        ref.read(StateProvider<String?>((ref) => null).notifier).state = cat.id;
                      },
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
