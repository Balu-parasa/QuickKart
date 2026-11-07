import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  static const _uuid = Uuid();
  String? _activeIdempotencyKey;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    // Guard against duplicate / double-tap submissions while an order is in flight
    if (state.isPlacingOrder) {
      if (state.lastResult != null) return state.lastResult!;
      return const CheckoutFailure('Order is already in progress, please wait...', canRetry: false);
    }

    state = const CheckoutState(isPlacingOrder: true);
    _activeIdempotencyKey ??= _uuid.v4();

    final result = await _placeOrder(
      retryOnTimeout: true,
      idempotencyKey: _activeIdempotencyKey!,
    );

    // If order succeeded or requires user review, reset the idempotency key for future checkouts
    if (result is CheckoutSuccess || result is CheckoutNeedsReview) {
      _activeIdempotencyKey = null;
    }

    state = CheckoutState(isPlacingOrder: false, lastResult: result);
    return result;
  }

  Future<CheckoutResult> _placeOrder({
    required bool retryOnTimeout,
    required String idempotencyKey,
  }) async {
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      return CheckoutFailure(
        config.storeClosedMessage.isNotEmpty
            ? config.storeClosedMessage
            : 'The store is currently closed. Please check back later.',
        canRetry: false,
      );
    }

    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty', canRetry: false);
    }

    // Step 1: Reconcile cart with current backend state before ordering
    final reconciler = ref.read(cartReconcilerProvider);
    final ReconciliationResult reconciliation;
    try {
      reconciliation = await reconciler.reconcile(cart);
    } on NetworkException {
      return const CheckoutFailure(
        'Cannot reach the store. Please check your internet connection.',
        canRetry: true,
      );
    } on ApiTimeoutException {
      return const CheckoutFailure(
        'Checking store prices timed out. Please try again.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }

    // If reconciliation found differences that require customer review, update cart and block order
    if (reconciliation.requiresUserReview) {
      await ref.read(cartControllerProvider.notifier).replace(reconciliation.cart);
      return CheckoutNeedsReview(reconciliation);
    }

    // Apply any silent updates (e.g. price drops)
    final orderCart = reconciliation.cart;
    if (orderCart != cart) {
      await ref.read(cartControllerProvider.notifier).replace(orderCart);
    }

    final pricing = CartPricing.compute(orderCart, config);

    // Step 2: Submit order with Idempotency-Key
    try {
      final order = await ref.read(orderApiProvider).placeOrder(
            orderCart,
            pricing,
            idempotencyKey: idempotencyKey,
          );
      await ref.read(cartControllerProvider.notifier).clear();
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // Retry once using the exact same Idempotency-Key so no duplicate order can be created
      if (retryOnTimeout) {
        return _placeOrder(
          retryOnTimeout: false,
          idempotencyKey: idempotencyKey,
        );
      }
      return const CheckoutFailure(
        'The request timed out. Your order may have been placed. Please check "My orders" before trying again.',
        canRetry: true,
      );
    } on ClientException catch (e) {
      if (e.code == 'STORE_CLOSED') {
        return CheckoutFailure(
          config.storeClosedMessage.isNotEmpty
              ? config.storeClosedMessage
              : 'The store is currently closed.',
          canRetry: false,
        );
      }
      if (e.code == 'PRICE_CHANGED' ||
          e.code == 'INSUFFICIENT_STOCK' ||
          e.code == 'PRODUCT_UNAVAILABLE' ||
          e.code == 'QUANTITY_LIMIT' ||
          e.code == 'COUPON_INVALID' ||
          e.code == 'TOTAL_MISMATCH') {
        // Server rejected because world changed right before placeOrder; re-reconcile
        try {
          final refreshed = await reconciler.reconcile(orderCart);
          await ref.read(cartControllerProvider.notifier).replace(refreshed.cart);
          return CheckoutNeedsReview(refreshed);
        } catch (_) {
          return CheckoutFailure(e.message, canRetry: true);
        }
      }
      return CheckoutFailure(e.message, canRetry: false);
    } on NetworkException {
      return const CheckoutFailure(
        'No internet connection. Please check your network and try again.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }
}
