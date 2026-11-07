import '../../../core/network/api_client.dart';
import '../domain/product.dart';
import 'product_dto.dart';

/// Remote data source for the catalog. See API_CONTRACT.md.
class CatalogApi {
  CatalogApi(this._client);

  final ApiClient _client;

  Future<List<Category>> getCategories() async {
    final json = await _client.get('/v1/categories');
    return (json as List)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [categoryId] null means "all products".
  Future<CatalogPage> getProducts({
    String? categoryId,
    String? cursor,
    int limit = 10,
    bool dealsOnly = false,
    bool refresh = false,
  }) async {
    final json = await _client.get(
      '/v1/products',
      query: {
        if (categoryId != null) 'category': categoryId,
        if (cursor != null) 'cursor': cursor,
        'limit': '$limit',
        if (dealsOnly) 'deals': 'true',
      },
      refresh: refresh,
    ) as Map<String, dynamic>;
    return CatalogPage(
      items: ProductDto.listFromJson(json['items']),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  Future<List<Product>> search(String query) async {
    final json = await _client.get('/v1/products/search', query: {'q': query})
        as Map<String, dynamic>;
    return ProductDto.listFromJson(json['items']);
  }

  /// Fetches the latest data for specific products (max 50 ids).
  /// Products that no longer exist or are not sold anymore are returned in
  /// [ProductBatch.missingIds].
  Future<ProductBatch> getProductsByIds(List<String> ids) async {
    final json = await _client.post('/v1/products/batch', body: {'ids': ids})
        as Map<String, dynamic>;
    return ProductBatch(
      products: ProductDto.listFromJson(json['items']),
      missingIds: (json['missing'] as List).cast<String>(),
    );
  }
}

class ProductBatch {
  const ProductBatch({required this.products, required this.missingIds});

  final List<Product> products;
  final List<String> missingIds;
}
