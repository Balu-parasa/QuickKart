import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/app.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/catalog/presentation/home_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

void main() {
  late InMemoryKeyValueStore store;
  late MockServer server;

  setUp(() {
    store = InMemoryKeyValueStore();
    server = MockServer.inMemory();
  });

  Widget buildApp({String appVersion = '1.0.0'}) {
    final config = AppConfig.fromValues(server.configValues);
    return ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        mockServerProvider.overrideWithValue(server),
        appVersionProvider.overrideWithValue(appVersion),
        appConfigControllerProvider.overrideWith(() {
          final notifier = AppConfigController();
          return notifier;
        }),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          // Hydrate initially like main.dart
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(appConfigControllerProvider.notifier).hydrate(config);
          });
          return const QuickKartApp();
        },
      ),
    );
  }

  testWidgets('Normal navigation works when no update is required', (tester) async {
    server.publishConfig({
      'min_supported_version': '1.0.0',
      'latest_version': '1.0.0',
    });

    await tester.pumpWidget(buildApp(appVersion: '1.0.0'));
    await tester.pumpAndSettle();

    // Verify Home Screen is present
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Update required'), findsNothing);

    // Open Dev Tools
    final devToolsButton = find.byTooltip('Dev tools');
    expect(devToolsButton, findsOneWidget);
    await tester.tap(devToolsButton);
    await tester.pumpAndSettle();

    // Verify Dev Tools screen opened
    expect(find.text('🛠 Dev tools'), findsOneWidget);

    // Pop back to Home
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Optional update is dismissible and leaves app usable', (tester) async {
    server.publishConfig({
      'min_supported_version': '1.0.0',
      'latest_version': '1.2.0',
    });

    await tester.pumpWidget(buildApp(appVersion: '1.0.0'));
    await tester.pumpAndSettle();

    // Dialog should appear
    expect(find.text('New version available'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);

    // Dismiss dialog via Later
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // Dialog should be gone, home screen interactable
    expect(find.text('New version available'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('Hardware Back does not pop root or exit while update is required', (tester) async {
    server.publishConfig({
      'min_supported_version': '2.0.0',
      'latest_version': '2.0.0',
    });

    await tester.pumpWidget(buildApp(appVersion: '1.0.0'));
    await tester.pumpAndSettle();

    // Force update screen is visible
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);

    // Attempt hardware Back gesture / pop
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // In unfixed code without PopScope(canPop: false), didPopRoute returns false (or exits).
    // PopScope(canPop: false) intercepts hardware back gestures.
    expect(find.byType(PopScope), findsWidgets);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('Required update arriving dynamically dismisses pushed routes and blocks access', (tester) async {
    server.publishConfig({
      'min_supported_version': '1.0.0',
      'latest_version': '1.0.0',
    });

    await tester.pumpWidget(buildApp(appVersion: '1.0.0'));
    await tester.pumpAndSettle();

    // Open Dev Tools
    await tester.tap(find.byTooltip('Dev tools'));
    await tester.pumpAndSettle();
    expect(find.text('🛠 Dev tools'), findsOneWidget);

    // Simulate remote config update pushing min_supported_version to 2.0.0
    server.publishConfig({
      'min_supported_version': '2.0.0',
      'latest_version': '2.0.0',
    });
    // Let AppConfigController stream and state update
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Pushed route (Dev Tools) must be gone or blocked; Force Update screen must be displayed
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('🛠 Dev tools'), findsNothing);

    // Attempt back gesture
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
  });
}

