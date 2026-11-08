import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// Returns a [ReconciliationResult] whose `cart` is what could be ordered
  /// right now:
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise it is
  ///   refreshed with the server's latest rules (a coupon whose minimum
  ///   order is not met stays in the cart - see BUSINESS_RULES.md);
  /// * the order of the remaining lines is preserved.
  ///
  /// `changes` lists every difference (one [CartChange] per product/coupon
  /// issue). An unchanged cart returns an empty list and an equal cart.
  ///
  /// Throws an `ApiException` if the server cannot be reached. It must never
  /// return a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty && cart.coupon == null) {
      return ReconciliationResult(cart: cart, changes: const []);
    }

    final changes = <CartChange>[];

    // 1. Fetch latest product info for all items in the cart
    final productMap = <String, Product>{};
    final missingIds = <String>{};

    if (cart.lines.isNotEmpty) {
      final ids = cart.lines.map((l) => l.productId).toList();
      final batch = await catalogApi.getProductsByIds(ids);
      for (final p in batch.products) {
        productMap[p.id] = p;
      }
      missingIds.addAll(batch.missingIds);
    }

    // 2. Reconcile each line preserving order
    final reconciledLines = <CartLine>[];
    for (final line in cart.lines) {
      if (missingIds.contains(line.productId)) {
        changes.add(ProductUnavailable(productId: line.productId));
        continue;
      }

      final serverProduct = productMap[line.productId];
      if (serverProduct == null || !serverProduct.inStock) {
        changes.add(OutOfStock(productId: line.productId));
        continue;
      }

      // Check price changes
      if (serverProduct.pricePaise != line.unitPricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: serverProduct.pricePaise,
        ));
      }

      // Check available quantity: min of current stock and per-order limit
      final availableQuantity = serverProduct.purchasableQuantity;
      final int finalQuantity;
      if (line.quantity > availableQuantity) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: line.quantity,
          availableQuantity: availableQuantity,
        ));
        finalQuantity = availableQuantity;
      } else {
        finalQuantity = line.quantity;
      }

      if (finalQuantity > 0) {
        reconciledLines.add(line.copyWith(
          name: serverProduct.name,
          unitPricePaise: serverProduct.pricePaise,
          quantity: finalQuantity,
          maxPerOrder: availableQuantity,
        ));
      } else {
        changes.add(OutOfStock(productId: line.productId));
      }
    }

    // 3. Reconcile coupon
    Coupon? reconciledCoupon = cart.coupon;
    if (cart.coupon != null) {
      try {
        final validated = await couponApi.validate(cart.coupon!.code);
        reconciledCoupon = validated;
      } on ClientException catch (e) {
        final reason = e.code == 'COUPON_EXPIRED' ? 'EXPIRED' : 'NOT_FOUND';
        changes.add(CouponRemoved(code: cart.coupon!.code, reason: reason));
        reconciledCoupon = null;
      }
    }

    final reconciledCart = Cart(lines: reconciledLines, coupon: reconciledCoupon);
    return ReconciliationResult(cart: reconciledCart, changes: changes);
  }
}
