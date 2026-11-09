import 'dart:async';
import 'dart:typed_data';

import 'package:erp_system/core/files/photo_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('byte budget evicts the least recently used completed photo', () async {
    final cache = PhotoCache(maxBytes: 10);
    final a = Uint8List(4);
    final b = Uint8List(4);
    final c = Uint8List(4);
    await cache.load('a', () async => a);
    await cache.load('b', () async => b);
    expect(cache.peek('a'), same(a));
    await cache.load('c', () async => c);
    expect(cache.peek('a'), same(a));
    expect(cache.peek('b'), isNull);
    expect(cache.peek('c'), same(c));
    var downloads = 0;
    await cache.load('b', () async {
      downloads++;
      return b;
    });
    expect(downloads, 1);
  });

  test('oversized photo is delivered without evicting small photos', () async {
    final cache = PhotoCache(maxBytes: 10);
    final small = Uint8List(4);
    final large = Uint8List(11);
    await cache.load('small', () async => small);
    expect(await cache.load('large', () async => large), same(large));
    expect(cache.peek('small'), same(small));
    expect(cache.peek('large'), isNull);
  });

  test('out-of-order downloads enforce byte budget on completion', () async {
    final cache = PhotoCache(maxBytes: 10);
    final first = Completer<Uint8List?>();
    final second = Completer<Uint8List?>();
    final a = cache.load('first', () => first.future);
    final b = cache.load('second', () => second.future);
    second.complete(Uint8List(6));
    await b;
    first.complete(Uint8List(6));
    await a;
    expect(cache.peek('first'), isNull);
    expect(cache.peek('second')?.length, 6);
  });

  test('cleared pending download cannot replace a new session entry', () async {
    final cache = PhotoCache(maxBytes: 10);
    final pending = Completer<Uint8List?>();
    final old = cache.load('photo', () => pending.future);
    cache.clear();
    final current = Uint8List(6);
    await cache.load('photo', () async => current);
    pending.complete(Uint8List(8));
    await old;
    expect(cache.peek('photo'), same(current));
    await cache.load('other', () async => Uint8List(4));
    expect(cache.peek('photo'), same(current));
  });

  test('entry eviction releases its byte allowance', () async {
    final cache = PhotoCache(maxEntries: 2, maxBytes: 10);
    await cache.load('a', () async => Uint8List(4));
    await cache.load('b', () async => Uint8List(4));
    await cache.load('c', () async => Uint8List(2));
    expect(cache.peek('a'), isNull);
    await cache.load('d', () async => Uint8List(4));
    expect(cache.peek('c')?.length, 2);
    expect(cache.peek('d')?.length, 4);
  });
}
