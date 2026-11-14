/// Category font colours and gender row backgrounds shared by the Hajari
/// Patrak and Result Excel/PDF templates.
///
/// - Category decides the FONT colour (same for boys and girls).
/// - In a mixed (B+G=T) school the gender decides the row BACKGROUND, so
///   boys and girls of the same category share a font colour but are easy
///   to tell apart. Single-gender schools keep a white background.
/// - The last student of each category (and the last student overall) gets
///   a double bottom line, like the Hajari Patrak register.
class XlsxRowColors {
  XlsxRowColors._();

  static const Map<String, String> categoryFont = <String, String>{
    'SC': 'FFC00000', // red
    'ST': 'FFBF6000', // amber / brown
    'OBC': 'FF202020', // dark charcoal / black
    'OTHER': 'FF214F9D', // blue
  };

  static const Map<String, String> genderFill = <String, String>{
    'BOYS': 'FFDCEBFB', // light blue
    'GIRLS': 'FFFDE2EE', // light pink
  };

  /// SC / ST / OBC / OTHER from any stored or Gujarati label.
  static String categoryKey(dynamic raw) {
    final t = '${raw ?? ''}'.toUpperCase().replaceAll(RegExp(r'[\s.]+'), '');
    if (t == 'ST' || t.contains('અજજા')) return 'ST';
    if (t == 'SC' || t.contains('અજા')) return 'SC';
    if (t == 'OBC' || t == 'SEBC' || t.contains('બક્ષી') || t.contains('બપં')) return 'OBC';
    return 'OTHER';
  }

  /// BOYS / GIRLS / '' from any stored or Gujarati label.
  static String genderKey(dynamic raw) {
    final t = '${raw ?? ''}'.trim().toUpperCase();
    if (t.startsWith('BOY') || t == 'M' || t == 'MALE' || t.contains('કુમાર')) return 'BOYS';
    if (t.startsWith('GIRL') || t == 'F' || t == 'FEMALE' || t.contains('કન્યા')) return 'GIRLS';
    return '';
  }

  /// Restyles every cell of the given rows: category font colour and (when
  /// [genderBackground]) a gender fill on cells whose template fill is empty.
  /// Returns the updated worksheet and styles XML.
  static (String, String) apply({
    required String stylesXml,
    required String sheetXml,
    required Map<int, ({String category, String gender, bool categoryEnd})> rows,
    required bool genderBackground,
  }) {
    if (rows.isEmpty) return (sheetXml, stylesXml);
    final fontsM = RegExp(r'<fonts\b[^>]*>.*?</fonts>', dotAll: true).firstMatch(stylesXml);
    final fillsM = RegExp(r'<fills\b[^>]*>.*?</fills>', dotAll: true).firstMatch(stylesXml);
    final bordersM = RegExp(r'<borders\b[^>]*>.*?</borders>', dotAll: true).firstMatch(stylesXml);
    final xfsM = RegExp(r'<cellXfs\b[^>]*>.*?</cellXfs>', dotAll: true).firstMatch(stylesXml);
    if (fontsM == null || fillsM == null || bordersM == null || xfsM == null) {
      return (sheetXml, stylesXml);
    }

    List<String> kids(String coll, String tag) => RegExp(
          '<$tag\\b[^>]*?(?:/>|>.*?</$tag>)',
          dotAll: true,
        ).allMatches(coll).map((m) => m.group(0)!).toList();

    final fonts = kids(fontsM.group(0)!, 'font');
    final fills = kids(fillsM.group(0)!, 'fill');
    final borders = kids(bordersM.group(0)!, 'border');
    final xfs = kids(xfsM.group(0)!, 'xf');
    if (fonts.isEmpty || xfs.isEmpty) return (sheetXml, stylesXml);

    final fontCache = <String, int>{};
    final fillCache = <String, int>{};
    final xfCache = <String, int>{};
    final borderCache = <String, int>{};

    /// Same border with a double (category end) or thin bottom line.
    int borderVariant(int baseId, bool doubleBottom) {
      if (borders.isEmpty) return baseId;
      final id = baseId.clamp(0, borders.length - 1);
      final original = borders[id];
      final bottom = RegExp(r'<bottom\b([^>]*?)>(.*?)</bottom>|<bottom\b([^>]*?)/>', dotAll: true)
          .firstMatch(original);
      final current = bottom == null
          ? ''
          : (RegExp(r'\bstyle="([^"]+)"').firstMatch(bottom.group(1) ?? bottom.group(3) ?? '')?.group(1) ?? '');
      final desired = doubleBottom ? 'double' : 'thin';
      if (current == desired || (!doubleBottom && current != 'double')) return id;
      final key = '$id|$desired';
      final hit = borderCache[key];
      if (hit != null) return hit;
      final newBottom = '<bottom style="$desired"><color rgb="FF000000"/></bottom>';
      String updated;
      if (bottom != null) {
        updated = original.replaceRange(bottom.start, bottom.end, newBottom);
      } else if (original.contains('<diagonal')) {
        // Schema order: left, right, top, bottom, diagonal.
        updated = original.replaceFirst('<diagonal', '$newBottom<diagonal');
      } else if (original.endsWith('/>')) {
        updated = '${original.substring(0, original.length - 2)}>$newBottom</border>';
      } else {
        updated = original.replaceFirst('</border>', '$newBottom</border>');
      }
      borders.add(updated);
      return borderCache[key] = borders.length - 1;
    }

    int fontVariant(int baseId, String color) {
      final key = '$baseId|$color';
      final hit = fontCache[key];
      if (hit != null) return hit;
      var font = fonts[baseId.clamp(0, fonts.length - 1)];
      final tag = '<color rgb="$color"/>';
      final colorPattern = RegExp(r'<color\b[^>]*/>');
      if (colorPattern.hasMatch(font)) {
        font = font.replaceFirst(colorPattern, tag);
      } else {
        final sz = RegExp(r'<sz\b[^>]*/>').firstMatch(font);
        font = sz != null
            ? font.replaceRange(sz.end, sz.end, tag)
            : font.replaceFirst('</font>', '$tag</font>');
      }
      fonts.add(font);
      return fontCache[key] = fonts.length - 1;
    }

    int fillVariant(String color) {
      final hit = fillCache[color];
      if (hit != null) return hit;
      fills.add(
        '<fill><patternFill patternType="solid"><fgColor rgb="$color"/><bgColor rgb="$color"/></patternFill></fill>',
      );
      return fillCache[color] = fills.length - 1;
    }

    String setAttr(String xf, String name, int value) {
      final p = RegExp('\\b$name="[^"]*"');
      return p.hasMatch(xf)
          ? xf.replaceFirst(p, '$name="$value"')
          : xf.replaceFirst('<xf ', '<xf $name="$value" ');
    }

    int styled(int baseXf, String category, String gender, bool categoryEnd) {
      final key = '$baseXf|$category|$gender|$categoryEnd';
      final hit = xfCache[key];
      if (hit != null) return hit;
      var xf = xfs[baseXf.clamp(0, xfs.length - 1)];
      int attr(String n) =>
          int.tryParse(RegExp('\\b$n="(\\d+)"').firstMatch(xf)?.group(1) ?? '') ?? 0;
      final color = categoryFont[category] ?? categoryFont['OTHER']!;
      xf = setAttr(xf, 'fontId', fontVariant(attr('fontId'), color));
      xf = setAttr(xf, 'applyFont', 1);
      final fillId = attr('fillId');
      final bg = genderFill[gender];
      if (genderBackground && bg != null && (fillId == 0 || fillId == 1)) {
        xf = setAttr(xf, 'fillId', fillVariant(bg));
        xf = setAttr(xf, 'applyFill', 1);
      }
      final borderId = attr('borderId');
      final newBorder = borderVariant(borderId, categoryEnd);
      if (newBorder != borderId) {
        xf = setAttr(xf, 'borderId', newBorder);
        xf = setAttr(xf, 'applyBorder', 1);
      }
      xfs.add(xf);
      return xfCache[key] = xfs.length - 1;
    }

    final rowPattern = RegExp(r'<row\b[^>]*?(?:/>|>.*?</row>)', dotAll: true);
    final cellPattern = RegExp(r'<c\b[^>]*?(?:/>|>.*?</c>)', dotAll: true);
    final newSheet = sheetXml.replaceAllMapped(rowPattern, (rm) {
      final rowXml = rm.group(0)!;
      final n = int.tryParse(RegExp(r'\br="(\d+)"').firstMatch(rowXml)?.group(1) ?? '') ?? 0;
      final info = rows[n];
      if (info == null) return rowXml;
      return rowXml.replaceAllMapped(cellPattern, (cm) {
        final cell = cm.group(0)!;
        final sM = RegExp(r'\bs="(\d+)"').firstMatch(cell);
        final base = int.tryParse(sM?.group(1) ?? '') ?? 0;
        final id = styled(base, info.category, info.gender, info.categoryEnd);
        return sM == null
            ? cell.replaceFirst('<c ', '<c s="$id" ')
            : cell.replaceFirst(sM.group(0)!, 's="$id"');
      });
    });

    String rebuild(String original, String tag, List<String> items) {
      final openEnd = original.indexOf('>');
      var open = original.substring(0, openEnd + 1);
      open = RegExp(r'\bcount="\d+"').hasMatch(open)
          ? open.replaceFirst(RegExp(r'\bcount="\d+"'), 'count="${items.length}"')
          : open.replaceFirst('>', ' count="${items.length}">');
      return '$open${items.join()}</$tag>';
    }

    // Replace from the last collection to the first so offsets stay valid.
    var styles = stylesXml;
    final edits = <(int, int, String)>[
      (fontsM.start, fontsM.end, rebuild(fontsM.group(0)!, 'fonts', fonts)),
      (fillsM.start, fillsM.end, rebuild(fillsM.group(0)!, 'fills', fills)),
      (bordersM.start, bordersM.end, rebuild(bordersM.group(0)!, 'borders', borders)),
      (xfsM.start, xfsM.end, rebuild(xfsM.group(0)!, 'cellXfs', xfs)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final e in edits) {
      styles = styles.replaceRange(e.$1, e.$2, e.$3);
    }
    return (newSheet, styles);
  }
}
