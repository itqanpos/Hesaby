// lib/features/auth/data/repositories/auth_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_session_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remoteDataSource);

  final AuthRemoteDataSource _remoteDataSource;

  @override
  Stream<AuthSession?> get authStateChanges =>
      _remoteDataSource.authStateChanges().map(_toEntityOrNull);

  @override
  Future<AuthSession?> getCurrentSession() async {
    final AuthSessionModel? model = _remoteDataSource.currentSession;
    return model?.toEntity();
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthSessionModel model = await _remoteDataSource
          .signInWithPassword(email: email, password: password);
      return model.toEntity();
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSupabaseAuthException(error, stackTrace);
    } on AuthException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknownException(error, stackTrace, operation: 'login');
    }
  }

  @override
  Future<AuthSession?> signUp({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
  }) async {
    try {
      final AuthSessionModel? model = await _remoteDataSource.signUp(
        email: email,
        password: password,
        fullName: fullName,
        companyName: companyName,
      );
      return model?.toEntity();
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSupabaseAuthException(error, stackTrace);
    } on AuthException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknownException(error, stackTrace, operation: 'signUp');
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _remoteDataSource.signOut();
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSupabaseAuthException(error, stackTrace);
    } on AuthException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknownException(error, stackTrace, operation: 'logout');
    }
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    try {
      await _remoteDataSource.updatePassword(newPassword: newPassword);
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapSupabaseAuthException(error, stackTrace);
    } on AuthException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknownException(error, stackTrace, operation: 'changePassword');
    }
  }

  static AuthSession? _toEntityOrNull(AuthSessionModel? model) =>
      model?.toEntity();

  static AuthException _mapSupabaseAuthException(
    supabase.AuthException error,
    StackTrace stackTrace,
  ) {
    final AuthFailureType type = _classify(error);
    AppLogger.warning(
      'Supabase auth error mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}, '
      'status: ${error.statusCode ?? 'n/a'}).',
    );
    return AuthException(type: type, cause: error, stackTrace: stackTrace);
  }

  static AuthException _mapUnknownException(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final AuthFailureType type = _looksLikeNetworkFailure(error)
        ? AuthFailureType.network
        : AuthFailureType.unknown;
    AppLogger.error(
      'Unhandled auth error during "$operation" '
      '(runtimeType: ${error.runtimeType}).',
      error,
      stackTrace,
    );
    return AuthException(type: type, cause: error, stackTrace: stackTrace);
  }

  static AuthFailureType _classify(supabase.AuthException error) {
    final String? rawCode = error.code;
    final String code = (rawCode ?? '').toLowerCase();
    final String message = error.message.toLowerCase();

    final String? rawStatus = error.statusCode;
    final int? status = rawStatus == null ? null : int.tryParse(rawStatus);

    switch (code) {
      case 'invalid_credentials':
      case 'invalid_grant':
        return AuthFailureType.invalidCredentials;
      case 'email_not_confirmed':
      case 'email_not_verified':
        return AuthFailureType.emailNotConfirmed;
      case 'user_not_found':
        return AuthFailureType.userNotFound;
      case 'user_already_exists':
      case 'email_exists':
        return AuthFailureType.emailAlreadyInUse;
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'too_many_requests':
        return AuthFailureType.tooManyRequests;
      case 'weak_password':
        return AuthFailureType.weakPassword;
      case 'request_failed':
      case 'network_error':
        return AuthFailureType.network;
    }

    if (status == 400) return AuthFailureType.invalidCredentials;
    if (status == 401) return AuthFailureType.invalidCredentials;
    if (status == 403) return AuthFailureType.emailNotConfirmed;
    if (status == 404) return AuthFailureType.userNotFound;
    if (status == 422) {
      if (message.contains('password')) {
        return AuthFailureType.weakPassword;
      }
      if (message.contains('already') || message.contains('exists')) {
        return AuthFailureType.emailAlreadyInUse;
      }
      return AuthFailureType.unknown;
    }
    if (status == 429) return AuthFailureType.tooManyRequests;

    if (message.contains('already') && message.contains('regist')) {
      return AuthFailureType.emailAlreadyInUse;
    }

    if (_messageLooksLikeNetwork(message)) {
      return AuthFailureType.network;
    }
    return AuthFailureType.unknown;
  }

  static bool _looksLikeNetworkFailure(Object error) {
    if (error is AuthException) {
      return error.type == AuthFailureType.network;
    }
    return _messageLooksLikeNetwork(error.toString().toLowerCase());
  }

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }
}
