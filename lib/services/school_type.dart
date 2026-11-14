/// Single source of truth for the school's gender type.
///
/// Schools are registered as boys-only, girls-only or mixed. Over time the
/// app stored this as 'boys' / 'girls' / 'mixed' / 'coed' / 'co-ed' and in
/// Gujarati ('કુમાર શાળા', 'કન્યા શાળા', 'મિશ્ર'). Every screen, report and
/// template must go through these helpers so all three school types behave
/// identically everywhere.
class SchoolType {
  SchoolType._();

  static const String boys = 'boys';
  static const String girls = 'girls';
  static const String mixed = 'mixed';

  /// Returns 'boys', 'girls' or 'mixed'. Unknown / empty values are mixed so
  /// both genders are always shown rather than silently dropped.
  static String canonical(dynamic raw) {
    final t = (raw ?? '').toString().trim().toLowerCase();
    if (t.isEmpty) return mixed;
    if (t.contains('mixed') ||
        t.contains('coed') ||
        t.contains('co-ed') ||
        t.contains('co_ed') ||
        t.contains('both') ||
        t.contains('મિશ્ર')) {
      return mixed;
    }
    if (t == 'boys' ||
        t == 'boy' ||
        t == 'b' ||
        t == 'only_boys' ||
        t == 'kumar' ||
        t.contains('boys') ||
        t.contains('કુમાર')) {
      return boys;
    }
    if (t == 'girls' ||
        t == 'girl' ||
        t == 'g' ||
        t == 'only_girls' ||
        t == 'kanya' ||
        t.contains('girls') ||
        t.contains('કન્યા')) {
      return girls;
    }
    return mixed;
  }

  /// Same as [canonical] but uses 'coed' for mixed schools (legacy screens
  /// and the Excel/PDF templates use that word).
  static String coedCompat(dynamic raw) {
    final c = canonical(raw);
    return c == mixed ? 'coed' : c;
  }

  static bool isMixed(dynamic raw) => canonical(raw) == mixed;
  static bool isBoys(dynamic raw) => canonical(raw) == boys;
  static bool isGirls(dynamic raw) => canonical(raw) == girls;

  /// Genders that exist in this school ('BOYS', 'GIRLS').
  static List<String> genders(dynamic raw) {
    switch (canonical(raw)) {
      case boys:
        return const <String>['BOYS'];
      case girls:
        return const <String>['GIRLS'];
      default:
        return const <String>['BOYS', 'GIRLS'];
    }
  }

  /// Gujarati label used on front pages and report headers.
  static String labelGu(dynamic raw) {
    switch (canonical(raw)) {
      case boys:
        return 'કુમાર શાળા';
      case girls:
        return 'કન્યા શાળા';
      default:
        return 'મિશ્ર શાળા';
    }
  }

  /// The first non-empty value among [candidates] decides the type; school
  /// names are used only as a last resort (a mixed school may be called
  /// "... Kumar Shala" for historical reasons).
  static String resolve(
    Iterable<dynamic> typeCandidates, {
    Iterable<dynamic> nameCandidates = const <dynamic>[],
  }) {
    for (final v in typeCandidates) {
      final t = (v ?? '').toString().trim();
      if (t.isNotEmpty && t.toLowerCase() != 'null') return canonical(t);
    }
    final names =
        nameCandidates.map((e) => '${e ?? ''}').join(' ').toLowerCase();
    if (names.contains('kumar') ||
        names.contains('કુમાર') ||
        names.contains('boys')) {
      return boys;
    }
    if (names.contains('kanya') ||
        names.contains('કન્યા') ||
        names.contains('girls')) {
      return girls;
    }
    return mixed;
  }
}
