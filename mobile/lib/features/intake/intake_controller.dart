import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../inventory/inventory_models.dart';
import 'intake_draft_store.dart';
import 'intake_models.dart';

/// The goods being counted in. Every scan (camera, hand scanner that types, or typing) goes
/// through [scan]: a known code adds one to its line at once, a new code gets a line and the
/// catalog is asked about it in the background, so scanning never waits for the network.
/// Everything is kept on the device after each change ([IntakeDraftStore]).
class IntakeController extends ChangeNotifier {
  IntakeController({
    required this.catalog,
    required this.store,
    this.locationId,
  });

  final CatalogRepository catalog;
  final IntakeDraftStore store;
  String? locationId;

  final List<IntakeEntry> _entries = [];
  bool _disposed = false;

  /// The line the last scan landed on (for the "just scanned" feedback).
  IntakeEntry? lastScanned;

  List<IntakeEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;
  int get lineCount => _entries.length;
  int get unitsMilli => _entries.fold(0, (sum, e) => sum + e.quantityMilli);

  /// Lines that are not tied to a catalog product yet (being asked, unknown, or offline).
  int get unresolvedCount =>
      _entries.where((e) => e.state != IntakeEntryState.found).length;

  /// Reopens what the device kept, and asks the catalog about lines that had no product.
  /// Returns whether there was a draft.
  bool restore() {
    final draft = store.load();
    if (draft == null) return false;
    locationId = draft.locationId ?? locationId;
    _entries
      ..clear()
      ..addAll(draft.entries);
    for (final e in List.of(_entries)) {
      if (e.state != IntakeEntryState.found) _lookup(e);
    }
    notifyListeners();
    return true;
  }

  /// One scan of [raw]. Returns the line it landed on, or null for an empty text.
  IntakeEntry? scan(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return null;
    final known = _entries
        .where((e) => e.code.toLowerCase() == code.toLowerCase())
        .firstOrNull;
    if (known != null) {
      known.quantityMilli += 1000;
      lastScanned = known;
      _changed();
      if (known.state == IntakeEntryState.lookupFailed) _lookup(known);
      return known;
    }
    final entry = IntakeEntry(code: code);
    _entries.add(entry);
    lastScanned = entry;
    _changed();
    _lookup(entry);
    return entry;
  }

  void setLocation(String? id) {
    locationId = id;
    _changed();
  }

  void retryLookup(IntakeEntry entry) => _lookup(entry);

  Future<void> _lookup(IntakeEntry entry) async {
    entry.state = IntakeEntryState.lookingUp;
    _notify();
    try {
      final product = await catalog.lookup(entry.code);
      if (!_entries.contains(entry)) return; // removed while asking
      if (product == null) {
        entry.state = IntakeEntryState.notFound;
      } else {
        _attach(entry, product);
      }
    } on ApiException catch (e) {
      if (!_entries.contains(entry)) return;
      // a refusal that is not "no connection" still leaves the line to retry or remove
      entry.state = e.kind == ApiErrorKind.client
          ? IntakeEntryState.notFound
          : IntakeEntryState.lookupFailed;
    } catch (_) {
      if (!_entries.contains(entry)) return;
      entry.state = IntakeEntryState.lookupFailed;
    }
    _changed();
  }

  /// Ties [entry] to [product]. When another line already stands for that product (two codes,
  /// one product), the counts are added up and one line remains.
  void _attach(IntakeEntry entry, Product product) {
    final ref = ProductRef.fromProduct(product);
    final twin = _entries
        .where((x) => !identical(x, entry) && x.product?.id == ref.id)
        .firstOrNull;
    if (twin == null) {
      entry.product = ref;
      entry.state = IntakeEntryState.found;
      return;
    }
    twin.quantityMilli += entry.quantityMilli;
    twin.costMinor ??= entry.costMinor;
    _entries.remove(entry);
    if (identical(lastScanned, entry)) lastScanned = twin;
  }

  /// Adds a new product to the catalog for an unknown code and ties the line to it. The price is
  /// left at zero (prices are typed at the sale) and the article number is the code unless the
  /// person typed another. Throws [ApiException] when the server refuses.
  Future<void> addProduct(
    IntakeEntry entry, {
    required String name,
    required String sku,
    required UnitRef unit,
  }) async {
    final draft = ProductDraft(
      sku: sku.trim(),
      name: name.trim(),
      unitId: unit.id,
      priceMinor: 0,
      priceCurrency: 'TMT',
      warrantyMonths: 0,
      warrantyTerms: '',
      barcodes: codeFitsAsArticle(entry.code) ? [entry.code] : const [],
    );
    Product product;
    try {
      product = await catalog.createProduct(draft);
    } on ApiException catch (e) {
      // The answer to an earlier try may have been lost: the product is already there under
      // this very name, so use it instead of complaining about the taken article number.
      final taken =
          e.fields['sku']?.any((f) => f.code == 'sku_taken') == true ||
          e.fields['barcodes']?.any((f) => f.code == 'barcode_taken') == true;
      if (!taken) rethrow;
      final existing = await catalog.lookup(draft.sku);
      if (existing != null &&
          existing.name.trim().toLowerCase() == draft.name.toLowerCase()) {
        product = existing;
      } else {
        rethrow;
      }
    }
    if (!_entries.contains(entry)) return;
    _attach(entry, product);
    _changed();
  }

  void setQuantity(IntakeEntry entry, int milli) {
    if (milli <= 0) return;
    entry.quantityMilli = milli;
    _changed();
  }

  void adjust(IntakeEntry entry, int deltaMilli) {
    final next = entry.quantityMilli + deltaMilli;
    if (next <= 0) return;
    entry.quantityMilli = next;
    _changed();
  }

  void setCost(IntakeEntry entry, int? minor) {
    entry.costMinor = minor;
    _changed();
  }

  void remove(IntakeEntry entry) {
    _entries.remove(entry);
    if (identical(lastScanned, entry)) lastScanned = null;
    _changed();
  }

  /// Forgets everything (after the goods were received, or when starting over).
  Future<void> clear() async {
    _entries.clear();
    lastScanned = null;
    await store.clear();
    _notify();
  }

  void _changed() {
    store.save(IntakeDraft(locationId: locationId, entries: _entries));
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
