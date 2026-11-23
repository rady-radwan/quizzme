import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PickedFile {
  PickedFile(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

/// Opens the system file picker. Returns null when the user cancels.
Future<PickedFile?> pickFile({List<String>? extensions, FileType type = FileType.custom}) async {
  final r = await FilePicker.platform.pickFiles(
    type: extensions == null ? type : FileType.custom,
    allowedExtensions: extensions,
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) return null;
  return PickedFile(f.name, bytes);
}

Future<List<PickedFile>> pickFiles({List<String>? extensions, FileType type = FileType.custom}) async {
  final r = await FilePicker.platform.pickFiles(
    type: extensions == null ? type : FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: true,
    withData: true,
  );
  if (r == null) return [];
  final out = <PickedFile>[];
  for (final f in r.files) {
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes != null) out.add(PickedFile(f.name, bytes));
  }
  return out;
}

/// Lets the user choose where to save [bytes]. Returns false if cancelled.
Future<bool> saveBytes(String fileName, List<int> bytes, {String title = 'Save file'}) async {
  final data = Uint8List.fromList(bytes);
  final path = await FilePicker.platform.saveFile(dialogTitle: title, fileName: fileName, bytes: data);
  if (path == null) return false;
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    // Desktop pickers only return a path; write the file ourselves.
    await File(path).writeAsBytes(data, flush: true);
  }
  return true;
}

/// Reads a bundled asset (e.g. an Excel template).
Future<List<int>> assetBytes(String path) async {
  final b = await rootBundle.load(path);
  return b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
}

const List<String> mediaExtensions = [
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'
];
