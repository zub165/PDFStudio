import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedPdf {
  final String name;
  final Uint8List bytes;
  const PickedPdf(this.name, this.bytes);
}

class PickedAsset {
  final String name;
  final Uint8List bytes;
  const PickedAsset(this.name, this.bytes);
}

/// Opens and saves PDFs using bytes instead of file paths,
/// so the same code works on the web, desktop and Android.
class FileService {
  static Future<PickedPdf?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true, // required on web, where there is no file path
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedPdf(file.name, bytes);
  }

  static Future<PickedAsset?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes == null) return null;
    return PickedAsset(file.name, file.bytes!);
  }

  static Future<PickedAsset?> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes == null) return null;
    return PickedAsset(file.name, file.bytes!);
  }

  /// Returns the chosen path on desktop, or null if cancelled.
  /// On web the browser downloads the file instead.
  static Future<String?> savePdf(Uint8List bytes, String fileName) {
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
  }
}
