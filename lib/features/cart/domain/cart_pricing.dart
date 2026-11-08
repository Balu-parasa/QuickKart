import '../../app_config/domain/app_config.dart';
import 'cart.dart';

/// Price breakdown of a cart. See BUSINESS_RULES.md for the rules.
class CartPricing {
  const CartPricing({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.deliveryFeePaise,
    required this.totalPaise,
    required this.amountForFreeDeliveryPaise,
  });

  static const zero = CartPricing(
    subtotalPaise: 0,
    discountPaise: 0,
    deliveryFeePaise: 0,
    totalPaise: 0,
    amountForFreeDeliveryPaise: 0,
  );

  final int subtotalPaise;
  final int discountPaise;
  final int deliveryFeePaise;
  final int totalPaise;

  /// How much more the user must add to get free delivery (0 if already
  /// free).
  final int amountForFreeDeliveryPaise;

  static CartPricing compute(Cart cart, AppConfig config, {DateTime? now}) {
    if (cart.isEmpty) return zero;
    final subtotal = cart.subtotalPaise;

    final coupon = cart.coupon;
    var discount = 0;
    if (coupon != null && !coupon.isExpired(now ?? DateTime.now())) {
      discount = coupon.discountFor(subtotal);
    }

    final payable = subtotal - discount;
    final threshold = config.freeDeliveryThresholdPaise;
    final deliveryFee = payable >= threshold ? 0 : config.deliveryFeePaise;

    return CartPricing(
      subtotalPaise: subtotal,
      discountPaise: discount,
      deliveryFeePaise: deliveryFee,
      totalPaise: payable + deliveryFee,
      amountForFreeDeliveryPaise: deliveryFee == 0 ? 0 : threshold - payable,
    );
  }
}
