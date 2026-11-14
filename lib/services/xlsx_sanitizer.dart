import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Makes generated workbooks open cleanly in Microsoft Excel.
///
/// When sheets are removed from a template, the template's print-area /
/// print-title names and formula chain can still point at the deleted
/// sheets. LibreOffice ignores that, but Excel reports the file as damaged
/// ("We found a problem with some content"). This removes such leftovers.
class XlsxSanitizer {
  XlsxSanitizer._();

  static Uint8List clean(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return bytes;
    }
    ArchiveFile? find(String name) {
      for (final f in archive.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    String? read(String name) {
      final f = find(name);
      final c = f?.readBytes();
      return c == null ? null : utf8.decode(c, allowMalformed: true);
    }

    void write(String name, String text) {
      for (var i = 0; i < archive.files.length; i++) {
        final original = archive.files[i];
        if (original.name != name) continue;
        final replacement = ArchiveFile.bytes(name, utf8.encode(text));
        replacement.compression = original.compression;
        archive.modifyAtIndex(i, replacement);
        return;
      }
    }

    var changed = false;
    final workbook = read('xl/workbook.xml');
    if (workbook == null) return bytes;
    final sheetNames = RegExp(r'<sheet\b[^>]*\bname="([^"]*)"')
        .allMatches(workbook)
        .map((m) => _unescape(m.group(1)!))
        .toList();

    // 1. Defined names that point at missing sheets or sheet indexes.
    var wb = workbook.replaceAllMapped(
      RegExp(r'<definedName\b([^>]*)>([^<]*)</definedName>'),
      (m) {
        final attrs = m.group(1)!;
        final value = _unescape(m.group(2)!);
        final local = RegExp(r'localSheetId="(\d+)"').firstMatch(attrs);
        if (local != null && int.parse(local.group(1)!) >= sheetNames.length) {
          changed = true;
          return '';
        }
        if (value.contains('#REF!')) {
          changed = true;
          return '';
        }
        for (final ref in RegExp(r"(?:'((?:[^']|'')+)'|([A-Za-z0-9_.]+))!").allMatches(value)) {
          final sheet = (ref.group(1) ?? ref.group(2) ?? '').replaceAll("''", "'");
          if (sheet.isNotEmpty && !sheetNames.contains(sheet)) {
            changed = true;
            return '';
          }
        }
        return m.group(0)!;
      },
    );
    if (RegExp(r'<definedNames>\s*</definedNames>').hasMatch(wb)) {
      wb = wb.replaceAll(RegExp(r'<definedNames>\s*</definedNames>'), '');
      changed = true;
    }
    if (wb != workbook) write('xl/workbook.xml', wb);

    // 2. A stale formula chain (Excel rebuilds it automatically).
    final calc = find('xl/calcChain.xml');
    if (calc != null) {
      archive.removeFile(calc);
      changed = true;
      final ct = read('[Content_Types].xml');
      if (ct != null) {
        write(
          '[Content_Types].xml',
          ct.replaceAll(RegExp(r'<Override\b[^>]*PartName="/xl/calcChain\.xml"[^>]*/>'), ''),
        );
      }
      final rels = read('xl/_rels/workbook.xml.rels');
      if (rels != null) {
        write(
          'xl/_rels/workbook.xml.rels',
          rels.replaceAll(RegExp(r'<Relationship\b[^>]*Target="[^"]*calcChain\.xml"[^>]*/>'), ''),
        );
      }
    }

    if (!changed) return bytes;
    final out = ZipEncoder().encode(archive);
    return out.isEmpty ? bytes : Uint8List.fromList(out);
  }

  static String _unescape(String s) => s
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
