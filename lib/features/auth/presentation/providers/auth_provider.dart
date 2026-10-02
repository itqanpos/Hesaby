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

/// Lifecycle stage of the authentication state.
enum AuthStatus {
  /// The application is still resolving whether a session exists.
  unknown,

  /// A valid session is available.
  authenticated,

  /// No session is available; the user must sign in.
  unauthenticated,
}

/// Immutable snapshot of the authentication state.
///
/// [session] is guaranteed to be non-null only when [status] is
/// [AuthStatus.authenticated].
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

/// Data source bound to the active Supabase client.
///
/// Falls back to `null` when Supabase was not initialised (for example when
/// credentials were not provided at build time). The data source handles a
/// `null` client gracefully.
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

/// The application's authentication repository.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
    );

/// `login` use case.
final Provider<Login> loginUseCaseProvider = Provider<Login>(
  (ref) => Login(ref.watch(authRepositoryProvider)),
);

/// `logout` use case.
final Provider<Logout> logoutUseCaseProvider = Provider<Logout>(
  (ref) => Logout(ref.watch(authRepositoryProvider)),
);

/// `getCurrentSession` use case.
final Provider<GetCurrentSession> getCurrentSessionUseCaseProvider =
    Provider<GetCurrentSession>(
      (ref) => GetCurrentSession(ref.watch(authRepositoryProvider)),
    );

/// Owns the authentication state and exposes safe authentication actions.
///
/// The notifier subscribes to [AuthRepository.authStateChanges] once, and
/// resolves the initial state through [GetCurrentSession] so that a missing
/// Supabase client still produces a deterministic `unauthenticated` result
/// rather than leaving the state `unknown` forever.
///
/// Lifecycle safety (Riverpod 2.x):
/// Riverpod 3.x exposes `ref.mounted`, but this project targets Riverpod 2.x.
/// Disposal is tracked with a private flag updated by [Ref.onDispose]. The
/// flag is flipped *and* the subscription is cancelled inside a single
/// callback, so behaviour does not depend on Riverpod's callback ordering.
/// Every write to [state] that can happen after an `await` is guarded by
/// this flag, matching the semantics that `ref.mounted` would provide.
class AuthNotifier extends Notifier<AuthState> {
  bool _isDisposed = false;

  @override
  AuthState build() {
    _isDisposed = false;

    final AuthRepository repository = ref.watch(authRepositoryProvider);

    final StreamSubscription<AuthSession?> subscription = repository
        .authStateChanges
        .listen(
          _applySession,
          onError: (Object _, StackTrace __) {
            if (_isDisposed) {
              return;
            }
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

  /// Signs in with the supplied credentials.
  ///
  /// Returns `null` on success, or a safe [AuthFailureType] the caller can
  /// translate into a localized message. Never returns raw backend text.
  Future<AuthFailureType?> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthSession session = await ref.read(loginUseCaseProvider)(
        email: email,
        password: password,
      );
      if (_isDisposed) {
        return null;
      }
      state = AuthState.authenticated(session);
      return null;
    } on AuthException catch (error) {
      return error.type;
    }
  }

  /// Signs the current user out.
  ///
  /// Returns `null` on success, or a safe [AuthFailureType] on failure.
  Future<AuthFailureType?> logout() async {
    try {
      await ref.read(logoutUseCaseProvider)();
      if (_isDisposed) {
        return null;
      }
      state = const AuthState.unauthenticated();
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
      if (_isDisposed || !state.isUnknown) {
        return;
      }
      _applySession(session);
    } on AuthException {
      if (_isDisposed || !state.isUnknown) {
        return;
      }
      state = const AuthState.unauthenticated();
    }
  }

  void _applySession(AuthSession? session) {
    if (_isDisposed) {
      return;
    }
    state = session == null
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(session);
  }
}

/// Provides the authentication state.
final NotifierProvider<AuthNotifier, AuthState> authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
