import 'dart:typed_data';

import 'package:erp_system/features/sales/document_actions.dart';

/// Stands in for the device's print and share dialogs: records what would have been
/// printed or shared.
class FakeDocuments implements DocumentActions {
  final List<({String name, Uint8List bytes})> printed = [];
  final List<({String name, Uint8List bytes})> shared = [];

  @override
  Future<void> printDocument(Uint8List bytes, String name) async =>
      printed.add((name: name, bytes: bytes));

  @override
  Future<void> shareDocument(Uint8List bytes, String name) async =>
      shared.add((name: name, bytes: bytes));
}
