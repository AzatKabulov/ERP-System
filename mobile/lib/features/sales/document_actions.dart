import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:printing/printing.dart';

/// What can be done with a receipt or invoice PDF on this device: print it, or share it
/// (save, send, open in another app). Behind an interface so tests can watch the calls.
abstract class DocumentActions {
  Future<void> printDocument(Uint8List bytes, String name);
  Future<void> shareDocument(Uint8List bytes, String name);
}

/// The device's own print and share dialogs (the `printing` package). A dedicated
/// receipt-printer integration only follows once a printer is chosen and tested (D9).
class DevicePrintingDocumentActions implements DocumentActions {
  const DevicePrintingDocumentActions();

  @override
  Future<void> printDocument(Uint8List bytes, String name) =>
      Printing.layoutPdf(name: name, onLayout: (_) async => bytes);

  @override
  Future<void> shareDocument(Uint8List bytes, String name) =>
      Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
}

/// Makes the document actions available to every screen, and replaceable in tests.
class DocumentsScope extends InheritedWidget {
  const DocumentsScope({
    super.key,
    required this.actions,
    required super.child,
  });

  final DocumentActions actions;

  static DocumentActions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DocumentsScope>()?.actions ??
      const DevicePrintingDocumentActions();

  @override
  bool updateShouldNotify(DocumentsScope oldWidget) =>
      actions != oldWidget.actions;
}
