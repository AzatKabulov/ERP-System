import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The text a person reads: placeholder and plural syntax removed.
String _visible(String text) {
  var out = text;
  var previous = '';
  while (previous != out) {
    previous = out;
    out = out.replaceAll(RegExp(r'\{[^{}]*\}'), '');
  }
  return out;
}

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  final ru = _load('app_ru.arb');
  final tk = _load('app_tk.arb');
  final ruKeys = ru.keys.where((k) => !k.startsWith('@')).toSet();
  final tkKeys = tk.keys.where((k) => !k.startsWith('@')).toSet();

  test('Russian and Turkmen define exactly the same strings', () {
    expect(ruKeys.difference(tkKeys), isEmpty, reason: 'missing in Turkmen');
    expect(tkKeys.difference(ruKeys), isEmpty, reason: 'missing in Russian');
  });

  test('no string is empty', () {
    for (final key in ruKeys) {
      expect((ru[key] as String).trim(), isNotEmpty, reason: 'ru $key');
      expect((tk[key] as String).trim(), isNotEmpty, reason: 'tk $key');
    }
  });

  test('both languages use the same placeholders for every string', () {
    for (final key in ruKeys.intersection(tkKeys)) {
      expect(
        _placeholders(tk[key] as String),
        _placeholders(ru[key] as String),
        reason: 'placeholders differ for "$key"',
      );
    }
  });

  test('Turkmen strings use the modern Latin alphabet, not Cyrillic', () {
    // Language names are shown in their own script, and the app name is a brand.
    const exempt = {'languageRussian', 'appName'};
    final cyrillic = RegExp(r'[Ѐ-ӿ]');
    for (final key in tkKeys.difference(exempt)) {
      expect(
        cyrillic.hasMatch(tk[key] as String),
        isFalse,
        reason: 'Turkmen string "$key" contains Cyrillic',
      );
    }
  });

  test('Russian strings contain Cyrillic (nothing was left in English)', () {
    const exempt = {'appName', 'languageTurkmen'};
    final cyrillic = RegExp(r'[Ѐ-ӿ]');
    for (final key in ruKeys.difference(exempt)) {
      final text = _visible(ru[key] as String);
      if (!RegExp(r'[A-Za-z]').hasMatch(text)) continue; // e.g. only a number
      expect(
        cyrillic.hasMatch(text),
        isTrue,
        reason: 'Russian string "$key" looks untranslated',
      );
    }
  });
}
