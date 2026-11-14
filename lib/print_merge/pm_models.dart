// Print Merge Studio: data model, shape geometry and colour helpers.

import 'dart:math' as math;
import 'dart:ui';

/// A4 artboard in screen pixels (96 dpi) and millimetres.
class PmA4 {
  static const double w = 794.0;
  static const double h = 1123.0;
  static const double mmW = 210.0;
  static const double mmH = 297.0;
  static const int maxPages = 10;
}

/// Fonts the studio can use: (family, name, asset files). The first two are
/// always loaded with the app; the others (SIL Open Font Licence, see
/// assets/fonts/pm/OFL_*.txt) are loaded the first time they are used.
const List<(String, String, List<String>)> kPmFonts = <(String, String, List<String>)>[
  ('NotoSansGujaratiLocal', 'Noto Sans Gujarati', <String>[]),
  ('PmHindVadodara', 'Hind Vadodara', <String>['HindVadodara-Regular.ttf', 'HindVadodara-Bold.ttf']),
  ('PmMuktaVaani', 'Mukta Vaani', <String>['MuktaVaani-Regular.ttf', 'MuktaVaani-Bold.ttf']),
  ('PmBalooBhai2', 'Baloo Bhai 2 (ગોળ)', <String>['BalooBhai2.ttf']),
  ('PmNotoSerifGujarati', 'Noto Serif Gujarati (સેરિફ)', <String>['NotoSerifGujarati.ttf']),
  ('PmRasa', 'Rasa (સેરિફ)', <String>['Rasa.ttf']),
  ('LohitGujaratiLocal', 'Lohit Gujarati', <String>[]),
  ('PmFarsan', 'Farsan (હસ્તલેખ)', <String>['Farsan-Regular.ttf']),
  ('PmShrikhand', 'Shrikhand (શણગાર)', <String>['Shrikhand-Regular.ttf']),
  ('PmKumarOne', 'Kumar One (શણગાર)', <String>['KumarOne-Regular.ttf']),
];

/// Ready-made text styles: (name, size, bold, colour, align, outline width).
const List<(String, double, bool, String, String, double)> kPmTextStyles =
    <(String, double, bool, String, String, double)>[
  ('મુખ્ય શીર્ષક', 30, true, '#1E3A8A', 'center', 0),
  ('શીર્ષક', 22, true, '#0F172A', 'center', 0),
  ('પેટા-શીર્ષક', 17, true, '#475569', 'center', 0),
  ('સામાન્ય લખાણ', 15, false, '#111111', 'left', 0),
  ('નાનું લખાણ', 11.5, false, '#475569', 'left', 0),
  ('વિદ્યાર્થીનું નામ', 26, true, '#991B1B', 'center', 0),
  ('ઝળકતું (કિનારી સાથે)', 28, true, '#FACC15', 'center', 1.6),
];

const Map<String, String> kPmShapeNames = <String, String>{
  'rect': 'લંબચોરસ',
  'square': 'ચોરસ',
  'roundrect': 'ગોળ ખૂણા',
  'ellipse': 'વર્તુળ',
  'oval': 'અંડાકાર',
  'triangle': 'ત્રિકોણ',
  'diamond': 'સમચતુષ્કોણ',
  'polygon': 'ષટ્કોણ',
  'star': 'તારો',
  'banner': 'રિબન',
  'arrow': 'તીર',
  'line': 'રેખા',
};

const Map<String, String> kPmShapeIcons = <String, String>{
  'rect': '▭',
  'square': '□',
  'roundrect': '▢',
  'ellipse': '◯',
  'oval': '⬭',
  'triangle': '△',
  'diamond': '◇',
  'polygon': '⬡',
  'star': '☆',
  'banner': '⚑',
  'arrow': '➔',
  'line': '╱',
};

const List<String> kPmPalette = <String>[
  '#FFFFFF', '#E2E8F0', '#94A3B8', '#475569', '#1E293B', '#000000',
  '#FEF08A', '#FACC15', '#F59E0B', '#D97706', '#B45309',
  '#FED7AA', '#FB923C', '#EA580C', '#DC2626', '#991B1B',
  '#FECDD3', '#F43F5E', '#DB2777', '#831843',
  '#F3E8FF', '#A855F7', '#7E22CE', '#4C1D95',
  '#DBEAFE', '#60A5FA', '#2563EB', '#1E3A8A',
  '#CFFAFE', '#06B6D4', '#0D9488', '#115E59',
  '#DCFCE7', '#4ADE80', '#16A34A', '#14532D',
];

const List<(String, String)> kPmThemes = <(String, String)>[
  ('white', 'સાદું સફેદ'),
  ('blue', 'વાદળી ફ્રેમ'),
  ('gold', 'સોનેરી ફ્રેમ'),
  ('emerald', 'લીલી ફ્રેમ'),
  ('minimal', 'સાદી ફ્રેમ'),
  ('cert', 'પ્રમાણપત્ર'),
];

Color pmColor(String hex, [Color fallback = const Color(0xFF111111)]) {
  final c = hex.trim().replaceFirst('#', '');
  if (c.length == 6) {
    final v = int.tryParse('FF$c', radix: 16);
    if (v != null) return Color(v);
  } else if (c.length == 8) {
    final v = int.tryParse(c, radix: 16);
    if (v != null) return Color(v);
  }
  return fallback;
}

int pmColorInt(String hex, [int fallback = 0xFF111111]) => pmColor(hex, Color(fallback)).toARGB32();

String pmGujDigits(String input) {
  const map = <String>['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];
  return input.replaceAllMapped(RegExp('[0-9]'), (m) => map[int.parse(m.group(0)!)]);
}

class PmObject {
  PmObject({
    required this.id,
    this.type = 'text',
    this.key = '',
    this.shapeKind = 'rect',
    this.imageId = '',
    this.customText = '',
    this.prefix = '',
    this.suffix = '',
    this.x = 60,
    this.y = 80,
    this.w = 260,
    this.h = 34,
    this.font = 'NotoSansGujaratiLocal',
    this.size = 16,
    this.lineH = 1.25,
    this.opacity = 100,
    this.color = '#111111',
    this.fill = '#DBEAFE',
    this.noFill = true,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.gujDigits = false,
    this.align = 'left',
    this.fit = 'cover',
    this.borderW = 0,
    this.borderC = '#1E3A8A',
    this.radius = 0,
    this.rotate = 0,
    this.locked = false,
    this.clipMode = 'none',
    this.clipKey = '',
    this.clipImageId = '',
    this.clipScale = 100,
    this.clipX = 0,
    this.clipY = 0,
    this.outlineW = 0,
    this.outlineC = '#FFFFFF',
    this.shadow = false,
    this.shadowC = '#94A3B8',
  });

  String id;

  /// 'text' (merge column) | 'static' | 'photo' (merge photo) | 'image' | 'shape'
  String type;

  /// Merge column for 'text' and 'photo'.
  String key;
  String shapeKind;

  /// Image store id for 'image'.
  String imageId;
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
  double opacity;
  String color;
  String fill;
  bool noFill;
  bool bold;
  bool italic;
  bool underline;
  bool gujDigits;
  String align;
  String fit;
  double borderW;
  String borderC;
  double radius;
  double rotate;
  bool locked;

  /// Clip inside a shape: 'none' | 'photo' (merge column [clipKey]) | 'image'.
  String clipMode;
  String clipKey;
  String clipImageId;
  double clipScale;
  double clipX;
  double clipY;

  /// Letter outline ("font border") width in px; 0 = none.
  double outlineW;
  String outlineC;
  bool shadow;
  String shadowC;

  bool get hasBorder => borderW > 0;
  bool get isTextual => type == 'text' || type == 'static';

  PmObject copy({String? newId, double dx = 0, double dy = 0}) =>
      PmObject.fromJson(toJson()..addAll(<String, dynamic>{'id': newId ?? id, 'x': x + dx, 'y': y + dy, 'locked': newId == null && locked}));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'key': key,
        'shapeKind': shapeKind,
        'imageId': imageId,
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
        'opacity': opacity,
        'color': color,
        'fill': fill,
        'noFill': noFill,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'gujDigits': gujDigits,
        'align': align,
        'fit': fit,
        'borderW': borderW,
        'borderC': borderC,
        'radius': radius,
        'rotate': rotate,
        'locked': locked,
        'clipMode': clipMode,
        'clipKey': clipKey,
        'clipImageId': clipImageId,
        'clipScale': clipScale,
        'clipX': clipX,
        'clipY': clipY,
        'outlineW': outlineW,
        'outlineC': outlineC,
        'shadow': shadow,
        'shadowC': shadowC,
      };

  factory PmObject.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] is num) ? (j[k] as num).toDouble() : def;
    String s(String k, String def) => j[k] == null ? def : '${j[k]}';
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    final font = s('font', 'NotoSansGujaratiLocal');
    return PmObject(
      id: s('id', ''),
      type: s('type', 'text'),
      key: s('key', ''),
      shapeKind: s('shapeKind', 'rect'),
      imageId: s('imageId', ''),
      customText: s('customText', ''),
      prefix: s('prefix', ''),
      suffix: s('suffix', ''),
      x: d('x', 60),
      y: d('y', 80),
      w: math.max(4, d('w', 260)),
      h: math.max(2, d('h', 34)),
      font: kPmFonts.any((f) => f.$1 == font) ? font : 'NotoSansGujaratiLocal',
      size: d('size', 16).clamp(4.0, 200.0),
      lineH: d('lineH', 1.25).clamp(0.8, 3.0),
      opacity: d('opacity', 100).clamp(5.0, 100.0),
      color: s('color', '#111111'),
      fill: s('fill', s('bgColor', '#DBEAFE')),
      noFill: b('noFill', b('bgTrans', true)),
      bold: b('bold', false),
      italic: b('italic', false),
      underline: b('underline', false),
      gujDigits: b('gujDigits', false),
      align: s('align', 'left'),
      fit: s('fit', 'cover'),
      borderW: (j['borderNone'] == true) ? 0 : d('borderW', 0).clamp(0.0, 30.0),
      borderC: s('borderC', '#1E3A8A'),
      radius: d('radius', 0).clamp(0.0, 400.0),
      rotate: d('rotate', 0),
      locked: b('locked', false),
      clipMode: s('clipMode', 'none'),
      clipKey: s('clipKey', ''),
      clipImageId: s('clipImageId', ''),
      clipScale: d('clipScale', 100).clamp(20.0, 300.0),
      clipX: d('clipX', 0),
      clipY: d('clipY', 0),
      outlineW: d('outlineW', 0).clamp(0.0, 8.0),
      outlineC: s('outlineC', '#FFFFFF'),
      shadow: b('shadow', false),
      shadowC: s('shadowC', '#94A3B8'),
    );
  }
}

class PmPage {
  PmPage({required this.id, required this.name, this.theme = 'white', this.bgImageId = '', List<PmObject>? objects})
      : objects = objects ?? <PmObject>[];

  String id;
  String name;
  String theme;

  /// Image store id of an uploaded page background (scanned certificate…).
  String bgImageId;
  final List<PmObject> objects;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'theme': theme,
        'bgImageId': bgImageId,
        'objects': objects.map((o) => o.toJson()).toList(),
      };

  factory PmPage.fromJson(Map<String, dynamic> j) => PmPage(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Page'}',
        theme: kPmThemes.any((t) => t.$1 == j['theme']) ? '${j['theme']}' : 'white',
        bgImageId: '${j['bgImageId'] ?? ''}',
        objects: <PmObject>[
          for (final o in (j['objects'] as List? ?? const <dynamic>[]))
            if (o is Map) PmObject.fromJson(Map<String, dynamic>.from(o)),
        ],
      );
}

// ---------------------------------------------------------------------------
// Shape geometry (shared by the artboard and the PDF)
// ---------------------------------------------------------------------------

class PmShapes {
  static Map<String, double> defaults(String kind) {
    switch (kind) {
      case 'square':
      case 'ellipse':
      case 'diamond':
      case 'polygon':
      case 'star':
        return <String, double>{'w': 160, 'h': 160, 'r': 0};
      case 'roundrect':
        return <String, double>{'w': 260, 'h': 130, 'r': 24};
      case 'oval':
        return <String, double>{'w': 240, 'h': 135, 'r': 0};
      case 'triangle':
        return <String, double>{'w': 160, 'h': 150, 'r': 0};
      case 'banner':
        return <String, double>{'w': 320, 'h': 64, 'r': 0};
      case 'arrow':
        return <String, double>{'w': 200, 'h': 70, 'r': 0};
      case 'line':
        return <String, double>{'w': 500, 'h': 8, 'r': 0};
      default:
        return <String, double>{'w': 260, 'h': 130, 'r': 0};
    }
  }

  /// Polygon points (fractions of width/height) or null for rect/ellipse/line.
  static List<Offset>? polygon(String kind) {
    switch (kind) {
      case 'triangle':
        return const <Offset>[Offset(0.5, 0), Offset(1, 1), Offset(0, 1)];
      case 'diamond':
        return const <Offset>[Offset(0.5, 0), Offset(1, 0.5), Offset(0.5, 1), Offset(0, 0.5)];
      case 'arrow':
        return const <Offset>[
          Offset(0.02, 0.33), Offset(0.62, 0.33), Offset(0.62, 0.08), Offset(0.98, 0.5),
          Offset(0.62, 0.92), Offset(0.62, 0.67), Offset(0.02, 0.67),
        ];
      case 'star':
        return const <Offset>[
          Offset(0.5, 0.04), Offset(0.63, 0.36), Offset(0.98, 0.38), Offset(0.7, 0.6), Offset(0.8, 0.95),
          Offset(0.5, 0.75), Offset(0.2, 0.95), Offset(0.3, 0.6), Offset(0.02, 0.38), Offset(0.37, 0.36),
        ];
      case 'polygon':
        return const <Offset>[
          Offset(0.5, 0.03), Offset(0.95, 0.26), Offset(0.95, 0.74), Offset(0.5, 0.97), Offset(0.05, 0.74), Offset(0.05, 0.26),
        ];
      case 'banner':
        return const <Offset>[Offset(0, 0), Offset(1, 0), Offset(0.93, 0.5), Offset(1, 1), Offset(0, 1), Offset(0.07, 0.5)];
      default:
        return null;
    }
  }

  static bool isEllipse(String kind) => kind == 'ellipse' || kind == 'oval';

  /// Flutter path of a shape inside [size], inset by [pad].
  static Path path(String kind, Size size, double pad, double radius) {
    final w = size.width, h = size.height;
    final p = Path();
    final inner = Rect.fromLTWH(pad, pad, math.max(1, w - pad * 2), math.max(1, h - pad * 2));
    if (isEllipse(kind)) return p..addOval(inner);
    final poly = polygon(kind);
    if (poly != null) {
      for (var i = 0; i < poly.length; i++) {
        final pt = Offset(inner.left + poly[i].dx * inner.width, inner.top + poly[i].dy * inner.height);
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    }
    final r = math.min(kind == 'roundrect' ? math.max(12.0, radius) : radius, math.min(inner.width, inner.height) / 2);
    return p..addRRect(RRect.fromRectAndRadius(inner, Radius.circular(r)));
  }
}
