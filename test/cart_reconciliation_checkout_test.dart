import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  // ===========================================================================
  // Part B: CartReconciler Unit Tests
  // ===========================================================================
  group('Part B: CartReconciler.reconcile()', () {
    test('detects price increases and marks requiresUserReview as true', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine.fromProduct(banana, quantity: 2),
      ]);

      // Server price increases by ₹10 (1000 paise)
      final newPrice = banana.pricePaise + 1000;
      h.server.setPrice('fruits-01', newPrice);

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isTrue);
      expect(result.cart.lineFor('fruits-01')!.unitPricePaise, equals(newPrice));
      expect(
        result.changes.any((c) => c is PriceChanged && c.productId == 'fruits-01' && c.requiresUserReview),
        isTrue,
      );
    });

    test('detects price drops and applies them silently (requiresUserReview == false)', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine.fromProduct(banana, quantity: 2),
      ]);

      // Server price drops by ₹5 (500 paise)
      final newPrice = banana.pricePaise - 500;
      h.server.setPrice('fruits-01', newPrice);

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isFalse);
      expect(result.cart.lineFor('fruits-01')!.unitPricePaise, equals(newPrice));
      expect(
        result.changes.any((c) => c is PriceChanged && c.productId == 'fruits-01' && !c.requiresUserReview),
        isTrue,
      );
    });

    test('detects out of stock and removes item with review required', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine.fromProduct(banana, quantity: 2),
      ]);

      h.server.setStock('fruits-01', 0);

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isTrue);
      expect(result.cart.lineFor('fruits-01'), isNull);
      expect(result.changes.any((c) => c is OutOfStock && c.productId == 'fruits-01'), isTrue);
    });

    test('detects quantity limit reduction and adjusts quantity with review required', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine.fromProduct(banana, quantity: 4),
      ]);

      // Reduce available stock to 2
      h.server.setStock('fruits-01', 2);

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isTrue);
      expect(result.cart.lineFor('fruits-01')!.quantity, equals(2));
      expect(
        result.changes.any((c) => c is QuantityReduced && c.productId == 'fruits-01' && c.availableQuantity == 2),
        isTrue,
      );
    });

    test('removes discontinued / inactive products as ProductUnavailable', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine.fromProduct(banana, quantity: 2),
      ]);

      // Server discontinues banana
      h.server.setActive('fruits-01', false);

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isTrue);
      expect(result.cart.lineFor('fruits-01'), isNull);
      expect(result.changes.any((c) => c is ProductUnavailable && c.productId == 'fruits-01'), isTrue);
    });

    test('removes expired coupons with review required', () async {
      final banana = h.server.product('fruits-01');
      final coupon = Coupon(
        code: 'SAVE10',
        type: CouponType.percent,
        value: 10,
        minOrderPaise: 19900,
        expiresAt: DateTime.now().add(const Duration(days: 10)),
      );
      final cart = Cart(
        lines: [CartLine.fromProduct(banana, quantity: 5)],
        coupon: coupon,
      );

      // Expire coupon on server
      h.server.expireCoupon('SAVE10');

      final reconciler = h.read(cartReconcilerProvider);
      final result = await reconciler.reconcile(cart);

      expect(result.hasChanges, isTrue);
      expect(result.requiresUserReview, isTrue);
      expect(result.cart.coupon, isNull);
      expect(result.changes.any((c) => c is CouponRemoved && c.code == 'SAVE10'), isTrue);
    });
  });

  // ===========================================================================
  // Part B: Safe Checkout & Idempotency Integration Tests
  // ===========================================================================
  group('Part B: Safe Checkout & Idempotency', () {
    test('checkout returns CheckoutNeedsReview when server state has conflicts', () async {
      final banana = h.server.product('fruits-01');
      final cartController = h.read(cartControllerProvider.notifier);
      await cartController.add(banana);

      // Mutate price on server
      h.server.setPrice('fruits-01', banana.pricePaise + 500);

      final checkout = h.read(checkoutControllerProvider.notifier);
      final result = await checkout.placeOrder();

      expect(result, isA<CheckoutNeedsReview>());
      // Order must NOT have been placed on server
      expect(h.server.orderCount, equals(0));
      // Local cart must have been updated to the reconciled cart
      expect(h.read(cartControllerProvider).lineFor(banana.id)!.unitPricePaise, equals(banana.pricePaise + 500));
    });

    test('lost order response does NOT create duplicate orders on retry (idempotency)', () async {
      final banana = h.server.product('fruits-01');
      final cartController = h.read(cartControllerProvider.notifier);
      await cartController.add(banana);

      // Simulate lost response on server: server receives order and processes it, but client drops response
      h.server.chaos.loseNextOrderResponses = 1;

      final checkout = h.read(checkoutControllerProvider.notifier);
      final result = await checkout.placeOrder();

      // With idempotency and timeout retry, the order succeeds and only 1 order exists on server
      expect(result, isA<CheckoutSuccess>());
      expect(h.server.orderCount, equals(1));
    });

    test('double tap / concurrent calls do not create duplicate orders', () async {
      final banana = h.server.product('fruits-01');
      final cartController = h.read(cartControllerProvider.notifier);
      await cartController.add(banana);

      final checkout = h.read(checkoutControllerProvider.notifier);
      // Trigger two placeOrder calls concurrently
      final future1 = checkout.placeOrder();
      final future2 = checkout.placeOrder();

      final results = await Future.wait([future1, future2]);

      expect(h.server.orderCount, equals(1));
      expect(results.any((r) => r is CheckoutSuccess), isTrue);
    });

    test('checkout while store is closed fails with honest message without sending request', () async {
      final banana = h.server.product('fruits-01');
      await h.read(cartControllerProvider.notifier).add(banana);

      // Close store via remote config
      h.server.publishConfig({
        'store_open': false,
        'store_closed_message': 'We are closed due to rain',
      });
      h.read(appConfigControllerProvider.notifier).hydrate(
            AppConfig.fromValues(h.server.configValues),
          );

      final initialRequests = h.server.requestLog.length;

      final checkout = h.read(checkoutControllerProvider.notifier);
      final result = await checkout.placeOrder();

      expect(result, isA<CheckoutFailure>());
      final failure = result as CheckoutFailure;
      expect(failure.message, contains('closed'));
      expect(failure.canRetry, isFalse);
      // No POST /v1/orders request was sent
      expect(h.server.requestLog.length, equals(initialRequests));
      expect(h.server.orderCount, equals(0));
    });

    test('offline checkout fails with honest network message', () async {
      final banana = h.server.product('fruits-01');
      await h.read(cartControllerProvider.notifier).add(banana);

      h.server.chaos.offline = true;

      final checkout = h.read(checkoutControllerProvider.notifier);
      final result = await checkout.placeOrder();

      expect(result, isA<CheckoutFailure>());
      final failure = result as CheckoutFailure;
      expect(failure.canRetry, isTrue);
      expect(failure.message, contains('connection'));
      expect(h.server.orderCount, equals(0));
    });
  });
}
