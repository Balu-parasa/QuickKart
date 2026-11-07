import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../domain/order.dart';

final orderApiProvider = Provider<OrderApi>(
  (ref) => OrderApi(ref.watch(apiClientProvider)),
);

class OrderApi {
  OrderApi(this._client);

  final ApiClient _client;

  /// `POST /v1/orders`. See API_CONTRACT.md for the error codes.
  Future<Order> placeOrder(Cart cart, CartPricing pricing) async {
    final json = await _client.post('/v1/orders', body: {
      'items': [
        for (final l in cart.lines)
          {
            'productId': l.productId,
            'quantity': l.quantity,
            'unitPricePaise': l.unitPricePaise,
          }
      ],
      'couponCode': cart.coupon?.code,
      'expectedTotalPaise': pricing.totalPaise,
    }) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<List<Order>> getOrders({bool refresh = true}) async {
    final json = await _client.get('/v1/orders', refresh: refresh)
        as Map<String, dynamic>;
    return (json['items'] as List)
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order> getOrder(String id) async {
    final json = await _client.get('/v1/orders/$id') as Map<String, dynamic>;
    return Order.fromJson(json);
  }
}
