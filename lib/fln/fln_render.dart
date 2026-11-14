// Draws FLN page layouts on screen and into a PDF.
//
// The PDF keeps boxes and lines as vectors. Text is drawn as small images
// rendered by Flutter's text engine, which shapes Gujarati correctly (the
// PDF library alone cannot join Gujarati conjuncts). Each distinct word or
// character is rendered once and reused on every page, so even a whole class
// of 130-question papers stays small.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fln_layout.dart';

// ---------------------------------------------------------------------------
// Screen preview
// ---------------------------------------------------------------------------

class FlnPagePainter extends CustomPainter {
  FlnPagePainter(this.page);
  final FlnPageLayout page;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / page.width;
    canvas.save();
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, page.width, page.height), Paint()..color = Colors.white);
    final t = FlnText.instance;
    for (final op in page.ops) {
      if (op is FlnBoxOp) {
        final rr = RRect.fromRectAndRadius(op.rect, Radius.circular(_radius(op)));
        if (op.fill != null) canvas.drawRRect(rr, Paint()..color = Color(op.fill!));
        if (op.stroke != null) {
          canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = op.strokeWidth
              ..color = Color(op.stroke!),
          );
        }
      } else if (op is FlnLineOp) {
        final paint = Paint()
          ..color = Color(op.color)
          ..strokeWidth = op.width;
        if (!op.dotted) {
          canvas.drawLine(op.a, op.b, paint);
        } else {
          final len = (op.b - op.a).distance;
          if (len <= 0) continue;
          final dir = (op.b - op.a) / len;
          for (var d = 0.0; d < len; d += 2.4) {
            canvas.drawLine(op.a + dir * d, op.a + dir * math.min(len, d + 0.8), paint);
          }
        }
      } else if (op is FlnWordOp) {
        if (FlnText.isSimple(op.text)) {
          var x = op.x;
          for (final r in op.text.runes) {
            final ch = String.fromCharCode(r);
            t.painter(ch, op.style).paint(canvas, Offset(x, op.y));
            x += t.charWidth(ch, op.style);
          }
        } else if (op.scale < 0.999) {
          canvas.save();
          canvas.translate(op.x, op.y);
          canvas.scale(op.scale);
          t.painter(op.text, op.style).paint(canvas, Offset.zero);
          canvas.restore();
        } else {
          t.painter(op.text, op.style).paint(canvas, Offset(op.x, op.y));
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlnPagePainter oldDelegate) => oldDelegate.page != page;
}

double _radius(FlnBoxOp op) =>
    math.max(0, math.min(op.radius, math.min(op.rect.width, op.rect.height) / 2));

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

class _Glyph {
  _Glyph(this.image, this.width, this.height, this.padX, this.padY);
  final PdfImage image;
  final double width;
  final double height;
  final double padX;
  final double padY;
}

/// Renders words / characters once (Flutter shapes Gujarati correctly) and
/// draws them into PDF pages as small reusable images.
class FlnGlyphAtlas {
  FlnGlyphAtlas(this.document);
  final PdfDocument document;

  /// Pixels per text unit (4 ≈ 288 dpi at 1 unit = 1 pt).
  static const double density = 4;

  final Map<String, _Glyph> _glyphs = <String, _Glyph>{};
  final Map<String, (String, FlnStyle)> _pending = <String, (String, FlnStyle)>{};

  static String _key(String text, FlnStyle st) => '${st.key}|$text';

  /// Queues the images needed to draw [word] in [st].
  void want(String word, FlnStyle st) {
    if (FlnText.isSimple(word)) {
      for (final r in word.runes) {
        final ch = String.fromCharCode(r);
        if (ch.trim().isEmpty) continue;
        final k = _key(ch, st);
        if (!_glyphs.containsKey(k)) _pending[k] = (ch, st);
      }
    } else {
      final k = _key(word, st);
      if (!_glyphs.containsKey(k)) _pending[k] = (word, st);
    }
  }

  int get pendingCount => _pending.length;

  /// Renders every queued image.
  Future<void> render({void Function(double progress)? onProgress}) async {
    final t = FlnText.instance;
    final total = _pending.length;
    var done = 0;
    for (final e in _pending.entries.toList()) {
      final text = e.value.$1;
      final st = e.value.$2;
      final tp = t.painter(text, st);
      final padX = st.size * 0.4;
      final padY = st.size * 0.5;
      final wPt = tp.width + padX * 2;
      final hPt = st.lineHeight + padY * 2;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(density);
      tp.paint(canvas, Offset(padX, padY));
      final picture = recorder.endRecording();
      final pxW = math.max(1, (wPt * density).ceil());
      final pxH = math.max(1, (hPt * density).ceil());
      final image = await picture.toImage(pxW, pxH);
      picture.dispose();
      ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      } catch (_) {
        bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      }
      image.dispose();
      if (bytes != null) {
        _glyphs[e.key] = _Glyph(
          PdfImage(document, image: bytes.buffer.asUint8List(), width: pxW, height: pxH),
          pxW / density,
          pxH / density,
          padX,
          padY,
        );
      }
      _pending.remove(e.key);
      done++;
      if (done % 40 == 0) {
        onProgress?.call(total == 0 ? 1 : done / total);
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Draws [word] with its line-box top-left at (x, yTop).
  ///
  /// [flipY]: page height when the canvas uses PDF coordinates (y up);
  /// null when the current transform already maps y downwards.
  void draw(PdfGraphics g, String word, FlnStyle st, double x, double yTop, {double? flipY, double scale = 1}) {
    void one(String key, double gx) {
      final gl = _glyphs[key];
      if (gl == null) return;
      final w = gl.width * scale;
      final h = gl.height * scale;
      final left = gx - gl.padX * scale;
      final top = yTop - gl.padY * scale;
      if (flipY != null) {
        g.drawImage(gl.image, left, flipY - top - h, w, h);
      } else {
        // y-down transform: a negative height keeps the image upright.
        g.drawImage(gl.image, left, top + h, w, -h);
      }
    }

    if (FlnText.isSimple(word)) {
      final t = FlnText.instance;
      var cx = x;
      for (final r in word.runes) {
        final ch = String.fromCharCode(r);
        if (ch.trim().isNotEmpty) one(_key(ch, st), cx);
        cx += t.charWidth(ch, st) * scale;
      }
    } else {
      one(_key(word, st), x);
    }
  }
}

class FlnPdfBuilder {
  static Future<Uint8List> build(
    List<FlnPageLayout> pages, {
    void Function(String stage, double progress)? onProgress,
    String title = 'FLN Workbook',
  }) async {
    final doc = pw.Document(compress: true, title: title, creator: 'Professional School Management');
    final atlas = FlnGlyphAtlas(doc.document);
    for (final page in pages) {
      for (final op in page.ops) {
        if (op is FlnWordOp) atlas.want(op.text, op.style);
      }
    }
    await atlas.render(onProgress: (p) => onProgress?.call('text', p));

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.CustomPaint(
          size: PdfPoint(page.width, page.height),
          painter: (g, size) => _paintPage(g, page, atlas),
        ),
      ));
      if (i % 20 == 0) {
        onProgress?.call('pages', (i + 1) / pages.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call('save', 1);
    await Future<void>.delayed(Duration.zero);
    return doc.save();
  }

  static void _paintPage(PdfGraphics g, FlnPageLayout page, FlnGlyphAtlas atlas) {
    final h = page.height;

    void path(FlnBoxOp op) {
      final r = op.rect;
      final rad = _radius(op);
      if (rad > 0) {
        g.drawRRect(r.left, h - r.bottom, r.width, r.height, rad, rad);
      } else {
        g.drawRect(r.left, h - r.bottom, r.width, r.height);
      }
    }

    for (final op in page.ops) {
      if (op is FlnBoxOp) {
        if (op.fill != null) {
          g.setFillColor(PdfColor.fromInt(op.fill!));
          path(op);
          g.fillPath();
        }
        if (op.stroke != null) {
          g.setStrokeColor(PdfColor.fromInt(op.stroke!));
          g.setLineWidth(op.strokeWidth);
          path(op);
          g.strokePath();
        }
      } else if (op is FlnLineOp) {
        g.setStrokeColor(PdfColor.fromInt(op.color));
        g.setLineWidth(op.width);
        if (op.dotted) g.setLineDashPattern(<num>[0.8, 1.6]);
        g.moveTo(op.a.dx, h - op.a.dy);
        g.lineTo(op.b.dx, h - op.b.dy);
        g.strokePath();
        if (op.dotted) g.setLineDashPattern();
      } else if (op is FlnWordOp) {
        atlas.draw(g, op.text, op.style, op.x, op.y, flipY: h, scale: op.scale);
      }
    }
  }
}
