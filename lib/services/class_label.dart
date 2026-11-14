/// One rule for printing class names.
///
/// Some schools name their classes "ધોરણ - 6 - અ", others just "6 - અ" or
/// "Class 6". Every printout that already has a "ધોરણ" caption must print the
/// class without its own "ધોરણ" word, otherwise it reads "ધોરણ ધોરણ - 6 - અ".
class ClassLabel {
  ClassLabel._();

  static final RegExp _prefix = RegExp(
    r'^\s*(?:ધોરણ|ધો(?:\s*\.|(?=[\s\d૦-૯\-–:]))|std\s*\.?|standard|class|grade)\s*[-–:.]*\s*',
    caseSensitive: false,
  );

  static final RegExp _mentions = RegExp(
    r'ધોરણ|ધો\.|\bstd\b|\bstandard\b|\bclass\b|\bgrade\b',
    caseSensitive: false,
  );

  /// Class name without a leading "ધોરણ" / "ધો." / "Std" / "Class" word:
  /// "ધોરણ - 6 - અ" → "6 - અ", "Class 7" → "7", "6-A" → "6-A".
  static String bare(Object? raw) {
    var t = '${raw ?? ''}'.trim();
    if (t.toLowerCase() == 'null') return '';
    for (var i = 0; i < 3; i++) {
      final m = _prefix.firstMatch(t);
      if (m == null || m.end >= t.length) break;
      t = t.substring(m.end).trim();
    }
    return t;
  }

  /// Class name with exactly one "ધોરણ" in front ("ધોરણ 6 - અ"); a
  /// Balvatika class is returned as it is.
  static String withStd(Object? raw, {String separator = ' '}) {
    final b = bare(raw);
    if (b.isEmpty) return '';
    if (b.contains('બાલવાટિકા') || b.toUpperCase().contains('BALVATIKA')) return b;
    return 'ધોરણ$separator$b';
  }

  /// True when a caption / prefix already names the standard.
  static bool mentionsStandard(String caption) => _mentions.hasMatch(caption);

  /// [value] as it should follow [caption] (stripped when the caption already
  /// says "ધોરણ").
  static String afterCaption(String caption, String value) =>
      mentionsStandard(caption) ? bare(value) : value;
}
