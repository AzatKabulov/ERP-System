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
  final Map<String, _PhotoEntry> _items = {};

  /// Read completed bytes synchronously so revisiting a cached tile has no
  /// FutureBuilder waiting frame. Business/version/size remain part of the key.
  Uint8List? peek(String key) {
    final entry = _items.remove(key);
    if (entry == null) return null;
    _items[key] = entry;
    return entry.bytes;
  }

  /// The picture under [key]; [fetch] runs only when it is not here. Several widgets asking at
  /// once share one request. A failed request is forgotten, so the next ask tries again.
  Future<Uint8List?> load(String key, Future<Uint8List?> Function() fetch) {
    final hit = _items.remove(key);
    if (hit != null) {
      _items[key] = hit;
      return hit.future;
    }
    final entry = _PhotoEntry();
    _items[key] = entry;
    final future = Future<Uint8List?>.sync(fetch).then<Uint8List?>(
      (bytes) {
        if (identical(_items[key], entry)) entry.bytes = bytes;
        return bytes;
      },
      onError: (Object _) {
        if (identical(_items[key], entry)) _items.remove(key);
        return null;
      },
    );
    entry.future = future;
    while (_items.length > _max) {
      _items.remove(_items.keys.first);
    }
    return future;
  }

  void clear() => _items.clear();
}

class _PhotoEntry {
  late final Future<Uint8List?> future;
  Uint8List? bytes;
}
