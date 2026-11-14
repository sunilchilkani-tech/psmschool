// ============================================================================
// CorelDRAW Print Merge Studio Pro — Gujarati Student Profiles & 200+ Column
// Edition (Complete Standalone Flutter / Dart Module)
// ============================================================================
// Drop this file into your Flutter project (e.g. `lib/coreldraw_print_merge_studio_pro.dart`)
// and mount `const CorelDrawPrintMergeStudioApp()` or `const CorelDrawPrintMergeStudioScreen()`.
//
// Features Included (100% Parity with HTML Studio):
// 1. 3 Workspace Views:
//    - 1 Upload & Data Setup (200+ Columns Table, CSV/TSV Import & Export,
//      210-Col Student Profile Generator, Gujarati Samman Patra Demo)
//    - 2 CorelDRAW / Illustrator Design Artboard (794×1123 A4 Canvas, Rulers,
//      Grid & Guides, Left Vector Toolbox, Top Property Bar, Right Inspector,
//      Layer & Lock Docker, and Right-Edge 56-Swatch CorelDRAW Color Bar)
//    - 3 Output & Multi-Up Imposition (1×1, 1×2, 2×2, 2×4, 3×4 N-Up Preview,
//      Guillotine Crop Marks, Student Range Filter, High-Res Page Render)
// 2. CorelDRAW Artboard Interactions:
//    - Template Background Visible Directly on Artboard
//    - 12 Vector Shapes (Rectangle, Square, Rounded Rect, Circle, Oval,
//      Triangle, Diamond, Hexagon, Star, Ribbon Banner, Arrow, Line)
//    - Shape Fill Colour, No Fill, Border Colour, Border Width, Border None,
//      and Shape/Object Opacity (5%–100%)
//    - Ctrl+A Select All, Shift+Click Multi-Selection & Marquee Selection
//    - CorelDRAW 8-Handle Grips with Proportional Corner Stretch (Opposite
//      Corner Fixed & Aspect Ratio Locked on NW, NE, SE, SW handles)
//    - CorelDRAW PowerClip Inside Container (Clip Image or Student Merge Photo
//      inside any Vector Shape with Zoom 20%–300%, Pan X/Y, Center, Extract)
//    - Strict Double-Click Text Insertion & Inline Text Editing on Artboard
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const CorelDrawPrintMergeStudioApp());
}

// ============================================================================
// 1. ROOT APPLICATION WIDGET
// ============================================================================
class CorelDrawPrintMergeStudioApp extends StatelessWidget {
  const CorelDrawPrintMergeStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CorelDRAW Print Merge Studio Pro — 200+ Column Edition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E2229),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF10B981),
          tertiary: Color(0xFFF59E0B),
          surface: Color(0xFF272C35),
        ),
      ),
      home: const CorelDrawPrintMergeStudioScreen(),
    );
  }
}

// ============================================================================
// 2. CONSTANTS, PALETTES & DATA MODELS
// ============================================================================
class A4Spec {
  static const double w = 794.0;
  static const double h = 1123.0;
  static const double mmw = 210.0;
  static const double mmh = 297.0;
  static const int maxPages = 10;
}

const List<String> kBuiltinGujFonts = [
  'Noto Sans Gujarati',
  'Noto Serif Gujarati',
  'Hind Vadodara',
  'Anek Gujarati',
  'Baloo Bhai 2',
  'Rasa',
  'Mukta Vaani',
  'Shruti',
  'Nirmala UI',
  'Inter',
  'Arial',
  'Times New Roman',
  'Georgia',
  'Verdana',
];

const Map<String, String> kShapeDisplayNames = {
  'rect': 'Rectangle',
  'square': 'Square',
  'roundrect': 'Rounded Rectangle',
  'ellipse': 'Circle',
  'oval': 'Oval / Ellipse',
  'triangle': 'Triangle',
  'diamond': 'Diamond',
  'polygon': 'Hexagon',
  'star': 'Star',
  'banner': 'Ribbon Banner',
  'arrow': 'Arrow',
  'line': 'Line',
};

const List<String> kCorelPaletteHex = [
  'none', '#FFFFFF', '#E2E8F0', '#94A3B8', '#475569', '#1E293B', '#000000',
  '#FEF08A', '#FDE047', '#FACC15', '#EAB308', '#F59E0B', '#D97706', '#B45309',
  '#FED7AA', '#FDBA74', '#FB923C', '#F97316', '#EA580C', '#DC2626', '#991B1B',
  '#FECDD3', '#FDA4AF', '#F43F5E', '#E11D48', '#DB2777', '#BE185D', '#831843',
  '#F3E8FF', '#D8B4FE', '#A855F7', '#9333EA', '#7E22CE', '#6D28D9', '#4C1D95',
  '#DBEAFE', '#93C5FD', '#60A5FA', '#3B82F6', '#2563EB', '#1D4ED8', '#1E3A8A',
  '#CFFAFE', '#67E8F9', '#06B6D4', '#0891B2', '#0D9488', '#0F766E', '#115E59',
  '#DCFCE7', '#86EFAC', '#4ADE80', '#22C55E', '#16A34A', '#15803D', '#14532D',
];

Color parseHexColor(String hex, [Color fallback = const Color(0xFF111111)]) {
  final String cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) {
    final int? val = int.tryParse('FF$cleaned', radix: 16);
    if (val != null) return Color(val);
  } else if (cleaned.length == 8) {
    final int? val = int.tryParse(cleaned, radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}

String colorToHex(Color c) {
  final int r = (c.r * 255.0).round() & 0xff;
  final int g = (c.g * 255.0).round() & 0xff;
  final int b = (c.b * 255.0).round() & 0xff;
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

String toGujaratiDigits(String input) {
  const List<String> map = ['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
  return input.replaceAllMapped(RegExp(r'[0-9]'), (m) => map[int.parse(m.group(0)!)]);
}

class CanvasObject {
  String id;
  String key;
  String type; // 'text' | 'static' | 'photo' | 'image' | 'shape'
  String shapeKind; // 'rect' | 'square' | 'roundrect' | 'ellipse' | 'oval' | 'triangle' | 'diamond' | 'polygon' | 'star' | 'banner' | 'arrow' | 'line'
  String src;
  String customText;
  String prefix;
  String suffix;
  double x;
  double y;
  double w;
  double h;
  String font;
  double size;
  double lineH;
  double charS;
  double opacity; // 5..100
  String color;
  String bgColor;
  bool bgTrans;
  bool bold;
  bool italic;
  bool underline;
  bool gujDigits;
  String align; // 'left' | 'center' | 'right' | 'justify'
  String fit; // 'cover' | 'contain' | 'fill'
  double borderW;
  String borderC;
  bool borderNone;
  double radius;
  double rotate;
  bool locked;

  // CorelDRAW PowerClip fields
  String clipMode; // 'none' | 'image' | 'photo'
  String clipSrc;
  String clipKey;
  double clipScale; // 20..300
  double clipX;
  double clipY;
  String clipFit; // 'cover' | 'contain' | 'fill'

  CanvasObject({
    required this.id,
    this.key = 'Field',
    this.type = 'text',
    this.shapeKind = 'rect',
    this.src = '',
    this.customText = '',
    this.prefix = '',
    this.suffix = '',
    this.x = 60,
    this.y = 80,
    this.w = 260,
    this.h = 34,
    this.font = 'Noto Sans Gujarati',
    this.size = 16,
    this.lineH = 1.25,
    this.charS = 0,
    this.opacity = 100,
    this.color = '#111111',
    this.bgColor = '#DBEAFE',
    this.bgTrans = true,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.gujDigits = false,
    this.align = 'left',
    this.fit = 'contain',
    this.borderW = 0,
    this.borderC = '#1E3A8A',
    this.borderNone = false,
    this.radius = 8,
    this.rotate = 0,
    this.locked = false,
    this.clipMode = 'none',
    this.clipSrc = '',
    this.clipKey = '',
    this.clipScale = 100,
    this.clipX = 0,
    this.clipY = 0,
    this.clipFit = 'cover',
  });

  CanvasObject clone({String? newId, double dx = 0, double dy = 0}) {
    return CanvasObject(
      id: newId ?? id,
      key: key,
      type: type,
      shapeKind: shapeKind,
      src: src,
      customText: customText,
      prefix: prefix,
      suffix: suffix,
      x: x + dx,
      y: y + dy,
      w: w,
      h: h,
      font: font,
      size: size,
      lineH: lineH,
      charS: charS,
      opacity: opacity,
      color: color,
      bgColor: bgColor,
      bgTrans: bgTrans,
      bold: bold,
      italic: italic,
      underline: underline,
      gujDigits: gujDigits,
      align: align,
      fit: fit,
      borderW: borderW,
      borderC: borderC,
      borderNone: borderNone,
      radius: radius,
      rotate: rotate,
      locked: false,
      clipMode: clipMode,
      clipSrc: clipSrc,
      clipKey: clipKey,
      clipScale: clipScale,
      clipX: clipX,
      clipY: clipY,
      clipFit: clipFit,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'type': type,
        'shapeKind': shapeKind,
        'src': src,
        'customText': customText,
        'prefix': prefix,
        'suffix': suffix,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'font': font,
        'size': size,
        'lineH': lineH,
        'charS': charS,
        'opacity': opacity,
        'color': color,
        'bgColor': bgColor,
        'bgTrans': bgTrans,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'gujDigits': gujDigits,
        'align': align,
        'fit': fit,
        'borderW': borderW,
        'borderC': borderC,
        'borderNone': borderNone,
        'radius': radius,
        'rotate': rotate,
        'locked': locked,
        'clipMode': clipMode,
        'clipSrc': clipSrc,
        'clipKey': clipKey,
        'clipScale': clipScale,
        'clipX': clipX,
        'clipY': clipY,
        'clipFit': clipFit,
      };

  factory CanvasObject.fromJson(Map<String, dynamic> j) {
    return CanvasObject(
      id: (j['id'] ?? '').toString(),
      key: (j['key'] ?? 'Field').toString(),
      type: (j['type'] ?? 'text').toString(),
      shapeKind: (j['shapeKind'] ?? 'rect').toString(),
      src: (j['src'] ?? '').toString(),
      customText: (j['customText'] ?? '').toString(),
      prefix: (j['prefix'] ?? '').toString(),
      suffix: (j['suffix'] ?? '').toString(),
      x: (j['x'] as num?)?.toDouble() ?? 60,
      y: (j['y'] as num?)?.toDouble() ?? 80,
      w: (j['w'] as num?)?.toDouble() ?? 260,
      h: (j['h'] as num?)?.toDouble() ?? 34,
      font: (j['font'] ?? 'Noto Sans Gujarati').toString(),
      size: (j['size'] as num?)?.toDouble() ?? 16,
      lineH: (j['lineH'] as num?)?.toDouble() ?? 1.25,
      charS: (j['charS'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 100,
      color: (j['color'] ?? '#111111').toString(),
      bgColor: (j['bgColor'] ?? '#DBEAFE').toString(),
      bgTrans: j['bgTrans'] as bool? ?? true,
      bold: j['bold'] as bool? ?? false,
      italic: j['italic'] as bool? ?? false,
      underline: j['underline'] as bool? ?? false,
      gujDigits: j['gujDigits'] as bool? ?? false,
      align: (j['align'] ?? 'left').toString(),
      fit: (j['fit'] ?? 'contain').toString(),
      borderW: (j['borderW'] as num?)?.toDouble() ?? 0,
      borderC: (j['borderC'] ?? '#1E3A8A').toString(),
      borderNone: j['borderNone'] as bool? ?? false,
      radius: (j['radius'] as num?)?.toDouble() ?? 8,
      rotate: (j['rotate'] as num?)?.toDouble() ?? 0,
      locked: j['locked'] as bool? ?? false,
      clipMode: (j['clipMode'] ?? 'none').toString(),
      clipSrc: (j['clipSrc'] ?? '').toString(),
      clipKey: (j['clipKey'] ?? '').toString(),
      clipScale: (j['clipScale'] as num?)?.toDouble() ?? 100,
      clipX: (j['clipX'] as num?)?.toDouble() ?? 0,
      clipY: (j['clipY'] as num?)?.toDouble() ?? 0,
      clipFit: (j['clipFit'] ?? 'cover').toString(),
    );
  }
}

class TemplatePage {
  String id;
  String name;
  String theme; // 'blue' | 'gold' | 'emerald' | 'minimal' | 'white' | 'cert'
  int pageNo;
  int totalThemePages;
  Uint8List? customBgBytes;
  List<CanvasObject> objects;

  TemplatePage({
    required this.id,
    required this.name,
    this.theme = 'blue',
    this.pageNo = 1,
    this.totalThemePages = 1,
    this.customBgBytes,
    List<CanvasObject>? objects,
  }) : objects = objects ?? [];

  TemplatePage clone() {
    return TemplatePage(
      id: id,
      name: name,
      theme: theme,
      pageNo: pageNo,
      totalThemePages: totalThemePages,
      customBgBytes: customBgBytes,
      objects: objects.map((o) => o.clone()).toList(),
    );
  }
}

// ============================================================================
// 3. VECTOR SHAPE GEOMETRY & POWERCLIP PAINTER / CLIPPER
// ============================================================================
class CorelShapeGeometry {
  static Map<String, double> defaultDimensions(String shapeKind) {
    switch (shapeKind) {
      case 'rect': return {'w': 260, 'h': 130, 'r': 0};
      case 'square': return {'w': 160, 'h': 160, 'r': 0};
      case 'roundrect': return {'w': 260, 'h': 130, 'r': 28};
      case 'ellipse': return {'w': 160, 'h': 160, 'r': 0};
      case 'oval': return {'w': 240, 'h': 135, 'r': 0};
      case 'triangle': return {'w': 160, 'h': 150, 'r': 0};
      case 'diamond': return {'w': 160, 'h': 160, 'r': 0};
      case 'polygon': return {'w': 160, 'h': 160, 'r': 0};
      case 'star': return {'w': 160, 'h': 160, 'r': 0};
      case 'banner': return {'w': 320, 'h': 64, 'r': 0};
      case 'arrow': return {'w': 200, 'h': 70, 'r': 0};
      case 'line': return {'w': 500, 'h': 8, 'r': 0};
      default: return {'w': 240, 'h': 130, 'r': 0};
    }
  }

  static Path buildShapePath(String shapeKind, Size size, double strokePad, double radius) {
    final double w = size.width;
    final double h = size.height;
    final double pad = strokePad;
    final Path path = Path();

    if (shapeKind == 'ellipse' || shapeKind == 'oval') {
      path.addOval(Rect.fromLTWH(
        pad,
        pad,
        math.max(2, w - pad * 2),
        math.max(2, h - pad * 2),
      ));
      return path;
    }
    if (shapeKind == 'triangle') {
      path.moveTo(w / 2, pad);
      path.lineTo(w - pad, h - pad);
      path.lineTo(pad, h - pad);
      path.close();
      return path;
    }
    if (shapeKind == 'diamond') {
      path.moveTo(w / 2, pad);
      path.lineTo(w - pad, h / 2);
      path.lineTo(w / 2, h - pad);
      path.lineTo(pad, h / 2);
      path.close();
      return path;
    }
    if (shapeKind == 'arrow') {
      path.moveTo(w * 0.02, h * 0.33);
      path.lineTo(w * 0.62, h * 0.33);
      path.lineTo(w * 0.62, h * 0.08);
      path.lineTo(w * 0.98, h * 0.50);
      path.lineTo(w * 0.62, h * 0.92);
      path.lineTo(w * 0.62, h * 0.67);
      path.lineTo(w * 0.02, h * 0.67);
      path.close();
      return path;
    }
    if (shapeKind == 'star') {
      const List<List<double>> rawPts = [
        [50, 4], [63, 36], [98, 38], [70, 60], [80, 95],
        [50, 75], [20, 95], [30, 60], [2, 38], [37, 36]
      ];
      for (int i = 0; i < rawPts.length; i++) {
        final double px = rawPts[i][0] * w / 100.0;
        final double py = rawPts[i][1] * h / 100.0;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      return path;
    }
    if (shapeKind == 'polygon') {
      const List<List<double>> rawPts = [
        [50, 3], [95, 26], [95, 74], [50, 97], [5, 74], [5, 26]
      ];
      for (int i = 0; i < rawPts.length; i++) {
        final double px = rawPts[i][0] * w / 100.0;
        final double py = rawPts[i][1] * h / 100.0;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      return path;
    }
    if (shapeKind == 'banner') {
      const List<List<double>> rawPts = [
        [0, 0], [200, 0], [186, 25], [200, 50], [0, 50], [14, 25]
      ];
      for (int i = 0; i < rawPts.length; i++) {
        final double px = rawPts[i][0] * w / 200.0;
        final double py = rawPts[i][1] * h / 50.0;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      return path;
    }

    final double rx = shapeKind == 'roundrect' ? math.max(22, radius) : radius;
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, math.max(2, w - pad * 2), math.max(2, h - pad * 2)),
        Radius.circular(rx),
      ),
    );
    return path;
  }
}

class CorelShapeClipper extends CustomClipper<Path> {
  final String shapeKind;
  final double strokePad;
  final double radius;

  const CorelShapeClipper({
    required this.shapeKind,
    required this.strokePad,
    required this.radius,
  });

  @override
  Path getClip(Size size) {
    return CorelShapeGeometry.buildShapePath(shapeKind, size, strokePad, radius);
  }

  @override
  bool shouldReclip(covariant CorelShapeClipper oldClipper) {
    return oldClipper.shapeKind != shapeKind ||
        oldClipper.strokePad != strokePad ||
        oldClipper.radius != radius;
  }
}

class CorelShapePainter extends CustomPainter {
  final CanvasObject obj;
  final bool fillOnly;
  final bool strokeOnly;

  const CorelShapePainter({
    required this.obj,
    this.fillOnly = false,
    this.strokeOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bool hasBorder = !obj.borderNone && obj.borderW > 0;
    final double sw = hasBorder ? obj.borderW : 0;

    if (obj.shapeKind == 'line') {
      if (!hasBorder || fillOnly) return;
      final Paint linePaint = Paint()
        ..color = parseHexColor(obj.borderC, const Color(0xFF1E40AF))
        ..strokeWidth = math.max(1.0, sw)
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        linePaint,
      );
      return;
    }

    final Path path = CorelShapeGeometry.buildShapePath(
      obj.shapeKind,
      size,
      sw / 2,
      obj.radius,
    );

    if (!strokeOnly && !obj.bgTrans) {
      final Paint fillPaint = Paint()
        ..color = parseHexColor(obj.bgColor, const Color(0xFFDBEAFE))
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    if (!fillOnly && hasBorder) {
      final Paint strokePaint = Paint()
        ..color = parseHexColor(obj.borderC, const Color(0xFF1E40AF))
        ..strokeWidth = sw
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CorelShapePainter oldDelegate) => true;
}

class TemplateBackgroundPainter extends CustomPainter {
  final String theme;
  final int pageNum;
  final int totalPages;
  final bool showGrid;
  final bool showGuides;

  const TemplateBackgroundPainter({
    required this.theme,
    required this.pageNum,
    required this.totalPages,
    this.showGrid = false,
    this.showGuides = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Map<String, Color>> palettes = {
      'blue': {
        'bg': const Color(0xFFFFFFFF),
        'outer': const Color(0xFF1E3A8A),
        'inner': const Color(0xFF3B82F6),
        'headBg': const Color(0xFFEFF6FF),
      },
      'gold': {
        'bg': const Color(0xFFFFFDF9),
        'outer': const Color(0xFF991B1B),
        'inner': const Color(0xFFD97706),
        'headBg': const Color(0xFFFEF3C7),
      },
      'emerald': {
        'bg': const Color(0xFFFFFFFF),
        'outer': const Color(0xFF065F46),
        'inner': const Color(0xFF10B981),
        'headBg': const Color(0xFFECFDF5),
      },
      'minimal': {
        'bg': const Color(0xFFFFFFFF),
        'outer': const Color(0xFF1E293B),
        'inner': const Color(0xFF64748B),
        'headBg': const Color(0xFFF8FAFC),
      },
      'cert': {
        'bg': const Color(0xFFFFFDF9),
        'outer': const Color(0xFFB45309),
        'inner': const Color(0xFFD97706),
        'headBg': const Color(0xFFFFFBEB),
      },
    };

    if (theme == 'white') {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white,
      );
    } else {
      final pal = palettes[theme] ?? palettes['blue']!;
      canvas.drawRect(Offset.zero & size, Paint()..color = pal['bg']!);

      // Outer border frame
      final RRect outerRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 24, 746, 1075),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        outerRect,
        Paint()
          ..color = pal['outer']!
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke,
      );

      // Inner frame
      final RRect innerRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(32, 32, 730, 1059),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        innerRect,
        Paint()
          ..color = pal['inner']!
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );

      if (theme != 'cert') {
        // Top header band
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(34, 34, 726, 92),
            const Radius.circular(4),
          ),
          Paint()..color = pal['headBg']!,
        );
        canvas.drawLine(
          const Offset(34, 126),
          const Offset(760, 126),
          Paint()
            ..color = pal['outer']!
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawLine(
          const Offset(58, 210),
          const Offset(736, 210),
          Paint()
            ..color = const Color(0xFFF59E0B)
            ..strokeWidth = 2,
        );
      }
    }

    // Optional Grid Overlay
    if (showGrid) {
      final Paint gridPaint = Paint()
        ..color = const Color(0x243B82F6)
        ..strokeWidth = 1;
      const double step = 18.897; // 5mm in 794px A4
      for (double x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Optional Center & Margin Guides
    if (showGuides) {
      final Paint guidePaint = Paint()
        ..color = const Color(0x6606B6D4)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), guidePaint);
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), guidePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TemplateBackgroundPainter oldDelegate) => true;
}

// ============================================================================
// 4. MAIN CORELDRAW STUDIO SCREEN STATE
// ============================================================================
class CorelDrawPrintMergeStudioScreen extends StatefulWidget {
  const CorelDrawPrintMergeStudioScreen({super.key});

  @override
  State<CorelDrawPrintMergeStudioScreen> createState() =>
      _CorelDrawPrintMergeStudioScreenState();
}

class _CorelDrawPrintMergeStudioScreenState
    extends State<CorelDrawPrintMergeStudioScreen> {
  // Active View ('setup' | 'design' | 'output')
  String _activeView = 'design';

  // Data State
  List<String> _headers = [];
  List<Map<String, String>> _rows = [];
  final Map<String, String> _photos = {}; // filename -> avatar label / color code
  final List<String> _systemFonts = [];
  List<TemplatePage> _pages = [];
  int _pageIdx = 0;
  int _recIdx = 0;

  // Selection & Artboard State
  String? _selId;
  List<String> _selIds = [];
  String? _inlineEditingId;
  String? _powerClipSourceId;
  bool _lockCornerRatio = true;
  bool _noPhotoMode = false;
  bool _wideArtboard = false;
  bool _showGrid = true;
  bool _showGuides = true;
  bool _snapGrid = false;
  bool _includeColLabel = true;
  double _zoom = 0.72;
  Offset _cursorMm = Offset.zero;

  // Marquee Selection State
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  // Undo / Redo History
  final List<String> _historyStack = [];
  final List<String> _redoStack = [];

  // Output / Imposition State
  String _nupMode = '1x1';
  double _nupGapMm = 0;
  bool _cropMarks = true;
  bool _padOddPages = false;
  int _fromRec = 1;
  int _toRec = 6;

  // Auto-Builder Wizard State
  String _wizTitle = 'શ્રી સરસ્વતી વિદ્યા મંદિર — વિદ્યાર્થી પ્રોફાઇલ રિપોર્ટ';
  String _wizSubtitle = 'Student Comprehensive Profile & Evaluation Sheet (2026–27)';
  int _wizPages = 4;
  int _wizColsPerRow = 3;
  String _wizPhotoOpt = 'none';
  String _wizTheme = 'blue';
  bool _wizLockBg = true;

  // Search Filters
  String _tableSearch = '';
  String _colSearch = '';

  // Top Default Text Style
  String _topFont = 'Noto Sans Gujarati';
  double _topSize = 18;
  String _topColor = '#111111';

  final GlobalKey _artboardRepaintKey = GlobalKey();
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _generate210ColumnStudentDataset();
    _buildAutoMultiPageTemplate(notifyUser: false);
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      math.Random().nextInt(9999).toRadixString(36);

  TemplatePage? get _curPage =>
      (_pageIdx >= 0 && _pageIdx < _pages.length) ? _pages[_pageIdx] : null;

  CanvasObject? get _primaryObj {
    final p = _curPage;
    if (p == null || _selId == null) return null;
    for (final o in p.objects) {
      if (o.id == _selId) return o;
    }
    return null;
  }

  List<CanvasObject> get _selectedObjs {
    final p = _curPage;
    if (p == null) return [];
    final Set<String> ids = {..._selIds};
    if (_selId != null) ids.add(_selId!);
    return p.objects.where((o) => ids.contains(o.id)).toList();
  }

  bool _isSelected(String id) => _selId == id || _selIds.contains(id);

  void _setSingleSelection(String? id) {
    _selId = id;
    _selIds = id != null ? [id] : [];
  }

  void _toggleShiftSelection(String id) {
    final Set<String> cur = {..._selIds};
    if (_selId != null) cur.add(_selId!);
    if (cur.contains(id)) {
      cur.remove(id);
      _selIds = cur.toList();
      _selId = _selIds.isNotEmpty ? _selIds.last : null;
    } else {
      cur.add(id);
      _selIds = cur.toList();
      _selId = id;
    }
  }

  void _selectAllOnPage() {
    final p = _curPage;
    if (p == null || p.objects.isEmpty) return;
    final unlocked = p.objects
        .where((o) => !o.locked && !(o.type == 'photo' && _noPhotoMode))
        .toList();
    final targets = unlocked.isNotEmpty ? unlocked : p.objects;
    setState(() {
      _selIds = targets.map((o) => o.id).toList();
      _selId = _selIds.isNotEmpty ? _selIds.last : null;
      _inlineEditingId = null;
    });
    _notify('☑ Selected all ${_selIds.length} object(s) on Page ${_pageIdx + 1} (Ctrl+A)');
  }

  void _notify(String msg, [bool isErr = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isErr ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        duration: const Duration(milliseconds: 2200),
        behavior: SnackBarBehavior.floating,
        width: 460,
      ),
    );
  }

  void _saveHistory() {
    final snap = jsonEncode({
      'page': _pageIdx,
      'sel': _selId,
      'pages': _pages
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'theme': p.theme,
                'pageNo': p.pageNo,
                'totalThemePages': p.totalThemePages,
                'objects': p.objects.map((o) => o.toJson()).toList(),
              })
          .toList(),
    });
    if (_historyStack.isNotEmpty && _historyStack.last == snap) return;
    _historyStack.add(snap);
    if (_historyStack.length > 30) _historyStack.removeAt(0);
    _redoStack.clear();
  }

  void _restoreSnapshot(String snap) {
    final Map<String, dynamic> data = jsonDecode(snap);
    final List<dynamic> rawPages = data['pages'] as List<dynamic>;
    _pages = rawPages.map((rp) {
      final m = rp as Map<String, dynamic>;
      return TemplatePage(
        id: m['id'] as String,
        name: m['name'] as String,
        theme: (m['theme'] ?? 'blue').toString(),
        pageNo: (m['pageNo'] as num?)?.toInt() ?? 1,
        totalThemePages: (m['totalThemePages'] as num?)?.toInt() ?? 1,
        objects: (m['objects'] as List<dynamic>)
            .map((o) => CanvasObject.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
    }).toList();
    _pageIdx = ((data['page'] as num?)?.toInt() ?? 0)
        .clamp(0, math.max(0, _pages.length - 1));
    _setSingleSelection(data['sel'] as String?);
  }

  void _undo() {
    if (_historyStack.isEmpty) {
      _notify('Nothing to undo');
      return;
    }
    final currentSnap = jsonEncode({
      'page': _pageIdx,
      'sel': _selId,
      'pages': _pages
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'theme': p.theme,
                'pageNo': p.pageNo,
                'totalThemePages': p.totalThemePages,
                'objects': p.objects.map((o) => o.toJson()).toList(),
              })
          .toList(),
    });
    _redoStack.add(currentSnap);
    setState(() {
      _restoreSnapshot(_historyStack.removeLast());
    });
    _notify('Undid last change');
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      _notify('Nothing to redo');
      return;
    }
    _saveHistory();
    setState(() {
      _restoreSnapshot(_redoStack.removeLast());
    });
    _notify('Redid change');
  }

  double _snapVal(double px) {
    if (!_snapGrid) return px;
    const double step = (A4Spec.w / A4Spec.mmw) * 2.0; // 2mm snap
    return (px / step).round() * step;
  }

  // --------------------------------------------------------------------------
  // DATASET & AUTO-TEMPLATE GENERATORS (210-COL STUDENT DEMO & GUJARATI DEMO)
  // --------------------------------------------------------------------------
  void _generate210ColumnStudentDataset() {
    final List<String> baseHeaders = [
      'Roll_No (રોલ નં)',
      'Student_Name (વિદ્યાર્થીનું નામ)',
      'GR_No (જી.આર. નં)',
      'Standard_Div (ધોરણ-વર્ગ)',
      'Medium (માધ્યમ)',
      'Birth_Date (જન્મ તારીખ)',
      'Blood_Group (બ્લડ ગ્રુપ)',
      'Father_Name (પિતાનું નામ)',
      'Mother_Name (માતાનું નામ)',
      'Mobile_No (મોબાઇલ નંબર)',
      'City_Village (ગામ / શહેર)',
      'Taluka (તાલુકો)',
      'District (જિલ્લો)',
      'Pin_Code (પીન કોડ)',
      'Aadhaar_Last4 (આધાર)',
      'House_Team (હાઉસ ટીમ)',
      'Attendance_Days (હાજર દિવસ)',
      'Overall_Grade (કુલ ગ્રેડ)',
      'Percentage (ટકાવારી %)',
      'Class_Rank (વર્ગ ક્રમાંક)'
    ];

    const List<String> subjects = [
      'Gujarati (ગુજરાતી)', 'Mathematics (ગણિત)', 'Science (વિજ્ઞાન)',
      'Social_Sci (સા.વિજ્ઞાન)', 'English (અંગ્રેજી)', 'Sanskrit (સંસ્કૃત)',
      'Hindi (હિન્દી)', 'Computer (કોમ્પ્યુટર)', 'Drawing (ચિત્રકામ)', 'PT_Yoga (યોગ)'
    ];
    const List<String> examMetrics = [
      'FA1_20', 'FA2_20', 'SA1_80', 'Term1_100', 'FA3_20',
      'FA4_20', 'SA2_80', 'Term2_100', 'Project_20', 'Practical_20',
      'Oral_10', 'Assignment_10', 'Attendance_Pt', 'Final_Total', 'Sub_Grade'
    ];

    final List<String> headers = [...baseHeaders];
    for (int sIdx = 0; sIdx < subjects.length; sIdx++) {
      final String subShort = subjects[sIdx].split(' ')[0];
      for (final m in examMetrics) {
        headers.add('S${sIdx + 1}_${subShort}_$m');
      }
    }
    for (int k = 1; k <= 40; k++) {
      headers.add('Skill_Eval_$k (કૌશલ્ય_$k)');
    }

    const List<List<String>> sampleStudents = [
      ['૧૦૧', 'આરવકુમાર રાજેશભાઈ પટેલ (Aarav Patel)', 'GR-2026-01', '10-A', 'ગુજરાતી', '14/05/2011', 'B+', 'રાજેશભાઈ પટેલ', 'ભાવનાબેન પટેલ', '9825011223', 'અમદાવાદ (બોપલ)', 'દસ્ક્રોઈ', 'અમદાવાદ', '380058', '4512', 'સરદાર હાઉસ', '218 / 225', 'A1', '94.6%', '1st'],
      ['૧૦૨', 'દિયાબેન કિરણભાઈ શાહ (Diya Shah)', 'GR-2026-02', '10-A', 'ગુજરાતી', '22/08/2011', 'O+', 'કિરણભાઈ શાહ', 'પૂજાબેન શાહ', '9879122334', 'સુરત (અડાજણ)', 'ચોર્યાસી', 'સુરત', '395009', '8834', 'ટાગોર હાઉસ', '221 / 225', 'A1', '93.2%', '2nd'],
      ['૧૦૩', 'હર્ષિલ મહેશભાઈ દેસાઈ (Harshil Desai)', 'GR-2026-03', '10-A', 'ગુજરાતી', '03/11/2011', 'A+', 'મહેશભાઈ દેસાઈ', 'કવિતાબેન દેસાઈ', '9909233445', 'વડોદરા (અલકાપુરી)', 'વડોદરા', 'વડોદરા', '390007', '6190', 'ગાંધી હાઉસ', '210 / 225', 'A2', '89.4%', '3rd'],
      ['૧૦૪', 'ક્રિષ્નાબેન નિલેશભાઈ જોશી (Krishna Joshi)', 'GR-2026-04', '10-B', 'ગુજરાતી', '19/01/2011', 'AB+', 'નિલેશભાઈ જોશી', 'મીનાબેન જોશી', '9824344556', 'રાજકોટ (કાલાવડ રોડ)', 'રાજકોટ', 'રાજકોટ', '360005', '3309', 'નેહરુ હાઉસ', '215 / 225', 'A2', '88.1%', '4th'],
      ['૧૦૫', 'પ્રાંશુ પંકજભાઈ ત્રિવેદી (Pranshu Trivedi)', 'GR-2026-05', '10-B', 'ગુજરાતી', '28/03/2011', 'B+', 'પંકજભાઈ ત્રિવેદી', 'સોનલબેન ત્રિવેદી', '9426455667', 'ગાંધીનગર (સેક્ટર-૧૧)', 'ગાંધીનગર', 'ગાંધીનગર', '382011', '7721', 'સરદાર હાઉસ', '219 / 225', 'A1', '91.5%', '5th'],
      ['૧૦૬', 'માનસીબેન ભરતભાઈ પરમાર (Mansi Parmar)', 'GR-2026-06', '10-B', 'ગુજરાતી', '09/07/2011', 'O+', 'ભરતભાઈ પરમાર', 'ગીતાબેન પરમાર', '9898566778', 'ભાવનગર (વાઘાવાડી)', 'ભાવનગર', 'ભાવનગર', '364002', '5120', 'ટાગોર હાઉસ', '214 / 225', 'B1', '85.0%', '6th'],
    ];

    const List<String> skillRatings = [
      'ઉત્તમ (Excellent)',
      'ઘણું સારું (Very Good)',
      'સારું (Good)',
      'A+ Grade'
    ];

    final List<Map<String, String>> rows = [];
    for (int sIdx = 0; sIdx < sampleStudents.length; sIdx++) {
      final List<String> vals = [...sampleStudents[sIdx]];
      for (int sub = 0; sub < 10; sub++) {
        final int f1 = 18 - ((sIdx + sub) % 3);
        final int f2 = 19 - ((sIdx + sub) % 2);
        final int sa1 = 72 - ((sIdx * 2 + sub) % 9);
        final int t1 = f1 + sa1;
        final int f3 = 18 - (sub % 3);
        final int f4 = 19 - (sIdx % 2);
        final int sa2 = 74 - ((sIdx + sub * 2) % 8);
        final int t2 = f3 + sa2;
        vals.addAll([
          '$f1', '$f2', '$sa1', '$t1',
          '$f3', '$f4', '$sa2', '$t2',
          '19/20', '18/20', '9/10', '10/10', '5/5',
          '${((t1 + t2) / 2).round()}/100',
          ((t1 + t2) / 2 >= 90 ? 'A1' : 'A2'),
        ]);
      }
      for (int k = 1; k <= 40; k++) {
        vals.add(skillRatings[(sIdx + k) % skillRatings.length]);
      }
      final Map<String, String> rowMap = {};
      for (int i = 0; i < headers.length; i++) {
        rowMap[headers[i]] = i < vals.length ? vals[i] : '';
      }
      rows.add(rowMap);
    }

    _headers = headers;
    _rows = rows;
    _recIdx = 0;
    _fromRec = 1;
    _toRec = _rows.length;
  }

  void _buildAutoMultiPageTemplate({bool notifyUser = true}) {
    if (_headers.isEmpty) {
      _generate210ColumnStudentDataset();
    }
    _saveHistory();
    final int numPages = _wizPages.clamp(1, A4Spec.maxPages);
    final int colsPerRow = _wizColsPerRow.clamp(1, 3);
    final bool includePhoto = _wizPhotoOpt == 'right';
    _noPhotoMode = !includePhoto;

    final List<String> dataCols = _headers.where((h) {
      if (!includePhoto && RegExp(r'photo|image|ફોટો', caseSensitive: false).hasMatch(h)) {
        return false;
      }
      return true;
    }).toList();

    final int perPage = (dataCols.length / numPages).ceil();
    final List<TemplatePage> builtPages = [];

    for (int pIdx = 0; pIdx < numPages; pIdx++) {
      final List<CanvasObject> objs = [
        CanvasObject(
          id: _uid(),
          type: 'static',
          customText: _wizTitle,
          x: 48,
          y: 44,
          w: 698,
          h: 36,
          font: 'Hind Vadodara',
          size: 22,
          bold: true,
          align: 'center',
          color: '#1E3A8A',
          locked: _wizLockBg,
        ),
        CanvasObject(
          id: _uid(),
          type: 'static',
          customText: '$_wizSubtitle — પૃષ્ઠ (Page) ${pIdx + 1} / $numPages',
          x: 48,
          y: 84,
          w: 698,
          h: 28,
          font: 'Noto Sans Gujarati',
          size: 13.5,
          bold: true,
          align: 'center',
          color: '#475569',
          locked: _wizLockBg,
        ),
      ];

      final String rollHeader = _headers.first;
      final String nameHeader = _headers.firstWhere(
        (h) => RegExp(r'name|નામ', caseSensitive: false).hasMatch(h),
        orElse: () => _headers.length > 1 ? _headers[1] : _headers.first,
      );

      objs.add(CanvasObject(
        id: _uid(),
        type: 'shape',
        shapeKind: 'roundrect',
        x: 44,
        y: 136,
        w: 706,
        h: 38,
        bgColor: '#DBEAFE',
        bgTrans: false,
        borderW: 1.5,
        borderC: '#3B82F6',
        radius: 14,
        locked: _wizLockBg,
      ));
      objs.add(CanvasObject(
        id: _uid(),
        type: 'text',
        key: rollHeader,
        prefix: '$rollHeader: ',
        x: 56,
        y: 143,
        w: 180,
        h: 26,
        font: 'Noto Sans Gujarati',
        size: 13.5,
        bold: true,
        color: '#0F172A',
      ));
      objs.add(CanvasObject(
        id: _uid(),
        type: 'text',
        key: nameHeader,
        prefix: '$nameHeader: ',
        x: 245,
        y: 143,
        w: 490,
        h: 26,
        font: 'Noto Sans Gujarati',
        size: 14.5,
        bold: true,
        color: '#991B1B',
      ));

      const double startY = 186;
      if (pIdx == 0 && includePhoto) {
        objs.add(CanvasObject(
          id: _uid(),
          type: 'photo',
          key: 'Photo',
          x: 618,
          y: 186,
          w: 128,
          h: 155,
          borderW: 2,
          borderC: '#1E3A8A',
          radius: 6,
          fit: 'cover',
        ));
      }

      final int startCol = pIdx * perPage;
      final int endCol = math.min(dataCols.length, (pIdx + 1) * perPage);
      final List<String> slice =
          startCol < dataCols.length ? dataCols.sublist(startCol, endCol) : [];
      final int totalRowsNeeded = (slice.length / colsPerRow).ceil();
      const double availHeight = 860;
      final double rowH = (availHeight / math.max(1, totalRowsNeeded)).clamp(20.0, 34.0);
      final double fontSize = rowH <= 23 ? 11.0 : (rowH <= 27 ? 12.5 : 14.0);

      for (int idx = 0; idx < slice.length; idx++) {
        final String colKey = slice[idx];
        final int r = idx ~/ colsPerRow;
        final int c = idx % colsPerRow;
        final double yPos = startY + r * rowH;
        final double rightLimit =
            (pIdx == 0 && includePhoto && yPos < 350) ? 560.0 : 706.0;
        final double colW = ((rightLimit - (colsPerRow - 1) * 10) / colsPerRow).floorToDouble();
        final double xPos = 44.0 + c * (colW + 10);

        objs.add(CanvasObject(
          id: _uid(),
          type: 'text',
          key: colKey,
          prefix: '$colKey: ',
          x: xPos,
          y: yPos,
          w: colW,
          h: rowH - 2,
          font: 'Noto Sans Gujarati',
          size: fontSize,
          color: '#1E293B',
          borderW: 1,
          borderC: '#CBD5E1',
          bgColor: r.isEven ? '#FFFFFF' : '#F8FAFC',
          bgTrans: false,
          radius: 4,
        ));
      }

      builtPages.add(TemplatePage(
        id: _uid(),
        name: 'Profile Page ${pIdx + 1}',
        theme: _wizTheme,
        pageNo: pIdx + 1,
        totalThemePages: numPages,
        objects: objs,
      ));
    }

    setState(() {
      _pages = builtPages;
      _pageIdx = 0;
      _setSingleSelection(null);
      _activeView = 'design';
    });
    if (notifyUser) {
      _notify('✨ Generated $numPages-Page Student Profile Template with ${dataCols.length} columns!');
    }
  }

  void _loadGujaratiSammanDemo() {
    _saveHistory();
    _noPhotoMode = false;
    _photos.clear();
    _photos['patel.jpg'] = 'RP|#1D4ED8';
    _photos['sharma.jpg'] = 'KS|#047857';
    _photos['shah.jpg'] = 'MS|#7C3AED';
    _photos['desai.jpg'] = 'ND|#B45309';
    _photos['joshi.jpg'] = 'PJ|#BE123C';

    _headers = ['ક્રમ', 'Photo', 'નામ (Full Name)', 'ગામ (City)', 'મોબાઇલ (Mobile)', 'હોદ્દો (Role)'];
    final List<List<String>> raw = [
      ['1', 'patel.jpg', 'રાજેશભાઈ કરશનભાઈ પટેલ', 'અમદાવાદ (નવરંગપુરા)', '9825011223', 'પ્રમુખશ્રી - સમાજ કલ્યાણ ટ્રસ્ટ'],
      ['2', 'sharma.jpg', 'કિરણબેન મહેશભાઈ શર્મા', 'સુરત (અડાજણ)', '9879122334', 'ઉપપ્રમુખશ્રી - મહિલા સમિતિ'],
      ['3', 'shah.jpg', 'મિતુલભાઈ જયંતિલાલ શાહ', 'વડોદરા (અલકાપુરી)', '9909233445', 'મંત્રીશ્રી - યુવા વિભાગ'],
      ['4', 'desai.jpg', 'નિલેશભાઈ રમણલાલ દેસાઈ', 'રાજકોટ (કાલાવડ રોડ)', '9824344556', 'ખજાનચીશ્રી - કારોબારી સમિતિ'],
      ['5', 'joshi.jpg', 'પંકજભાઈ હરિપ્રસાદ જોશી', 'ગાંધીનગર (સેક્ટર-૧૧)', '9426455667', 'સભ્યશ્રી - શિક્ષણ સમિતિ'],
    ];
    _rows = raw.map((r) {
      return {for (int i = 0; i < _headers.length; i++) _headers[i]: r[i]};
    }).toList();

    _pages = [
      TemplatePage(
        id: _uid(),
        name: 'Gujarati Samman Patra A4',
        theme: 'cert',
        pageNo: 1,
        totalThemePages: 1,
        objects: [
          CanvasObject(
            id: _uid(),
            type: 'static',
            customText: '॥ શ્રી ગણેશાય નમઃ ॥',
            x: 220, y: 62, w: 354, h: 36,
            font: 'Noto Sans Gujarati', size: 22, bold: true, align: 'center', color: '#991B1B', locked: true,
          ),
          CanvasObject(
            id: _uid(),
            type: 'static',
            customText: 'ગુજરાત પરિવાર સ્નેહમિલન તથા સન્માન સમારોહ',
            x: 75, y: 112, w: 644, h: 48,
            font: 'Hind Vadodara', size: 26, bold: true, align: 'center', color: '#1E3A8A', locked: true,
          ),
          CanvasObject(
            id: _uid(),
            type: 'shape',
            shapeKind: 'banner',
            customText: 'આમંત્રણ પત્રિકા / ઓળખ પત્ર (Print Merge Card)',
            x: 150, y: 162, w: 494, h: 40,
            font: 'Noto Sans Gujarati', size: 16, bold: true, color: '#92400E',
            bgColor: '#FEF3C7', bgTrans: false, borderW: 1.5, borderC: '#D97706', locked: true,
          ),
          CanvasObject(
            id: _uid(),
            key: 'Photo',
            type: 'photo',
            x: 545, y: 245, w: 155, h: 190,
            borderW: 3, borderC: '#B45309', radius: 10, fit: 'cover',
          ),
          CanvasObject(
            id: _uid(),
            key: 'ક્રમ',
            type: 'text',
            prefix: 'નોંધણી ક્રમાંક: ',
            gujDigits: true,
            x: 80, y: 245, w: 260, h: 36,
            font: 'Noto Sans Gujarati', size: 18, bold: true, color: '#334155',
          ),
          CanvasObject(
            id: _uid(),
            key: 'નામ (Full Name)',
            type: 'text',
            prefix: 'શ્રી ',
            suffix: ' સ.જોડે',
            x: 80, y: 300, w: 440, h: 44,
            font: 'Noto Sans Gujarati', size: 22, bold: true, color: '#991B1B',
          ),
          CanvasObject(
            id: _uid(),
            key: 'હોદ્દો (Role)',
            type: 'text',
            prefix: 'હોદ્દો: ',
            x: 80, y: 358, w: 440, h: 38,
            font: 'Hind Vadodara', size: 18, bold: true, color: '#1E40AF',
          ),
          CanvasObject(
            id: _uid(),
            key: 'ગામ (City)',
            type: 'text',
            prefix: 'મુ. ગામ / શહેર: ',
            x: 80, y: 410, w: 440, h: 36,
            font: 'Noto Sans Gujarati', size: 18, color: '#1E293B',
          ),
          CanvasObject(
            id: _uid(),
            key: 'મોબાઇલ (Mobile)',
            type: 'text',
            prefix: 'મોબાઇલ નંબર: +૯૧ ',
            gujDigits: true,
            x: 80, y: 460, w: 440, h: 36,
            font: 'Noto Sans Gujarati', size: 18, color: '#047857', bold: true,
          ),
        ],
      ),
    ];

    setState(() {
      _pageIdx = 0;
      _recIdx = 0;
      _fromRec = 1;
      _toRec = _rows.length;
      _setSingleSelection(null);
      _activeView = 'design';
    });
    _notify('✨ Loaded Gujarati Samman Patra Print Merge Demo!');
  }

  // --------------------------------------------------------------------------
  // ARTBOARD OBJECT CREATION, ALIGNMENT, POWERCLIP & EDITING METHODS
  // --------------------------------------------------------------------------
  void _addMergeColumnField(String colKey) {
    final p = _curPage;
    if (p == null) return;
    _saveHistory();
    final bool isPhoto = RegExp(r'photo|image|ફોટો', caseSensitive: false).hasMatch(colKey) && !_noPhotoMode;
    final o = CanvasObject(
      id: _uid(),
      key: colKey,
      type: isPhoto ? 'photo' : 'text',
      prefix: (_includeColLabel && !isPhoto) ? '$colKey: ' : '',
      x: 55,
      y: math.min(1040, 85.0 + (p.objects.length % 22) * 38.0),
      w: isPhoto ? 130 : 320,
      h: isPhoto ? 160 : 30,
      font: _topFont,
      size: _topSize,
      color: _topColor,
      fit: isPhoto ? 'cover' : 'contain',
      borderW: isPhoto ? 2 : 0,
      borderC: '#1E293B',
      radius: isPhoto ? 8 : 0,
    );
    setState(() {
      p.objects.add(o);
      _setSingleSelection(o.id);
    });
    _notify('Inserted «$colKey» on Page ${_pageIdx + 1}');
  }

  void _addVectorShape(String shapeKind) {
    final p = _curPage;
    if (p == null) return;
    _saveHistory();
    final bool isLine = shapeKind == 'line';
    final dim = CorelShapeGeometry.defaultDimensions(shapeKind);
    final o = CanvasObject(
      id: _uid(),
      type: 'shape',
      shapeKind: shapeKind,
      x: isLine ? 120 : 240,
      y: 220,
      w: dim['w']!,
      h: dim['h']!,
      radius: dim['r']!,
      font: _topFont,
      size: _topSize,
      color: _topColor,
      bgColor: shapeKind == 'star'
          ? '#FEF08A'
          : (shapeKind == 'roundrect' ? '#DBEAFE' : '#E0E7FF'),
      bgTrans: isLine,
      borderW: isLine ? 3.0 : 2.5,
      borderC: '#1E40AF',
    );
    setState(() {
      p.objects.add(o);
      _setSingleSelection(o.id);
      _activeView = 'design';
    });
    _notify('Added ${kShapeDisplayNames[shapeKind] ?? shapeKind} — double-click to type inside or PowerClip!');
  }

  void _addStaticTextAt(Offset posPx) {
    final p = _curPage;
    if (p == null) return;
    _saveHistory();
    final o = CanvasObject(
      id: _uid(),
      type: 'static',
      customText: 'નવું લખાણ (Double-click to edit)',
      x: posPx.dx.clamp(20.0, A4Spec.w - 260.0),
      y: posPx.dy.clamp(20.0, A4Spec.h - 50.0),
      w: 280,
      h: math.max(38, (_topSize * 1.6).roundToDouble()),
      font: _topFont,
      size: _topSize,
      bold: true,
      color: _topColor,
    );
    setState(() {
      p.objects.add(o);
      _setSingleSelection(o.id);
      _inlineEditingId = o.id;
    });
  }

  void _alignSelected(String mode) {
    final targets = _selectedObjs.where((x) => !x.locked).toList();
    if (targets.isEmpty) {
      _notify('Select an unlocked object on the artboard first', true);
      return;
    }
    _saveHistory();
    const double margin = 28.0;
    final CanvasObject anchor =
        (_primaryObj != null && !_primaryObj!.locked) ? _primaryObj! : targets.last;
    final p = _curPage;
    final bool isPartialMulti = targets.length > 1 &&
        p != null &&
        targets.length < p.objects.where((x) => !x.locked).length &&
        mode != 'P';

    setState(() {
      if (isPartialMulti) {
        for (final o in targets) {
          if (o.id == anchor.id) continue;
          if (mode == 'L') o.x = anchor.x;
          if (mode == 'R') o.x = anchor.x + anchor.w - o.w;
          if (mode == 'T') o.y = anchor.y;
          if (mode == 'B') o.y = anchor.y + anchor.h - o.h;
          if (mode == 'C') o.x = anchor.x + (anchor.w - o.w) / 2;
          if (mode == 'E') o.y = anchor.y + (anchor.h - o.h) / 2;
        }
      } else {
        for (final o in targets) {
          if (mode == 'L') o.x = margin;
          if (mode == 'R') o.x = A4Spec.w - margin - o.w;
          if (mode == 'T') o.y = margin;
          if (mode == 'B') o.y = A4Spec.h - margin - o.h;
          if (mode == 'C') o.x = (A4Spec.w - o.w) / 2;
          if (mode == 'E') o.y = (A4Spec.h - o.h) / 2;
          if (mode == 'P') {
            o.x = (A4Spec.w - o.w) / 2;
            o.y = (A4Spec.h - o.h) / 2;
          }
        }
      }
    });
  }

  void _deleteSelected() {
    final p = _curPage;
    final targets = _selectedObjs;
    if (p == null || targets.isEmpty) return;
    final unlocked = targets.where((o) => !o.locked).toList();
    if (unlocked.isEmpty) {
      _notify('Selected object(s) are locked — press Ctrl+L to unlock first', true);
      return;
    }
    _saveHistory();
    final Set<String> delIds = unlocked.map((o) => o.id).toSet();
    setState(() {
      p.objects.removeWhere((x) => delIds.contains(x.id));
      _setSingleSelection(null);
    });
    _notify('Deleted ${delIds.length} selected object(s)');
  }

  void _duplicateSelected() {
    final p = _curPage;
    final targets = _selectedObjs;
    if (p == null || targets.isEmpty) return;
    _saveHistory();
    final List<String> newIds = [];
    setState(() {
      for (final o in targets) {
        final copy = o.clone(newId: _uid(), dx: 14, dy: 14);
        p.objects.add(copy);
        newIds.add(copy.id);
      }
      _selIds = newIds;
      _selId = newIds.isNotEmpty ? newIds.last : null;
    });
    _notify('Duplicated ${newIds.length} object(s) (Ctrl+D)');
  }

  void _toggleLockSelected() {
    final targets = _selectedObjs;
    if (targets.isEmpty) return;
    final bool nextLock = !(_primaryObj?.locked ?? false);
    setState(() {
      for (final o in targets) {
        o.locked = nextLock;
      }
    });
    _notify(nextLock
        ? '🔒 Locked ${targets.length} object(s)'
        : '🔓 Unlocked ${targets.length} object(s)');
  }

  // CorelDRAW PowerClip: Place Image/Photo Object Inside Target Shape
  void _placeObjectIntoShapePowerClip(CanvasObject srcObj, CanvasObject targetShape) {
    final p = _curPage;
    if (p == null || targetShape.type != 'shape') return;
    _saveHistory();
    setState(() {
      if (srcObj.type == 'image') {
        targetShape.clipMode = 'image';
        targetShape.clipSrc = srcObj.src;
        targetShape.clipKey = srcObj.key;
      } else {
        targetShape.clipMode = 'photo';
        targetShape.clipKey = srcObj.key;
        targetShape.clipSrc = '';
      }
      targetShape.clipScale = 100;
      targetShape.clipX = 0;
      targetShape.clipY = 0;
      targetShape.clipFit = 'cover';
      p.objects.removeWhere((x) => x.id == srcObj.id);
      _powerClipSourceId = null;
      _setSingleSelection(targetShape.id);
    });
    _notify('📎 PowerClipped inside ${kShapeDisplayNames[targetShape.shapeKind] ?? targetShape.shapeKind}!');
  }

  // --------------------------------------------------------------------------
  // BUILD UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Column(
          children: [
            _buildTopHeaderBar(),
            _buildCorelPropertyBar(),
            Expanded(
              child: _activeView == 'setup'
                  ? _buildSetupView()
                  : (_activeView == 'design'
                      ? _buildDesignWorkspaceView()
                      : _buildOutputView()),
            ),
            _buildBottomStatusBar(),
          ],
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_inlineEditingId != null) return;

    final bool ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    if (ctrl && key == LogicalKeyboardKey.keyA) {
      _selectAllOnPage();
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      _undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      _redo();
    } else if (ctrl && key == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
    } else if (ctrl && key == LogicalKeyboardKey.keyL) {
      _toggleLockSelected();
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _deleteSelected();
    } else if (!ctrl && key == LogicalKeyboardKey.keyL) {
      _alignSelected('L');
    } else if (!ctrl && key == LogicalKeyboardKey.keyR) {
      _alignSelected('R');
    } else if (!ctrl && key == LogicalKeyboardKey.keyT) {
      _alignSelected('T');
    } else if (!ctrl && key == LogicalKeyboardKey.keyB) {
      _alignSelected('B');
    } else if (!ctrl && key == LogicalKeyboardKey.keyC) {
      _alignSelected('C');
    } else if (!ctrl && key == LogicalKeyboardKey.keyE) {
      _alignSelected('E');
    } else if (!ctrl && key == LogicalKeyboardKey.keyP) {
      _alignSelected('P');
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final targets = _selectedObjs.where((o) => !o.locked).toList();
      if (targets.isEmpty) return;
      final double step = shift ? 10.0 : 1.0;
      setState(() {
        for (final o in targets) {
          if (key == LogicalKeyboardKey.arrowLeft) o.x = math.max(0, o.x - step);
          if (key == LogicalKeyboardKey.arrowRight) o.x = math.min(A4Spec.w - o.w, o.x + step);
          if (key == LogicalKeyboardKey.arrowUp) o.y = math.max(0, o.y - step);
          if (key == LogicalKeyboardKey.arrowDown) o.y = math.min(A4Spec.h - o.h, o.y + step);
        }
      });
    }
  }

  // --------------------------------------------------------------------------
  // TOP HEADER & CORELDRAW PROPERTY BAR
  // --------------------------------------------------------------------------
  Widget _buildTopHeaderBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF171A20),
        border: Border(bottom: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF2563EB)],
                ),
              ),
              child: const Text(
                'C',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CorelDRAW Print Merge Pro',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                ),
                Text(
                  '200+ Cols · 10 Pages · PowerClip & Corner Ratio',
                  style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(width: 14),
            _buildViewTabButton('setup', '1 Upload'),
            const SizedBox(width: 4),
            _buildViewTabButton('design', '2 Design'),
            const SizedBox(width: 4),
            _buildViewTabButton('output', '3 Output'),
            const SizedBox(width: 16),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _showAutoBuilderWizardDialog,
              icon: const Icon(Icons.bolt, size: 15),
              label: const Text('Auto-Generate 1–10 Page Profile', style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () {
                _generate210ColumnStudentDataset();
                _wizPages = 4;
                _wizColsPerRow = 3;
                _wizPhotoOpt = 'none';
                _buildAutoMultiPageTemplate();
              },
              icon: const Icon(Icons.school, size: 15),
              label: const Text('210-Col Student Demo', style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _loadGujaratiSammanDemo,
              icon: const Icon(Icons.auto_awesome, size: 15),
              label: const Text('ગુજરાતી Demo Data', style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x2E3B82F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x593B82F6)),
              ),
              child: Text(
                '${_rows.length} students · ${_headers.length} cols',
                style: const TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewTabButton(String viewKey, String label) {
    final bool active = _activeView == viewKey;
    return InkWell(
      onTap: () => setState(() => _activeView = viewKey),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0x293B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active ? const Color(0x663B82F6) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? const Color(0xFF60A5FA) : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildCorelPropertyBar() {
    final CanvasObject? o = _primaryObj;
    final bool isBorderNone = o == null || o.borderNone || o.borderW <= 0;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF272C35),
        border: Border(bottom: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _propBarBtn('↩ Undo', _undo),
            const SizedBox(width: 4),
            _propBarBtn('↪ Redo', _redo),
            const SizedBox(width: 4),
            _propBarBtn('☑ Select All (Ctrl+A)', _selectAllOnPage),
            _propDivider(),
            // Corner Ratio Lock Toggle
            Row(
              children: [
                Checkbox(
                  value: _lockCornerRatio,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() => _lockCornerRatio = v ?? true),
                ),
                const Text(
                  '🔒 Corner Ratio',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6EE7B7), fontWeight: FontWeight.w600),
                ),
              ],
            ),
            _propDivider(),
            // Font & Size Controls
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: kBuiltinGujFonts.contains(o?.font ?? _topFont)
                    ? (o?.font ?? _topFont)
                    : kBuiltinGujFonts.first,
                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                dropdownColor: const Color(0xFF272C35),
                items: kBuiltinGujFonts
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _topFont = val;
                    for (final t in _selectedObjs) {
                      t.font = val;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 6),
            _propBarBtn('A-', () {
              setState(() {
                _topSize = math.max(6, (_primaryObj?.size ?? _topSize) - 2);
                for (final t in _selectedObjs) {
                  t.size = _topSize;
                }
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${(o?.size ?? _topSize).round()}px',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            _propBarBtn('A+', () {
              setState(() {
                _topSize = math.min(200, (_primaryObj?.size ?? _topSize) + 2);
                for (final t in _selectedObjs) {
                  t.size = _topSize;
                }
              });
            }),
            const SizedBox(width: 4),
            _propBarBtn('B', () {
              if (_selectedObjs.isEmpty) return;
              final bool next = !(_primaryObj?.bold ?? false);
              setState(() {
                for (final t in _selectedObjs) {
                  t.bold = next;
                }
              });
            }, active: o?.bold ?? false),
            const SizedBox(width: 4),
            _propBarBtn('🚫 No Fill', () {
              final targets = _selectedObjs.where((x) => !x.locked).toList();
              if (targets.isEmpty) return;
              final bool next = !(o?.bgTrans ?? false);
              setState(() {
                for (final t in targets) {
                  t.bgTrans = next;
                }
              });
            }, active: o?.bgTrans ?? false),
            const SizedBox(width: 4),
            _propBarBtn('🚫 Border None', () {
              final targets = _selectedObjs.where((x) => !x.locked).toList();
              if (targets.isEmpty) return;
              _saveHistory();
              final bool nextNone = !isBorderNone;
              setState(() {
                for (final t in targets) {
                  t.borderNone = nextNone;
                  t.borderW = nextNone ? 0 : 2.5;
                }
              });
            }, active: isBorderNone),
            const SizedBox(width: 6),
            // Opacity Quick Stepper
            const Text('Opacity:', style: TextStyle(fontSize: 10.5, color: Color(0xFFFBBF24))),
            const SizedBox(width: 4),
            SizedBox(
              width: 90,
              child: Slider(
                value: (o?.opacity ?? 100.0).clamp(5.0, 100.0),
                min: 5,
                max: 100,
                onChanged: (val) {
                  setState(() {
                    for (final t in _selectedObjs) {
                      t.opacity = val.roundToDouble();
                    }
                  });
                },
              ),
            ),
            Text('${(o?.opacity ?? 100).round()}%', style: const TextStyle(fontSize: 10.5)),
            _propDivider(),
            // PowerClip Button
            _propBarBtn('📎 PowerClip', () {
              final sel = _selectedObjs;
              CanvasObject? selImg;
              CanvasObject? selShape;
              for (final item in sel) {
                if (item.type == 'image' || item.type == 'photo') selImg = item;
                if (item.type == 'shape') selShape = item;
              }
              if (selImg != null && selShape != null) {
                _placeObjectIntoShapePowerClip(selImg, selShape);
                return;
              }
              if (o != null && o.type == 'shape') {
                _saveHistory();
                setState(() {
                  o.clipMode = 'photo';
                  o.clipKey = 'Photo';
                  _noPhotoMode = false;
                });
                _notify('👤 PowerClipped Student Merge Photo inside ${kShapeDisplayNames[o.shapeKind] ?? o.shapeKind}!');
              } else if (o != null && (o.type == 'image' || o.type == 'photo')) {
                setState(() {
                  _powerClipSourceId = _powerClipSourceId == o.id ? null : o.id;
                });
                _notify('🎯 Click any Shape on the artboard to PowerClip this image inside it!');
              } else {
                _notify('Select a Shape or Image/Photo on the artboard to use CorelDRAW PowerClip!');
              }
            }, active: _powerClipSourceId != null),
            _propDivider(),
            // Alignment Buttons
            _propBarBtn('⬅ L', () => _alignSelected('L')),
            const SizedBox(width: 3),
            _propBarBtn('↔ C', () => _alignSelected('C')),
            const SizedBox(width: 3),
            _propBarBtn('➡ R', () => _alignSelected('R')),
            const SizedBox(width: 3),
            _propBarBtn('⬆ T', () => _alignSelected('T')),
            const SizedBox(width: 3),
            _propBarBtn('↕ E', () => _alignSelected('E')),
            const SizedBox(width: 3),
            _propBarBtn('⬇ B', () => _alignSelected('B')),
            const SizedBox(width: 3),
            _propBarBtn('🎯 P', () => _alignSelected('P')),
            _propDivider(),
            _propBarBtn(o?.locked == true ? '🔓 Unlock' : '🔒 Lock', _toggleLockSelected),
            const SizedBox(width: 4),
            _propBarBtn('⛶ Bigger Artboard', () => setState(() => _wideArtboard = !_wideArtboard), active: _wideArtboard),
            const SizedBox(width: 4),
            _propBarBtn('# Grid', () => setState(() => _showGrid = !_showGrid), active: _showGrid),
            const SizedBox(width: 4),
            _propBarBtn('┼ Guides', () => setState(() => _showGuides = !_showGuides), active: _showGuides),
          ],
        ),
      ),
    );
  }

  Widget _propBarBtn(String label, VoidCallback onTap, {bool active = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3B82F6) : const Color(0xFF2F3541),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFF60A5FA) : const Color(0xFF4C566A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFFF1F5F9),
          ),
        ),
      ),
    );
  }

  Widget _propDivider() {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFF3D4554),
    );
  }

  // --------------------------------------------------------------------------
  // VIEW 1: UPLOAD & 200+ COLUMN DATA TABLE SETUP
  // --------------------------------------------------------------------------
  Widget _buildSetupView() {
    final List<String> visibleHeaders = _headers.take(30).toList();
    final List<MapEntry<int, Map<String, String>>> filteredRows = _rows
        .asMap()
        .entries
        .where((e) =>
            _tableSearch.isEmpty ||
            e.value.values.any((v) => v.toLowerCase().contains(_tableSearch.toLowerCase())))
        .toList();

    return Row(
      children: [
        // Left Setup Sidebar
        Container(
          width: 270,
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: Color(0xFF272C35),
            border: Border(right: BorderSide(color: Color(0xFF3D4554))),
          ),
          child: ListView(
            children: [
              _sidebarBox(
                title: '1. Data Source (200+ Cols)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _showImportCsvDialog,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Paste / Import CSV or TSV'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                if (_headers.isEmpty) {
                                  _headers = ['Roll_No', 'Student_Name', 'Standard', 'City'];
                                }
                                _rows.add({
                                  for (int i = 0; i < _headers.length; i++)
                                    _headers[i]: i == 0 ? '${_rows.length + 1}' : ''
                                });
                              });
                              _notify('Added new student row');
                            },
                            child: const Text('+ Row', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final colName = 'Field_${_headers.length + 1}';
                              setState(() {
                                _headers.add(colName);
                                for (final r in _rows) {
                                  r[colName] = '';
                                }
                              });
                              _notify('Added column $colName');
                            },
                            child: const Text('+ Col', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _sidebarBox(
                title: '2. Templates (Up to 10 Pages)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Select Artboard Background Theme or add blank A4 pages:',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['blue', 'gold', 'emerald', 'minimal', 'white'].map((th) {
                        return ActionChip(
                          label: Text(th.toUpperCase(), style: const TextStyle(fontSize: 10.5)),
                          onPressed: () {
                            if (_curPage != null) {
                              setState(() {
                                _curPage!.theme = th;
                                _activeView = 'design';
                              });
                              _notify('Applied $th template theme on current page!');
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (_pages.length >= A4Spec.maxPages) {
                          _notify('Maximum ${A4Spec.maxPages} pages reached', true);
                          return;
                        }
                        _saveHistory();
                        setState(() {
                          _pages.add(TemplatePage(
                            id: _uid(),
                            name: 'Page ${_pages.length + 1}',
                            theme: 'blue',
                            pageNo: _pages.length + 1,
                            totalThemePages: _pages.length + 1,
                          ));
                          _pageIdx = _pages.length - 1;
                          _activeView = 'design';
                        });
                      },
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('+ Add Blank A4 Design Page'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Right Data Table Area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '${_rows.length} students × ${_headers.length} columns',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF93C5FD)),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: '🔍 Search student name / roll no...',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _tableSearch = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181C23),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFF3D4554)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 36,
                          dataRowMinHeight: 32,
                          dataRowMaxHeight: 36,
                          columns: [
                            const DataColumn(label: Text('#')),
                            for (final h in visibleHeaders)
                              DataColumn(
                                label: Text(
                                  h,
                                  style: const TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                          rows: filteredRows.map((entry) {
                            final int idx = entry.key;
                            final Map<String, String> row = entry.value;
                            return DataRow(
                              cells: [
                                DataCell(Text('${idx + 1}')),
                                for (final h in visibleHeaders)
                                  DataCell(
                                    Text(row[h] ?? ''),
                                    onTap: () => _editCellDialog(idx, h, row[h] ?? ''),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _editCellDialog(int rowIdx, String colKey, String currentVal) {
    final ctrl = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Row #${rowIdx + 1} — $colKey', style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() => _rows[rowIdx][colKey] = ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showImportCsvDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import CSV / TSV Student Records'),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste CSV or Excel TSV rows (Row 1 = Headers)...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final lines = const LineSplitter().convert(ctrl.text.trim());
              if (lines.length >= 2) {
                final sep = lines.first.contains('\t') ? '\t' : ',';
                final headers = lines.first.split(sep).map((s) => s.trim()).toList();
                final rows = <Map<String, String>>[];
                for (int i = 1; i < lines.length; i++) {
                  final cols = lines[i].split(sep);
                  rows.add({
                    for (int c = 0; c < headers.length; c++)
                      headers[c]: c < cols.length ? cols[c].trim() : ''
                  });
                }
                setState(() {
                  _headers = headers;
                  _rows = rows;
                  _recIdx = 0;
                  _toRec = rows.length;
                });
                _notify('Loaded ${rows.length} records × ${headers.length} columns');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Import Data'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // VIEW 2: CORELDRAW / ILLUSTRATOR DESIGN WORKSPACE
  // --------------------------------------------------------------------------
  Widget _buildDesignWorkspaceView() {
    return Row(
      children: [
        // 1. Left Vector Toolbox
        _buildLeftVectorToolbox(),
        // 2. Left Docker (Merge Columns & Vector Shapes Gallery)
        if (!_wideArtboard) _buildLeftDocker(),
        // 3. Center Canvas Stage with Rulers & Interactive Artboard
        Expanded(child: _buildCenterCanvasStage()),
        // 4. Right Docker (Student Navigator, Object Inspector, PowerClip & Layer Docker)
        if (!_wideArtboard) _buildRightInspectorDocker(),
        // 5. Classic Right-Edge CorelDRAW Vertical Color Strip
        _buildRightCorelColorStrip(),
      ],
    );
  }

  Widget _buildLeftVectorToolbox() {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1F26),
        border: Border(right: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _toolBtn('↖', 'Pick Tool', () {
              setState(() {
                _powerClipSourceId = null;
                _inlineEditingId = null;
              });
            }, active: _powerClipSourceId == null),
            _toolBtn('અ', 'Double-Click on Artboard to Add Text (F8)', () {
              _notify('💡 Double-click anywhere on the artboard to insert new text!');
            }),
            const Divider(color: Color(0xFF3D4554), indent: 8, endIndent: 8),
            _toolBtn('▭', 'Rectangle (F6)', () => _addVectorShape('rect')),
            _toolBtn('▢', 'Rounded Rectangle', () => _addVectorShape('roundrect')),
            _toolBtn('◯', 'Circle / Ellipse (F7)', () => _addVectorShape('ellipse')),
            _toolBtn('△', 'Triangle', () => _addVectorShape('triangle')),
            _toolBtn('◇', 'Diamond', () => _addVectorShape('diamond')),
            _toolBtn('╱', 'Divider Line', () => _addVectorShape('line')),
            _toolBtn('➔', 'Arrow Shape', () => _addVectorShape('arrow')),
            _toolBtn('★', 'Star Medallion', () => _addVectorShape('star')),
            _toolBtn('⬡', 'Hexagon Crest (Y)', () => _addVectorShape('polygon')),
            _toolBtn('⚑', 'Ribbon Banner', () => _addVectorShape('banner')),
            const Divider(color: Color(0xFF3D4554), indent: 8, endIndent: 8),
            _toolBtn('🔒', 'Lock / Unlock (Ctrl+L)', _toggleLockSelected),
            _toolBtn('⧉', 'Duplicate (Ctrl+D)', _duplicateSelected),
            _toolBtn('⊕', 'Center to Page (P)', () => _alignSelected('P')),
            _toolBtn('🗑', 'Delete (Del)', _deleteSelected),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(String iconText, String tooltip, VoidCallback onTap, {bool active = false}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 32,
          margin: const EdgeInsets.only(bottom: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0x383B82F6) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? const Color(0xFF3B82F6) : Colors.transparent,
            ),
          ),
          child: Text(
            iconText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: active ? const Color(0xFF60A5FA) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftDocker() {
    final List<String> filteredCols = _headers
        .where((h) => _colSearch.isEmpty || h.toLowerCase().contains(_colSearch.toLowerCase()))
        .toList();

    return Container(
      width: 245,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFF272C35),
        border: Border(right: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: ListView(
        children: [
          _sidebarBox(
            title: 'Merge Columns (${_headers.length})',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '🔍 Filter 200+ columns...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 11),
                  onChanged: (v) => setState(() => _colSearch = v),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _includeColLabel,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => _includeColLabel = v ?? true),
                    ),
                    const Expanded(
                      child: Text(
                        'Include "Column: " prefix',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF93C5FD)),
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: const Color(0xFF171A20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3D4554)),
                  ),
                  child: ListView.builder(
                    itemCount: filteredCols.length,
                    itemBuilder: (ctx, i) {
                      final colKey = filteredCols[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF262C36))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_headers.indexOf(colKey) + 1}. $colKey',
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () => _addMergeColumnField(colKey),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2F3541),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF4C566A)),
                                ),
                                child: const Text('+ Add', style: TextStyle(fontSize: 10)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          _sidebarBox(
            title: 'Corel / Illustrator Shapes',
            child: Column(
              children: [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  childAspectRatio: 1.35,
                  children: kShapeDisplayNames.entries.map((e) {
                    return InkWell(
                      onTap: () => _addVectorShape(e.key),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171A20),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFF3D4554)),
                        ),
                        child: Text(
                          e.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF93C5FD)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _addStaticTextAt(const Offset(180, 120)),
                        child: const Text('+ Text', style: TextStyle(fontSize: 10.5)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _addVectorShape('rect'),
                        child: const Text('+ Frame', style: TextStyle(fontSize: 10.5)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CENTER CANVAS STAGE WITH RULERS, MARQUEE, DOUBLE-CLICK & 8-HANDLE GRIPS
  // --------------------------------------------------------------------------
  Widget _buildCenterCanvasStage() {
    final TemplatePage? p = _curPage;

    return Container(
      padding: const EdgeInsets.all(6),
      color: const Color(0xFF1E2229),
      child: Column(
        children: [
          // Page Thumbnails Strip & Page Controls
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pages.length,
                    itemBuilder: (ctx, i) {
                      final bool active = i == _pageIdx;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _pageIdx = i;
                          _setSingleSelection(null);
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? const Color(0xFF2563EB) : const Color(0xFF272C35),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: active ? const Color(0xFF60A5FA) : const Color(0xFF475569),
                            ),
                          ),
                          child: Text(
                            'Page ${i + 1}/${_pages.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Text(
                '💡 Double-click blank area to add text · Double-click text/shape to edit!',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF93C5FD)),
              ),
              const SizedBox(width: 8),
              _propBarBtn('+ Page', () {
                if (_pages.length >= A4Spec.maxPages) return;
                _saveHistory();
                setState(() {
                  _pages.add(TemplatePage(
                    id: _uid(),
                    name: 'Page ${_pages.length + 1}',
                    theme: 'blue',
                    pageNo: _pages.length + 1,
                    totalThemePages: _pages.length + 1,
                  ));
                  _pageIdx = _pages.length - 1;
                });
              }),
            ],
          ),
          const SizedBox(height: 6),
          // Artboard Stage
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF3B4252),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3D4554)),
              ),
              child: p == null
                  ? const Center(child: Text('No page active'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Center(
                          child: SizedBox(
                            width: A4Spec.w * _zoom,
                            height: A4Spec.h * _zoom,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: RepaintBoundary(
                                key: _artboardRepaintKey,
                                child: _buildArtboardA4Surface(p),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtboardA4Surface(TemplatePage p) {
    final Map<String, String> curRecord =
        (_recIdx >= 0 && _recIdx < _rows.length) ? _rows[_recIdx] : {};

    return MouseRegion(
      onHover: (ev) {
        setState(() {
          _cursorMm = Offset(
            (ev.localPosition.dx / A4Spec.w * A4Spec.mmw).clamp(0.0, A4Spec.mmw),
            (ev.localPosition.dy / A4Spec.h * A4Spec.mmh).clamp(0.0, A4Spec.mmh),
          );
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Single tap on empty canvas ONLY deselects (never spawns text on single click!)
        onTap: () {
          setState(() {
            _powerClipSourceId = null;
            _setSingleSelection(null);
            _inlineEditingId = null;
          });
        },
        // Strictly Double-Tap on empty canvas to insert new text at that exact coordinate!
        onDoubleTapDown: (details) {
          _addStaticTextAt(details.localPosition);
        },
        // Rubber-band Marquee Selection on empty canvas drag
        onPanStart: (details) {
          setState(() {
            _marqueeStart = details.localPosition;
            _marqueeCurrent = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _marqueeCurrent = details.localPosition;
          });
        },
        onPanEnd: (_) {
          if (_marqueeStart != null && _marqueeCurrent != null) {
            final Rect rect = Rect.fromPoints(_marqueeStart!, _marqueeCurrent!);
            if (rect.width > 6 || rect.height > 6) {
              final hits = p.objects.where((o) {
                if (o.locked) return false;
                final objRect = Rect.fromLTWH(o.x, o.y, o.w, o.h);
                return rect.overlaps(objRect);
              }).toList();
              if (hits.isNotEmpty) {
                setState(() {
                  _selIds = hits.map((o) => o.id).toList();
                  _selId = _selIds.last;
                });
                _notify('Selected ${hits.length} object(s)');
              }
            }
          }
          setState(() {
            _marqueeStart = null;
            _marqueeCurrent = null;
          });
        },
        child: SizedBox(
          width: A4Spec.w,
          height: A4Spec.h,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 1. Template Background Layer (Visible directly on Artboard!)
              Positioned.fill(
                child: CustomPaint(
                  painter: TemplateBackgroundPainter(
                    theme: p.theme,
                    pageNo: p.pageNo,
                    totalPages: p.totalThemePages,
                    showGrid: _showGrid,
                    showGuides: _showGuides,
                  ),
                ),
              ),
              // 2. Artboard Objects Layer
              for (final o in p.objects)
                if (!(o.type == 'photo' && _noPhotoMode))
                  _buildInteractiveCanvasObject(o, curRecord),
              // 3. Rubber-band Marquee Selection Box
              if (_marqueeStart != null && _marqueeCurrent != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(_marqueeStart!, _marqueeCurrent!),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0x243B82F6),
                        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveCanvasObject(CanvasObject o, Map<String, String> curRecord) {
    final bool selected = _isSelected(o.id);
    final bool isMultiSecondary = selected && _selIds.length > 1 && _selId != o.id;
    final bool isEditing = _inlineEditingId == o.id;

    return Positioned(
      left: o.x,
      top: o.y,
      width: o.w,
      height: o.h,
      child: Transform.rotate(
        angle: o.rotate * math.pi / 180.0,
        child: Opacity(
          opacity: (o.opacity / 100.0).clamp(0.05, 1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Object Body
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final bool shift = HardwareKeyboard.instance.isShiftPressed;
                    if (_powerClipSourceId != null &&
                        o.type == 'shape' &&
                        o.id != _powerClipSourceId) {
                      final srcObj = _curPage?.objects
                          .where((x) => x.id == _powerClipSourceId)
                          .firstOrNull;
                      if (srcObj != null) {
                        _placeObjectIntoShapePowerClip(srcObj, o);
                        return;
                      }
                    }
                    setState(() {
                      if (shift) {
                        _toggleShiftSelection(o.id);
                      } else {
                        _setSingleSelection(o.id);
                      }
                      _inlineEditingId = null;
                    });
                  },
                  onDoubleTap: () {
                    setState(() {
                      o.locked = false;
                      _setSingleSelection(o.id);
                      _inlineEditingId = o.id;
                    });
                  },
                  onPanStart: (_) {
                    if (o.locked || isEditing) return;
                    if (!_isSelected(o.id)) {
                      setState(() => _setSingleSelection(o.id));
                    }
                    _saveHistory();
                  },
                  onPanUpdate: (details) {
                    if (o.locked || isEditing) return;
                    final targets = _selectedObjs.where((t) => !t.locked).toList();
                    setState(() {
                      for (final t in targets) {
                        t.x = _snapVal((t.x + details.delta.dx).clamp(0.0, A4Spec.w - 10));
                        t.y = _snapVal((t.y + details.delta.dy).clamp(0.0, A4Spec.h - 10));
                      }
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: selected
                          ? Border.all(
                              color: isEditing
                                  ? const Color(0xFF10B981)
                                  : (isMultiSecondary
                                      ? const Color(0xFF0EA5E9)
                                      : const Color(0xFFF59E0B)),
                              width: 2,
                            )
                          : (o.type != 'shape'
                              ? Border.all(color: const Color(0x552563EB), width: 0.8)
                              : null),
                    ),
                    child: isEditing
                        ? _buildInlineEditorField(o, curRecord)
                        : _buildObjectVisualContent(o, curRecord),
                  ),
                ),
              ),
              // Lock Badge
              if (o.locked)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xE6EF4444),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('🔒', style: TextStyle(fontSize: 9)),
                  ),
                ),
              // CorelDRAW 8-Handle Selection Grips (4 Corner Proportional Grips + 4 Side Stretch Grips)
              if (selected && !o.locked && !isEditing) ...[
                _buildResizeHandle(o, 'nw', Alignment.topLeft),
                _buildResizeHandle(o, 'n', Alignment.topCenter),
                _buildResizeHandle(o, 'ne', Alignment.topRight),
                _buildResizeHandle(o, 'e', Alignment.centerRight),
                _buildResizeHandle(o, 'se', Alignment.bottomRight),
                _buildResizeHandle(o, 's', Alignment.bottomCenter),
                _buildResizeHandle(o, 'sw', Alignment.bottomLeft),
                _buildResizeHandle(o, 'w', Alignment.centerLeft),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizeHandle(CanvasObject o, String dir, Alignment alignment) {
    final bool isCorner = dir == 'nw' || dir == 'ne' || dir == 'se' || dir == 'sw';
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _saveHistory(),
        onPanUpdate: (details) {
          final double dx = details.delta.dx;
          final double dy = details.delta.dy;
          final double ow = math.max(12.0, o.w);
          final double oh = math.max(6.0, o.h);
          final double aspect = ow / math.max(1.0, oh);
          final double anchorRight = o.x + ow;
          final double anchorBottom = o.y + oh;

          setState(() {
            if (isCorner && _lockCornerRatio) {
              // CorelDRAW Proportional Corner Stretch: Opposite corner stays fixed!
              final double rawW = dir.contains('e') ? (ow + dx) : (ow - dx);
              final double rawH = dir.contains('s') ? (oh + dy) : (oh - dy);
              final double sW = rawW / ow;
              final double sH = rawH / oh;
              final double scale = (sW - 1.0).abs() >= (sH - 1.0).abs() ? sW : sH;
              double nw = math.max(16.0, ow * scale);
              double nh = nw / aspect;
              if (nh < 12.0) {
                nh = 12.0;
                nw = nh * aspect;
              }
              o.w = nw;
              o.h = nh;
              if (dir.contains('w')) o.x = anchorRight - o.w;
              if (dir.contains('n')) o.y = anchorBottom - o.h;
            } else {
              if (dir.contains('e')) o.w = math.max(14.0, ow + dx);
              if (dir.contains('s')) o.h = math.max(8.0, oh + dy);
              if (dir.contains('w')) {
                final double nw = math.max(14.0, ow - dx);
                o.x = anchorRight - nw;
                o.w = nw;
              }
              if (dir.contains('n')) {
                final double nh = math.max(8.0, oh - dy);
                o.y = anchorBottom - nh;
                o.h = nh;
              }
            }
          });
        },
        child: Container(
          width: isCorner ? 11 : 8,
          height: isCorner ? 11 : 8,
          decoration: BoxDecoration(
            color: isCorner ? const Color(0xFFF59E0B) : const Color(0xFF111111),
            border: Border.all(
              color: isCorner ? const Color(0xFF111111) : const Color(0xFFF59E0B),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(isCorner ? 2 : 1),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditorField(CanvasObject o, Map<String, String> curRecord) {
    final String initialText = (o.type == 'static' || o.type == 'shape')
        ? o.customText
        : (curRecord[o.key] ?? '');
    final ctrl = TextEditingController(text: initialText);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(
          fontSize: o.size,
          fontWeight: o.bold ? FontWeight.bold : FontWeight.normal,
          color: parseHexColor(o.color),
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (val) {
          if (o.type == 'static' || o.type == 'shape') {
            o.customText = val;
          } else if (_recIdx >= 0 && _recIdx < _rows.length) {
            _rows[_recIdx][o.key] = val;
          }
        },
        onSubmitted: (_) => setState(() => _inlineEditingId = null),
      ),
    );
  }

  Widget _buildObjectVisualContent(CanvasObject o, Map<String, String> curRecord) {
    if (o.type == 'shape') {
      final bool hasBorder = !o.borderNone && o.borderW > 0;
      final double sw = hasBorder ? o.borderW : 0;
      final bool hasPowerClip = o.clipMode != 'none';
      final String caption = _formatObjectText(o, '');

      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: CorelShapePainter(obj: o, fillOnly: hasPowerClip)),
          if (hasPowerClip)
            ClipPath(
              clipper: CorelShapeClipper(
                shapeKind: o.shapeKind,
                strokePad: sw / 2,
                radius: o.radius,
              ),
              child: Transform.translate(
                offset: Offset(o.clipX, o.clipY),
                child: Transform.scale(
                  scale: (o.clipScale / 100.0).clamp(0.2, 3.0),
                  child: _buildStudentPhotoAvatar(curRecord, o.clipKey),
                ),
              ),
            ),
          if (hasPowerClip)
            CustomPaint(painter: CorelShapePainter(obj: o, strokeOnly: true)),
          if (caption.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: o.size,
                    fontWeight: o.bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: o.italic ? FontStyle.italic : FontStyle.normal,
                    decoration: o.underline ? TextDecoration.underline : TextDecoration.none,
                    color: parseHexColor(o.color),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final bool hasBorder = !o.borderNone && o.borderW > 0;
    final BoxDecoration boxDeco = BoxDecoration(
      color: o.bgTrans ? Colors.transparent : parseHexColor(o.bgColor, Colors.white),
      borderRadius: BorderRadius.circular(o.radius),
      border: hasBorder
          ? Border.all(color: parseHexColor(o.borderC), width: o.borderW)
          : null,
    );

    if (o.type == 'photo' || o.type == 'image') {
      return Container(
        decoration: boxDeco,
        clipBehavior: Clip.antiAlias,
        child: _buildStudentPhotoAvatar(curRecord, o.key),
      );
    }

    final String rawVal = o.type == 'static'
        ? o.customText
        : (curRecord[o.key] ?? '«${o.key}»');
    final String displayTxt = _formatObjectText(o, rawVal);

    TextAlign textAlign = TextAlign.left;
    if (o.align == 'center') textAlign = TextAlign.center;
    if (o.align == 'right') textAlign = TextAlign.right;
    if (o.align == 'justify') textAlign = TextAlign.justify;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: boxDeco,
      child: Text(
        displayTxt,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: o.size,
          height: o.lineH,
          letterSpacing: o.charS,
          fontWeight: o.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: o.italic ? FontStyle.italic : FontStyle.normal,
          decoration: o.underline ? TextDecoration.underline : TextDecoration.none,
          color: parseHexColor(o.color),
        ),
      ),
    );
  }

  Widget _buildStudentPhotoAvatar(Map<String, String> curRecord, String key) {
    final String photoVal = curRecord[key] ?? '';
    final String? spec = _photos[photoVal] ?? _photos[photoVal.toLowerCase()];
    final String nameCol = _headers.firstWhere(
      (h) => RegExp(r'name|નામ', caseSensitive: false).hasMatch(h),
      orElse: () => _headers.isNotEmpty ? _headers.first : 'Student',
    );
    final String stName = curRecord[nameCol] ?? 'Student';
    final String initials = spec != null
        ? spec.split('|').first
        : (stName.trim().isNotEmpty ? stName.trim().characters.first : 'S');
    final Color bg = spec != null && spec.contains('|')
        ? parseHexColor(spec.split('|').last, const Color(0xFF1D4ED8))
        : const Color(0xFF1E3A8A);

    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, color: Colors.white70, size: 42),
          const SizedBox(height: 4),
          Text(
            initials,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatObjectText(CanvasObject o, String rawVal) {
    final String base =
        (o.type == 'static' || o.type == 'shape') ? o.customText : rawVal;
    String txt = '${o.prefix}$base${o.suffix}';
    if (o.gujDigits) txt = toGujaratiDigits(txt);
    return txt;
  }

  // --------------------------------------------------------------------------
  // RIGHT INSPECTOR DOCKER (STUDENT JUMP, OPACITY, BORDER NONE, POWERCLIP, LAYERS)
  // --------------------------------------------------------------------------
  Widget _buildRightInspectorDocker() {
    final CanvasObject? o = _primaryObj;
    final TemplatePage? p = _curPage;

    return Container(
      width: 270,
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFF272C35),
        border: Border(left: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: ListView(
        children: [
          // 1. Student Record Navigator
          _sidebarBox(
            title: 'Student Navigator (${_rows.isNotEmpty ? _recIdx + 1 : 0}/${_rows.length})',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _recIdx = 0),
                      icon: const Icon(Icons.first_page, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _recIdx = math.max(0, _recIdx - 1)),
                      icon: const Icon(Icons.chevron_left, size: 18),
                    ),
                    Text(
                      'Record #${_recIdx + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(
                          () => _recIdx = math.min(_rows.length - 1, _recIdx + 1)),
                      icon: const Icon(Icons.chevron_right, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _recIdx = math.max(0, _rows.length - 1)),
                      icon: const Icon(Icons.last_page, size: 18),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Zoom:', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 0.35,
                        max: 1.35,
                        onChanged: (v) => setState(() => _zoom = v),
                      ),
                    ),
                    Text('${(_zoom * 100).round()}%', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          // 2. Selected Object Properties & PowerClip Inspector
          _sidebarBox(
            title: 'Object Properties (${_selectedObjs.length} Sel)',
            child: o == null
                ? const Text(
                    'Click any object to select, Shift+Click for multi-select, or press Ctrl+A. Drag any corner to scale proportionally!',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Opacity Control
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '🔆 Shape / Object Opacity',
                            style: TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${o.opacity.round()}%',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFFBBF24), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [25, 50, 75, 100].map((preset) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                                onPressed: () {
                                  setState(() {
                                    for (final t in _selectedObjs) {
                                      t.opacity = preset.toDouble();
                                    }
                                  });
                                },
                                child: Text('$preset%', style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 14),
                      // Border Colour & Border None Swatches
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '🎨 Border Colour',
                            style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24), fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              Checkbox(
                                value: o.borderNone || o.borderW <= 0,
                                visualDensity: VisualDensity.compact,
                                onChanged: (val) {
                                  setState(() {
                                    for (final t in _selectedObjs) {
                                      t.borderNone = val ?? false;
                                      t.borderW = (val ?? false) ? 0 : 2.5;
                                    }
                                  });
                                },
                              ),
                              const Text('Border None', style: TextStyle(fontSize: 10.5)),
                            ],
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          '#000000', '#1E3A8A', '#2563EB', '#DC2626',
                          '#991B1B', '#D97706', '#059669', '#7C3AED'
                        ].map((hex) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                for (final t in _selectedObjs) {
                                  t.borderNone = false;
                                  t.borderC = hex;
                                  if (t.borderW <= 0) t.borderW = 2.5;
                                }
                              });
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: parseHexColor(hex),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white54),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 14),
                      // CorelDRAW PowerClip Controls
                      if (o.type == 'shape') ...[
                        const Text(
                          '📎 CorelDRAW PowerClip (આકારમાં ફોટો)',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6EE7B7), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonal(
                                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                onPressed: () {
                                  _saveHistory();
                                  setState(() {
                                    o.clipMode = 'photo';
                                    o.clipKey = 'Photo';
                                    _noPhotoMode = false;
                                  });
                                  _notify('👤 PowerClipped Student Merge Photo inside shape!');
                                },
                                child: const Text('👤 Student Photo Clip', style: TextStyle(fontSize: 10.5)),
                              ),
                            ),
                            if (o.clipMode != 'none') ...[
                              const SizedBox(width: 4),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Remove PowerClip',
                                onPressed: () => setState(() => o.clipMode = 'none'),
                                icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFFCA5A5)),
                              ),
                            ],
                          ],
                        ),
                        if (o.clipMode != 'none') ...[
                          Row(
                            children: [
                              const Text('Zoom:', style: TextStyle(fontSize: 10.5)),
                              Expanded(
                                child: Slider(
                                  value: o.clipScale.clamp(20.0, 300.0),
                                  min: 20,
                                  max: 300,
                                  onChanged: (v) => setState(() => o.clipScale = v),
                                ),
                              ),
                              Text('${o.clipScale.round()}%', style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
          ),

          // 3. Layer & Lock Docker
          _sidebarBox(
            title: 'Objects & Lock Docker (Page ${_pageIdx + 1})',
            child: SizedBox(
              height: 150,
              child: p == null || p.objects.isEmpty
                  ? const Center(child: Text('No objects', style: TextStyle(fontSize: 11)))
                  : ListView.builder(
                      itemCount: p.objects.length,
                      itemBuilder: (ctx, i) {
                        final item = p.objects[p.objects.length - 1 - i];
                        final bool isSel = _isSelected(item.id);
                        final String label = item.type == 'text'
                            ? '«${item.key}»'
                            : (item.type == 'static'
                                ? (item.customText.isEmpty ? 'Static Text' : item.customText)
                                : '${item.type} (${item.shapeKind})');
                        return InkWell(
                          onTap: () => setState(() => _setSingleSelection(item.id)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            color: isSel ? const Color(0x383B82F6) : Colors.transparent,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() => item.locked = !item.locked),
                                  child: Text(item.locked ? '🔒' : '🔓', style: const TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightCorelColorStrip() {
    return Container(
      width: 28,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF14171D),
        border: Border(left: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: ListView.builder(
        itemCount: kCorelPaletteHex.length,
        itemBuilder: (ctx, i) {
          final String cHex = kCorelPaletteHex[i];
          final bool isNone = cHex == 'none';
          return Tooltip(
            message: isNone
                ? 'Tap: No Fill | Long-Press: Border None'
                : '$cHex — Tap: Fill | Long-Press: Border/Text',
            child: GestureDetector(
              onTap: () {
                final targets = _selectedObjs.where((x) => !x.locked).toList();
                if (targets.isEmpty) return;
                _saveHistory();
                setState(() {
                  for (final o in targets) {
                    if (isNone) {
                      o.bgTrans = true;
                    } else {
                      o.bgTrans = false;
                      o.bgColor = cHex;
                    }
                  }
                });
              },
              onLongPress: () {
                final targets = _selectedObjs.where((x) => !x.locked).toList();
                if (targets.isEmpty) return;
                _saveHistory();
                setState(() {
                  for (final o in targets) {
                    if (isNone) {
                      o.borderNone = true;
                      o.borderW = 0;
                    } else {
                      o.borderNone = false;
                      if (o.type == 'shape') {
                        o.borderC = cHex;
                        if (o.borderW <= 0) o.borderW = 2.5;
                      } else {
                        o.color = cHex;
                        o.borderC = cHex;
                      }
                    }
                  }
                });
              },
              child: Container(
                width: 20,
                height: 15,
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isNone ? Colors.white : parseHexColor(cHex),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.white54, width: 0.8),
                ),
                child: isNone
                    ? const Center(
                        child: Text('✕', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // VIEW 3: CORELDRAW N-UP IMPOSITION & PRINT MERGE OUTPUT
  // --------------------------------------------------------------------------
  Widget _buildOutputView() {
    final parts = _nupMode.split('x').map(int.parse).toList();
    final int cols = parts[0], rows = parts[1];
    final int perSheet = cols * rows;
    final int totalItemPages = _rows.length * _pages.length;
    final int totalSheets = (totalItemPages / perSheet).ceil();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'CorelDRAW Print Merge — Multi-Up Imposition & Export',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _metricCard('${_rows.length}', 'Students / Records'),
                  const SizedBox(width: 10),
                  _metricCard('${_pages.length}', 'Pages per Student'),
                  const SizedBox(width: 10),
                  _metricCard('$totalSheets', 'Total A4 Output Sheets'),
                  const SizedBox(width: 10),
                  _metricCard('${_headers.length}', 'Columns Ready'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sidebarBox(
                      title: '1. Student Range & Options',
                      child: Column(
                        children: [
                          SwitchListTile(
                            dense: true,
                            title: const Text('Add blank back page after odd-page profiles (Duplex)'),
                            value: _padOddPages,
                            onChanged: (v) => setState(() => _padOddPages = v),
                          ),
                          SwitchListTile(
                            dense: true,
                            title: const Text('Skip / hide all student photo boxes (No-Photo mode)'),
                            value: _noPhotoMode,
                            onChanged: (v) => setState(() => _noPhotoMode = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _sidebarBox(
                      title: '2. CorelDRAW Multi-Up Sheet Imposition (N-Up)',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _nupMode,
                            decoration: const InputDecoration(
                              labelText: 'Profiles per A4 Sheet Layout',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: '1x1', child: Text('1-Up Full A4 Sheet (1 × 1)')),
                              DropdownMenuItem(value: '1x2', child: Text('2-Up Half A4 Split (1 × 2)')),
                              DropdownMenuItem(value: '2x2', child: Text('4-Up Quarter A4 Cards (2 × 2)')),
                              DropdownMenuItem(value: '2x4', child: Text('8-Up ID Badges (2 × 4)')),
                              DropdownMenuItem(value: '3x4', child: Text('12-Up Exam Desk Slips (3 × 4)')),
                            ],
                            onChanged: (v) => setState(() => _nupMode = v ?? '1x1'),
                          ),
                          SwitchListTile(
                            dense: true,
                            title: const Text('Print CorelDRAW Guillotine Crop Marks'),
                            value: _cropMarks,
                            onChanged: (v) => setState(() => _cropMarks = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String bigVal, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F242D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3D4554)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bigVal,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA)),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  Widget _sidebarBox({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F242D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3D4554)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
              color: Color(0xFF93C5FD),
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF14171D),
        border: Border(top: BorderSide(color: Color(0xFF3D4554))),
      ),
      child: Row(
        children: [
          Text(
            'X: ${_cursorMm.dx.toStringAsFixed(1)} Y: ${_cursorMm.dy.toStringAsFixed(1)} mm',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF60A5FA), fontWeight: FontWeight.w600),
          ),
          _propDivider(),
          const Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                'Ctrl+A Select All   |   Shift+Click Multi-Select   |   Corner Drag = Lock Ratio   |   Double-Click = Add/Edit Text   |   L/R/T/B/C/E/P = Align   |   Ctrl+L = Lock   |   Ctrl+D = Duplicate',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAutoBuilderWizardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text(
            '⚡ Auto-Generate Multi-Page Student Profile Template (1–10 Pages)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: _wizTitle),
                  decoration: const InputDecoration(labelText: 'School / Institute Header Title'),
                  onChanged: (v) => _wizTitle = v,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _wizPages,
                        decoration: const InputDecoration(labelText: 'Pages (1–10)'),
                        items: [for (int p = 1; p <= 10; p++) DropdownMenuItem(value: p, child: Text('$p Pages'))],
                        onChanged: (v) => setModalState(() => _wizPages = v ?? 4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _wizColsPerRow,
                        decoration: const InputDecoration(labelText: 'Columns / Row'),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 Column')),
                          DropdownMenuItem(value: 2, child: Text('2 Columns')),
                          DropdownMenuItem(value: 3, child: Text('3 Columns (200+ Fields)')),
                        ],
                        onChanged: (v) => setModalState(() => _wizColsPerRow = v ?? 3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _buildAutoMultiPageTemplate();
              },
              child: const Text('✨ Generate Multi-Page Template Now'),
            ),
          ],
        ),
      ),
    );
  }
}