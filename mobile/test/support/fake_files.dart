import 'dart:typed_data';

import 'package:erp_system/core/files/file_services.dart';

/// Stands in for the camera, the gallery and the file dialog: hands out what the test queued.
class FakeFilePicking implements FilePicking {
  FakeFilePicking({this.hasCamera = true});

  @override
  final bool hasCamera;

  /// What the next photo or file choice returns (null = the person cancelled).
  PickedFile? nextPhoto;
  PickedFile? nextFile;
  final List<String> photoRequests = []; // "camera" or "gallery"
  final List<List<String>> fileRequests = [];

  @override
  Future<PickedFile?> pickPhoto({required bool camera}) async {
    photoRequests.add(camera ? 'camera' : 'gallery');
    return nextPhoto;
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    fileRequests.add(extensions);
    return nextFile;
  }
}

class FakeFileSharing implements FileSharing {
  final List<({String name, String mimeType, Uint8List bytes})> shared = [];

  @override
  Future<void> share(Uint8List bytes, String name, String mimeType) async =>
      shared.add((name: name, mimeType: mimeType, bytes: bytes));
}
