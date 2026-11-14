import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'psm_file_saver_stub.dart'
    if (dart.library.html) 'psm_file_saver_web.dart'
    if (dart.library.io) 'psm_file_saver_io.dart' as saver;

/// Saves directly from web/desktop. Mobile continues to use the share sheet.
class PsmFileExportHelper {
  static Future<void> saveOrShare({
    required Uint8List bytes,
    required String filename,
    required String title,
    required String mimeType,
  }) async {
    final isDesktopOrWeb = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (isDesktopOrWeb) {
      await saver.saveBytesToDevice(bytes, filename, mimeType);
      return;
    }

    await SharePlus.instance.share(ShareParams(
      title: title,
      files: <XFile>[
        XFile.fromData(bytes, name: filename, mimeType: mimeType),
      ],
    ));
  }
}