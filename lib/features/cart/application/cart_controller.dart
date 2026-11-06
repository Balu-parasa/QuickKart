import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/product.dart';
import '../data/cart_storage.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';

/// The cart. Hydrated from storage in `main.dart` before the first frame.
final cartControllerProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

class CartController extends Notifier<Cart> {
  CartStorage get _storage => ref.read(cartStorageProvider);

  @override
  Cart build() => const Cart.empty();

  /// Used at startup with the cart restored from storage.
  void hydrate(Cart cart) => state = cart;

  /// Adds one unit of [product].
  Future<void> add(Product product) async {
    final current = state;
    final existing = current.lineFor(product.id);
    final Cart updated;
    if (existing == null) {
      if (!product.inStock) return;
      updated = current.upsertLine(CartLine.fromProduct(product));
    } else {
      if (existing.quantity >= existing.maxPerOrder) return;
      updated = current.updateQuantity(product.id, existing.quantity + 1);
    }
    await _storage.save(updated);
    state = updated;
  }

  /// Adds one more unit of a product that is already in the cart.
  Future<void> increment(String productId) async {
    final current = state;
    final line = current.lineFor(productId);
    if (line == null || line.quantity >= line.maxPerOrder) return;
    final updated = current.updateQuantity(productId, line.quantity + 1);
    await _storage.save(updated);
    state = updated;
  }

  /// Removes one unit (and the line when it reaches zero).
  Future<void> decrement(String productId) async {
    final line = state.lineFor(productId);
    if (line == null) return;
    final updated = state.updateQuantity(productId, line.quantity - 1);
    await _storage.save(updated);
    state = updated;
  }

  Future<void> remove(String productId) async {
    final updated = state.removeLine(productId);
    await _storage.save(updated);
    state = updated;
  }

  Future<void> applyCoupon(Coupon coupon) async {
    final updated = state.withCoupon(coupon);
    await _storage.save(updated);
    state = updated;
  }

  Future<void> removeCoupon() async {
    final updated = state.withoutCoupon();
    await _storage.save(updated);
    state = updated;
  }

  /// Replaces the whole cart (e.g. after reconciliation).
  Future<void> replace(Cart cart) async {
    state = cart;
    await _storage.save(cart);
  }

  Future<void> clear() async {
    state = const Cart.empty();
    await _storage.clear();
  }
}
