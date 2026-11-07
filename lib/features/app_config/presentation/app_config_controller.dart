import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  StreamSubscription<int>? _subscription;
  int _updateRequestId = 0;

  @override
  AppConfig build() {
    final repo = ref.read(configRepositoryProvider);
    _subscription?.cancel();
    _subscription = repo.remoteUpdates.listen((_) async {
      final currentRequestId = ++_updateRequestId;
      final config = await repo.load();
      if (currentRequestId == _updateRequestId) {
        state = config;
      }
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
      _updateRequestId++;
    });

    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  Future<void> refresh() async {
    final currentRequestId = ++_updateRequestId;
    final config = await ref.read(configRepositoryProvider).load();
    if (currentRequestId == _updateRequestId) {
      state = config;
    }
  }
}
