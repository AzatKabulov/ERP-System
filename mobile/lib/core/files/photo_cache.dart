import 'dart:typed_data';

/// Recent downloads shared by lists, galleries and searches within entry and byte
/// budgets. Keys include business, product, version and size, so replacement
/// pictures cannot reuse old bytes. Nothing is written to the device, and
/// everything is forgotten when the person signs out.
class PhotoCache {
  PhotoCache({this.maxEntries = 400, this.maxBytes = 16 * 1024 * 1024})
    : assert(maxEntries > 0),
      assert(maxBytes > 0);
  static final PhotoCache instance = PhotoCache();

  final int maxEntries;

  /// Encoded image bytes only; Flutter manages decoded images separately.
  final int maxBytes;
  int _bytes = 0;

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
        if (identical(_items[key], entry)) {
          if (bytes != null && bytes.lengthInBytes > maxBytes) {
            // Still deliver the photo to its caller, without emptying the cache
            // of smaller reusable thumbnails to retain one oversized image.
            _items.remove(key);
          } else {
            entry.bytes = bytes;
            _bytes += bytes?.lengthInBytes ?? 0;
            _trim();
          }
        }
        return bytes;
      },
      onError: (Object _) {
        if (identical(_items[key], entry)) _items.remove(key);
        return null;
      },
    );
    entry.future = future;
    _trim();
    return future;
  }

  void _trim() {
    while (_items.length > maxEntries || _bytes > maxBytes) {
      final removed = _items.remove(_items.keys.first)!;
      _bytes -= removed.bytes?.lengthInBytes ?? 0;
    }
  }

  void clear() {
    _items.clear();
    _bytes = 0;
  }
}

class _PhotoEntry {
  late final Future<Uint8List?> future;
  Uint8List? bytes;
}
