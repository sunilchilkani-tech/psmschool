import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> saveBytesToDevice(Uint8List bytes, String filename, String mimeType) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save $filename',
    fileName: filename,
  );
  if (path == null || path.trim().isEmpty) return null;
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}