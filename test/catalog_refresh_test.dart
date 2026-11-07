import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  // ---------------------------------------------------------------------------
  // Test 1: API GET cache bypass
  // Verifies that a GET request can bypass the in-memory cache to fetch fresh
  // server data when explicit refresh/bypass is requested.
  // ---------------------------------------------------------------------------
  test('QK-102: API GET cache bypass retrieves updated server data on refresh', () async {
    final client = h.read(apiClientProvider);

    // Initial fetch of dairy products
    final firstResponse =
        await client.get('/v1/products', query: {'category': 'dairy', 'limit': '10'})
            as Map<String, dynamic>;
    final itemsFirst = firstResponse['items'] as List;
    final initialEggPrice =
        itemsFirst.firstWhere((e) => e['id'] == 'dairy-03')['price'] as num;

    // Mutate the price on the server: increase Farm Eggs (dairy-03) by ₹10 (1000 paise)
    final eggSnapshot = h.server.product('dairy-03');
    h.server.setPrice('dairy-03', eggSnapshot.pricePaise + 1000);

    // Fetch again with refresh/bypass (using refresh: true)
    // In unfixed code, client.get does not support refresh parameter or ignores it, returning cached data.
    final refreshedResponse =
        await client.get('/v1/products', query: {'category': 'dairy', 'limit': '10'}, refresh: true)
            as Map<String, dynamic>;
    final itemsRefreshed = refreshedResponse['items'] as List;
    final updatedEggPrice =
        itemsRefreshed.firstWhere((e) => e['id'] == 'dairy-03')['price'] as num;

    expect(
      updatedEggPrice,
      isNot(equals(initialEggPrice)),
      reason: 'Bypassing cache on refresh must return the updated price from the server',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 2: Normal cache behavior
  // Verifies standard GET requests continue using in-memory cache within TTL
  // when refresh is not requested (refresh defaults to false).
  // ---------------------------------------------------------------------------
  test('QK-102: standard GET requests use in-memory cache when refresh is false', () async {
    final client = h.read(apiClientProvider);

    final initial =
        await client.get('/v1/products', query: {'category': 'dairy', 'limit': '10'})
            as Map<String, dynamic>;
    final initialEggPrice =
        (initial['items'] as List).firstWhere((e) => e['id'] == 'dairy-03')['price'] as num;

    // Mutate price on server
    final eggSnapshot = h.server.product('dairy-03');
    h.server.setPrice('dairy-03', eggSnapshot.pricePaise + 1000);

    // Standard GET without refresh flag
    final cachedResponse =
        await client.get('/v1/products', query: {'category': 'dairy', 'limit': '10'})
            as Map<String, dynamic>;
    final cachedEggPrice =
        (cachedResponse['items'] as List).firstWhere((e) => e['id'] == 'dairy-03')['price'] as num;

    expect(
      cachedEggPrice,
      equals(initialEggPrice),
      reason: 'Normal GET requests without refresh must continue serving cached response within TTL',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 3: Catalog refresh updates prices & offline fallback remains intact
  // ---------------------------------------------------------------------------
  test('QK-102: catalog refresh shows updated price and preserves offline cache fallback', () async {
    final controller =
        h.container.read(catalogControllerProvider('fruits').notifier);

    // Allow microtask from build() to populate initial state and persist page to CatalogCache
    await Future<void>.delayed(Duration.zero);
    final initialBanana = h.container
        .read(catalogControllerProvider('fruits'))
        .items
        .firstWhere((p) => p.id == 'fruits-01');
    final initialPrice = initialBanana.pricePaise;

    // Mutate banana price on server
    h.server.setPrice('fruits-01', initialPrice + 500);

    // Trigger pull-to-refresh
    await controller.refresh();

    final refreshedBanana = h.container
        .read(catalogControllerProvider('fruits'))
        .items
        .firstWhere((p) => p.id == 'fruits-01');

    expect(
      refreshedBanana.pricePaise,
      equals(initialPrice + 500),
      reason: 'Pull-to-refresh must display updated price from server',
    );

    // Verify offline fallback through CatalogCache:
    // Because _loadFirstPage and refresh both call getPage(), the page is written to h.store
    // via CatalogCache.write('page.first', page). When we restart, restartedHarness uses h.store.
    final restartedHarness = h.restart();
    try {
      restartedHarness.server.chaos.offline = true;

      final offlinePage = await restartedHarness
          .read(catalogRepositoryProvider)
          .getPage(categoryId: 'fruits');

      expect(offlinePage.fromCache, isTrue);
      expect(offlinePage.items, isNotEmpty);
    } finally {
      restartedHarness.dispose();
    }
  });

  // ---------------------------------------------------------------------------
  // Test 4: Orders refresh reflects newly placed order
  // ---------------------------------------------------------------------------
  test('QK-102: orders refresh fetches newly placed order instead of stale cached list', () async {
    final trackingRepo = h.read(orderTrackingRepositoryProvider);
    final orderApi = h.read(orderApiProvider);

    // 1. Initial orders fetch (empty list, cached by ApiClient in unfixed code)
    final initialOrders = await trackingRepo.getOrders();
    expect(initialOrders, isEmpty);

    // 2. Place an order on the server
    final banana = h.server.product('fruits-01');
    final cart = Cart(lines: [
      CartLine(
        productId: banana.id,
        name: banana.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: banana.pricePaise,
        quantity: 1,
        maxPerOrder: banana.maxPerOrder,
      ),
    ]);
    final pricing = CartPricing.compute(cart, AppConfig.defaults());
    final createdOrder = await orderApi.placeOrder(cart, pricing);
    expect(createdOrder.id, isNotEmpty);

    // 3. Fetch orders list again (simulating pull-to-refresh or re-querying orders)
    // In unfixed code, ApiClient returns cached GET /v1/orders (empty list).
    // The refresh mechanism must allow getOrders() or ordersProvider refresh
    // to bypass or invalidate the stale orders cache.
    final refreshedOrders = await trackingRepo.getOrders();

    expect(
      refreshedOrders.map((o) => o.id),
      contains(createdOrder.id),
      reason: 'Fetching orders after placing an order must reflect the new order, not stale cache',
    );
  });
}
