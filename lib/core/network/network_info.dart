// lib/core/network/network_info.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signature of a connectivity probe.
typedef ConnectivityProbe = Future<bool> Function();

/// Abstraction over device connectivity.
///
/// The concrete probe is injected so that a platform connectivity plugin can
/// be wired in a later phase without touching any consumer.
abstract interface class NetworkInfo {
  /// Whether the device currently has a usable network connection.
  Future<bool> get isConnected;
}

/// Default [NetworkInfo] implementation.
final class NetworkInfoImpl implements NetworkInfo {
  const NetworkInfoImpl({ConnectivityProbe probe = _optimisticProbe})
      : _probe = probe;

  final ConnectivityProbe _probe;

  @override
  Future<bool> get isConnected => _probe();

  /// Until a platform connectivity plugin is introduced, connectivity is
  /// assumed to be available. Every network call still handles its own
  /// failures, so this only affects optimistic UI decisions.
  static Future<bool> _optimisticProbe() async => true;
}

/// Provides the application's [NetworkInfo].
final Provider<NetworkInfo> networkInfoProvider = Provider<NetworkInfo>(
  (ref) => const NetworkInfoImpl(),
);
