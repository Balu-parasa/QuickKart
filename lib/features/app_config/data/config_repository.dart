import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  static const _storageKey = 'config.v1';

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  Future<AppConfig> load() async {
    try {
      final json = await _client.get('/v1/config', refresh: true);
      if (json is Map && json['values'] is Map) {
        final values = (json['values'] as Map).cast<String, Object?>();
        try {
          await _store.setString(_storageKey, jsonEncode(values));
        } catch (_) {
          // Local storage write failure should not prevent returning fresh config
        }
        return AppConfig.fromValues(values);
      }
      // Malformed server response payload falls back to cache or defaults
      return await _loadFromCacheOrDefault();
    } catch (_) {
      // Handles ApiException, FormatException, TypeError, and any other transport or decoding errors
      return await _loadFromCacheOrDefault();
    }
  }

  Future<AppConfig> _loadFromCacheOrDefault() async {
    try {
      final cached = await _store.getString(_storageKey);
      if (cached != null) {
        final decoded = jsonDecode(cached);
        if (decoded is Map) {
          return AppConfig.fromValues(decoded.cast<String, Object?>());
        }
      }
    } catch (_) {
      // Corrupt cache or storage read failure safely falls back to defaults
    }
    return AppConfig.defaults();
  }
}
