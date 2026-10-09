// lib/features/auth/data/datasources/auth_remote_datasource.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart'

import '../../domain/repositories/auth_repository.dart';
import '../models/auth_session_model.dart';

/// Thin wrapper around Supabase Auth.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  AuthSessionModel? get currentSession {
    final SupabaseClient? client = _client;
    if (client == null) return null;
    final Session? session = client.auth.currentSession;
    if (session == null) return null;
    return AuthSessionModel.fromSupabaseSession(session);
  }

  Stream<AuthSessionModel?> authStateChanges() {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const Stream<AuthSessionModel?>.empty();
    }
    return client.auth.onAuthStateChange.map((AuthState event) {
      final Session? session = event.session;
      if (session == null) return null;
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

  /// Registers a new user.
  ///
  /// Extra metadata is passed to Supabase Auth and becomes
  /// `auth.users.raw_user_meta_data`. The database trigger
  /// `handle_new_user` reads `company_name` from that metadata to
  /// bootstrap a company + owner membership for the new user.
  ///
  /// Returns `null` when Supabase is configured to require email
  /// confirmation: in that case no session is created until the user
  /// confirms their address.
  Future<AuthSessionModel?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }

    final Map<String, dynamic> metadata = <String, dynamic>{};
    final String? name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      metadata['full_name'] = name;
    }
    final String? company = companyName?.trim();
    if (company != null && company.isNotEmpty) {
      metadata['company_name'] = company;
    }

    final AuthResponse response = await client.auth.signUp(
      email: email,
      password: password,
      data: metadata.isEmpty ? null : metadata,
    );

    final Session? session = response.session;
    if (session == null) {
      return null;
    }

    return AuthSessionModel.fromSupabaseSession(session);
  }

  /// Starts the Google OAuth flow.
  ///
  /// On web, [Uri.base] resolves to the current page URL, which is exactly
  /// the redirect target Supabase needs to send the user back to. On other
  /// platforms a custom URL scheme is used; the mobile build configures
  /// that scheme natively.
  ///
  /// [LaunchMode.externalApplication] keeps the OAuth screen in the system
  /// browser on mobile and in a full-page redirect on web, so the user
  /// can complete the flow without the app interfering.
  Future<void> signInWithOAuth() async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException(
        type: AuthFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }

    final String redirectTo = kIsWeb
        ? '${Uri.base.scheme}://${Uri.base.host}${Uri.base.path}'
        : 'io.supabase.hesabi://login-callback';

    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
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
