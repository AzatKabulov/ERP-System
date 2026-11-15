import 'package:flutter/services.dart';

Future<String> readLabelText(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
    throw StateError('Invalid photo size');
  }
  return await const MethodChannel('erp/label-text')
          .invokeMethod<String>('read', bytes)
          .timeout(const Duration(seconds: 45)) ??
      '';
}
