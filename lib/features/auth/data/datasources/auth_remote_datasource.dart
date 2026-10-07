// lib/features/auth/data/datasources/auth_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthResponse,
        AuthState,
        Session,
        SupabaseClient,
        UserAttributes,
        UserResponse;

import '../../domain/repositories/auth_repository.dart';
import '../models/auth_session_model.dart';

/// Thin wrapper around Supabase Auth.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

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

  /// Updates the password of the currently authenticated user.
  ///
  /// Supabase requires an active session; the current password is not
  /// re-checked because the session already proves possession.
  Future<void> updatePassword({required String newPassword}) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }

    final UserResponse response = await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    if (response.user == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _emptyUserMessage,
      );
    }
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
  static const String _emptySessionMessage =
      'Supabase returned no session after a successful sign-in.';
  static const String _emptyUserMessage =
      'Supabase returned no user after a successful password update.';
}
