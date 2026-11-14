/// Resolve a school's Gujarati display name without silently printing an
/// English name into a Gujarati leave form. The canonical value is maintained
/// by Developer in `schools.school_name_gu`; school_settings aliases are kept
/// for older school records.
String psmGujaratiSchoolLabel({
  Map<String, dynamic>? schoolContext,
  Map<String, dynamic>? schoolConfig,
  String fallbackEnglish = '',
}) {
  final context = schoolContext ?? const <String, dynamic>{};
  final config = schoolConfig ?? const <String, dynamic>{};
  String firstNonEmpty(Iterable<dynamic> candidates) {
    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  final gujarati = firstNonEmpty(<dynamic>[
    context['school_name_gu'], context['schoolNameGu'], context['school_name_gj'],
    context['gujarati_school_name'], context['name_gu'], context['schoolNameGujarati'],
    config['school_name_gu'], config['schoolNameGu'], config['school_name_gj'],
    config['gujarati_school_name'], config['name_gu'], config['schoolNameGujarati'],
  ]);
  if (gujarati.isNotEmpty) return gujarati;

  final english = firstNonEmpty(<dynamic>[
    context['school_name_en'], context['school_name'], context['schoolName'],
    config['school_name_en'], config['schoolNameEn'], config['school_name'],
    config['schoolName'], config['name'], fallbackEnglish,
  ]);
  // Known school's English alias is mapped to the Gujarati name shown in the
  // original school leave template. Other schools should register their own
  // Gujarati name instead of receiving a guessed translation.
  final normalized = english.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (normalized.contains('daredkumar') || normalized.contains('daredkumaar')) {
    return 'દરેડ કુમાર શાળા';
  }
  if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(english)) return english;
  return 'શાળાનું ગુજરાતી નામ નોંધાયેલ નથી';
}
