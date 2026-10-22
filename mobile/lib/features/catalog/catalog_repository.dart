import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/files/file_services.dart';
import '../../core/files/photo_cache.dart';
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
    String? locationId,
  }) async {
    final response = (await api.get(
      '$_base/products/',
      query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'category': ?categoryId,
        'location': ?locationId,
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

  /// The whole catalog as a CSV file (UTF-8, semicolons), ready for a spreadsheet.
  Future<Uint8List> exportCsv() async {
    final response = await api.download(
      '$_base/catalog/export/',
      accept: 'text/csv, application/json',
    );
    return response.bytes ?? Uint8List(0);
  }

  /// Checks a CSV file without changing anything.
  Future<ImportPreview> previewImport(PickedFile file) async =>
      ImportPreview.fromJson(
        (await api.upload(
          '$_base/catalog/import/preview/',
          ApiUpload(field: 'file', filename: file.name, bytes: file.bytes),
        )).map,
      );

  /// Adds every product of the file, or nothing at all. Returns how many were added.
  Future<int> applyImport(PickedFile file) async =>
      ((await api.upload(
            '$_base/catalog/import/apply/',
            ApiUpload(field: 'file', filename: file.name, bytes: file.bytes),
          )).map['created']
          as int?) ??
      0;

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

  /// The picture of [product] (a small one for lists, the larger one for the product page), or
  /// null when it has none. Downloaded once and kept in memory while its version stays the same.
  Future<Uint8List?> photo(Product product, {bool full = false}) {
    final version = product.photoVersion;
    if (version == null) return Future.value(null);
    final size = full ? 'full' : 'thumb';
    return PhotoCache.instance.load(
      '$businessId/${product.id}/$version/$size',
      () async {
        final response = await api.download(
          '$_base/products/${product.id}/photo/',
          query: {'size': size},
          accept: 'image/jpeg',
        );
        return response.bytes;
      },
    );
  }

  /// Sets (or replaces) the product's picture. The server makes it small and clean.
  Future<Product> uploadPhoto(String productId, PickedFile file) async =>
      Product.fromJson(
        (await api.upload(
          '$_base/products/$productId/photo/',
          ApiUpload(field: 'file', filename: file.name, bytes: file.bytes),
        )).map,
      );

  Future<Product> removePhoto(String productId) async => Product.fromJson(
    (await api.send('DELETE', '$_base/products/$productId/photo/')).map,
  );

  /// What the open product databases (asked by the server) say about a barcode, or null.
  Future<ExternalInfo?> externalInfo(String code) async {
    final response = await api.get(
      '$_base/barcodes/info/',
      query: {'code': code.trim()},
    );
    return ExternalInfo.fromJson(response.map);
  }

  /// Products that still need a selling price or a cost.
  Future<List<ToCompleteItem>> toComplete() async {
    final map = (await api.get('$_base/catalog/to-complete/')).map;
    return [
      for (final r in map['results'] as List)
        ToCompleteItem.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<void> setPrice(String id, int priceMinor, String currency) async {
    await api.patch(
      '$_base/products/$id/',
      body: {
        'price_amount': toServerDecimal(priceMinor, 2),
        'price_currency': currency,
      },
    );
  }

  /// The real cost (TMT): batches that waited for it get it and past sales are corrected.
  Future<void> setCost(String id, int costMinor) async {
    await api.post(
      '$_base/products/$id/cost/',
      body: {'unit_cost': toServerDecimal(costMinor, 2)},
    );
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
