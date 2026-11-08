import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/app_config/domain/update_policy.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/catalog/presentation/home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class QuickKartApp extends ConsumerWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigControllerProvider);
    final currentVersion = ref.watch(appVersionProvider);

    final updateRequirement = UpdatePolicy.evaluate(
      currentVersion: currentVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );

    final isForceUpdate = updateRequirement == UpdateRequirement.required;

    if (isForceUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = appNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      });
    }

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      builder: (context, child) {
        if (isForceUpdate) {
          return ForceUpdateScreen(
            updateUrl: config.updateUrl,
            minVersion: config.minSupportedVersion,
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: const HomeScreen(),
    );
  }
}
