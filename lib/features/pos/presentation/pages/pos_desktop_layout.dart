// lib/features/pos/presentation/pages/pos_desktop_layout.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import '../widgets/pos_cart_list.dart';
import '../widgets/pos_categories_bar.dart'; // ⬅️ ملف جديد للتصنيفات
import '../widgets/pos_customer_bar.dart';
import '../widgets/pos_pay_button.dart';
import '../widgets/pos_results_list.dart';
import '../widgets/pos_search_field.dart';
import '../widgets/pos_totals_bar.dart';

/// POS layout for desktop and wide-desktop screens (width ≥ 1024 dp).
class PosDesktopLayout extends ConsumerWidget {
  const PosDesktopLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PosSearchState search = ref.watch(posSearchProvider);
    final bool isSearching = search.isNotEmpty;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ⬅️ Left column — Products, Search, Categories
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PosCustomerBar(),
              const PosSearchField(),
              const PosCategoriesBar(), // ⬅️ شريط التصنيفات
              Expanded(
                child: isSearching
                    ? const PosResultsList()
                    : const _SearchHint(),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),

        // ➡️ Right column — Cart (Top) + Totals (Bottom)
        Expanded(
          flex: 3,
          child: Container(
            color: scheme.surface, // خلفية داكنة للعمود الأيمن
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // --- Cart Section (Top) ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.shopping_cart_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'سلة المشتريات',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const Expanded(
                  child: PosCartList(), // تأخذ كل المساحة المتاحة فوق الإجماليات
                ),
                Divider(height: 2, thickness: 2, color: scheme.outlineVariant),

                // --- Totals & Pay Section (Bottom) ---
                const PosTotalsBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 56,
                      child: const PosPayButton(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.touch_app_outlined, size: 64, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'اختر منتجاً من التصنيفات أو ابحث عنه',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
