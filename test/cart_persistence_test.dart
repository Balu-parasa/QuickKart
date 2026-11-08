import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/catalog/domain/product.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import 'helpers/test_harness.dart';

Product productFromSnapshot(ServerProductSnapshot s, {String emoji = '🍌', String unit = '1 pc'}) =>
    Product(
      id: s.id,
      name: s.name,
      categoryId: s.categoryId,
      emoji: emoji,
      unit: unit,
      pricePaise: s.pricePaise,
      mrpPaise: s.mrpPaise,
      stock: s.stock,
      maxPerOrder: s.maxPerOrder,
    );

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('QK-101: decrementing a product quantity persists across app restart', () async {
    // 1. Setup: add 2 units of banana to the cart
    final banana = productFromSnapshot(h.server.product('fruits-01'), emoji: '🍌', unit: '6 pcs');
    final controller = h.read(cartControllerProvider.notifier);
    await controller.add(banana);
    await controller.increment(banana.id);
    expect(h.read(cartControllerProvider).quantityOf(banana.id), 2);

    // 2. Action: decrement banana from 2 to 1
    await controller.decrement(banana.id);
    expect(h.read(cartControllerProvider).quantityOf(banana.id), 1);

    // 3. Simulate app restart: same key-value store, fresh provider container
    final restartedHarness = h.restart();
    final restoredCart = await restartedHarness.read(cartStorageProvider).load();
    restartedHarness.read(cartControllerProvider.notifier).hydrate(restoredCart);

    // 4. Verify: restored cart must have 1 banana, not 2
    expect(
      restartedHarness.read(cartControllerProvider).quantityOf(banana.id),
      1,
      reason: 'Cart should persist decremented quantity across restart',
    );
    restartedHarness.dispose();
  });

  test('QK-101: removing a product persists across app restart', () async {
    // 1. Setup: add banana and milk to the cart
    final banana = productFromSnapshot(h.server.product('fruits-01'), emoji: '🍌', unit: '6 pcs');
    final milk = productFromSnapshot(h.server.product('dairy-01'), emoji: '🥛', unit: '500 ml');
    final controller = h.read(cartControllerProvider.notifier);
    await controller.add(banana);
    await controller.add(milk);
    expect(h.read(cartControllerProvider).lines.length, 2);

    // 2. Action: remove banana completely
    await controller.remove(banana.id);
    expect(h.read(cartControllerProvider).lineFor(banana.id), isNull);
    expect(h.read(cartControllerProvider).lines.length, 1);

    // 3. Simulate app restart
    final restartedHarness = h.restart();
    final restoredCart = await restartedHarness.read(cartStorageProvider).load();
    restartedHarness.read(cartControllerProvider.notifier).hydrate(restoredCart);

    // 4. Verify: removed product must not reappear after restart
    expect(
      restartedHarness.read(cartControllerProvider).lineFor(banana.id),
      isNull,
      reason: 'Removed product must not reappear in cart after restart',
    );
    expect(restartedHarness.read(cartControllerProvider).lines.length, 1);
    restartedHarness.dispose();
  });

  test('QK-101: removing a coupon persists across app restart', () async {
    // 1. Setup: add product and apply coupon
    final banana = productFromSnapshot(h.server.product('fruits-01'), emoji: '🍌', unit: '6 pcs');
    final controller = h.read(cartControllerProvider.notifier);
    await controller.add(banana);

    final coupon = Coupon(
      code: 'FLAT50',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 29900,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      description: 'Flat ₹50 off',
    );
    await controller.applyCoupon(coupon);
    expect(h.read(cartControllerProvider).coupon, isNotNull);

    // 2. Action: remove coupon
    await controller.removeCoupon();
    expect(h.read(cartControllerProvider).coupon, isNull);

    // 3. Simulate app restart
    final restartedHarness = h.restart();
    final restoredCart = await restartedHarness.read(cartStorageProvider).load();
    restartedHarness.read(cartControllerProvider.notifier).hydrate(restoredCart);

    // 4. Verify: coupon must remain removed after restart
    expect(
      restartedHarness.read(cartControllerProvider).coupon,
      isNull,
      reason: 'Removed coupon must remain removed after restart',
    );
    restartedHarness.dispose();
  });
}

