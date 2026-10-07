import '../../core/api/api_client.dart';
import '../../core/money/decimal_math.dart';
import '../../core/api/api_exception.dart';
import 'catalog_models.dart';

/// Products, their reference data and the lookup by barcode, over the API. No rules
/// live here: the server validates and answers with codes.
class CatalogRepository {
  CatalogRepository(this.api, this.businessId);

  final ApiClient api;
  final String businessId;

  String get _base => '/api/v1/businesses/$businessId';

  Future<ProductPage> products({
    String query = '',
    String? categoryId,
    bool archived = false,
    int offset = 0,
    int limit = 30,
  }) async {
    final response = (await api.get(
      '$_base/products/',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'category': ?categoryId,
        'active': archived ? '0' : '1',
        'limit': '$limit',
        'offset': '$offset',
      },
    )).map;
    return ProductPage([
      for (final item in response['results'] as List)
        Product.fromJson((item as Map).cast<String, dynamic>()),
    ], response['count'] as int);
  }

  Future<Product> product(String id) async =>
      Product.fromJson((await api.get('$_base/products/$id/')).map);

  /// Read-only lookup. Null when no active product has this barcode.
  Future<Product?> lookup(String code) async {
    try {
      final response = await api.get(
        '$_base/barcodes/lookup/',
        query: {'code': code.trim()},
      );
      return Product.fromJson(response.map);
    } on ApiException catch (e) {
      if (e.code == 'barcode_not_found') return null;
      rethrow;
    }
  }

  Future<Product> createProduct(ProductDraft draft) async => Product.fromJson(
    (await api.post('$_base/products/', body: draft.toJson())).map,
  );

  Future<Product> updateProduct(String id, ProductDraft draft) async =>
      Product.fromJson(
        (await api.patch('$_base/products/$id/', body: draft.toJson())).map,
      );

  Future<List<ReorderLevel>> reorderLevels(String productId) async {
    final map = (await api.get(
      '$_base/products/$productId/reorder-settings/',
    )).map;
    return [
      for (final r in map['settings'] as List)
        ReorderLevel.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  /// Replaces the levels of the product: one row per location that has a minimum and a target.
  Future<List<ReorderLevel>> saveReorderLevels(
    String productId,
    List<({String locationId, int minimumMilli, int targetMilli})> rows,
  ) async {
    final map = (await api.send(
      'PUT',
      '$_base/products/$productId/reorder-settings/',
      body: {
        'settings': [
          for (final r in rows)
            {
              'location': r.locationId,
              'minimum': toServerDecimal(r.minimumMilli, 3),
              'target': toServerDecimal(r.targetMilli, 3),
            },
        ],
      },
    )).map;
    return [
      for (final r in map['settings'] as List)
        ReorderLevel.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<Product> setActive(String id, bool active) async => Product.fromJson(
    (await api.patch('$_base/products/$id/', body: {'is_active': active})).map,
  );

  Future<List<UnitRef>> units() async => [
    for (final i in await _all('$_base/units/')) UnitRef.fromJson(i),
  ];

  Future<List<NamedRef>> categories() async => [
    for (final i in await _all('$_base/categories/')) NamedRef.fromJson(i),
  ];

  Future<List<NamedRef>> brands() async => [
    for (final i in await _all('$_base/brands/')) NamedRef.fromJson(i),
  ];

  Future<NamedRef> createCategory(String name) async => NamedRef.fromJson(
    (await api.post('$_base/categories/', body: {'name': name})).map,
  );

  Future<NamedRef> createBrand(String name) async => NamedRef.fromJson(
    (await api.post('$_base/brands/', body: {'name': name})).map,
  );

  Future<UnitRef> createUnit({
    required String name,
    required String symbol,
    required int decimalPlaces,
  }) async => UnitRef.fromJson(
    (await api.post(
      '$_base/units/',
      body: {'name': name, 'symbol': symbol, 'decimal_places': decimalPlaces},
    )).map,
  );

  /// The latest USD -> TMT rate first, then older ones.
  Future<List<ExchangeRateEntry>> exchangeRates({int limit = 10}) async {
    final page = (await api.get(
      '$_base/exchange-rates/',
      query: {'limit': '$limit'},
    )).map;
    return [
      for (final i in page['results'] as List)
        ExchangeRateEntry.fromJson((i as Map).cast<String, dynamic>()),
    ];
  }

  /// [rate] is TMT per 1 USD as a decimal string with up to 6 decimals.
  Future<ExchangeRateEntry> setExchangeRate(String rate) async =>
      ExchangeRateEntry.fromJson(
        (await api.post(
          '$_base/exchange-rates/',
          body: {'currency': 'USD', 'rate': rate},
        )).map,
      );

  Future<List<Map<String, dynamic>>> _all(String path) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = (await api.get(
        path,
        query: {'limit': '200', 'offset': '$offset'},
      )).map;
      final results = [
        for (final r in page['results'] as List)
          (r as Map).cast<String, dynamic>(),
      ];
      out.addAll(results);
      offset += results.length;
      if (results.isEmpty || offset >= (page['count'] as int)) return out;
    }
  }
}
