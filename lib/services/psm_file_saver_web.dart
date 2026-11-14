import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

Future<String?> saveBytesToDevice(Uint8List bytes, String filename, String mimeType) async {
  final body = html.document.body;
  if (body == null) throw StateError('The browser page is not ready to download files.');
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  body.children.add(anchor);
  anchor.click();
  anchor.remove();
  // Keep the object URL alive briefly so the browser can start the download.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  html.Url.revokeObjectUrl(url);
  return filename;
}