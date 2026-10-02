import 'package:flutter/foundation.dart';

enum ProductCategory { filters, brakes, oils, electrical }

enum ActivityKind { sale, receipt, transfer, count, expense, refund }

@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.brand,
    required this.category,
    required this.priceMinor,
    required this.costMinor,
    required this.minimum,
    required this.target,
    required this.shelf,
  });
  final String id;
  final String name;
  final String sku;
  final String barcode;
  final String brand;
  final ProductCategory category;
  final int priceMinor;
  final int costMinor;
  final int minimum;
  final int target;
  final String shelf;
}

@immutable
class DemoActivity {
  const DemoActivity(
    this.kind,
    this.reference,
    this.quantity,
    this.amountMinor,
  );
  final ActivityKind kind;
  final String reference;
  final int quantity;
  final int amountMinor;
}

@immutable
class DemoSale {
  const DemoSale(this.id, this.location, this.items, this.totalMinor);
  final String id;
  final String location;
  final Map<String, int> items;
  final int totalMinor;
}

class DemoStore extends ChangeNotifier {
  static const locationIds = ['store', 'warehouse', 'branch'];
  final products = const [
    Product(
      id: 'filter',
      name: 'Масляный фильтр',
      sku: 'FLT-001',
      barcode: '400001',
      brand: 'Bosch',
      category: ProductCategory.filters,
      priceMinor: 8500,
      costMinor: 5400,
      minimum: 8,
      target: 30,
      shelf: 'A-01',
    ),
    Product(
      id: 'brake',
      name: 'Тормозные колодки',
      sku: 'BRK-014',
      barcode: '400002',
      brand: 'Brembo',
      category: ProductCategory.brakes,
      priceMinor: 42000,
      costMinor: 29000,
      minimum: 10,
      target: 25,
      shelf: 'B-04',
    ),
    Product(
      id: 'oil',
      name: 'Моторное масло 5W-30 · 4 л',
      sku: 'OIL-030',
      barcode: '400003',
      brand: 'Shell',
      category: ProductCategory.oils,
      priceMinor: 36000,
      costMinor: 24500,
      minimum: 12,
      target: 40,
      shelf: 'C-02',
    ),
    Product(
      id: 'air',
      name: 'Воздушный фильтр',
      sku: 'FLT-008',
      barcode: '400004',
      brand: 'Mann',
      category: ProductCategory.filters,
      priceMinor: 12500,
      costMinor: 7800,
      minimum: 6,
      target: 20,
      shelf: 'A-03',
    ),
    Product(
      id: 'plug',
      name: 'Свеча зажигания',
      sku: 'ELC-021',
      barcode: '400005',
      brand: 'NGK',
      category: ProductCategory.electrical,
      priceMinor: 6500,
      costMinor: 3900,
      minimum: 15,
      target: 50,
      shelf: 'D-01',
    ),
    Product(
      id: 'battery',
      name: 'Аккумулятор 60 Ah',
      sku: 'ELC-060',
      barcode: '400006',
      brand: 'Varta',
      category: ProductCategory.electrical,
      priceMinor: 145000,
      costMinor: 109000,
      minimum: 3,
      target: 10,
      shelf: 'D-05',
    ),
    Product(
      id: 'disc',
      name: 'Тормозной диск',
      sku: 'BRK-020',
      barcode: '400007',
      brand: 'TRW',
      category: ProductCategory.brakes,
      priceMinor: 58000,
      costMinor: 38000,
      minimum: 4,
      target: 15,
      shelf: 'B-06',
    ),
    Product(
      id: 'coolant',
      name: 'Антифриз G12 · 1 л',
      sku: 'OIL-012',
      barcode: '400008',
      brand: 'Febi',
      category: ProductCategory.oils,
      priceMinor: 9500,
      costMinor: 6000,
      minimum: 8,
      target: 25,
      shelf: 'C-04',
    ),
  ];

  final Map<String, Map<String, int>> _stock = {
    'store': {
      'filter': 24,
      'brake': 4,
      'oil': 8,
      'air': 18,
      'plug': 42,
      'battery': 2,
      'disc': 9,
      'coolant': 16,
    },
    'warehouse': {
      'filter': 80,
      'brake': 35,
      'oil': 60,
      'air': 45,
      'plug': 120,
      'battery': 12,
      'disc': 25,
      'coolant': 50,
    },
    'branch': {
      'filter': 10,
      'brake': 12,
      'oil': 6,
      'air': 9,
      'plug': 20,
      'battery': 4,
      'disc': 3,
      'coolant': 7,
    },
  };
  final Map<String, int> _cart = {};
  final List<DemoActivity> _activities = [];
  final List<DemoSale> _sales = [];
  final Map<String, Map<String, int>> _returned = {};
  final List<({String label, int amountMinor})> _expenses = [];
  final Set<String> _receivedOrders = {};
  String _location = 'store';

  String get location => _location;
  Map<String, int> get cart => Map.unmodifiable(_cart);
  List<DemoActivity> get activities => List.unmodifiable(_activities.reversed);
  List<DemoSale> get sales => List.unmodifiable(_sales.reversed);
  List<({String label, int amountMinor})> get expenses =>
      List.unmodifiable(_expenses.reversed);
  int stock(Product product, [String? location]) =>
      _stock[location ?? _location]![product.id] ?? 0;
  Product product(String id) => products.firstWhere((p) => p.id == id);
  int get cartCount => _cart.values.fold(0, (a, b) => a + b);
  int get cartTotal => _cart.entries.fold(
    0,
    (sum, e) => sum + product(e.key).priceMinor * e.value,
  );
  int get inventoryValue =>
      products.fold(0, (sum, p) => sum + stock(p) * p.costMinor);
  int get unitCount => products.fold(0, (sum, p) => sum + stock(p));
  List<Product> get lowStock =>
      products.where((p) => stock(p) < p.minimum).toList();
  int get salesTotal => _activities
      .where((a) => a.kind == ActivityKind.sale)
      .fold(0, (sum, a) => sum + a.amountMinor);
  int get refundTotal => _activities
      .where((a) => a.kind == ActivityKind.refund)
      .fold(0, (sum, a) => sum + a.amountMinor);
  int get expenseTotal => _expenses.fold(0, (sum, e) => sum + e.amountMinor);

  bool changeLocation(String id, {bool discardCart = false}) {
    if (!locationIds.contains(id)) return false;
    if (_cart.isNotEmpty && !discardCart && id != _location) return false;
    if (id != _location) _cart.clear();
    _location = id;
    notifyListeners();
    return true;
  }

  bool addToCart(Product p) {
    final current = _cart[p.id] ?? 0;
    if (current >= stock(p)) return false;
    _cart[p.id] = current + 1;
    notifyListeners();
    return true;
  }

  void removeFromCart(Product p) {
    final current = _cart[p.id] ?? 0;
    if (current <= 1) {
      _cart.remove(p.id);
    } else {
      _cart[p.id] = current - 1;
    }
    notifyListeners();
  }

  DemoSale? checkout() {
    if (_cart.isEmpty ||
        _cart.entries.any((e) => e.value > stock(product(e.key)))) {
      return null;
    }
    final sale = DemoSale(
      'DEMO-${1001 + _sales.length}',
      _location,
      Map.unmodifiable(_cart),
      cartTotal,
    );
    final count = cartCount;
    for (final entry in _cart.entries) {
      _stock[_location]![entry.key] = stock(product(entry.key)) - entry.value;
    }
    _sales.add(sale);
    _activities.add(
      DemoActivity(ActivityKind.sale, sale.id, count, sale.totalMinor),
    );
    _cart.clear();
    notifyListeners();
    return sale;
  }

  bool receive(Product p, int quantity, {String? orderId}) {
    if (quantity <= 0 ||
        (orderId != null && _receivedOrders.contains(orderId))) {
      return false;
    }
    _stock[_location]![p.id] = stock(p) + quantity;
    if (orderId != null) _receivedOrders.add(orderId);
    _activities.add(
      DemoActivity(ActivityKind.receipt, orderId ?? p.sku, quantity, 0),
    );
    notifyListeners();
    return true;
  }

  bool orderReceived(String id) => _receivedOrders.contains(id);

  bool transfer(Product p, int quantity, String destination) {
    if (quantity <= 0 ||
        quantity > stock(p) - (_cart[p.id] ?? 0) ||
        destination == _location ||
        !locationIds.contains(destination)) {
      return false;
    }
    _stock[_location]![p.id] = stock(p) - quantity;
    _stock[destination]![p.id] = stock(p, destination) + quantity;
    _activities.add(DemoActivity(ActivityKind.transfer, p.sku, quantity, 0));
    notifyListeners();
    return true;
  }

  bool count(Product p, int actual) {
    if (actual < 0 || actual < (_cart[p.id] ?? 0)) return false;
    final difference = actual - stock(p);
    _stock[_location]![p.id] = actual;
    _activities.add(DemoActivity(ActivityKind.count, p.sku, difference, 0));
    notifyListeners();
    return true;
  }

  int returnable(DemoSale sale, String id) =>
      (sale.items[id] ?? 0) - (_returned[sale.id]?[id] ?? 0);

  bool refund(
    DemoSale sale,
    String id,
    int quantity, {
    required bool sellable,
  }) {
    if (!_sales.contains(sale) ||
        quantity <= 0 ||
        quantity > returnable(sale, id)) {
      return false;
    }
    final previous = _returned.putIfAbsent(sale.id, () => {});
    previous[id] = (previous[id] ?? 0) + quantity;
    if (sellable) {
      _stock[sale.location]![id] = stock(product(id), sale.location) + quantity;
    }
    _activities.add(
      DemoActivity(
        ActivityKind.refund,
        sale.id,
        quantity,
        product(id).priceMinor * quantity,
      ),
    );
    notifyListeners();
    return true;
  }

  bool addExpense(String label, int minor) {
    if (label.trim().isEmpty || minor <= 0) return false;
    _expenses.add((label: label.trim(), amountMinor: minor));
    _activities.add(DemoActivity(ActivityKind.expense, label.trim(), 0, minor));
    notifyListeners();
    return true;
  }
}
