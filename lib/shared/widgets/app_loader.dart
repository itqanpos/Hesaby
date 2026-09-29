// lib/shared/widgets/app_loader.dart
import 'package:flutter/material.dart';

/// Centred progress indicator with an optional message.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message, this.size = 32});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? messageText = message;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(strokeWidth: 3),
          ),
          if (messageText != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              messageText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
