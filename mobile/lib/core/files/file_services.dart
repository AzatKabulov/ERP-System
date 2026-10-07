import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

/// A file the person chose: its name and its content.
@immutable
class PickedFile {
  const PickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Taking a photo, choosing a photo or a file. Behind an interface so the screens can be
/// tested without a camera or a file dialog.
abstract class FilePicking {
  /// Whether the device has a camera to take a photo with.
  bool get hasCamera;

  /// A photo from the camera or the gallery; null when the person cancelled.
  Future<PickedFile?> pickPhoto({required bool camera});

  /// Any file with one of [extensions] (without the dot); null when cancelled.
  Future<PickedFile?> pickFile({required List<String> extensions});
}

/// Sending a file somewhere else (save, mail, messenger).
abstract class FileSharing {
  Future<void> share(Uint8List bytes, String name, String mimeType);
}

/// The device's own camera, gallery and file dialogs.
class DeviceFilePicking implements FilePicking {
  const DeviceFilePicking();

  @override
  bool get hasCamera => !kIsWeb;

  @override
  Future<PickedFile?> pickPhoto({required bool camera}) async {
    final picked = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return PickedFile(name: picked.name, bytes: await picked.readAsBytes());
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }
}

class DeviceFileSharing implements FileSharing {
  const DeviceFileSharing();

  @override
  Future<void> share(Uint8List bytes, String name, String mimeType) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
        ),
      );
}

/// Makes the file helpers available to every screen, and replaceable in tests.
class FilesScope extends InheritedWidget {
  const FilesScope({
    super.key,
    required this.picking,
    required this.sharing,
    required super.child,
  });

  final FilePicking picking;
  final FileSharing sharing;

  static FilePicking pickingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FilesScope>()?.picking ??
      const DeviceFilePicking();

  static FileSharing sharingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FilesScope>()?.sharing ??
      const DeviceFileSharing();

  @override
  bool updateShouldNotify(FilesScope oldWidget) =>
      picking != oldWidget.picking || sharing != oldWidget.sharing;
}
