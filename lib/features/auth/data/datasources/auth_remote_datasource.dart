// lib/features/auth/data/datasources/auth_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthResponse, AuthState, Session, SupabaseClient;

import '../../domain/repositories/auth_repository.dart';
import '../models/auth_session_model.dart';

/// Thin wrapper around Supabase Auth.
///
/// This is the only place within the auth feature that talks to the
/// Supabase Auth API directly. Everything above this class deals with
/// [AuthSessionModel] and never sees Supabase types.
///
/// The data source accepts a nullable [SupabaseClient]. In Phase 0 the
/// Supabase client is only initialised when credentials are provided at
/// build time; when it is absent, the data source fails predictably with
/// an [AuthException] rather than throwing a low-level state error.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote authentication calls.
  bool get isAvailable => _client != null;

  /// Returns the session currently held by Supabase, if any.
  ///
  /// This is a synchronous read of the in-memory session; it does not
  /// perform a network call.
  AuthSessionModel? get currentSession {
    final SupabaseClient? client = _client;
    if (client == null) {
      return null;
    }
    final Session? session = client.auth.currentSession;
    if (session == null) {
      return null;
    }
    return AuthSessionModel.fromSupabaseSession(session);
  }

  /// Emits the session whenever Supabase Auth reports a state change.
  ///
  /// Emits `null` when the user is signed out. When Supabase is not
  /// available, emits a closed stream containing no events.
  Stream<AuthSessionModel?> authStateChanges() {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const Stream<AuthSessionModel?>.empty();
    }
    return client.auth.onAuthStateChange.map((AuthState event) {
      final Session? session = event.session;
      if (session == null) {
        return null;
      }
      return AuthSessionModel.fromSupabaseSession(session);
    });
  }

  /// Signs in with email and password.
  ///
  /// Throws [AuthException] when Supabase is unavailable, or rethrows the
  /// underlying [AuthException] raised by Supabase so that the repository
  /// can translate it into a safe [AuthFailureType].
  Future<AuthSessionModel> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }

    final AuthResponse response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final Session? session = response.session;
    if (session == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _emptySessionMessage,
      );
    }

    return AuthSessionModel.fromSupabaseSession(session);
  }

  /// Signs the current user out.
  ///
  /// Throws [AuthException] when Supabase is unavailable.
  Future<void> signOut() async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    await client.auth.signOut();
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
  static const String _emptySessionMessage =
      'Supabase returned no session after a successful sign-in.';
}
