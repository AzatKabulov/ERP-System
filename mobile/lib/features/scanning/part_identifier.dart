/// A selected label identifier, not a guess at vehicle compatibility.
class PartIdentifier {
  const PartIdentifier(this.article, this.brand);
  final String article;
  final String brand;
}

const _partBrands = [
  'MITSUBISHI FUSO',
  'GOODRUBBER',
  'MITSUBISHI',
  'SUPREME',
  'MAWROOIL',
  'TAIHO',
  'ISUZU',
  'FUSO',
  'KYB',
  'OSK',
];

PartIdentifier? identifyPart(String raw) {
  var value = raw.trim().toUpperCase();
  if (value.length > 64 || !RegExp(r'^[A-Z0-9 .-]+$').hasMatch(value)) {
    return null;
  }
  var brand = '';
  for (final label in _partBrands) {
    if (value.startsWith('$label ')) {
      brand = label;
      value = value.substring(label.length).trim();
      break;
    }
  }
  final compound = RegExp(
    r'^((?:ME|MH|MB|MC)[0-9]{6}) +[0-9]{4}$',
  ).firstMatch(value);
  value = (compound?.group(1) ?? value).replaceAll(' ', '');
  if (!RegExp(r'^[A-Z0-9][A-Z0-9.-]{2,39}$').hasMatch(value) ||
      !value.contains(RegExp('[0-9]'))) {
    return null;
  }
  if (RegExp(r'^[0-9]+$').hasMatch(value) &&
      !(brand == 'KYB' && value.length == 6)) {
    return null;
  }
  return PartIdentifier(value, brand);
}

/// OCR offers candidates for explicit selection. It never corrects O/0, I/1 or a part suffix.
List<String> partCandidates(String text) {
  if (text.length > 20000) return const [];
  final upper = text.toUpperCase();
  final brand = _partBrands
      .where(
        (b) =>
            RegExp('(^|[^A-Z])${RegExp.escape(b)}([^A-Z]|\$)').hasMatch(upper),
      )
      .firstOrNull;
  final candidates = <String>{};
  // Spaces may separate an OEM prefix from its digits, as on printed package labels.
  final prepared = upper.replaceAllMapped(
    RegExp(r'\b(ME|MH|MB|MC|JX|YCE)\s+([0-9])'),
    (m) => '${m[1]}${m[2]}',
  );
  for (final match in RegExp(
    r'\b[A-Z0-9]+(?:[-.][A-Z0-9]+)*\b',
  ).allMatches(prepared)) {
    final token = match[0]!;
    if (token.length < 4 ||
        token.length > 32 ||
        RegExp(r'^(19|20)[0-9]{2}$').hasMatch(token)) {
      continue;
    }
    final part = identifyPart(brand == null ? token : '$brand $token');
    if (part == null) continue;
    if (!RegExp(
      r'^(?:[A-Z]{1,5}[-.]?[0-9]{3,}[A-Z0-9.-]*|[18]-[0-9-]{8,}|[0-9]{6})$',
    ).hasMatch(part.article)) {
      continue;
    }
    if (!token.contains(RegExp('[A-Z]')) &&
        !(brand == 'KYB' && token.length == 6)) {
      continue;
    }
    if (RegExp(r'^[0-9]+(?:[.-][0-9]+)+$').hasMatch(token) &&
        !RegExp(r'^[18]-[0-9]{5}-?[0-9]{3}-[0-9]$').hasMatch(token)) {
      continue;
    }
    // Standards, engine families and dimensions are not product identifiers.
    if (RegExp(
      r'^(ISO|[0-9]+MM|[0-9]+X|4D[0-9]{2}$|4HF[0-9]$)',
    ).hasMatch(token)) {
      continue;
    }
    candidates.add(brand == null ? part.article : '$brand ${part.article}');
  }
  return candidates.take(12).toList();
}
