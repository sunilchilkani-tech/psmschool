// Print Merge Studio: artboard painters and the PDF exporter.
//
// The PDF is vector (frames, shapes, borders) with photos/images embedded
// once each and text drawn from the shared Gujarati glyph atlas, so a whole
// class of certificates stays small and prints sharply.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fln/fln_layout.dart';
import '../fln/fln_render.dart';
import '../services/class_label.dart';
import 'pm_models.dart';

// ---------------------------------------------------------------------------
// Page background themes (screen + PDF use the same geometry)
// ---------------------------------------------------------------------------

class _ThemeColors {
  const _ThemeColors(this.bg, this.outer, this.inner, this.head);
  final int bg;
  final int outer;
  final int inner;
  final int head;
}

const Map<String, _ThemeColors> _themes = <String, _ThemeColors>{
  'blue': _ThemeColors(0xFFFFFFFF, 0xFF1E3A8A, 0xFF3B82F6, 0xFFEFF6FF),
  'gold': _ThemeColors(0xFFFFFDF9, 0xFF991B1B, 0xFFD97706, 0xFFFEF3C7),
  'emerald': _ThemeColors(0xFFFFFFFF, 0xFF065F46, 0xFF10B981, 0xFFECFDF5),
  'minimal': _ThemeColors(0xFFFFFFFF, 0xFF1E293B, 0xFF64748B, 0xFFF8FAFC),
  'cert': _ThemeColors(0xFFFFFDF9, 0xFFB45309, 0xFFD97706, 0xFFFFFBEB),
};

class PmBackgroundPainter extends CustomPainter {
  const PmBackgroundPainter({required this.theme, this.showGrid = false, this.showGuides = false, this.background = true});
  final String theme;
  final bool showGrid;
  final bool showGuides;

  /// false = only the grid / guides overlay.
  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    final t = background ? _themes[theme] : null;
    if (background) canvas.drawRect(Offset.zero & size, Paint()..color = Color(t?.bg ?? 0xFFFFFFFF));
    if (t != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(24, 24, 746, 1075), const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = Color(t.outer),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(32, 32, 730, 1059), const Radius.circular(5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Color(t.inner),
      );
      if (theme == 'cert') {
        canvas.drawLine(const Offset(58, 210), const Offset(736, 210), Paint()
          ..strokeWidth = 2
          ..color = const Color(0xFFF59E0B));
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 34, 726, 92), const Radius.circular(4)),
            Paint()..color = Color(t.head));
        canvas.drawLine(const Offset(34, 126), const Offset(760, 126), Paint()
          ..strokeWidth = 2
          ..color = Color(t.outer));
      }
    }
    if (showGrid) {
      final p = Paint()
        ..color = const Color(0x243B82F6)
        ..strokeWidth = 1;
      const step = PmA4.w / PmA4.mmW * 5;
      for (var x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
      for (var y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }
    if (showGuides) {
      final p = Paint()
        ..color = const Color(0x6606B6D4)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant PmBackgroundPainter old) =>
      old.theme != theme || old.showGrid != showGrid || old.showGuides != showGuides || old.background != background;
}

class PmShapePainter extends CustomPainter {
  const PmShapePainter(this.o, {this.fillOnly = false, this.strokeOnly = false});
  final PmObject o;
  final bool fillOnly;
  final bool strokeOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = o.hasBorder ? o.borderW : 0.0;
    if (o.shapeKind == 'line') {
      if (fillOnly) return;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = pmColor(o.borderC)
          ..strokeWidth = math.max(1, sw),
      );
      return;
    }
    final path = PmShapes.path(o.shapeKind, size, sw / 2, o.radius);
    if (!strokeOnly && !o.noFill) canvas.drawPath(path, Paint()..color = pmColor(o.fill));
    if (!fillOnly && sw > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeJoin = StrokeJoin.round
          ..color = pmColor(o.borderC),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PmShapePainter old) => true;
}

class PmShapeClipper extends CustomClipper<Path> {
  const PmShapeClipper(this.kind, this.pad, this.radius);
  final String kind;
  final double pad;
  final double radius;
  @override
  Path getClip(Size size) => PmShapes.path(kind, size, pad, radius);
  @override
  bool shouldReclip(covariant PmShapeClipper old) => old.kind != kind || old.pad != pad || old.radius != radius;
}

/// Text style shared by the artboard and the PDF.
FlnStyle pmTextStyle(PmObject o) => FlnStyle(
      o.size,
      weight: o.bold ? 700 : 400,
      color: pmColorInt(o.color),
      family: o.font,
      italic: o.italic,
      lineFactor: o.lineH,
    );

/// Text shown for an object and record ('' when a merge value is missing).
String pmObjectText(PmObject o, Map<String, String> record) {
  var base = (o.type == 'static' || o.type == 'shape') ? o.customText : (record[o.key] ?? '');
  // "ધોરણ: " + "ધોરણ - 6 - અ" prints once: "ધોરણ: 6 - અ".
  if (o.type == 'text') base = ClassLabel.afterCaption(o.prefix, base);
  if (o.type == 'text' && base.trim().isEmpty) return '';
  if (o.type == 'shape' && base.trim().isEmpty) return '';
  final t = '${o.prefix}$base${o.suffix}';
  return o.gujDigits ? pmGujDigits(t) : t;
}

TextAlign pmAlign(String a) => switch (a) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };

// ---------------------------------------------------------------------------
// PDF export
// ---------------------------------------------------------------------------

/// Photo bytes for a record and merge column (null = no photo).
typedef PmPhotoLookup = Uint8List? Function(Map<String, String> record, String column);

class PmPdfExporter {
  static const double _px2pt = 595.2756 / PmA4.w;

  /// Best grid for [n] items per A4 sheet: (landscape, cols, rows).
  static (bool, int, int) grid(int n, double gapMm) {
    if (n <= 1) return (false, 1, 1);
    var best = (false, 1, n);
    var bestScale = 0.0;
    for (final landscape in const <bool>[false, true]) {
      final sw = (landscape ? 297.0 : 210.0) - 10;
      final sh = (landscape ? 210.0 : 297.0) - 10;
      for (var c = 1; c <= n; c++) {
        if (n % c != 0) continue;
        final r = n ~/ c;
        final cw = (sw - gapMm * (c - 1)) / c;
        final ch = (sh - gapMm * (r - 1)) / r;
        final scale = math.min(cw / 210.0, ch / 297.0);
        if (scale > bestScale + 1e-6) {
          bestScale = scale;
          best = (landscape, c, r);
        }
      }
    }
    return best;
  }

  static Future<Uint8List> build({
    required List<PmPage> pages,
    required List<Map<String, String>> records,
    required Map<String, Uint8List> images,
    required PmPhotoLookup photoFor,
    int perSheet = 1,
    double gapMm = 0,
    bool cropMarks = true,
    bool padOddPages = false,
    bool noPhoto = false,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final doc = pw.Document(compress: true, title: 'Print Merge', creator: 'Professional School Management');
    final atlas = FlnGlyphAtlas(doc.document);

    // 1. Items (page × record) and their text layouts.
    final items = <(PmPage?, Map<String, String>)>[];
    for (final r in records) {
      for (final p in pages) {
        items.add((p, r));
      }
      if (padOddPages && pages.length.isOdd) items.add((null, r));
    }
    final layouts = <String, (List<FlnWordOp>, double)>{};
    String lkey(int item, String objId) => '$item|$objId';
    for (var i = 0; i < items.length; i++) {
      final page = items[i].$1;
      if (page == null) continue;
      for (final o in page.objects) {
        if (!(o.isTextual || o.type == 'shape')) continue;
        if (o.type == 'shape' && o.shapeKind == 'line') continue;
        final text = pmObjectText(o, items[i].$2);
        if (text.trim().isEmpty) continue;
        final st = pmTextStyle(o);
        final maxW = math.max(4.0, o.w - 8);
        final lay = flnLayoutParagraph(text, st, maxW, align: o.type == 'shape' ? TextAlign.center : pmAlign(o.align));
        layouts[lkey(i, o.id)] = lay;
        for (final w in lay.$1) {
          atlas.want(w.text, w.style);
          if (o.outlineW > 0) atlas.want(w.text, w.style.withColor(pmColorInt(o.outlineC)));
          if (o.shadow) atlas.want(w.text, w.style.withColor(pmColorInt(o.shadowC)));
        }
      }
      if (i % 50 == 0) {
        onProgress?.call('layout', (i + 1) / items.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    await atlas.render(onProgress: (p) => onProgress?.call('text', p));

    // 2. Images, embedded once each.
    final pdfImages = <int, PdfImage?>{};
    PdfImage? pdfImage(Uint8List? bytes) {
      if (bytes == null || bytes.isEmpty) return null;
      final k = identityHashCode(bytes);
      if (pdfImages.containsKey(k)) return pdfImages[k];
      PdfImage? img;
      try {
        img = PdfImage.file(doc.document, bytes: bytes);
      } catch (_) {
        img = null;
      }
      pdfImages[k] = img;
      return img;
    }

    // 3. Sheets.
    final g0 = grid(perSheet, gapMm);
    final landscape = g0.$1, cols = g0.$2, rows = g0.$3;
    final sheetW = (landscape ? 297.0 : 210.0) * kMm;
    final sheetH = (landscape ? 210.0 : 297.0) * kMm;
    final margin = perSheet <= 1 ? 0.0 : 5 * kMm;
    final gap = gapMm * kMm;
    final cellW = (sheetW - margin * 2 - gap * (cols - 1)) / cols;
    final cellH = (sheetH - margin * 2 - gap * (rows - 1)) / rows;
    final scale = perSheet <= 1 ? 1.0 : math.min(cellW / (PmA4.w * _px2pt), cellH / (PmA4.h * _px2pt));
    final contentW = PmA4.w * _px2pt * scale;
    final contentH = PmA4.h * _px2pt * scale;

    final sheets = (items.length / perSheet).ceil();
    for (var s = 0; s < sheets; s++) {
      final first = s * perSheet;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(perSheet <= 1 ? 595.2756 : sheetW, perSheet <= 1 ? 841.8898 : sheetH, marginAll: 0),
        build: (_) => pw.CustomPaint(
          size: PdfPoint(perSheet <= 1 ? 595.2756 : sheetW, perSheet <= 1 ? 841.8898 : sheetH),
          painter: (g, size) {
            for (var c = 0; c < perSheet && first + c < items.length; c++) {
              final col = c % cols, row = c ~/ cols;
              final cx = margin + col * (cellW + gap) + (cellW - contentW) / 2;
              final cyTop = margin + row * (cellH + gap) + (cellH - contentH) / 2;
              final item = items[first + c];
              g.saveContext();
              final m = Matrix4.identity()
                ..translate(perSheet <= 1 ? 0.0 : cx, size.y - (perSheet <= 1 ? 0.0 : cyTop))
                ..scale(_px2pt * scale, -_px2pt * scale, 1.0);
              g.setTransform(m);
              if (item.$1 != null) {
                _drawPage(g, item.$1!, item.$2, first + c, layouts, lkey, atlas, images, pdfImage, photoFor, noPhoto);
              }
              g.restoreContext();
              if (cropMarks && perSheet > 1) {
                _cropMarks(g, size.y, cx, cyTop, contentW, contentH);
              }
            }
          },
        ),
      ));
      if (s % 10 == 0) {
        onProgress?.call('pages', (s + 1) / sheets);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call('save', 1);
    await Future<void>.delayed(Duration.zero);
    return doc.save();
  }

  static void _cropMarks(PdfGraphics g, double sheetH, double x, double yTop, double w, double h) {
    const len = 3 * kMm, off = 1 * kMm;
    g.setStrokeColor(PdfColors.black);
    g.setLineWidth(0.3);
    final yB = sheetH - (yTop + h), yT = sheetH - yTop;
    void l(double x1, double y1, double x2, double y2) {
      g.moveTo(x1, y1);
      g.lineTo(x2, y2);
    }

    for (final px in <double>[x, x + w]) {
      l(px, yT + off, px, yT + off + len);
      l(px, yB - off, px, yB - off - len);
    }
    for (final py in <double>[yT, yB]) {
      l(x - off, py, x - off - len, py);
      l(x + w + off, py, x + w + off + len, py);
    }
    g.strokePath();
  }

  /// Draws one design page for one record. The transform maps artboard
  /// pixels with y pointing down.
  static void _drawPage(
    PdfGraphics g,
    PmPage page,
    Map<String, String> record,
    int item,
    Map<String, (List<FlnWordOp>, double)> layouts,
    String Function(int, String) lkey,
    FlnGlyphAtlas atlas,
    Map<String, Uint8List> images,
    PdfImage? Function(Uint8List?) pdfImage,
    PmPhotoLookup photoFor,
    bool noPhoto,
  ) {
    // Background colour and theme frame.
    final t = _themes[page.theme];
    g.setFillColor(PdfColor.fromInt(t?.bg ?? 0xFFFFFFFF));
    g.drawRect(0, 0, PmA4.w, PmA4.h);
    g.fillPath();
    final bg = pdfImage(images[page.bgImageId]);
    if (bg != null) _image(g, bg, const Rect.fromLTWH(0, 0, PmA4.w, PmA4.h), 'fill');
    if (t != null) {
      g.setStrokeColor(PdfColor.fromInt(t.outer));
      g.setLineWidth(3.5);
      g.drawRRect(24, 24, 746, 1075, 8, 8);
      g.strokePath();
      g.setStrokeColor(PdfColor.fromInt(t.inner));
      g.setLineWidth(1.2);
      g.drawRRect(32, 32, 730, 1059, 5, 5);
      g.strokePath();
      if (page.theme == 'cert') {
        g.setStrokeColor(PdfColor.fromInt(0xFFF59E0B));
        g.setLineWidth(2);
        g.moveTo(58, 210);
        g.lineTo(736, 210);
        g.strokePath();
      } else {
        g.setFillColor(PdfColor.fromInt(t.head));
        g.drawRRect(34, 34, 726, 92, 4, 4);
        g.fillPath();
        g.setStrokeColor(PdfColor.fromInt(t.outer));
        g.setLineWidth(2);
        g.moveTo(34, 126);
        g.lineTo(760, 126);
        g.strokePath();
      }
    }

    for (final o in page.objects) {
      if (o.type == 'photo' && noPhoto) continue;
      g.saveContext();
      if (o.rotate != 0) {
        final cx = o.x + o.w / 2, cy = o.y + o.h / 2;
        g.setTransform(Matrix4.identity()
          ..translate(cx, cy)
          ..rotateZ(o.rotate * math.pi / 180)
          ..translate(-cx, -cy));
      }
      if (o.opacity < 99.5) g.setGraphicState(PdfGraphicState(opacity: o.opacity / 100));
      final rect = Rect.fromLTWH(o.x, o.y, o.w, o.h);
      final sw = o.hasBorder ? o.borderW : 0.0;

      if (o.type == 'shape') {
        if (o.shapeKind == 'line') {
          g.setStrokeColor(PdfColor.fromInt(pmColorInt(o.borderC)));
          g.setLineWidth(math.max(1, sw));
          g.moveTo(o.x, o.y + o.h / 2);
          g.lineTo(o.x + o.w, o.y + o.h / 2);
          g.strokePath();
        } else {
          if (!o.noFill) {
            g.setFillColor(PdfColor.fromInt(pmColorInt(o.fill)));
            _shapePath(g, o, rect, sw / 2);
            g.fillPath();
          }
          if (o.clipMode != 'none') {
            final bytes = o.clipMode == 'image' ? images[o.clipImageId] : photoFor(record, o.clipKey);
            final img = pdfImage(bytes);
            if (img != null) {
              g.saveContext();
              _shapePath(g, o, rect, sw / 2);
              g.clipPath();
              final s = o.clipScale / 100;
              final iw = rect.width * s, ih = rect.height * s;
              final box = Rect.fromLTWH(
                rect.left + (rect.width - iw) / 2 + o.clipX,
                rect.top + (rect.height - ih) / 2 + o.clipY,
                iw,
                ih,
              );
              _image(g, img, box, 'cover');
              g.restoreContext();
            }
          }
          if (sw > 0) {
            g.setStrokeColor(PdfColor.fromInt(pmColorInt(o.borderC)));
            g.setLineWidth(sw);
            _shapePath(g, o, rect, sw / 2);
            g.strokePath();
          }
          final lay = layouts[lkey(item, o.id)];
          if (lay != null) {
            final top = o.y + (o.h - lay.$2) / 2;
            _words(g, atlas, lay.$1, o.x + 4, top, o);
          }
        }
      } else if (o.type == 'photo' || o.type == 'image') {
        final rr = math.min(o.radius, math.min(o.w, o.h) / 2);
        if (!o.noFill) {
          g.setFillColor(PdfColor.fromInt(pmColorInt(o.fill)));
          _rrect(g, rect, rr);
          g.fillPath();
        }
        final bytes = o.type == 'image' ? images[o.imageId] : photoFor(record, o.key);
        final img = pdfImage(bytes);
        if (img != null) {
          g.saveContext();
          _rrect(g, rect, rr);
          g.clipPath();
          _image(g, img, rect, o.fit);
          g.restoreContext();
        }
        if (sw > 0) {
          g.setStrokeColor(PdfColor.fromInt(pmColorInt(o.borderC)));
          g.setLineWidth(sw);
          _rrect(g, rect.deflate(sw / 2), math.max(0, rr - sw / 2));
          g.strokePath();
        }
      } else {
        final rr = math.min(o.radius, math.min(o.w, o.h) / 2);
        if (!o.noFill) {
          g.setFillColor(PdfColor.fromInt(pmColorInt(o.fill)));
          _rrect(g, rect, rr);
          g.fillPath();
        }
        if (sw > 0) {
          g.setStrokeColor(PdfColor.fromInt(pmColorInt(o.borderC)));
          g.setLineWidth(sw);
          _rrect(g, rect.deflate(sw / 2), math.max(0, rr - sw / 2));
          g.strokePath();
        }
        final lay = layouts[lkey(item, o.id)];
        if (lay != null) _words(g, atlas, lay.$1, o.x + 4, o.y + 2, o);
      }
      g.restoreContext();
    }
  }

  static void _words(PdfGraphics g, FlnGlyphAtlas atlas, List<FlnWordOp> words, double dx, double dy, PmObject o) {
    final t = FlnText.instance;
    final underline = o.underline;
    for (final w in words) {
      if (o.shadow) {
        final off = math.max(1.0, w.style.size * 0.07);
        atlas.draw(g, w.text, w.style.withColor(pmColorInt(o.shadowC)), w.x + dx + off, w.y + dy + off, scale: w.scale);
      }
      if (o.outlineW > 0) {
        final ow = o.outlineW;
        final outline = w.style.withColor(pmColorInt(o.outlineC));
        for (var k = 0; k < 12; k++) {
          final a = k * math.pi / 6;
          atlas.draw(g, w.text, outline, w.x + dx + math.cos(a) * ow, w.y + dy + math.sin(a) * ow, scale: w.scale);
        }
      }
      atlas.draw(g, w.text, w.style, w.x + dx, w.y + dy, scale: w.scale);
      if (underline) {
        final width = t.wordWidth(w.text, w.style) * w.scale + t.spaceWidth(w.style) * 0.5;
        final base = w.y + dy + w.style.lineHeight * 0.82;
        g.setStrokeColor(PdfColor.fromInt(w.style.color));
        g.setLineWidth(math.max(0.6, w.style.size / 16));
        g.moveTo(w.x + dx, base);
        g.lineTo(w.x + dx + width, base);
        g.strokePath();
      }
    }
  }

  static void _rrect(PdfGraphics g, Rect r, double radius) {
    if (radius > 0.5) {
      g.drawRRect(r.left, r.top, r.width, r.height, radius, radius);
    } else {
      g.drawRect(r.left, r.top, r.width, r.height);
    }
  }

  static void _shapePath(PdfGraphics g, PmObject o, Rect rect, double pad) {
    final inner = Rect.fromLTWH(
      rect.left + pad,
      rect.top + pad,
      math.max(1, rect.width - pad * 2),
      math.max(1, rect.height - pad * 2),
    );
    if (PmShapes.isEllipse(o.shapeKind)) {
      g.drawEllipse(inner.center.dx, inner.center.dy, inner.width / 2, inner.height / 2);
      return;
    }
    final poly = PmShapes.polygon(o.shapeKind);
    if (poly != null) {
      for (var i = 0; i < poly.length; i++) {
        final x = inner.left + poly[i].dx * inner.width;
        final y = inner.top + poly[i].dy * inner.height;
        i == 0 ? g.moveTo(x, y) : g.lineTo(x, y);
      }
      g.closePath();
      return;
    }
    final r = math.min(o.shapeKind == 'roundrect' ? math.max(12.0, o.radius) : o.radius,
        math.min(inner.width, inner.height) / 2);
    _rrect(g, inner, r);
  }

  /// Draws [img] into [box] (y-down transform) with the given fit.
  static void _image(PdfGraphics g, PdfImage img, Rect box, String fit) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    if (iw <= 0 || ih <= 0) return;
    double dw, dh;
    if (fit == 'fill') {
      dw = box.width;
      dh = box.height;
    } else {
      final s = fit == 'contain' ? math.min(box.width / iw, box.height / ih) : math.max(box.width / iw, box.height / ih);
      dw = iw * s;
      dh = ih * s;
    }
    final left = box.left + (box.width - dw) / 2;
    final top = box.top + (box.height - dh) / 2;
    g.drawImage(img, left, top + dh, dw, -dh);
  }
}
