import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

class SchoolModuleDefinition {
  const SchoolModuleDefinition({
    required this.key,
    required this.group,
    required this.titleEn,
    required this.titleGu,
    required this.subtitle,
  });

  final String key;
  final String group;
  final String titleEn;
  final String titleGu;
  final String subtitle;

  String get displayTitle => '$titleEn / $titleGu';
}

/// Central registry of all school modules controllable per school by the Developer.
/// Uses a `disabled_modules` blacklist on `schools/{schoolRef}` so that:
/// 1. By default (`disabled_modules` empty/absent), all modules are enabled.
/// 2. Any newly added module in future versions is automatically enabled by default.
/// 3. The Developer can allow all modules, only 1, 2, 3, or any custom combination per school.
class SchoolModuleRegistry {
  SchoolModuleRegistry._();

  static const List<(String, String)> groups = <(String, String)>[
    ('daily', 'દૈનિક કામ / Daily Work'),
    ('students', 'વિદ્યાર્થી અને પરિણામ / Students & Results'),
    ('admin', 'શાળા સંચાલન / School Administration'),
    ('tools', 'સાધનો / Tools'),
  ];

  static const List<SchoolModuleDefinition> allModules = <SchoolModuleDefinition>[
    // Daily Work
    SchoolModuleDefinition(
      key: 'attendance',
      group: 'daily',
      titleEn: 'Attendance Entry',
      titleGu: 'દૈનિક હાજરી નોંધણી',
      subtitle: 'દૈનિક હાજરી, PM POSHAN અને અલ્પાહાર નોંધણી.',
    ),
    SchoolModuleDefinition(
      key: 'reports',
      group: 'daily',
      titleEn: 'Attendance Reports',
      titleGu: 'હાજરી અહેવાલ',
      subtitle: 'Datewise, Class-wise, TARIJ, MDM EKANDAR અને વર્ગ ઇતિહાસ.',
    ),
    SchoolModuleDefinition(
      key: 'hajari_patrak',
      group: 'daily',
      titleEn: 'Hajari Patrak',
      titleGu: 'હાજરીપત્રક',
      subtitle: 'માસિક મુખપૃષ્ઠ, કોરું અને ભરેલું હાજરીપત્રક.',
    ),
    SchoolModuleDefinition(
      key: 'parent_message',
      group: 'daily',
      titleEn: 'Parent Message',
      titleGu: 'વાલી સંદેશ',
      subtitle: 'વિદ્યાર્થી હાજરી % અને ગુજરાતી WhatsApp સંદેશ ડ્રાફ્ટ.',
    ),
    SchoolModuleDefinition(
      key: 'most_present',
      group: 'daily',
      titleEn: 'Most Present Students',
      titleGu: 'સૌથી વધુ હાજર વિદ્યાર્થી',
      subtitle: 'અઠવાડિક, માસિક, ત્રિમાસિક કે વાર્ષિક સૌથી વધુ હાજર.',
    ),
    SchoolModuleDefinition(
      key: 'leave',
      group: 'daily',
      titleEn: 'Teacher Leave',
      titleGu: 'રજા અરજી અને રિપોર્ટ',
      subtitle: 'શિક્ષક રજા અરજી, રજા ચાર્જ અને રિપોર્ટ.',
    ),
    SchoolModuleDefinition(
      key: 'library',
      group: 'daily',
      titleEn: 'Library Register',
      titleGu: 'પુસ્તકાલય રજીસ્ટર',
      subtitle: 'પુસ્તક આપ-લે, રજીસ્ટ્રેશન અને Excel રિપોર્ટ.',
    ),
    // Students & Results
    SchoolModuleDefinition(
      key: 'student_search',
      group: 'students',
      titleEn: 'Global Student Search',
      titleGu: 'વિદ્યાર્થી ગ્લોબલ સર્ચ',
      subtitle: 'સમગ્ર શાળા કે વર્ગના વિદ્યાર્થીની શોધ અને વિગત સુધારા.',
    ),
    SchoolModuleDefinition(
      key: 'student_management',
      group: 'students',
      titleEn: 'Student Management',
      titleGu: 'વિદ્યાર્થી વ્યવસ્થાપન',
      subtitle: 'વિદ્યાર્થી રેકોર્ડ, વર્ગ અને Excel અપલોડ ટૂલ્સ.',
    ),
    SchoolModuleDefinition(
      key: 'result',
      group: 'students',
      titleEn: 'Result Register',
      titleGu: 'પરિણામ પત્રક',
      subtitle: 'સત્રવાર ગુણ એન્ટ્રી, પરિણામ પત્રક અને પ્રગતિપત્રક.',
    ),
    SchoolModuleDefinition(
      key: 'result_summary',
      group: 'students',
      titleEn: 'Whole School Result Summary',
      titleGu: 'સમગ્ર શાળાનું પરિણામ સારાંશ',
      subtitle: 'ત્રણેય ફોર્મેટ (Class-Section, Category-Grade, Whole School) + Top 3 Ranker.',
    ),
    SchoolModuleDefinition(
      key: 'bonafide',
      group: 'students',
      titleEn: 'Bonafide Certificate',
      titleGu: 'બોનાફાઈડ પ્રમાણપત્ર',
      subtitle: 'વિદ્યાર્થી ડેટાબેઝમાંથી બોનાફાઈડ પ્રમાણપત્ર.',
    ),
    SchoolModuleDefinition(
      key: 'leaving_certificate',
      group: 'students',
      titleEn: 'Leaving Certificate (LC)',
      titleGu: 'શાળા છોડ્યાનું પ્રમાણપત્ર (LC)',
      subtitle: 'LC જનરેશન અને પ્રિન્ટ.',
    ),
    SchoolModuleDefinition(
      key: 'id_card',
      group: 'students',
      titleEn: 'ID Card Studio',
      titleGu: 'ઓળખપત્ર સ્ટુડિયો',
      subtitle: 'ડેટાબેઝ અથવા Excel માંથી ઓળખપત્ર ડિઝાઇન.',
    ),
    SchoolModuleDefinition(
      key: 'fln_workbook',
      group: 'students',
      titleEn: 'FLN 130 Question Paper',
      titleGu: 'FLN ૧૩૦ પ્રશ્નપત્ર / વર્કબુક',
      subtitle: 'ધોરણવાર FLN ગણિત પ્રશ્નપત્ર અને જવાબવહી (PDF).',
    ),
    // School Administration
    SchoolModuleDefinition(
      key: 'daily_dashboard',
      group: 'admin',
      titleEn: 'Daily Attendance Dashboard',
      titleGu: 'દૈનિક હાજરી ડેશબોર્ડ અને WhatsApp રીમાઈન્ડર',
      subtitle: 'લાઈવ દૈનિક હાજરી સ્ટેટસ અને બાકી વર્ગ ૧-ક્લિક WhatsApp રીમાઈન્ડર.',
    ),
    SchoolModuleDefinition(
      key: 'rojmel',
      group: 'admin',
      titleEn: 'Rojmel & Audit',
      titleGu: 'રોજમેળ અને સરકારી ઓડિટ',
      subtitle: 'કેશબુક, ગ્રાન્ટ હેડ અને ૨૧ સરકારી ઓડિટ રિપોર્ટ.',
    ),
    SchoolModuleDefinition(
      key: 'attendance_permission',
      group: 'admin',
      titleEn: 'Teacher Attendance Permission (4 Modes)',
      titleGu: 'હાજરી પૂરવાની પરવાનગી (૪ વિકલ્પ)',
      subtitle: 'વર્ગ શિક્ષક, વિભાગવાર, વિષય શિક્ષક કે કોઈપણ શિક્ષક (+ રજા ચાર્જ).',
    ),
    SchoolModuleDefinition(
      key: 'admin_panel',
      group: 'admin',
      titleEn: 'Admin Centre (Admin Panel)',
      titleGu: 'શાળા સંચાલન (Admin Panel)',
      subtitle: 'લોગો, સંદેશ, રજા મંજૂરી, હોલિડે અને બેકઅપ.',
    ),
    SchoolModuleDefinition(
      key: 'classes_teachers',
      group: 'admin',
      titleEn: 'Classes & Teachers',
      titleGu: 'વર્ગ અને શિક્ષક વ્યવસ્થાપન',
      subtitle: 'વર્ગ અને શિક્ષક ખાતા બનાવવા અને વર્ગ ફાળવણી.',
    ),
    SchoolModuleDefinition(
      key: 'timetable',
      group: 'admin',
      titleEn: 'Timetable Studio',
      titleGu: 'સમયપત્રક',
      subtitle: 'ઝીરો-ક્લેશ ઓટોમેટિક અને એડિટેબલ શાળા સમયપત્રક.',
    ),
    SchoolModuleDefinition(
      key: 'exam_planner',
      group: 'admin',
      titleEn: 'Exam Planner',
      titleGu: 'પરીક્ષા આયોજન',
      subtitle: 'પરીક્ષા સમયપત્રક, બેઠક વ્યવસ્થા, સુપરવિઝન અને રજીસ્ટર.',
    ),
    // Tools
    SchoolModuleDefinition(
      key: 'print_merge',
      group: 'tools',
      titleEn: 'Print Merge Studio',
      titleGu: 'પ્રિન્ટ મર્જ સ્ટુડિયો',
      subtitle: 'Excel / CSV લિસ્ટમાંથી પ્રમાણપત્રો અને કાર્ડ PDF.',
    ),
    SchoolModuleDefinition(
      key: 'file_beam',
      group: 'tools',
      titleEn: 'FileBeam Pro',
      titleGu: 'ફાઈલ અને ટેક્સ્ટ શેર',
      subtitle: 'મોબાઈલ અને PC વચ્ચે સીધી ફાઈલ અને ગુજરાતી ટેક્સ્ટ શેર.',
    ),
    SchoolModuleDefinition(
      key: 'low_attendance_alerts',
      group: 'daily',
      titleEn: 'Low-Attendance Alerts',
      titleGu: 'સતત ગેરહાજર / ઓછી હાજરી યાદી',
      subtitle: '૩+ સતત ગેરહાજર, ૭૫% થી ઓછી હાજરી, વાલી WhatsApp અને Excel ડાઉનલોડ.',
    ),
    SchoolModuleDefinition(
      key: 'pm_poshan_menu',
      group: 'daily',
      titleEn: 'Weekly PM POSHAN & Breakfast Menu',
      titleGu: 'સાપ્તાહિક PM POSHAN અને અલ્પાહાર મેનુ',
      subtitle: 'સોમ થી શનિનું વાનગી અને સામગ્રી-જથ્થા સાથેનું મેનુ અને દૈનિક પોપઅપ.',
    ),
    SchoolModuleDefinition(
      key: 'academic_calendar',
      group: 'admin',
      titleEn: 'Academic Calendar & Reminders',
      titleGu: 'શૈક્ષણિક કેલેન્ડર અને પરિપત્ર રીમાઈન્ડર',
      subtitle: 'પરીક્ષા, PTM, SMC સભા અને સરકારી ડેડલાઈનનું શાળા કેલેન્ડર.',
    ),
    SchoolModuleDefinition(
      key: 'textbook_issue_register',
      group: 'students',
      titleEn: 'Textbook Issue Register',
      titleGu: 'પાઠ્યપુસ્તક વિતરણ રજીસ્ટર',
      subtitle: 'વિદ્યાર્થી/વાલી સહી સાથેનું પાઠ્યપુસ્તક વિતરણ પહોંચ પ્રિન્ટ / PDF.',
    ),
  ];

  static final Set<String> allKnownKeys =
      allModules.map((m) => m.key).toSet();

  static List<String> normalizeDisabledList(dynamic raw) {
    if (raw is! Iterable) return const <String>[];
    final out = <String>{};
    for (final item in raw) {
      final key = '${item ?? ''}'.trim().toLowerCase();
      if (key.isNotEmpty && allKnownKeys.contains(key)) {
        out.add(key);
      }
    }
    final sorted = out.toList()..sort();
    return sorted;
  }

  static Set<String> extractDisabledModules(
    Map<String, dynamic>? primary, [
    Map<String, dynamic>? fallback,
  ]) {
    if (primary != null &&
        (primary.containsKey('disabled_modules') ||
            primary.containsKey('disabledModules'))) {
      final raw = primary['disabled_modules'] ?? primary['disabledModules'];
      return normalizeDisabledList(raw).toSet();
    }
    if (fallback != null &&
        (fallback.containsKey('disabled_modules') ||
            fallback.containsKey('disabledModules'))) {
      final raw = fallback['disabled_modules'] ?? fallback['disabledModules'];
      return normalizeDisabledList(raw).toSet();
    }
    return const <String>{};
  }

  static bool isModuleEnabled(
    String moduleKey, {
    Map<String, dynamic>? schoolContext,
    Map<String, dynamic>? profile,
    bool developerShowAll = false,
  }) {
    if (developerShowAll) return true;
    final key = moduleKey.trim().toLowerCase();
    if (key.isEmpty) return true;
    final disabled = extractDisabledModules(schoolContext, profile);
    return !disabled.contains(key);
  }
}

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
      cfg['school_name_en'], cfg['school_name_en'], cfg['school_name'], cfg['schoolName'], cfg['name'],
      fallbackEnglish,
    ]);
    if (language == gujarati && gu.isNotEmpty) return gu;
    return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : 'School');
  }
}
