// lib/shared/widgets/statements/widgets/statement_active_filter_bar.dart
//
// Compact bar shown under the summary bar **only when at least one filter
// is active**. Displays the active filters and offers a one-tap "مسح"
// action to reset everything back to `all`.
//
// Renders nothing (`SizedBox.shrink`) when the filter is default — the
// caller can therefore include it unconditionally in the Column, and the
// page stays clean when no filter is applied.
//
// Uses `label` (getter on StatementPeriodPresetX) and `arabicLabel` on
// StatementEntryFilter — same strings as the chips in the sheet, so the
// user immediately recognises what is active.

import 'package:flutter/material.dart';

import '../models/statement_filters.dart';
import '../models/statement_models.dart';

class StatementActiveFilterBar extends StatelessWidget {
  const StatementActiveFilterBar({
    required this.preset,
    required this.entryFilter,
    required this.onClear,
    super.key,
  });

  final StatementPeriodPreset preset;
  final StatementEntryFilter entryFilter;
  final VoidCallback onClear;

  /// Whether any filter is active (used by the caller to decide whether
  /// to show the bar, and to compute the AppBar badge count).
  static bool isActive({
    required StatementPeriodPreset preset,
    required StatementEntryFilter entryFilter,
  }) {
    return preset != StatementPeriodPreset.all ||
        entryFilter != StatementEntryFilter.all;
  }

  /// Human-readable summary of the active filters.
  static String describe({
    required StatementPeriodPreset preset,
    required StatementEntryFilter entryFilter,
  }) {
    final List<String> parts = <String>[];
    if (preset != StatementPeriodPreset.all) {
      parts.add(preset.label);
    }
    if (entryFilter != StatementEntryFilter.all) {
      parts.add(entryFilter.arabicLabel);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (!isActive(preset: preset, entryFilter: entryFilter)) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.filter_alt,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              describe(preset: preset, entryFilter: entryFilter),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
  }
}
