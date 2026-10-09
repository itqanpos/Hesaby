// lib/features/companies/presentation/widgets/permission_group_card.dart

import 'package:flutter/material.dart';

import '../../domain/entities/member_permission.dart';

/// A card that displays one [PermissionGroup] with its toggles.
///
/// The switch value reflects the **granted** state:
/// * `on`  → permission granted (not in the deny-list),
/// * `off` → permission denied.
class PermissionGroupCard extends StatelessWidget {
  const PermissionGroupCard({
    super.key,
    required this.group,
    required this.denied,
    required this.enabled,
    required this.onToggle,
    required this.onToggleAll,
  });

  final PermissionGroup group;

  /// Current deny-list (permission codes explicitly revoked).
  final Set<String> denied;

  /// Whether toggles are enabled (false during save).
  final bool enabled;

  /// Called with the permission code when a single toggle changes.
  final void Function(String code, bool granted) onToggle;

  /// Called with `true` to grant all, `false` to deny all.
  final void Function(bool grantAll) onToggleAll;

  int get _deniedCount =>
      group.permissions.where((String code) => denied.contains(code)).length;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasDenied = _deniedCount > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasDenied
              ? scheme.error.withValues(alpha: 0.4)
              : scheme.outlineVariant,
          width: hasDenied ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- Header ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    group.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasDenied)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          '$_deniedCount مُلغاة',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'تفعيل الكل',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled && hasDenied
                      ? () => onToggleAll(true)
                      : null,
                  icon: const Icon(Icons.done_all),
                ),
                IconButton(
                  tooltip: 'إلغاء الكل',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled && _deniedCount < group.permissions.length
                      ? () => onToggleAll(false)
                      : null,
                  icon: const Icon(Icons.block_outlined),
                ),
              ],
            ),
          ),

          // ---- Permission rows ----
          for (int i = 0; i < group.permissions.length; i++) ...<Widget>[
            _PermissionRow(
              code: group.permissions[i],
              granted: !denied.contains(group.permissions[i]),
              enabled: enabled,
              onChanged: (bool v) => onToggle(group.permissions[i], v),
            ),
            if (i < group.permissions.length - 1)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
          ],

          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ============================================================================
// Single row
// ============================================================================

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.code,
    required this.granted,
    required this.enabled,
    required this.onChanged,
  });

  final String code;
  final bool granted;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      value: granted,
      onChanged: enabled ? onChanged : null,
      title: Text(
        MemberPermission.label(code),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: granted ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
