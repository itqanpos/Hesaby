// lib/core/network/network_status_provider.dart

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// Coarse-grained network availability, as reported by the OS.
///
/// Note: this only tells us whether the device has *any* active interface
/// (Wi-Fi, mobile, ethernet). It does **not** guarantee that a specific
/// server (e.g. Supabase) is reachable — for that we rely on request
/// failures and the offline queue (Phase O-2).
enum NetworkStatus { online, offline }

/// Emits [NetworkStatus] whenever the OS reports a change.
///
/// Starts in [AsyncLoading] until the first event arrives; consumers that
/// need a synchronous answer should use [isOnlineProvider], which defaults
/// to `true` while loading.
final StreamProvider<NetworkStatus> networkStatusStreamProvider =
    StreamProvider<NetworkStatus>((Ref ref) {
  final Connectivity connectivity = Connectivity();

  return connectivity.onConnectivityChanged
      .map(_mapConnectivity)
      .handleError((Object error, StackTrace stackTrace) {
    AppLogger.warning('Connectivity stream error (non-fatal): $error');
  });
});

/// Boolean convenience view of [networkStatusStreamProvider].
///
/// Returns `true` while the first event is still pending — this avoids a
/// brief "offline" flash at cold start.
final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  final AsyncValue<NetworkStatus> status =
      ref.watch(networkStatusStreamProvider);
  return status.maybeWhen(
    data: (NetworkStatus s) => s == NetworkStatus.online,
    orElse: () => true,
  );
});

/// Maps the list of connectivity results from `connectivity_plus` into a
/// single [NetworkStatus].
///
/// The device is considered offline only when the list is empty or every
/// entry is [ConnectivityResult.none]. Anything else means at least one
/// interface is up.
NetworkStatus _mapConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty) return NetworkStatus.offline;
  final bool allNone = results.every(
    (ConnectivityResult r) => r == ConnectivityResult.none,
  );
  return allNone ? NetworkStatus.offline : NetworkStatus.online;
}
