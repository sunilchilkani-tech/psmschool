part of '../supabase_id_card_studio_screen.dart';

// ============================================================================
// UNIFORM PHOTO FRAME PAINTER, PRINCIPAL SIGN PAINTER & WHITE-BG PROCESSOR
// ============================================================================

/// Removes near-white background from an uploaded Seal or Principal Signature image
/// and crops to tight non-transparent bounds.
Future<(Uint8List, double)> processSealRemoveWhiteBg(
  Uint8List rawBytes, {
  int tolerance = 38,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return (rawBytes, w / math.max(1, h));

    final data = Uint8List.fromList(byteData.buffer.asUint8List());
    final thr = 255 - tolerance.clamp(0, 120).toInt();
    int minX = w, minY = h, maxX = 0, maxY = 0;
    bool found = false;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        final r = data[idx];
        final g = data[idx + 1];
        final b = data[idx + 2];
        final a = data[idx + 3];
        if (a < 15) {
          data[idx + 3] = 0;
          continue;
        }
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final sat = maxC - minC;
        final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
        if (tolerance > 0) {
          if (r >= thr && g >= thr && b >= thr && sat < tolerance + 18) {
            data[idx + 3] = 0;
            continue;
          } else if (lum >= thr - 18 && sat < tolerance + 28) {
            final fade = ((255 - lum) / math.max(1, 255 - (thr - 18)))
                .clamp(0.0, 1.0);
            data[idx + 3] = (a * fade).round().clamp(0, 255).toInt();
            if (data[idx + 3] < 12) {
              data[idx + 3] = 0;
              continue;
            }
          }
        }
        if (data[idx + 3] > 15) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          found = true;
        }
      }
    }

    final completer = ui.ImmutableBuffer.fromUint8List(data);
    final buf = await completer;
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final outCodec = await desc.instantiateCodec();
    final outFrame = await outCodec.getNextFrame();
    final fullProcessed = outFrame.image;

    if (!found) {
      final png =
          await fullProcessed.toByteData(format: ui.ImageByteFormat.png);
      return (
        png?.buffer.asUint8List() ?? rawBytes,
        w / math.max(1.0, h.toDouble())
      );
    }

    const pad = 2;
    final sx = math.max(0, minX - pad);
    final sy = math.max(0, minY - pad);
    final sw = math.min(w - sx, (maxX - minX + 1) + pad * 2);
    final sh = math.min(h - sy, (maxY - minY + 1) + pad * 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      fullProcessed,
      Rect.fromLTWH(sx.toDouble(), sy.toDouble(), sw.toDouble(), sh.toDouble()),
      Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
      Paint(),
    );
    final croppedImg = await recorder.endRecording().toImage(sw, sh);
    final croppedPng =
        await croppedImg.toByteData(format: ui.ImageByteFormat.png);
    if (croppedPng == null) {
      return (rawBytes, w / math.max(1.0, h.toDouble()));
    }
    return (
      croppedPng.buffer.asUint8List(),
      sw / math.max(1.0, sh.toDouble())
    );
  } catch (_) {
    return (rawBytes, 1.0);
  }
}

/// Draws a rounded-rectangle or circular photo border with 100% uniform
/// thickness around all corners so the frame is NEVER cut at the corners
/// even when cornerRadius is large.
class UniformPhotoFramePainter extends CustomPainter {
  final double cornerRadius;
  final double borderWidth;
  final Color borderColor;
  final bool isSelected;

  const UniformPhotoFramePainter({
    required this.cornerRadius,
    required this.borderWidth,
    required this.borderColor,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxR = math.min(size.width, size.height) / 2.0;
    final clampedR = cornerRadius.clamp(0.0, maxR);

    if (borderWidth > 0.05) {
      final halfBw = borderWidth / 2.0;
      final insetRect = (Offset.zero & size).deflate(halfBw);
      final strokeRadius = math.max(0.0, clampedR - halfBw);
      final rrect =
          RRect.fromRectAndRadius(insetRect, Radius.circular(strokeRadius));
      final paint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..isAntiAlias = true;
      canvas.drawRRect(rrect, paint);
    }

    if (isSelected) {
      final selPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..isAntiAlias = true;
      final selRRect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.8),
        Radius.circular(clampedR),
      );
      canvas.drawRRect(selRRect, selPaint);
    }
  }

  @override
  bool shouldRepaint(covariant UniformPhotoFramePainter oldDelegate) =>
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.isSelected != isSelected;
}

class DemoSignaturePainter extends CustomPainter {
  const DemoSignaturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pen = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, h * 0.032);

    final path = Path()
      ..moveTo(w * 0.12, h * 0.58)
      ..quadraticBezierTo(w * 0.24, h * 0.16, w * 0.34, h * 0.54)
      ..quadraticBezierTo(w * 0.44, h * 0.72, w * 0.56, h * 0.32)
      ..quadraticBezierTo(w * 0.68, h * 0.62, w * 0.88, h * 0.38);
    canvas.drawPath(path, pen);

    final tp = TextPainter(
      text: TextSpan(
        text: 'Principal Sign',
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          color: const Color(0xFF334155),
          fontSize: math.max(7.0, h * 0.18),
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, h - tp.height - 2));
  }

  @override
  bool shouldRepaint(covariant DemoSignaturePainter oldDelegate) => false;
}

class CardGridAndRulerPainter extends CustomPainter {
  final double scale;
  final bool showGrid;
  final bool showRulers;

  const CardGridAndRulerPainter({
    required this.scale,
    required this.showGrid,
    required this.showRulers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step5mm = 50.0 * scale; // 5mm in editor units
    final step10mm = 100.0 * scale; // 10mm (1cm) in editor units

    if (showGrid && step5mm >= 6) {
      final minorPaint = Paint()
        ..color = const Color(0x1E0F172A)
        ..strokeWidth = 0.6;
      final majorPaint = Paint()
        ..color = const Color(0x380D7480)
        ..strokeWidth = 0.9;

      for (double x = 0; x <= size.width; x += step5mm) {
        final isMajor = ((x / step5mm).round() % 2) == 0;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          isMajor ? majorPaint : minorPaint,
        );
      }
      for (double y = 0; y <= size.height; y += step5mm) {
        final isMajor = ((y / step5mm).round() % 2) == 0;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          isMajor ? majorPaint : minorPaint,
        );
      }
    }

    if (showRulers && step10mm >= 14) {
      final tickPaint = Paint()
        ..color = const Color(0x770F172A)
        ..strokeWidth = 1.0;
      for (double x = 0; x <= size.width; x += step5mm) {
        final isCm = ((x / step5mm).round() % 2) == 0;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, isCm ? 7.0 : 4.0),
          tickPaint,
        );
      }
      for (double y = 0; y <= size.height; y += step5mm) {
        final isCm = ((y / step5mm).round() % 2) == 0;
        canvas.drawLine(
          Offset(0, y),
          Offset(isCm ? 7.0 : 4.0, y),
          tickPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CardGridAndRulerPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.showRulers != showRulers;
}

class CardTemplatePainter extends CustomPainter {
  final BuiltInTemplateTheme theme;
  final String headerTitle;
  final Color accentColor;

  const CardTemplatePainter({
    required this.theme,
    required this.headerTitle,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final isV = w < h;
    final minDim = math.min(w, h);

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bgPaint);
    if (theme == BuiltInTemplateTheme.none) {
      if (headerTitle.trim().isNotEmpty) {
        final bandY = isV ? h * 0.07 : h * 0.10;
        _drawCenteredText(
          canvas,
          headerTitle,
          Offset(w / 2, bandY),
          accentColor,
          minDim * 0.044,
        );
      }
      return;
    }

    if (theme == BuiltInTemplateTheme.blankBorder) {
      final inset = minDim * 0.032;
      final p1 = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, minDim * 0.008);
      canvas.drawRect(
        Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
        p1,
      );
      final p2 = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(
        Rect.fromLTWH(
            inset + 5, inset + 5, w - (inset + 5) * 2, h - (inset + 5) * 2),
        p2,
      );
      if (headerTitle.trim().isNotEmpty) {
        final bandY = isV ? h * 0.08 : h * 0.12;
        _drawCenteredText(
          canvas,
          headerTitle,
          Offset(w / 2, bandY),
          accentColor,
          minDim * 0.044,
        );
        canvas.drawLine(
          Offset(inset + 12, bandY + minDim * 0.035),
          Offset(w - inset - 12, bandY + minDim * 0.035),
          p2..strokeWidth = 1.5,
        );
      }
      return;
    }

    if (theme == BuiltInTemplateTheme.blankHeader) {
      final headH = isV ? h * 0.12 : h * 0.165;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, headH),
        Paint()..color = accentColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(6, 6, w - 12, h - 12),
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      if (headerTitle.trim().isNotEmpty) {
        _drawCenteredText(
          canvas,
          headerTitle,
          Offset(w / 2, headH / 2),
          Colors.white,
          headH * 0.40,
        );
      }
      return;
    }

    if (theme == BuiltInTemplateTheme.blankBadge) {
      final inset = minDim * 0.025;
      canvas.drawRect(
        Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      final slotW = w * 0.14;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH((w - slotW) / 2, inset + 6, slotW, 8),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFFCBD5E1),
      );
      if (headerTitle.trim().isNotEmpty) {
        _drawCenteredText(
          canvas,
          headerTitle,
          Offset(w / 2, inset + minDim * 0.08),
          accentColor,
          minDim * 0.042,
        );
      }
      return;
    }

    Color p1 = accentColor;
    Color p2 = accentColor.withAlpha(200);
    Color bg = const Color(0xFFF8FAFC);

    switch (theme) {
      case BuiltInTemplateTheme.teal:
        p1 = const Color(0xFF0F766E);
        p2 = const Color(0xFF14B8A6);
        break;
      case BuiltInTemplateTheme.navy:
        p1 = const Color(0xFF1E3A8A);
        p2 = const Color(0xFF3B82F6);
        break;
      case BuiltInTemplateTheme.gold:
        p1 = const Color(0xFF78350F);
        p2 = const Color(0xFFD97706);
        bg = const Color(0xFFFFFBEB);
        break;
      case BuiltInTemplateTheme.crimson:
        p1 = const Color(0xFF881337);
        p2 = const Color(0xFFF43F5E);
        bg = const Color(0xFFFFF1F2);
        break;
      case BuiltInTemplateTheme.minimal:
        p1 = const Color(0xFF0F172A);
        p2 = const Color(0xFF475569);
        bg = Colors.white;
        break;
      case BuiltInTemplateTheme.emerald:
        p1 = const Color(0xFF065F46);
        p2 = const Color(0xFF10B981);
        bg = const Color(0xFFF0FDF4);
        break;
      default:
        break;
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final headH = isV ? h * 0.115 : h * 0.155;
    final footH = math.max(8.0, h * 0.032);

    final wave2 = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, headH + 8)
      ..quadraticBezierTo(w * 0.55, headH + 22, 0, headH + 4)
      ..close();
    canvas.drawPath(wave2, Paint()..color = p2);

    final wave1 = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, headH - 3)
      ..quadraticBezierTo(w * 0.6, headH + 14, 0, headH - 2)
      ..close();
    canvas.drawPath(wave1, Paint()..color = p1);

    canvas.drawRect(
        Rect.fromLTWH(0, h - footH, w, footH), Paint()..color = p1);

    if (headerTitle.trim().isNotEmpty) {
      _drawCenteredText(
        canvas,
        headerTitle,
        Offset(w / 2, headH * 0.48),
        Colors.white,
        headH * 0.38,
      );
    }
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CardTemplatePainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.headerTitle != headerTitle ||
      oldDelegate.accentColor != accentColor;
}

class DemoAvatarPainter extends CustomPainter {
  final String initials;
  const DemoAvatarPainter({required this.initials});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(rect, paint);

    final fg = Paint()..color = const Color(0xFF94A3B8);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.36),
      size.width * 0.18,
      fg,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.96),
        width: size.width * 0.68,
        height: size.height * 0.48,
      ),
      math.pi,
      math.pi,
      true,
      fg,
    );

    if (initials.trim().isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: initials,
          style: TextStyle(
            fontFamily: 'NotoSansGujaratiLocal',
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w700,
            fontSize: size.width * 0.12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          size.width * 0.5 - tp.width / 2,
          size.height * 0.78 - tp.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DemoAvatarPainter oldDelegate) =>
      oldDelegate.initials != initials;
}

class DemoSealPainter extends CustomPainter {
  const DemoSealPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.44;
    final stroke = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * 0.06);
    canvas.drawCircle(c, r, stroke);
    canvas.drawCircle(
      c,
      r * 0.82,
      Paint()..color = const Color(0x181D4ED8),
    );
    canvas.drawCircle(
        c, r * 0.82, stroke..strokeWidth = math.max(1.0, r * 0.03));

    final tp = TextPainter(
      text: TextSpan(
        text: 'SEAL',
        style: TextStyle(
          color: const Color(0xFF1E3A8A),
          fontSize: r * 0.26,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DemoSealPainter oldDelegate) => false;
}

class CutGuidePainter extends CustomPainter {
  final CutGuideStyle style;
  const CutGuidePainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    if (style == CutGuideStyle.solid) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    if (style == CutGuideStyle.crop) {
      final m = math.min(size.width, size.height) * 0.06;
      canvas.drawLine(const Offset(0, 0), Offset(m, 0), paint);
      canvas.drawLine(const Offset(0, 0), Offset(0, m), paint);
      canvas.drawLine(Offset(size.width - m, 0), Offset(size.width, 0), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, m), paint);
      canvas.drawLine(
          Offset(0, size.height - m), Offset(0, size.height), paint);
      canvas.drawLine(
          Offset(0, size.height), Offset(m, size.height), paint);
      canvas.drawLine(Offset(size.width - m, size.height),
          Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, size.height - m),
          Offset(size.width, size.height), paint);
      return;
    }

    const dash = 5.0;
    const gap = 4.0;
    for (double x = 0; x < size.width; x += dash + gap) {
      final x2 = math.min(size.width, x + dash);
      canvas.drawLine(Offset(x, 0), Offset(x2, 0), paint);
      canvas.drawLine(
          Offset(x, size.height), Offset(x2, size.height), paint);
    }
    for (double y = 0; y < size.height; y += dash + gap) {
      final y2 = math.min(size.height, y + dash);
      canvas.drawLine(Offset(0, y), Offset(0, y2), paint);
      canvas.drawLine(
          Offset(size.width, y), Offset(size.width, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CutGuidePainter oldDelegate) =>
      oldDelegate.style != style;
}
