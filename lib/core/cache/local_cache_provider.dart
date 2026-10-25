// lib/core/cache/local_cache_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'json_local_cache.dart';

/// Provides a ready-to-use [JsonLocalCache].
final FutureProvider<JsonLocalCache> jsonLocalCacheProvider =
    FutureProvider<JsonLocalCache>((ref) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return JsonLocalCache(prefs);
});
