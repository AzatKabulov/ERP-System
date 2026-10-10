String _two(int n) => n.toString().padLeft(2, '0');

/// Locale-neutral timestamp (the Turkmen date formatting is not approved yet).
String formatStamp(DateTime t) {
  final local = t.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}
