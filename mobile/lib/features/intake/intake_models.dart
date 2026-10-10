import '../catalog/catalog_models.dart';
import '../inventory/inventory_models.dart';

/// Where one scanned code stands.
enum IntakeEntryState {
  /// The catalog is being asked.
  lookingUp,

  /// A catalog product was found (or just created) for the code.
  found,

  /// The catalog has nothing for this code: add the product or remove the line.
  notFound,

  /// The catalog could not be asked (no connection); try again.
  lookupFailed,
}

/// One line of the goods being counted in: a code, the product it stands for and how many
/// were scanned. Several codes of one product are merged into one line once they resolve.
class IntakeEntry {
  IntakeEntry({
    required this.code,
    this.product,
    this.state = IntakeEntryState.lookingUp,
    this.quantityMilli = 1000,
    this.costMinor,
  });

  /// The text that was scanned or typed (trimmed).
  final String code;
  ProductRef? product;
  IntakeEntryState state;

  /// Thousandths of the product's unit; one scan adds one whole unit (1000).
  int quantityMilli;

  /// Cost per unit in TMT hundredths; null = not entered (only roles that may see costs set it).
  int? costMinor;

  Map<String, dynamic> toJson() => {
    'code': code,
    'quantity': quantityMilli,
    if (costMinor != null) 'cost': costMinor,
    if (product != null)
      'product': {
        'id': product!.id,
        'sku': product!.sku,
        'name': product!.name,
        'unit': {
          'id': product!.unit.id,
          'name': product!.unit.name,
          'symbol': product!.unit.symbol,
          'decimal_places': product!.unit.decimalPlaces,
        },
      },
  };

  factory IntakeEntry.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return IntakeEntry(
      code: json['code'] as String,
      quantityMilli: json['quantity'] as int,
      costMinor: json['cost'] as int?,
      product: product is Map
          ? ProductRef.fromJson(product.cast<String, dynamic>())
          : null,
      // Entries without a product are asked about again when the draft is reopened.
      state: product is Map
          ? IntakeEntryState.found
          : IntakeEntryState.lookingUp,
    );
  }
}

/// What the device keeps between visits: the place and the entries counted so far.
class IntakeDraft {
  const IntakeDraft({required this.locationId, required this.entries});
  final String? locationId;
  final List<IntakeEntry> entries;

  Map<String, dynamic> toJson() => {
    'location': locationId,
    'entries': [for (final e in entries) e.toJson()],
  };

  factory IntakeDraft.fromJson(Map<String, dynamic> json) => IntakeDraft(
    locationId: json['location'] as String?,
    entries: [
      for (final e in json['entries'] as List)
        IntakeEntry.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );
}

/// Whether a scanned text can serve as an article number (and be remembered as a barcode):
/// a short single token. A QR code that holds a web address cannot; the person types the
/// article number from the label instead.
bool codeFitsAsArticle(String code) =>
    code.isNotEmpty &&
    code.length <= 64 &&
    !code.contains(RegExp(r'\s')) &&
    !code.contains('://');

/// The unit a quickly added product gets unless the person picks another: the one that counts
/// pieces ("шт", "sany", "pcs"), else the first that counts whole numbers.
UnitRef? defaultPieceUnit(List<UnitRef> units) {
  final active = [
    for (final u in units)
      if (u.isActive) u,
  ];
  const pieceSymbols = {'шт', 'sany', 'pcs', 'pc'};
  final whole = [
    for (final u in active)
      if (u.decimalPlaces == 0) u,
  ];
  return whole
          .where((u) => pieceSymbols.contains(u.symbol.trim().toLowerCase()))
          .firstOrNull ??
      whole.firstOrNull ??
      active.firstOrNull;
}
