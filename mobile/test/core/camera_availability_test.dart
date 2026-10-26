import 'package:erp_system/features/scanning/barcode_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final address in [
    'https://erp.example.com',
    'https://192.168.0.29:8000',
    'http://localhost:8000',
    'http://127.0.0.1:8000',
    'http://127.0.0.2:8000',
    'http://[::1]:8000',
  ]) {
    test('camera can be requested from $address', () {
      expect(
        cameraScanningAvailable(isWeb: true, origin: Uri.parse(address)),
        isTrue,
      );
    });
  }
  for (final address in [
    'http://192.168.0.29:8000',
    'http://example.com',
    'http://localhost.example.com',
    'http://127.0.0.1.example.com',
    'http://127.0.0.999',
    'ftp://localhost',
  ]) {
    test('insecure origin $address cannot request live video', () {
      expect(
        cameraScanningAvailable(isWeb: true, origin: Uri.parse(address)),
        isFalse,
      );
    });
  }
  test('native scanner does not depend on the API or page origin', () {
    expect(
      cameraScanningAvailable(
        isWeb: false,
        origin: Uri.parse('http://192.168.0.29'),
      ),
      isTrue,
    );
    expect(const CameraBarcodeScanner().isAvailable, isTrue);
  });
}
