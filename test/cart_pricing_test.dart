import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';

CartLine line(String id, int pricePaise, int qty) => CartLine(
      productId: id,
      name: id,
      emoji: '🛒',
      unit: '1 pc',
      unitPricePaise: pricePaise,
      quantity: qty,
      maxPerOrder: 10,
    );

void main() {
  final config = AppConfig.defaults(); // fee ₹25, free delivery from ₹199

  test('empty cart costs nothing', () {
    final pricing = CartPricing.compute(const Cart.empty(), config);
    expect(pricing.totalPaise, 0);
    expect(pricing.deliveryFeePaise, 0);
  });

  test('small cart pays the delivery fee', () {
    final cart = Cart(lines: [line('a', 4000, 2)]); // ₹80
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.subtotalPaise, 8000);
    expect(pricing.deliveryFeePaise, 2500);
    expect(pricing.totalPaise, 10500);
  });

  test('large cart gets free delivery', () {
    final cart = Cart(lines: [line('a', 15000, 2)]); // ₹300
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 30000);
  });

  test('flat coupon is applied when the minimum order is met', () {
    final coupon = Coupon(
      code: 'FLAT50',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 29900,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final cart = Cart(lines: [line('a', 20000, 2)], coupon: coupon); // ₹400
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.discountPaise, 5000);
    expect(pricing.totalPaise, 35000);
  });

  test('exact threshold ₹199 qualifies for free delivery', () {
    final cart = Cart(lines: [line('a', 19900, 1)]); // ₹199
    final pricing = CartPricing.compute(cart, config);
    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
    expect(pricing.amountForFreeDeliveryPaise, 0);
  });

  test('regression: billing calculation for Hybrid Tomato (x3), Cucumber (x1), Lemon (x1)', () {
    // Actual catalog seed prices:
    // Hybrid Tomato: 3 x 1999 paise = 5997 paise (₹19.99 each)
    // Cucumber: 1 x 2900 paise = 2900 paise (₹29.00 each)
    // Lemon: 1 x 2500 paise = 2500 paise (₹25.00 each)
    final cart = Cart(lines: [
      line('fruits-03', 1999, 3),
      line('fruits-07', 2900, 1),
      line('fruits-08', 2500, 1),
    ]);
    final pricing = CartPricing.compute(cart, config);

    expect(pricing.subtotalPaise, 11397, reason: 'Expected subtotal = 11397 paise (₹113.97)');
    expect(pricing.deliveryFeePaise, 2500, reason: 'Expected delivery fee = 2500 paise (₹25.00)');
    expect(pricing.discountPaise, 0);
    expect(pricing.totalPaise, 13897, reason: 'Expected payable = 13897 paise (₹138.97)');
  });
}
