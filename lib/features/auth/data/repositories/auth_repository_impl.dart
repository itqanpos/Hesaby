// lib/features/auth/data/repositories/auth_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_session_model.dart';

/// Concrete implementation of [AuthRepository] backed by Supabase Auth.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate Supabase session models into pure [AuthSession] entities.
/// * Translate Supabase and low-level errors into safe [AuthException]s
///   carrying an [AuthFailureType]. Raw backend messages never leave this
///   layer, and no credential or token is ever logged.
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
          .signInWithPassword(
            email: email,
            password: password,
          );
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

    return AuthException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static AuthException _mapUnknownException(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final bool looksLikeNetwork = _looksLikeNetworkFailure(error);
    final AuthFailureType type = looksLikeNetwork
        ? AuthFailureType.network
        : AuthFailureType.unknown;

    AppLogger.error(
      'Unhandled auth error during "$operation" '
      '(runtimeType: ${error.runtimeType}).',
      error,
      stackTrace,
    );

    return AuthException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static AuthFailureType _classify(supabase.AuthException error) {
    final String? rawCode = error.code;
    final String code = (rawCode ?? '').toLowerCase();
    final String message = error.message.toLowerCase();

    // `statusCode` is delivered by supabase_flutter as a `String?`, since it
    // originates from an HTTP response header. It is parsed to an `int?` so
    // that the classification below can use numeric comparisons. A
    // non-numeric value (unexpected) safely falls back to `null` and skips
    // the numeric branches.
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
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'too_many_requests':
        return AuthFailureType.tooManyRequests;
      case 'request_failed':
      case 'network_error':
        return AuthFailureType.network;
    }

    if (status == 400) {
      return AuthFailureType.invalidCredentials;
    }
    if (status == 401) {
      return AuthFailureType.invalidCredentials;
    }
    if (status == 403) {
      return AuthFailureType.emailNotConfirmed;
    }
    if (status == 404) {
      return AuthFailureType.userNotFound;
    }
    if (status == 429) {
      return AuthFailureType.tooManyRequests;
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
    final String description = error.toString().toLowerCase();
    return _messageLooksLikeNetwork(description);
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
