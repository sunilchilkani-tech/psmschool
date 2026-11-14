import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Shared school-name language preference for report, leave and message exports.
/// The key deliberately matches the existing Hajari Patrak setting so all modules
/// on the same browser/device use one choice per school.
class SchoolNameLanguageService {
  SchoolNameLanguageService._();

  static const String gujarati = 'gu';
  static const String english = 'en';
  static const String _keyPrefix = 'hajari_patrak_school_name_language_';

  static String preferenceKey(String schoolRef) => '$_keyPrefix${schoolRef.trim()}';

  static Future<String> loadLanguage({required String schoolRef}) async {
    if (schoolRef.trim().isEmpty) return gujarati;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(preferenceKey(schoolRef)) == english ? english : gujarati;
    } catch (_) {
      return gujarati;
    }
  }

  static Future<void> saveLanguage({required String schoolRef, required String language}) async {
    final ref = schoolRef.trim();
    if (ref.isEmpty || !const <String>{gujarati, english}.contains(language)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey(ref), language);
  }

  static Future<String> currentSchoolRef(SupabaseClient client) async {
    try {
      final value = await client.rpc('current_school_ref');
      return (value ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, dynamic>> loadCurrentSchoolContext(SupabaseClient client) async {
    try {
      final value = await client.rpc('psm_library_school_context');
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      if (value is List && value.isNotEmpty && value.first is Map) {
        final row = value.first as Map;
        return row.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Older deployments may not provide this RPC; caller profile is still used.
    }
    return <String, dynamic>{};
  }

  static String resolveSchoolName({
    required String language,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? schoolContext,
    Map<String, dynamic>? schoolConfig,
    String fallbackEnglish = 'School',
  }) {
    final p = profile ?? const <String, dynamic>{};
    final c = schoolContext ?? const <String, dynamic>{};
    final cfg = schoolConfig ?? const <String, dynamic>{};
    String first(Iterable<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    final gu = first(<dynamic>[
      c['school_name_gu'], c['schoolNameGu'], c['school_name_gj'],
      c['gujarati_school_name'], c['name_gu'], c['schoolNameGujarati'],
      p['school_name_gu'], p['schoolNameGu'], p['school_name_gj'],
      p['gujarati_school_name'], p['name_gu'], p['schoolNameGujarati'],
      cfg['school_name_gu'], cfg['schoolNameGu'], cfg['school_name_gj'],
      cfg['gujarati_school_name'], cfg['name_gu'], cfg['schoolNameGujarati'],
    ]);
    final en = first(<dynamic>[
      c['school_name_en'], c['schoolNameEn'], c['school_name'], c['schoolName'], c['name'],
      p['school_name_en'], p['schoolNameEn'], p['school_name'], p['schoolName'], p['name'],
      cfg['school_name_en'], cfg['schoolNameEn'], cfg['school_name'], cfg['schoolName'], cfg['name'],
      fallbackEnglish,
    ]);
    if (language == gujarati && gu.isNotEmpty) return gu;
    return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : 'School');
  }
}
