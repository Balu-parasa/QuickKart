import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  // ===========================================================================
  // 1. ConfigRepository persistence and offline fallback
  // ===========================================================================
  group('Part C: ConfigRepository caching & offline resilience', () {
    test('successful load persists configuration to KeyValueStore under config.v1', () async {
      // Configure non-default delivery fee on server
      h.server.publishConfig({
        'delivery_fee_paise': 4500,
        'free_delivery_threshold_paise': 30000,
      });

      final repo = h.read(configRepositoryProvider);
      final config = await repo.load();

      expect(config.deliveryFeePaise, equals(4500));
      expect(config.freeDeliveryThresholdPaise, equals(30000));

      // Verify that data was written to KeyValueStore with key 'config.v1'
      final rawStored = await h.store.getString('config.v1');
      expect(rawStored, isNotNull, reason: 'Config must be stored in KeyValueStore under config.v1');
      final jsonMap = jsonDecode(rawStored!) as Map<String, dynamic>;
      expect(jsonMap['delivery_fee_paise'], equals(4500));
    });

    test('offline start with cached data uses last known good config instead of defaults', () async {
      // 1. Initial successful fetch saves to store
      h.server.publishConfig({
        'delivery_fee_paise': 5000,
        'store_closed_message': 'Custom closed message',
      });
      final repo = h.read(configRepositoryProvider);
      await repo.load();

      // 2. Simulate restarting the app in offline mode with same storage
      final restartedHarness = h.restart();
      try {
        restartedHarness.server.chaos.offline = true;

        final offlineRepo = restartedHarness.read(configRepositoryProvider);
        final offlineConfig = await offlineRepo.load();

        expect(offlineConfig.deliveryFeePaise, equals(5000),
            reason: 'Offline load should return cached delivery fee from last known good config');
        expect(offlineConfig.storeClosedMessage, equals('Custom closed message'),
            reason: 'Offline load should return cached store closed message');
      } finally {
        restartedHarness.dispose();
      }
    });

    test('offline start with no cached data falls back safely to AppConfig.defaults() without throwing', () async {
      h.server.chaos.offline = true;
      final repo = h.read(configRepositoryProvider);

      final config = await repo.load();

      expect(config.deliveryFeePaise, equals(AppConfig.defaults().deliveryFeePaise));
      expect(config.storeOpen, isTrue);
    });

    test('corrupted cache or storage read failure falls back safely to defaults', () async {
      // Intentionally write corrupt non-JSON string into KeyValueStore
      await h.store.setString('config.v1', '{invalid_json:');
      h.server.chaos.offline = true;

      final repo = h.read(configRepositoryProvider);
      final config = await repo.load();

      expect(config.deliveryFeePaise, equals(AppConfig.defaults().deliveryFeePaise));
      expect(config.storeOpen, isTrue);
    });
  });

  // ===========================================================================
  // 2. Live configuration updates in bare ProviderContainer
  // ===========================================================================
  group('Part C: AppConfigController live updates in bare container', () {
    test('AppConfigController updates automatically on remoteUpdates without app restart', () async {
      // In bare ProviderContainer, listen to appConfigControllerProvider
      h.container.read(appConfigControllerProvider.notifier);
      final initialConfig = h.container.read(appConfigControllerProvider);
      expect(initialConfig.deliveryFeePaise, equals(2500));

      // Publish new configuration from the server / console
      h.server.publishConfig({
        'delivery_fee_paise': 3500,
        'store_open': false,
      });

      // Allow stream event and microtask to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedConfig = h.container.read(appConfigControllerProvider);
      expect(
        updatedConfig.deliveryFeePaise,
        equals(3500),
        reason: 'AppConfigController should update its state on server configUpdates without restart',
      );
      expect(
        updatedConfig.storeOpen,
        isFalse,
        reason: 'AppConfigController should reflect live store_open change',
      );
    });
  });

  // ===========================================================================
  // 3. UpdatePolicy.evaluate unit tests
  // ===========================================================================
  group('Part C: UpdatePolicy.evaluate', () {
    test('returns required when current version is strictly less than minSupportedVersion', () {
      final requirement = UpdatePolicy.evaluate(
        currentVersion: '1.3.0',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      );
      expect(requirement, equals(UpdateRequirement.required));
    });

    test('returns optional when current is >= minSupported but less than latestVersion', () {
      final requirement = UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      );
      expect(requirement, equals(UpdateRequirement.optional));
    });

    test('returns none when current version is equal to or newer than latestVersion', () {
      final requirement = UpdatePolicy.evaluate(
        currentVersion: '1.5.0',
        minSupportedVersion: '1.4.0',
        latestVersion: '1.5.0',
      );
      expect(requirement, equals(UpdateRequirement.none));
    });

    test('handles missing segments correctly by treating missing segment as 0', () {
      // 1.4 == 1.4.0
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.4',
        ),
        equals(UpdateRequirement.none),
      );

      // 1.4 < 1.4.1
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4',
          minSupportedVersion: '1.0.0',
          latestVersion: '1.4.1',
        ),
        equals(UpdateRequirement.optional),
      );
    });

    test('compares multi-digit segments numerically rather than lexicographically', () {
      // 1.10.0 is newer than 1.4.0
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.10.0',
          minSupportedVersion: '1.4.0',
          latestVersion: '1.4.0',
        ),
        equals(UpdateRequirement.none),
      );

      // 1.4.0 is older than 1.10.0
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.2.0',
          latestVersion: '1.10.0',
        ),
        equals(UpdateRequirement.optional),
      );
    });

    test('returns UpdateRequirement.none safely when ANY version string is malformed', () {
      // Letters or non-digits
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0-beta',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        equals(UpdateRequirement.none),
      );

      // Empty string
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        equals(UpdateRequirement.none),
      );

      // Negative segment
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.-4.0',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        equals(UpdateRequirement.none),
      );

      // Malformed minSupportedVersion
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: 'invalid',
          latestVersion: '2.0.0',
        ),
        equals(UpdateRequirement.none),
      );

      // Malformed latestVersion alone
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.0.0',
          latestVersion: 'broken',
        ),
        equals(UpdateRequirement.none),
      );
    });
  });

  // ===========================================================================
  // 4. HomeLayout.parse unit tests
  // ===========================================================================
  group('Part C: HomeLayout.parse', () {
    test('parses valid JSON array and preserves order', () {
      final json = jsonEncode(['deals', 'banner', 'categories', 'all_products']);
      final sections = HomeLayout.parse(json);

      expect(sections, equals([
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.categories,
        HomeSection.allProducts,
      ]));
    });

    test('ignores unknown section IDs without failing', () {
      final json = jsonEncode(['banner', 'stories_carousel', 'live_stream', 'categories']);
      final sections = HomeLayout.parse(json);

      expect(sections, equals([
        HomeSection.banner,
        HomeSection.categories,
      ]));
    });

    test('deduplicates sections while keeping first occurrence order', () {
      final json = jsonEncode(['deals', 'banner', 'deals', 'categories', 'banner']);
      final sections = HomeLayout.parse(json);

      expect(sections, equals([
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.categories,
      ]));
    });

    test('falls back to defaultSections on null, malformed JSON, or non-array', () {
      expect(HomeLayout.parse(null), equals(HomeLayout.defaultSections));
      expect(HomeLayout.parse(''), equals(HomeLayout.defaultSections));
      expect(HomeLayout.parse('{not: array}'), equals(HomeLayout.defaultSections));
      expect(HomeLayout.parse('["broken JSON,'), equals(HomeLayout.defaultSections));
      expect(HomeLayout.parse(jsonEncode(['unknown1', 'unknown2'])), equals(HomeLayout.defaultSections));
    });
  });
}

