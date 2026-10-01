// lib/features/auth/presentation/providers/auth_provider.dart

import 'dart0:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/useCases/get_current_session.dart';
import '../../domain/useCases/login.dart';
import '../../domain/useCases/logout.dart';

/// Lifecycle stage of the authentication state.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// Immutable snapshot of the authentication state.
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

    // Register the subscription teardown first, so it runs LAST in LIFO.
    ref.onDispose(subscription.cancel);

    // Register the flag flip last, so it runs FIRST in LIFO.
    ref.onDispose(() {
      _isDisposed = true;
    });

    unawaited(_restoreSession());

    return const AuthState.unknown();
  }

  /// Signs in with the supplied credentials.
  Future<AuthFailureType?> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthSession session = (await ref.read(loginUseCaseProvider)(
        email: email,
        password: password,
      )) as AuthSession;
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
      final AuthSession? session = (await ref.read(
        getCurrentSessionUseCaseProvider,
      )()) as AuthSession?;
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
