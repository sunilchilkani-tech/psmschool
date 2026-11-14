part of '../supabase_id_card_studio_screen.dart';

// ============================================================================
// DATA MODELS, ENUMS, SIGNATURE BOX & CACHED AUTO-FIT TYPOGRAPHY ENGINE
// ============================================================================

enum PrintRecordScope {
  all('all', 'All Students'),
  selectedOnly('selected', 'Selected Students Only'),
  currentOnly('current', 'Current Student Only'),
  filteredOnly('filtered', 'Current Filtered List'),
  fromToRange('range', 'From–To Row Range');

  final String code;
  final String label;
  const PrintRecordScope(this.code, this.label);
}

enum TextFitMode {
  auto('auto', 'Smart Wrap + Auto-Shrink (Recommended)'),
  nowrap('nowrap', 'Single Line Only — Auto-Shrink Width'),
  wrap('wrap', 'Multi-Line Wrap + Auto-Shrink Box');

  final String code;
  final String label;
  const TextFitMode(this.code, this.label);

  static TextFitMode fromCode(String? c) =>
      TextFitMode.values.firstWhere((e) => e.code == c, orElse: () => auto);
}

enum VerticalTextAlign {
  top('top', 'Top'),
  middle('middle', 'Middle'),
  bottom('bottom', 'Bottom');

  final String code;
  final String label;
  const VerticalTextAlign(this.code, this.label);

  static VerticalTextAlign fromCode(String? c) => VerticalTextAlign.values
      .firstWhere((e) => e.code == c, orElse: () => middle);
}

enum TextCaseTransform {
  none('none', 'Normal (As Entered)'),
  upper('upper', 'UPPERCASE'),
  lower('lower', 'lowercase'),
  title('title', 'Title Case');

  final String code;
  final String label;
  const TextCaseTransform(this.code, this.label);

  static TextCaseTransform fromCode(String? c) => TextCaseTransform.values
      .firstWhere((e) => e.code == c, orElse: () => none);

  String apply(String input) {
    if (input.isEmpty) return input;
    switch (this) {
      case TextCaseTransform.none:
        return input;
      case TextCaseTransform.upper:
        return input.toUpperCase();
      case TextCaseTransform.lower:
        return input.toLowerCase();
      case TextCaseTransform.title:
        return input
            .split(RegExp(r'(\s+)'))
            .map((word) {
              if (word.trim().isEmpty) return word;
              return word[0].toUpperCase() + word.substring(1).toLowerCase();
            })
            .join();
    }
  }
}

enum BuiltInTemplateTheme {
  none('none', 'Blank White', true),
  blankBorder('blank-border', 'Blank Frame', true),
  blankHeader('blank-header', 'Blank Header', true),
  blankBadge('blank-badge', 'Blank Badge', true),
  teal('teal', 'Teal Wave', false),
  navy('navy', 'Corp Navy', false),
  gold('gold', 'Acad Gold', false),
  crimson('crimson', 'Crimson', false),
  minimal('minimal', 'Minimal', false),
  emerald('emerald', 'Emerald', false);

  final String code;
  final String label;
  final bool isBlankStyle;
  const BuiltInTemplateTheme(this.code, this.label, this.isBlankStyle);

  static BuiltInTemplateTheme fromCode(String? c) =>
      BuiltInTemplateTheme.values
          .firstWhere((e) => e.code == c, orElse: () => none);
}

enum CutGuideStyle {
  solid('solid', 'Solid Hairline Box'),
  crop('crop', 'Corner Crop Marks'),
  dashed('dashed', 'Dashed Cut Lines');

  final String code;
  final String label;
  const CutGuideStyle(this.code, this.label);

  static CutGuideStyle fromCode(String? c) =>
      CutGuideStyle.values.firstWhere((e) => e.code == c, orElse: () => solid);
}

enum SelectedItemType { field, photo, seal, signature }

class SelectedItemKey {
  final SelectedItemType type;
  final int index;
  const SelectedItemKey(this.type, [this.index = 0]);

  Map<String, dynamic> toJson() => {'type': type.name, 'index': index};

  factory SelectedItemKey.fromJson(Map<String, dynamic> j) {
    final tName = j['type'] as String? ?? 'field';
    final t = SelectedItemType.values.firstWhere(
      (e) => e.name == tName,
      orElse: () => SelectedItemType.field,
    );
    return SelectedItemKey(t, (j['index'] as num?)?.toInt() ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is SelectedItemKey && other.type == type && other.index == index;

  @override
  int get hashCode => Object.hash(type, index);
}

abstract class CardBoxItem {
  double get x;
  set x(double v);
  double get y;
  set y(double v);
  double get w;
  set w(double v);
  double get h;
  set h(double v);
  bool get locked;
  set locked(bool v);
  int? get groupId;
  set groupId(int? v);
}

class DbStudentHeaderSpec {
  final String key;
  final String labelEn;
  final String labelGu;
  final String defaultPrefix;

  const DbStudentHeaderSpec({
    required this.key,
    required this.labelEn,
    required this.labelGu,
    this.defaultPrefix = '',
  });

  String get displayLabel => '$labelEn ($labelGu)';
}

const List<DbStudentHeaderSpec> kCoreStudentHeaderSpecs = [
  DbStudentHeaderSpec(
    key: 'student_name',
    labelEn: 'Student Name',
    labelGu: 'વિદ્યાર્થીનું નામ',
    defaultPrefix: '',
  ),
  DbStudentHeaderSpec(
    key: 'class_label',
    labelEn: 'Class / Standard',
    labelGu: 'ધોરણ',
    defaultPrefix: 'ધોરણ: ',
  ),
  DbStudentHeaderSpec(
    key: 'roll_no',
    labelEn: 'Roll No',
    labelGu: 'રોલ નંબર',
    defaultPrefix: 'રોલ નં: ',
  ),
  DbStudentHeaderSpec(
    key: 'gr_no',
    labelEn: 'GR Number',
    labelGu: 'જી.આર. નંબર',
    defaultPrefix: 'GR નં: ',
  ),
  DbStudentHeaderSpec(
    key: 'birth_date',
    labelEn: 'Birth Date',
    labelGu: 'જન્મ તારીખ',
    defaultPrefix: 'જન્મ તારીખ: ',
  ),
  DbStudentHeaderSpec(
    key: 'mobile',
    labelEn: 'Mobile Number',
    labelGu: 'મોબાઈલ નંબર',
    defaultPrefix: 'મો: ',
  ),
  DbStudentHeaderSpec(
    key: 'father_name',
    labelEn: 'Father Name',
    labelGu: 'પિતાનું નામ',
    defaultPrefix: 'પિતા: ',
  ),
  DbStudentHeaderSpec(
    key: 'mother_name',
    labelEn: 'Mother Name',
    labelGu: 'માતાનું નામ',
    defaultPrefix: 'માતા: ',
  ),
  DbStudentHeaderSpec(
    key: 'religion',
    labelEn: 'Religion (Gujarati)',
    labelGu: 'ધર્મ',
    defaultPrefix: 'ધર્મ: ',
  ),
  DbStudentHeaderSpec(
    key: 'religion_en',
    labelEn: 'Religion (English)',
    labelGu: 'RELIGION IN ENGLISH',
    defaultPrefix: 'Religion: ',
  ),
  DbStudentHeaderSpec(
    key: 'caste',
    labelEn: 'Caste / Sub-caste',
    labelGu: 'જ્ઞાતિ / પેટાજ્ઞાતિ',
    defaultPrefix: 'જ્ઞાતિ: ',
  ),
  DbStudentHeaderSpec(
    key: 'category',
    labelEn: 'Category',
    labelGu: 'કેટેગરી',
    defaultPrefix: 'કેટેગરી: ',
  ),
  DbStudentHeaderSpec(
    key: 'gender',
    labelEn: 'Gender',
    labelGu: 'લિંગ',
    defaultPrefix: '',
  ),
  DbStudentHeaderSpec(
    key: 'address',
    labelEn: 'Address',
    labelGu: 'સરનામું',
    defaultPrefix: 'સરનામું: ',
  ),
  DbStudentHeaderSpec(
    key: 'uid',
    labelEn: 'UID Number',
    labelGu: 'UID નંબર',
    defaultPrefix: 'UID: ',
  ),
  DbStudentHeaderSpec(
    key: 'pen',
    labelEn: 'PEN Number',
    labelGu: 'PEN નંબર',
    defaultPrefix: 'PEN: ',
  ),
  DbStudentHeaderSpec(
    key: 'apaar_id',
    labelEn: 'APAAR ID',
    labelGu: 'APAAR ID',
    defaultPrefix: 'APAAR: ',
  ),
  DbStudentHeaderSpec(
    key: 'enroll_school',
    labelEn: 'Admission Date',
    labelGu: 'દાખલ તારીખ',
    defaultPrefix: 'દાખલ તા: ',
  ),
  DbStudentHeaderSpec(
    key: 'school_name',
    labelEn: 'School Name',
    labelGu: 'શાળાનું નામ',
    defaultPrefix: '',
  ),
];

const List<String> kAllAvailableStudioFonts = [
  'NotoSansGujaratiLocal',
  'LohitGujaratiLocal',
  'Roboto',
  'Poppins',
  'Montserrat',
  'Oswald',
  'Merriweather',
  'Lora',
  'Playfair Display',
  'Open Sans',
  'Inter',
  'Nunito',
];

const List<double> kQuickFontSizes = [
  6.0,
  7.0,
  8.0,
  8.5,
  9.0,
  9.5,
  10.0,
  11.0,
  12.0,
  14.0,
  16.0,
  18.0,
  24.0,
];

class CardFieldItem implements CardBoxItem {
  int col; // >= 0 for Excel/DB column; -1 when isDirectText == true
  bool isDirectText;
  String staticText;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  bool locked;
  @override
  int? groupId;

  double fontSize;
  double minFontSize;
  bool autoFit;
  TextFitMode textMode;
  TextAlign align;
  VerticalTextAlign valign;
  double lineHeight;
  double letterSpacing;
  TextCaseTransform textCase;
  String prefix;
  bool prefixBold;
  String fontFamily;
  bool bold;
  bool italic;
  bool underline;
  Color color;

  final double _origFontSize;
  final double _origMinFontSize;
  final bool _origAutoFit;
  final TextFitMode _origTextMode;
  final TextAlign _origAlign;
  final VerticalTextAlign _origValign;
  final double _origLineHeight;
  final double _origLetterSpacing;
  final TextCaseTransform _origTextCase;
  final String _origFontFamily;
  final bool _origBold;
  final bool _origItalic;
  final bool _origUnderline;
  final Color _origColor;

  CardFieldItem({
    required this.col,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.isDirectText = false,
    this.staticText = '',
    this.locked = false,
    this.groupId,
    this.fontSize = 9.5,
    this.minFontSize = 4.5,
    this.autoFit = true,
    this.textMode = TextFitMode.auto,
    this.align = TextAlign.left,
    this.valign = VerticalTextAlign.middle,
    this.lineHeight = 1.15,
    this.letterSpacing = 0.0,
    this.textCase = TextCaseTransform.none,
    this.prefix = '',
    this.prefixBold = true,
    this.fontFamily = 'NotoSansGujaratiLocal',
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = const Color(0xFF0F172A),
  })  : _origFontSize = fontSize,
        _origMinFontSize = minFontSize,
        _origAutoFit = autoFit,
        _origTextMode = textMode,
        _origAlign = align,
        _origValign = valign,
        _origLineHeight = lineHeight,
        _origLetterSpacing = letterSpacing,
        _origTextCase = textCase,
        _origFontFamily = fontFamily,
        _origBold = bold,
        _origItalic = italic,
        _origUnderline = underline,
        _origColor = color;

  void resetToOriginalStyle() {
    fontSize = _origFontSize;
    minFontSize = _origMinFontSize;
    autoFit = _origAutoFit;
    textMode = _origTextMode;
    align = _origAlign;
    valign = _origValign;
    lineHeight = _origLineHeight;
    letterSpacing = _origLetterSpacing;
    textCase = _origTextCase;
    fontFamily = _origFontFamily;
    bold = _origBold;
    italic = _origItalic;
    underline = _origUnderline;
    color = _origColor;
  }

  CardFieldItem copy() => CardFieldItem(
        col: col,
        isDirectText: isDirectText,
        staticText: staticText,
        x: x,
        y: y,
        w: w,
        h: h,
        locked: locked,
        groupId: groupId,
        fontSize: fontSize,
        minFontSize: minFontSize,
        autoFit: autoFit,
        textMode: textMode,
        align: align,
        valign: valign,
        lineHeight: lineHeight,
        letterSpacing: letterSpacing,
        textCase: textCase,
        prefix: prefix,
        prefixBold: prefixBold,
        fontFamily: fontFamily,
        bold: bold,
        italic: italic,
        underline: underline,
        color: color,
      );

  Map<String, dynamic> toJson() => {
        'col': col,
        'isDirectText': isDirectText,
        'staticText': staticText,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'locked': locked,
        'groupId': groupId,
        'fontSize': fontSize,
        'minFontSize': minFontSize,
        'autoFit': autoFit,
        'textMode': textMode.code,
        'align': align.name,
        'valign': valign.code,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'textCase': textCase.code,
        'prefix': prefix,
        'prefixBold': prefixBold,
        'fontFamily': fontFamily,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'color': color.toARGB32(),
      };

  factory CardFieldItem.fromJson(Map<String, dynamic> j) => CardFieldItem(
        col: (j['col'] as num?)?.toInt() ?? 0,
        isDirectText: j['isDirectText'] as bool? ?? false,
        staticText: j['staticText'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 300,
        y: (j['y'] as num?)?.toDouble() ?? 100,
        w: (j['w'] as num?)?.toDouble() ?? 450,
        h: (j['h'] as num?)?.toDouble() ?? 32,
        locked: j['locked'] as bool? ?? false,
        groupId: (j['groupId'] as num?)?.toInt(),
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 9.5,
        minFontSize: (j['minFontSize'] as num?)?.toDouble() ?? 4.5,
        autoFit: j['autoFit'] as bool? ?? true,
        textMode: TextFitMode.fromCode(j['textMode'] as String?),
        align: _parseTextAlign(j['align'] as String?),
        valign: VerticalTextAlign.fromCode(j['valign'] as String?),
        lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.15,
        letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0.0,
        textCase: TextCaseTransform.fromCode(j['textCase'] as String?),
        prefix: j['prefix'] as String? ?? '',
        prefixBold: j['prefixBold'] as bool? ?? true,
        fontFamily: j['fontFamily'] as String? ?? 'NotoSansGujaratiLocal',
        bold: j['bold'] as bool? ?? false,
        italic: j['italic'] as bool? ?? false,
        underline: j['underline'] as bool? ?? false,
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF0F172A),
      );

  static TextAlign _parseTextAlign(String? s) {
    if (s == 'center') return TextAlign.center;
    if (s == 'right') return TextAlign.right;
    return TextAlign.left;
  }
}

class CardPhotoBox implements CardBoxItem {
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  bool locked;
  @override
  int? groupId;

  Color borderColor;
  double borderWidth;
  String borderStyle; // 'solid' | 'dashed' | 'none'
  double borderRadius;
  double brightness; // 50..150
  BoxFit fit;

  CardPhotoBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.locked = false,
    this.groupId,
    this.borderColor = const Color(0xFF0D7480),
    this.borderWidth = 2.5,
    this.borderStyle = 'solid',
    this.borderRadius = 12,
    this.brightness = 100,
    this.fit = BoxFit.cover,
  });

  CardPhotoBox copy() => CardPhotoBox(
        x: x,
        y: y,
        w: w,
        h: h,
        locked: locked,
        groupId: groupId,
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderStyle: borderStyle,
        borderRadius: borderRadius,
        brightness: brightness,
        fit: fit,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'locked': locked,
        'groupId': groupId,
        'bc': borderColor.toARGB32(),
        'bw': borderWidth,
        'bs': borderStyle,
        'br': borderRadius,
        'bright': brightness,
        'fit': fit == BoxFit.contain ? 'contain' : 'cover',
      };

  factory CardPhotoBox.fromJson(Map<String, dynamic> j) => CardPhotoBox(
        x: (j['x'] as num?)?.toDouble() ?? 48,
        y: (j['y'] as num?)?.toDouble() ?? 120,
        w: (j['w'] as num?)?.toDouble() ?? 205,
        h: (j['h'] as num?)?.toDouble() ?? 255,
        locked: j['locked'] as bool? ?? false,
        groupId: (j['groupId'] as num?)?.toInt(),
        borderColor: Color((j['bc'] as num?)?.toInt() ?? 0xFF0D7480),
        borderWidth: (j['bw'] as num?)?.toDouble() ?? 2.5,
        borderStyle: j['bs'] as String? ?? 'solid',
        borderRadius: (j['br'] as num?)?.toDouble() ?? 12,
        brightness: (j['bright'] as num?)?.toDouble() ?? 100,
        fit: j['fit'] == 'contain' ? BoxFit.contain : BoxFit.cover,
      );
}

class CardSealBox implements CardBoxItem {
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  bool locked;
  @override
  int? groupId;
  double overlapPercent;

  CardSealBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.locked = false,
    this.groupId,
    this.overlapPercent = 50,
  });

  CardSealBox copy() => CardSealBox(
        x: x,
        y: y,
        w: w,
        h: h,
        locked: locked,
        groupId: groupId,
        overlapPercent: overlapPercent,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'locked': locked,
        'groupId': groupId,
        'ov': overlapPercent,
      };

  factory CardSealBox.fromJson(Map<String, dynamic> j) => CardSealBox(
        x: (j['x'] as num?)?.toDouble() ?? 195,
        y: (j['y'] as num?)?.toDouble() ?? 315,
        w: (j['w'] as num?)?.toDouble() ?? 95,
        h: (j['h'] as num?)?.toDouble() ?? 95,
        locked: j['locked'] as bool? ?? false,
        groupId: (j['groupId'] as num?)?.toInt(),
        overlapPercent: (j['ov'] as num?)?.toDouble() ?? 50,
      );
}

class CardSignatureBox implements CardBoxItem {
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  bool locked;
  @override
  int? groupId;

  CardSignatureBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.locked = false,
    this.groupId,
  });

  CardSignatureBox copy() => CardSignatureBox(
        x: x,
        y: y,
        w: w,
        h: h,
        locked: locked,
        groupId: groupId,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'locked': locked,
        'groupId': groupId,
      };

  factory CardSignatureBox.fromJson(Map<String, dynamic> j) => CardSignatureBox(
        x: (j['x'] as num?)?.toDouble() ?? 610,
        y: (j['y'] as num?)?.toDouble() ?? 430,
        w: (j['w'] as num?)?.toDouble() ?? 180,
        h: (j['h'] as num?)?.toDouble() ?? 75,
        locked: j['locked'] as bool? ?? false,
        groupId: (j['groupId'] as num?)?.toInt(),
      );
}

class CardClipboardPayload {
  final List<CardFieldItem> fields;
  final CardPhotoBox? photo;
  final CardSealBox? seal;
  final CardSignatureBox? signature;

  const CardClipboardPayload({
    this.fields = const [],
    this.photo,
    this.seal,
    this.signature,
  });

  bool get isEmpty =>
      fields.isEmpty && photo == null && seal == null && signature == null;
}

class CardLayoutSet {
  List<CardFieldItem> fields;
  CardPhotoBox photo;
  CardSealBox seal;
  CardSignatureBox signature;

  CardLayoutSet({
    required this.fields,
    required this.photo,
    required this.seal,
    CardSignatureBox? signature,
  }) : signature =
            signature ?? CardSignatureBox(x: 610, y: 430, w: 180, h: 75);

  CardLayoutSet copy() => CardLayoutSet(
        fields: fields.map((f) => f.copy()).toList(),
        photo: photo.copy(),
        seal: seal.copy(),
        signature: signature.copy(),
      );

  Map<String, dynamic> toJson() => {
        'fields': fields.map((f) => f.toJson()).toList(),
        'photo': photo.toJson(),
        'seal': seal.toJson(),
        'signature': signature.toJson(),
      };

  factory CardLayoutSet.fromJson(Map<String, dynamic> j) => CardLayoutSet(
        fields: ((j['fields'] as List?) ?? [])
            .map((e) => CardFieldItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        photo: CardPhotoBox.fromJson(
            Map<String, dynamic>.from(j['photo'] as Map? ?? {})),
        seal: CardSealBox.fromJson(
            Map<String, dynamic>.from(j['seal'] as Map? ?? {})),
        signature: j['signature'] is Map
            ? CardSignatureBox.fromJson(
                Map<String, dynamic>.from(j['signature'] as Map))
            : null,
      );
}

class FittedTextResult {
  final double fittedPt;
  final bool shrunk;
  final TextSpan span;
  const FittedTextResult({
    required this.fittedPt,
    required this.shrunk,
    required this.span,
  });
}

class SheetGeometry {
  final double paperWmm;
  final double paperHmm;
  final double cardWmm;
  final double cardHmm;
  final double gapMm;
  final int cols;
  final int rows;
  final int perSheet;
  final double x0Mm;
  final double y0Mm;
  final int totalPages;

  const SheetGeometry({
    required this.paperWmm,
    required this.paperHmm,
    required this.cardWmm,
    required this.cardHmm,
    required this.gapMm,
    required this.cols,
    required this.rows,
    required this.perSheet,
    required this.x0Mm,
    required this.y0Mm,
    required this.totalPages,
  });
}

class AutoFitTypographyEngine {
  static const double kPtToEditorUnits = 3.528; // 1pt in 10-units/mm space
  static final Map<String, FittedTextResult> _fitCache =
      <String, FittedTextResult>{};

  static void clearCache() => _fitCache.clear();

  static TextSpan buildFieldSpan(
    CardFieldItem f,
    String rawValue,
    double fontPx,
  ) {
    final baseVal = (f.isDirectText ? f.staticText : rawValue).trim();
    final pfx = f.prefix;
    // A "ધોરણ: " prefix already names the standard: print "6 - અ", not
    // "ધોરણ: ધોરણ - 6 - અ".
    final val = f.textCase.apply(f.isDirectText ? baseVal : ClassLabel.afterCaption(pfx, baseVal));
    final baseStyle = TextStyle(
      fontFamily: f.fontFamily,
      fontSize: fontPx,
      fontWeight: f.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: f.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          f.underline ? TextDecoration.underline : TextDecoration.none,
      color: f.color,
      height: f.lineHeight,
      letterSpacing: f.letterSpacing,
    );

    if (val.isEmpty && pfx.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }
    if (pfx.isNotEmpty) {
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: pfx,
            style: baseStyle.copyWith(
              fontWeight: f.prefixBold ? FontWeight.w700 : baseStyle.fontWeight,
            ),
          ),
          TextSpan(text: val),
        ],
      );
    }
    return TextSpan(text: val, style: baseStyle);
  }

  static FittedTextResult computeFittedFontSize(
    CardFieldItem f,
    String rawValue, {
    double scale = 1.0,
    double ptScale = kPtToEditorUnits,
  }) {
    final cleanVal = f.textCase.apply(f.isDirectText
        ? f.staticText.trim()
        : ClassLabel.afterCaption(f.prefix, rawValue.trim()));
    final cacheKey =
        '${f.fontFamily}|${f.fontSize}|${f.minFontSize}|${f.autoFit}|${f.textMode.code}|'
        '${f.align.name}|${f.lineHeight}|${f.letterSpacing}|${f.bold}|${f.italic}|'
        '${f.underline}|${f.color.toARGB32()}|${f.prefix}|${f.prefixBold}|'
        '${f.w.toStringAsFixed(1)}|${f.h.toStringAsFixed(1)}|'
        '${scale.toStringAsFixed(3)}|${ptScale.toStringAsFixed(3)}|$cleanVal';

    final cached = _fitCache[cacheKey];
    if (cached != null) return cached;

    final maxPt = math.max(4.0, f.fontSize);
    final minPt = math.max(3.0, math.min(maxPt, f.minFontSize));
    if ((cleanVal.isEmpty && f.prefix.isEmpty) || !f.autoFit) {
      final res = FittedTextResult(
        fittedPt: maxPt,
        shrunk: false,
        span: buildFieldSpan(f, rawValue, maxPt * ptScale),
      );
      _putCache(cacheKey, res);
      return res;
    }

    final boxW = math.max(16.0, (f.w - 8.0) * scale);
    final boxH = math.max(10.0, (f.h - 4.0) * scale);
    final isSingleLine = f.textMode == TextFitMode.nowrap;

    bool fitsAt(double pt) {
      final px = pt * ptScale;
      final span = buildFieldSpan(f, rawValue, px);
      final tp = TextPainter(
        text: span,
        textAlign: f.align,
        textDirection: TextDirection.ltr,
        maxLines: isSingleLine ? 1 : null,
      );
      tp.layout(
        minWidth: 0,
        maxWidth: isSingleLine ? double.infinity : boxW,
      );
      if (tp.width > boxW + 0.8 || tp.height > boxH + 0.8) {
        return false;
      }
      if (!isSingleLine) {
        final longestWord =
            ('${f.prefix}$cleanVal').split(RegExp(r'\s+')).fold<String>(
                  '',
                  (prev, elem) => elem.length > prev.length ? elem : prev,
                );
        if (longestWord.isNotEmpty) {
          final wordTp = TextPainter(
            text: TextSpan(
              text: longestWord,
              style: span.style,
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          if (wordTp.width > boxW + 1.0) return false;
        }
      }
      return true;
    }

    if (fitsAt(maxPt)) {
      final res = FittedTextResult(
        fittedPt: maxPt,
        shrunk: false,
        span: buildFieldSpan(f, rawValue, maxPt * ptScale),
      );
      _putCache(cacheKey, res);
      return res;
    }

    double lo = math.min(minPt, 2.75);
    double hi = maxPt;
    double best = lo;
    for (int i = 0; i < 9; i++) {
      final mid = (lo + hi) / 2.0;
      if (fitsAt(mid)) {
        best = mid;
        lo = mid;
      } else {
        hi = mid;
      }
    }
    best = (best * 4.0).floorToDouble() / 4.0;
    best = math.max(2.75, best);

    final res = FittedTextResult(
      fittedPt: best,
      shrunk: best < maxPt - 0.1,
      span: buildFieldSpan(f, rawValue, best * ptScale),
    );
    _putCache(cacheKey, res);
    return res;
  }

  static void _putCache(String k, FittedTextResult v) {
    if (_fitCache.length > 1200) {
      _fitCache.clear();
    }
    _fitCache[k] = v;
  }
}
