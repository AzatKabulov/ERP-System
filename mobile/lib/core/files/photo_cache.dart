import 'dart:typed_data';

/// Pictures the app has already downloaded, kept in memory so a list, a gallery or a search asks
/// for each picture once. A key names the business, the product, the picture's version and the
/// size, so a new picture is a new key and an old one is never shown by mistake. Nothing is
/// written to the device, and everything is forgotten when the person signs out.
class PhotoCache {
  PhotoCache._();
  static final PhotoCache instance = PhotoCache._();

  static const _max = 400;

  /// Insertion order is use order: the oldest entry goes first.
  final Map<String, Future<Uint8List?>> _items = {};

  /// The picture under [key]; [fetch] runs only when it is not here. Several widgets asking at
  /// once share one request. A failed request is forgotten, so the next ask tries again.
  Future<Uint8List?> load(String key, Future<Uint8List?> Function() fetch) {
    final hit = _items.remove(key);
    if (hit != null) {
      _items[key] = hit;
      return hit;
    }
    final future = fetch().then<Uint8List?>(
      (bytes) => bytes,
      onError: (Object _) {
        _items.remove(key);
        return null;
      },
    );
    _items[key] = future;
    while (_items.length > _max) {
      _items.remove(_items.keys.first);
    }
    return future;
  }

  void clear() => _items.clear();
}
