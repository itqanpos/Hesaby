// lib/shared/widgets/app_loader.dart

import 'package:flutter/material.dart';

/// A smart loader that automatically adapts to its context.
///
/// * When used for a full page (e.g. `loading: () => const AppLoader()`),
///   it renders a list of [AppSkeletonCard]s to give a faster perceived
///   loading experience.
/// * When used in a small area (e.g. inside a button or a small card),
///   it falls back to a standard [CircularProgressIndicator].
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message, this.size = 32});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder allows us to know the available height.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // If the loader is placed in a large area (like a page body)
        // and there's no custom message, show the skeleton list.
        final bool isFullPage = constraints.maxHeight > 300 || constraints.maxHeight.isInfinite;
        
        if (isFullPage && message == null) {
          return const AppSkeletonList();
        }

        // Otherwise, show the normal spinner (for buttons, small widgets, etc.)
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: size,
                height: size,
                child: const CircularProgressIndicator(strokeWidth: 3),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Skeleton Loaders (شاشات التحميل الهيكلية)
// ============================================================================

/// A shimmering box used to build skeleton loaders.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double opacity = 0.05 + (_controller.value * 0.1);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// A skeleton card that resembles a generic list item.
class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const _ShimmerBox(width: 44, height: 44, borderRadius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _ShimmerBox(width: 140, height: 16),
                  const SizedBox(height: 8),
                  const _ShimmerBox(width: 90, height: 12),
                  const SizedBox(height: 8),
                  Row(
                    children: const <Widget>[
                      _ShimmerBox(width: 60, height: 20, borderRadius: 10),
                      SizedBox(width: 6),
                      _ShimmerBox(width: 60, height: 20, borderRadius: 10),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of skeleton cards to display during initial load.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (BuildContext context, int index) {
        return const AppSkeletonCard();
      },
    );
  }
}
