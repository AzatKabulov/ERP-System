import 'package:erp_system/core/api/api_client.dart';
import 'package:erp_system/core/api/api_exception.dart';
import 'package:erp_system/core/session/token_stores.dart';
import 'package:erp_system/features/catalog/catalog_models.dart';
import 'package:erp_system/features/catalog/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/catalog_test.dart' show seedProduct;
import 'fake_server.dart';

Future<(FakeServer, CatalogRepository)> rig() async {
  final server = FakeServer();
  final api = ApiClient(
    baseUrl: 'https://api.example.test',
    tokens: MemoryTokenStore(),
    httpClient: server.client,
  );
  await api.login('aman', 'right-password');
  return (server, CatalogRepository(api, 'b-1'));
}

void main() {
  test(
    'products are read as exact minor units, never floating point',
    () async {
      final (server, repo) = await rig();
      seedProduct(server, sku: 'A', name: 'Cheap', price: '0.10');
      seedProduct(
        server,
        sku: 'B',
        name: 'Odd',
        price: '1234.57',
        cost: '999.99',
      );
      final page = await repo.products();
      expect(page.count, 2);
      expect(page.items.map((p) => p.priceMinor), [10, 123457]);
      expect(page.items.last.defaultCostMinor, 99999);
      expect(page.items.first.defaultCostMinor, isNull);
    },
  );

  test(
    'a draft is sent as decimal strings with the cost only when allowed',
    () {
      const draft = ProductDraft(
        sku: 'A',
        name: 'N',
        unitId: 'u',
        priceMinor: 125050,
        priceCurrency: 'USD',
        defaultCostMinor: 800,
        warrantyMonths: 3,
        warrantyTerms: '',
        barcodes: ['1'],
      );
      final json = draft.toJson();
      expect(json['price_amount'], '1250.50');
      expect(json.containsKey('default_purchase_cost'), isFalse);
      const withCost = ProductDraft(
        sku: 'A',
        name: 'N',
        unitId: 'u',
        priceMinor: 100,
        priceCurrency: 'TMT',
        defaultCostMinor: 800,
        includeCost: true,
        warrantyMonths: 0,
        warrantyTerms: '',
        barcodes: [],
      );
      expect(withCost.toJson()['default_purchase_cost'], '8.00');
    },
  );

  test(
    'lookup returns null for an unknown barcode and the product otherwise',
    () async {
      final (server, repo) = await rig();
      seedProduct(server, sku: 'A', name: 'Known', barcodes: ['111']);
      expect(await repo.lookup('222'), isNull);
      expect((await repo.lookup(' 111 '))!.sku, 'A');
      expect(server.productWrites, 0); // a lookup never writes
    },
  );

  test('other errors from the lookup are not swallowed', () async {
    final (server, repo) = await rig();
    server.reachable = false;
    await expectLater(repo.lookup('111'), throwsA(isA<ApiException>()));
  });

  test('archiving flips only the active flag', () async {
    final (server, repo) = await rig();
    final seeded = seedProduct(server, sku: 'A', name: 'Known');
    final archived = await repo.setActive(seeded['id'] as String, false);
    expect(archived.isActive, isFalse);
    expect(server.productsData.single['name'], 'Known');
  });

  test('exchange rates come back newest first', () async {
    final (_, repo) = await rig();
    await repo.setExchangeRate('3.500000');
    await repo.setExchangeRate('3.620000');
    final rates = await repo.exchangeRates();
    expect(rates.map((r) => r.rate), ['3.620000', '3.500000']);
  });
}
