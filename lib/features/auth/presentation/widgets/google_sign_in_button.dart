// lib/features/auth/presentation/widgets/google_sign_in_button.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';

/// "Sign in with Google" button.
///
/// Launches the OAuth flow in the system browser. The actual session
/// arrives asynchronously through [authProvider]; when it lands, the
/// router redirects automatically — this button only needs to trigger
/// the flow and surface the ability to launch it.
///
/// On failure (e.g. Supabase provider not configured, network error) a
/// SnackBar shows a translated message, and the app stays on the current
/// screen.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() =>
      _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final AuthFailureType? failure =
        await ref.read(authProvider.notifier).signInWithGoogle();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (failure != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_failureMessage(failure))),
        );
    }
  }

  static String _failureMessage(AuthFailureType type) => switch (type) {
        AuthFailureType.invalidCredentials =>
          'تعذّر بدء تسجيل الدخول. حاول مرة أخرى.',
        AuthFailureType.emailNotConfirmed =>
          'البريد الإلكتروني غير مؤكد.',
        AuthFailureType.userNotFound => 'الحساب غير موجود.',
        AuthFailureType.tooManyRequests =>
          'محاولات كثيرة. يرجى المحاولة بعد قليل.',
        AuthFailureType.weakPassword => 'كلمة المرور ضعيفة.',
        AuthFailureType.emailAlreadyInUse =>
          'هذا البريد مُستخدم بالفعل.',
        AuthFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        AuthFailureType.unknown =>
          'تعذّر بدء تسجيل الدخول بـ Google. حاول مرة أخرى.',
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return OutlinedButton(
      onPressed: _isLoading ? null : _handleTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (_isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          else
            const _GoogleGlyph(size: 22),
          const SizedBox(width: 12),
          Text(
            'الدخول باستخدام Google',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Google "G" glyph — a stylized letter rendered with the brand blue.
// Avoids bundling a raster asset while keeping the button recognizable.
// ============================================================================

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: size,
            height: 1,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
