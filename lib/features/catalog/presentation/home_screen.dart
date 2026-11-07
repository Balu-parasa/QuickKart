import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/domain/update_policy.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/paginated_catalog_view.dart';
import 'widgets/product_card.dart';

final dealsProvider = FutureProvider<CatalogPage>((ref) {
  return ref.watch(catalogRepositoryProvider).getDeals();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _dismissedOptionalVersion;

  @override
  Widget build(BuildContext context) {
    final storeName = ref.watch(mockServerProvider).storeName;
    final config = ref.watch(appConfigControllerProvider);
    final currentVersion = ref.watch(appVersionProvider);

    // Evaluate update policy
    final updateRequirement = UpdatePolicy.evaluate(
      currentVersion: currentVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );

    // If a required update is triggered, block entire app with full-screen non-dismissible view
    if (updateRequirement == UpdateRequirement.required) {
      return _ForceUpdateScreen(
        updateUrl: config.updateUrl,
        minVersion: config.minSupportedVersion,
      );
    }

    // If an optional update is available and has not been dismissed for this version, prompt
    if (updateRequirement == UpdateRequirement.optional &&
        _dismissedOptionalVersion != config.latestVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _dismissedOptionalVersion == config.latestVersion) return;
        _showOptionalUpdateDialog(context, config);
      });
    }

    final sections = HomeLayout.parse(config.homeSectionsJson);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: PaginatedCatalogView(
        categoryId: kAllProductsCategory,
        headerSlivers: [
          // Store closed prominent banner
          if (!config.storeOpen)
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_mall_directory_outlined, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        config.storeClosedMessage.isNotEmpty
                            ? config.storeClosedMessage
                            : 'The store is closed right now.',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search for products',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Search "milk", "chips"…', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
          ),

          // Dynamically rendered home sections based on parsed layout order
          for (final section in sections) ..._buildSectionSlivers(section, config),
        ],
      ),
    );
  }

  List<Widget> _buildSectionSlivers(HomeSection section, AppConfig config) {
    switch (section) {
      case HomeSection.banner:
        final banner = config.homeBanner;
        if (banner == null) return const [];
        return [
          SliverToBoxAdapter(
            child: _HomeBannerWidget(banner: banner),
          ),
        ];
      case HomeSection.categories:
        return const [
          SliverToBoxAdapter(child: _CategoriesRow()),
        ];
      case HomeSection.deals:
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Deals & Discounts 🔥',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _DealsRow()),
        ];
      case HomeSection.allProducts:
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'All products',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ];
    }
  }

  void _showOptionalUpdateDialog(BuildContext context, AppConfig config) {
    String? dialogError;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('New version available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QuickKart ${config.latestVersion} is available with improvements and fixes.',
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _dismissedOptionalVersion = config.latestVersion;
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () async {
                  final opened = await _launchUrl(config.updateUrl);
                  if (!ctx.mounted) return;
                  if (opened) {
                    setState(() {
                      _dismissedOptionalVersion = config.latestVersion;
                    });
                    Navigator.of(ctx).pop();
                  } else {
                    setDialogState(() {
                      dialogError = 'Could not open update link. Please visit the app store.';
                    });
                  }
                },
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<bool> _launchUrl(String rawUrl) async {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https')) || uri.host.isEmpty) {
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class _ForceUpdateScreen extends StatefulWidget {
  const _ForceUpdateScreen({required this.updateUrl, required this.minVersion});

  final String updateUrl;
  final String minVersion;

  @override
  State<_ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<_ForceUpdateScreen> {
  String? _errorMessage;

  Future<void> _handleUpdate() async {
    setState(() => _errorMessage = null);
    final opened = await _launchUrl(widget.updateUrl);
    if (!mounted) return;
    if (!opened) {
      setState(() {
        _errorMessage = 'Could not open update link. Please visit the app store.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Update required',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Please update QuickKart to version ${widget.minVersion} or newer to continue using the app.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _handleUpdate,
                child: const Text('Update now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBannerWidget extends StatelessWidget {
  const _HomeBannerWidget({required this.banner});

  final HomeBanner banner;

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.orange.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _parseColor(banner.colorHex);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            banner.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          if (banner.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              banner.subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _DealsRow extends ConsumerWidget {
  const _DealsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(dealsProvider);
    return SizedBox(
      height: 210,
      child: dealsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
        data: (page) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: page.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final product = page.items[index];
            return SizedBox(
              width: 140,
              child: ProductCard(product: product),
            );
          },
        ),
      ),
    );
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CategoryScreen(category: c)),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child:
                          Text(c.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
