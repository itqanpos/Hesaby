// lib/features/pos/presentation/widgets/pos_categories_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/category.dart';
import '../../../products/presentation/providers/category_providers.dart';

/// مزود حالة التصنيف المختار في نقطة البيع (لكل جلسة)
final StateProvider<String?> posSelectedCategoryProvider = 
    StateProvider<String?>((ref) => null);

class PosCategoriesBar extends ConsumerWidget {
  const PosCategoriesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProductCategory>> categoriesAsync = ref.watch(categoriesProvider);
    final String? selectedCategory = ref.watch(posSelectedCategoryProvider);

    return SizedBox(
      height: 50,
      child: categoriesAsync.when(
        loading: () => const Center(child: LinearProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
        data: (List<ProductCategory> categories) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: <Widget>[
              // زر "الكل"
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: const Text('الكل'),
                  selected: selectedCategory == null,
                  onSelected: (_) {
                    ref.read(posSelectedCategoryProvider.notifier).state = null;
                  },
                ),
              ),
              // باقي التصنيفات
              ...categories.map((ProductCategory cat) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: selectedCategory == cat.id,
                      onSelected: (_) {
                        ref.read(posSelectedCategoryProvider.notifier).state = cat.id;
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
