import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

/// Opens the system file picker. Returns null when the user cancels.
Future<PickedFile?> pickFile({List<String>? extensions, FileType type = FileType.custom}) async {
  final f = await FilePicker.pickFile(
    type: extensions == null ? type : FileType.custom,
    allowedExtensions: extensions,
  );
  if (f == null) return null;
  return PickedFile(f.name, await f.readAsBytes());
}

Future<List<PickedFile>> pickFiles({List<String>? extensions, FileType type = FileType.custom}) async {
  final files = await FilePicker.pickFiles(
    type: extensions == null ? type : FileType.custom,
    allowedExtensions: extensions,
  );
  final out = <PickedFile>[];
  for (final f in files) {
    out.add(PickedFile(f.name, await f.readAsBytes()));
  }
  return out;
}

/// Lets the user choose where to save [bytes]. Returns false if cancelled.
Future<bool> saveBytes(String fileName, List<int> bytes, {String title = 'Save file'}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
    dialogTitle: title,
  );
  return uri != null;
}

/// Reads a bundled asset (e.g. an Excel template).
Future<List<int>> assetBytes(String path) async {
  final b = await rootBundle.load(path);
  return b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
}

const List<String> mediaExtensions = [
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'
];
