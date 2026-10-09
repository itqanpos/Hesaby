// lib/features/auth/presentation/providers/auth_provider.dart

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/get_current_session.dart';
import '../../domain/usecases/login.dart';
import '../../domain/usecases/logout.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

@immutable
class AuthState extends Equatable {
  const AuthState({required this.status, this.session});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);
  const AuthState.authenticated(AuthSession session)
      : this(status: AuthStatus.authenticated, session: session);

  final AuthStatus status;
  final AuthSession? session;

  bool get isUnknown => status == AuthStatus.unknown;
  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;

  @override
  List<Object?> get props => <Object?>[status, session];
}

final Provider<AuthRemoteDataSource> authRemoteDataSourceProvider =
    Provider<AuthRemoteDataSource>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return AuthRemoteDataSource(client);
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
);

final Provider<Login> loginUseCaseProvider = Provider<Login>(
  (ref) => Login(ref.watch(authRepositoryProvider)),
);

final Provider<Logout> logoutUseCaseProvider = Provider<Logout>(
  (ref) => Logout(ref.watch(authRepositoryProvider)),
);

final Provider<GetCurrentSession> getCurrentSessionUseCaseProvider =
    Provider<GetCurrentSession>(
  (ref) => GetCurrentSession(ref.watch(authRepositoryProvider)),
);

class AuthNotifier extends Notifier<AuthState> {
  bool _isDisposed = false;

  @override
  AuthState build() {
    _isDisposed = false;
    final AuthRepository repository = ref.watch(authRepositoryProvider);

    final StreamSubscription<AuthSession?> subscription =
        repository.authStateChanges.listen(
      _applySession,
      onError: (Object _, StackTrace __) {
        if (_isDisposed) return;
        state = const AuthState.unauthenticated();
      },
    );

    ref.onDispose(() {
      _isDisposed = true;
      subscription.cancel();
    });

    unawaited(_restoreSession());

    return const AuthState.unknown();
  }

  Future<AuthFailureType?> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthSession session = await ref.read(loginUseCaseProvider)(
        email: email,
        password: password,
      );
      if (_isDisposed) return null;
      state = AuthState.authenticated(session);
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  /// Registers a new user. When [companyName] is provided, the backend
  /// bootstraps a company owned by the new user.
  ///
  /// Returns:
  /// * `null` on success with an active session (email confirmation
  ///   disabled), or
  /// * `AuthSignUpResult.needsEmailConfirmation` on success without a
  ///   session, or
  /// * an [AuthFailureType] on failure.
  Future<Object?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
  }) async {
    try {
      final AuthSession? session =
          await ref.read(authRepositoryProvider).signUp(
                email: email,
                password: password,
                fullName: fullName,
                companyName: companyName,
              );

      if (_isDisposed) return null;

      if (session == null) {
        return AuthSignUpResult.needsEmailConfirmation;
      }

      state = AuthState.authenticated(session);
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  /// Starts the Google OAuth flow.
  ///
  /// The returned value reflects only the ability to *launch* the flow.
  /// The actual session arrives asynchronously through the auth state
  /// stream owned by this notifier — by the time it fires, `state` is
  /// already updated and every listener (including the router) reacts.
  Future<AuthFailureType?> signInWithGoogle() async {
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  Future<AuthFailureType?> logout() async {
    try {
      await ref.read(logoutUseCaseProvider)();
      if (_isDisposed) return null;
      state = const AuthState.unauthenticated();
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  Future<AuthFailureType?> changePassword({
    required String newPassword,
  }) async {
    try {
      await ref.read(authRepositoryProvider).changePassword(
            newPassword: newPassword,
          );
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  Future<void> _restoreSession() async {
    try {
      final AuthSession? session = await ref.read(
        getCurrentSessionUseCaseProvider,
      )();
      if (_isDisposed || !state.isUnknown) return;
      _applySession(session);
    } on AuthException {
      if (_isDisposed || !state.isUnknown) return;
      state = const AuthState.unauthenticated();
    }
  }

  void _applySession(AuthSession? session) {
    if (_isDisposed) return;
    state = session == null
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(session);
  }
}

/// Result marker returned by [AuthNotifier.signUp] when Supabase is
/// configured to require email confirmation.
enum AuthSignUpResult {
  needsEmailConfirmation,
}

final NotifierProvider<AuthNotifier, AuthState> authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
