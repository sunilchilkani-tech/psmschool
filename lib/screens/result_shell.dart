import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../data/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/supabase_result_api_service.dart';
import '../services/supabase_class_service.dart';
import '../services/supabase_hajari_patrak_service.dart';
import '../services/result_xlsx_template_exporter.dart';
import '../services/template_print/print_page.dart';
import '../services/template_print/template_print_plans.dart';
import '../services/template_print/template_print_service.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialogs.dart';
import 'setup_screen.dart';
import '../services/certificate_service.dart';
import 'package:pmshri_attendance/services/class_label.dart';
import '../theme/responsive.dart';

class _GradeRuleEditor {
  _GradeRuleEditor({required String label, required String minimumPercent})
      : labelController = TextEditingController(text: label),
        percentController = TextEditingController(text: minimumPercent);

  final TextEditingController labelController;
  final TextEditingController percentController;

  void dispose() {
    labelController.dispose();
    percentController.dispose();
  }
}

class _MaxMarkInputFormatter extends TextInputFormatter {
  _MaxMarkInputFormatter({
    required this.max,
    required this.onExceeded,
  });

  final int max;
  final void Function(int attempted, int max) onExceeded;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.trim();
    if (text.isEmpty) return newValue;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return oldValue;
    if (parsed > max) {
      onExceeded(parsed, max);
      return oldValue;
    }
    return newValue;
  }
}

class ResultShell extends StatefulWidget {
  const ResultShell({super.key});

  @override
  State<ResultShell> createState() => _ResultShellState();
}

class _ResultShellState extends State<ResultShell> {
  static const String kSubjectVV = 'વ્યક્તિત્વ વિકાસ';
  String _domainLabelForSentenceIndex(int idx) {
    if (idx < 8) return 'ક્ષેત્ર-૧: વ્યક્તિગત અને સામાજિક ગુણો';
    if (idx < 14) return 'ક્ષેત્ર-૨: વિદ્યાર્થીનાં વલણો';
    if (idx < 18) return 'ક્ષેત્ર-૩: સાહિત્ય';
    if (idx < 23) return 'ક્ષેત્ર-૩: સંગીત અને કલા';
    if (idx < 28) return 'ક્ષેત્ર-૩: શારીરિક શિક્ષણ અને યોગ';
    if (idx < 31) return 'ક્ષેત્ર-૩: સાંસ્કૃતિક કાર્યક્રમ';
    if (idx < 35) return 'ક્ષેત્ર-૪: સહશૈક્ષણિક પ્રવૃત્તિ';
    return 'ક્ષેત્ર-૪: કાર્યાનુભવ';
  }

  Future<void> _openEdit40SentencesDialog() async {
    final controllers = List<TextEditingController>.generate(
      40,
      (i) => TextEditingController(text: _vvSentences[i]),
    );

    final savedList = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          // Wrap (not a Row): the reset button drops below the title on phones.
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                  '✏️ વ્યક્તિત્વ વિકાસના 40 વિધાનો બદલો ($_cleanClassCode)',
                  style: guFont(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy),
                ),
              TextButton.icon(
                onPressed: () {
                  for (int i = 0; i < 40; i++) {
                    controllers[i].text = kVv40Sentences[i];
                  }
                },
                icon: const Icon(Icons.restore, size: 18),
                label: Text('મૂળ વિધાનો (Default)',
                    style: guFont(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: 480,
            child: ListView.separated(
              itemCount: 40,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final showDomainBanner = i == 0 ||
                    _domainLabelForSentenceIndex(i) !=
                        _domainLabelForSentenceIndex(i - 1);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDomainBanner)
                      Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _domainLabelForSentenceIndex(i),
                          style: guFont(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.slateLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: guFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controllers[i],
                            style: guFont(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('રદ કરો (Cancel)',
                  style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            AppButton(
              label: '💾 40 વિધાનો સેવ કરો',
              background: AppColors.greenDeep,
              onPressed: () {
                final updated = List<String>.generate(
                  40,
                  (i) {
                    final t = controllers[i].text.trim();
                    return t.isEmpty ? kVv40Sentences[i] : t;
                  },
                );
                Navigator.pop(ctx, updated);
              },
            ),
          ],
        );
      },
    );

    for (final c in controllers) {
      c.dispose();
    }

    if (savedList == null || !mounted || _selectedClass == null) return;
    final state = context.read<AppState>();
    if (state.resultApi == null) return;

    setState(() {
      _vvSentences = savedList;
      _saving = true;
    });

    try {
      final res = await state.resultApi!.saveVvSentences(
        className: _selectedClass!,
        sentences: savedList,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertIsError = res['result'] != 'success';
        _alert = res['result'] == 'success'
            ? '✅ $_cleanClassCode ના બંને સત્રના વ્યક્તિત્વ વિકાસ પત્રકમાં 40 વિધાનો (C5:AP5) સેવ થઈ ગયા!'
            : '❌ ${res['message'] ?? 'સેવ કરવામાં ભૂલ'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertIsError = true;
        _alert = '❌ ભૂલ: $e';
      });
    }
  }

  /// 4 Main Tabs in Result Screen:
  /// 0 = ગુણ એન્ટ્રી (Marks Entry - Only Name + Selected Subject Marks)
  /// 1 = પસંદગી વિગત એન્ટ્રી (Selected Detail Mode - Only Name + Selected Field)
  /// 2 = સંપૂર્ણ વિગત (Edit All Details in Line with Sticky Name Column)
  /// 3 = નવો વિદ્યાર્થી ઉમેરો (Step-by-Step New Student Entry saved at bottom of Class Sheet)
  int _activeTab = 0;

  /// Selected Field in Tab 1 (Quick Detail Selection Mode)
  String _selectedDetailField = 'gr';

  static const Map<String, String> kDetailFieldModes = {
    'delete_student': '🗑️ વિદ્યાર્થી કાઢી નાખો (Delete Student)',
    'roll_name': '🔢 રોલ નંબર અને 👤 નામ સુધારો',
    'gr': '🔢 જનરલ રજીસ્ટર નંબર (GR No)',
    'dob': '🎂 જન્મ તારીખ (DD / MM / YYYY - Col D, E, F)',
    'present': '📅 હાજર દિવસો (Present Days)',
    'category': '🏷️ કેટેગરી પસંદગી (Col C: અ.જા. / અ.જ.જા. / બક્ષીપંચ / અન્ય)',
    'gender': '👧👦 લિંગ (Boys / Girls / Not set)',
    'uid_pen': '🆔 U.I.D. (Col G) અને PEN નંબર (Col H)',
    'parents': '👨‍👩‍👦 મોબાઈલ (I), પિતા (J), માતા (K), સરનામું (L)',
    'sem2_status': '🔄 સત્ર-૨ અભ્યાસ ચાલુ? (Col M: Yes / No - નામ કમી)',
    'divyang':
        '♿ દિવ્યાંગ વિદ્યાર્થી? (Col R: YES = 20% પાસિંગ / NO = 35% પાસિંગ)',
  };

  static const List<String> kCategoryOptions = [
    'અ.જા.',
    'અ.જ.જા.',
    'બક્ષીપંચ',
    'અન્ય',
  ];

  static const List<String> kVv40Sentences = [
    'શાળામાં નિયમિત આવે છે.',
    'પ્રાર્થના સંમેલનમાં નિયમિત સામેલ થાય છે.',
    'શાળાની સ્વચ્છતા જાળવે છે.',
    'બીજા વિદ્યાર્થીઓને મદદરૂપ થાય છે.',
    'સોંપેલું કાર્ય સારી રીતે કરે છે.',
    'કોઈપણ કાર્ય કરવામાં તત્પરતા દાખવે છે.',
    'નવીન બાબત ઉત્સાહપૂર્વક શીખે છે.',
    'દરેક કાર્યમાં સમયનું પાલન કરે છે.',
    'શિક્ષણ પ્રત્યે હકારાત્મક વલણ ધરાવે છે.',
    'શાળા મિલકતની જાળવણી રાખે છે.',
    'સહાધ્યાયી પ્રત્યે સહયોગ દાખવે છે.',
    'વ્યક્તિગત સ્વચ્છતા અને સુઘડતા જાળવે છે.',
    'પર્યાવરણની સમતુલા જાળવવામાં ઉપયોગી થાય છે.',
    'શિક્ષકનો આદર જાળવે છે.',
    'ઈતર વાંચન',
    'ભાષા શુદ્ધિ સાથેનું મરોડદાર અક્ષરલેખન',
    'મૌલિક વાર્તા કથન / વક્તવ્ય',
    'સર્જનાત્મક લેખન',
    'ગાન / વાદન (અભિનય, બાળગીત વગેરે)',
    'નાટ્ય / નૃત્ય / વેશભૂષા / અભિનય',
    'ચિત્રમાં રેખાંકન સ્પષ્ટ અને સુંદર કરે છે.',
    'ચિત્રમાં રંગપૂરણી સારી રીતે કરે છે.',
    'ચિટક કામ કરે છે.',
    'યૌગિક ક્રિયાઓ ઉત્સાહપૂર્વક કરે છે.',
    'સરળ આસનો ઉત્સાહપૂર્વક કરે છે.',
    'સાંઘિક રમતો કૌશલ્યપૂર્વક રમે છે.',
    'ખેલકૂદ અને જિમ્નાસ્ટિક ગતિમેળ અને લયબદ્ધ રીતે કરે છે.',
    'ઈનડોર રમત રમવામાં રસ ધરાવે છે.',
    'ઉત્સવ ઉજવણી',
    'વિશેષ દિન ઉજવણી',
    'કાર્યક્રમનું સંચાલન કરવામાં ઉત્સુકતા દાખવે છે.',
    'પ્રશ્નમંચ (ક્વિઝ) માં ભાગીદારી',
    'મૂલ્ય શિક્ષણની પ્રવૃત્તિમાં ભાગીદારી',
    'વિવિધ સ્પર્ધાઓ',
    'હસ્ત લિખિત અંકો બનાવવા, પ્રદર્શનમાં ભાગીદારી',
    'ઈકો ક્લબની પ્રવૃત્તિ',
    'પ્રવાસ પર્યટન / મુલાકાત',
    'માટીકામ / બાગકામ / શાળા સુશોભન',
    'કાગળકામ / ટી. એલ. એમ. નિર્માણમાં સહયોગ',
    'વડીલો, અશક્તો અને બિમાર વ્યક્તિને મદદરૂપ થાય',
  ];

  static const Map<String, String> kEntryCombinations = {
    'only_a': '1️⃣ માત્ર રચનાત્મક / પત્રક A (40)',
    'only_s': '2️⃣ માત્ર સત્રાંત મૂલ્યાંકન (40)',
    'only_sw': '3️⃣ માત્ર સ્વ-અધ્યયન (20)',
    'a_s': '🔗 રચનાત્મક (40) + સત્રાંત (40) [80]',
    'a_sw': '🔗 રચનાત્મક (40) + સ્વ-અધ્યયન (20) [60]',
    's_sw': '🔗 સત્રાંત (40) + સ્વ-અધ્યયન (20) [60]',
    'all_3': '✅ ત્રણેય સાથે: રચનાત્મક + સત્રાંત + સ્વ-અધ્યયન (100)',
    'both_sem_all_6': '🌟 બંને સત્ર સાથે: સત્ર-૧ (100) + સત્ર-૨ (100) [200]',
  };

  String? _selectedClass;
  bool _classSelectionCorrectionPending = false;
  String _selectedSem = '1'; // '1', '2', or 'Annual'
  String? _selectedSubject;
  List<String> _assignedSubjects = <String>[];
  bool _isClassTeacher = false;
  String _entryCombo = 'all_3';
  bool _sem1DirectOutOf100 = false;

  String _classTeacherName = '';
  String _firstSemResultDate = '';
  String _resultDate = '';
  String _academicYear = '';

  String get _effectiveSecondSemResultDate => _resultDate.trim().isNotEmpty
      ? _resultDate.trim()
      : ResultSheetData.defaultSecondSemResultDateForNow();

  String get _effectiveFirstSemResultDate => _firstSemResultDate.trim().isNotEmpty
      ? _firstSemResultDate.trim()
      : ResultSheetData.defaultFirstSemResultDateForNow();

  String get _activeSemResultDate =>
      _selectedSem == '1' ? _effectiveFirstSemResultDate : _effectiveSecondSemResultDate;
  String _frontPageDistrict = '';
  String _frontPageEducationAuthority = '';
  String _frontPageVillage = '';
  String _frontPageTaluka = '';
  String _frontPagePayCenter = '';
  String _frontPageCrc = '';
  bool _savingFrontPageSettings = false;
  bool _showFrontPageSettings = false;
  int _frontPageSettingsRevision = 0;

  // Exact logo anchor dimensions from RESULT 2026-27.xlsx. The Semester-1
  // front-page logo is anchored in row 4 at 205.5 pt; Semester-2 uses 219.75 pt.
  static const double _excelSem1LogoRowHeight = 200.0;
  static const double _excelSem1LogoImageWidth = 270.0;
  static const double _excelSem1LogoImageHeight = 200.0;
  static const double _excelSem2LogoRowHeight = 200.0;
  static const double _excelSem2LogoImageWidth = 270.0;
  static const double _excelSem2LogoImageHeight = 200.0;

  String _schoolNameLanguage = 'gu';
  bool _schoolNameLanguageLoadStarted = false;
  bool _schoolBrandingLoaded = false;
  String _loadedSchoolRef = '';
  Map<String, dynamic> _registeredSchoolBranding = <String, dynamic>{};
  Uint8List? _schoolLogoBytes;
  pw.MemoryImage? _cachedSchoolLogo;

  Map<String, dynamic> get _schoolProfile => context.read<AppState>().school;

  Map<String, dynamic> get _brandingProfile => <String, dynamic>{
        ..._schoolProfile,
        ..._registeredSchoolBranding,
      };

  String _brandText(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  String get _schoolDisplayName {
    final p = _brandingProfile;
    final englishName = _brandText(p['school_name_en']).isNotEmpty
        ? _brandText(p['school_name_en'])
        : _brandText(p['schoolNameEn']).isNotEmpty
            ? _brandText(p['schoolNameEn'])
            : _brandText(p['school_name'] ?? p['schoolName'] ?? p['name']);
    final gujaratiName = _brandText(p['school_name_gu']).isNotEmpty
        ? _brandText(p['school_name_gu'])
        : _brandText(p['schoolNameGu']).isNotEmpty
            ? _brandText(p['schoolNameGu'])
            : _brandText(p['gujaratiSchoolName'] ?? p['name_gu']);
    if (_schoolNameLanguage == 'gu' && gujaratiName.isNotEmpty)
      return gujaratiName;
    if (_schoolNameLanguage == 'en' && englishName.isNotEmpty)
      return englishName;
    return gujaratiName.isNotEmpty
        ? gujaratiName
        : (englishName.isNotEmpty ? englishName : 'School Management');
  }

  String get _schoolDiseCode {
    final p = _brandingProfile;
    for (final key in const <String>[
      'dise_number',
      'school_dise_code',
      'schoolDiseCode',
      'dise_code',
      'udise_number',
      'school_id'
    ]) {
      final value = _brandText(p[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String get _schoolNameLanguagePreferenceKey {
    final p = _schoolProfile;
    final schoolRef = _loadedSchoolRef.isNotEmpty
        ? _loadedSchoolRef
        : (p['schoolRef'] ?? p['school_ref'] ?? '').toString().trim();
    return schoolRef.isEmpty
        ? ''
        : 'hajari_patrak_school_name_language_$schoolRef';
  }

  Future<void> _loadSchoolNameLanguage() async {
    if (_schoolNameLanguageLoadStarted) return;
    final key = _schoolNameLanguagePreferenceKey;
    if (key.isEmpty) return;
    _schoolNameLanguageLoadStarted = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(key) ?? 'gu';
      if (mounted)
        setState(() => _schoolNameLanguage = saved == 'en' ? 'en' : 'gu');
    } catch (_) {}
  }

  Future<void> _changeSchoolNameLanguage(String? value) async {
    if (value == null || (value != 'gu' && value != 'en')) return;
    final key = _schoolNameLanguagePreferenceKey;
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'School reference is not available; language preference was not saved.')));
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
      if (!mounted) return;
      setState(() => _schoolNameLanguage = value);
      final p = _brandingProfile;
      final gujaratiName =
          _brandText(p['school_name_gu'] ?? p['schoolNameGu'] ?? p['name_gu']);
      if (value == 'gu' && gujaratiName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'આ શાળાનું ગુજરાતી નામ નોંધાયેલું નથી. Developer Panel માં ગુજરાતી નામ ઉમેરો.'),
          duration: Duration(seconds: 6),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('School name language save failed: $error')));
    }
  }

  String _normalizeResultSchoolType(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.contains('coed') ||
        raw.contains('co-ed') ||
        raw.contains('co_educational') ||
        raw.contains('mixed') ||
        raw.contains('મિશ્ર')) {
      return 'coed';
    }
    if (raw.contains('girl') || raw.contains('કન્યા')) return 'girls';
    if (raw.contains('boy') || raw.contains('કુમાર')) return 'boys';
    return '';
  }

  String get _resultSchoolType {
    final appType =
        _normalizeResultSchoolType(context.read<AppState>().schoolType);
    if (appType.isNotEmpty) return appType;
    final profileType = _normalizeResultSchoolType(
      _brandingProfile['school_type'] ??
          _brandingProfile['schoolType'] ??
          _brandingProfile['school_type_gu'],
    );
    // A missing/legacy type should retain both genders instead of silently
    // dropping girls or boys from the class-wise Tarij summary.
    return profileType.isNotEmpty ? profileType : 'coed';
  }

  String get _frontPageLocationLine {
    final parts = <String>[];
    if (_frontPageVillage.trim().isNotEmpty) {
      parts.add('ગામ :- ${_frontPageVillage.trim()}');
    }
    if (_frontPageTaluka.trim().isNotEmpty) {
      parts.add('તાલુકો :- ${_frontPageTaluka.trim()}');
    }
    if (_frontPageDistrict.trim().isNotEmpty) {
      parts.add('જિલ્લો :- ${_frontPageDistrict.trim()}');
    }
    return parts.isEmpty
        ? _schoolLocationLine
        : parts.join('        |        ');
  }

  String get _schoolLocationLine {
    final p = _brandingProfile;
    final address = _schoolNameLanguage == 'gu'
        ? _brandText(
            p['school_address_gu'] ?? p['schoolAddressGu'] ?? p['address_gu'])
        : _brandText(
            p['school_address_en'] ?? p['schoolAddressEn'] ?? p['address_en']);
    if (address.isNotEmpty) return address.replaceAll(RegExp(r'\s+'), ' ');
    final alternateAddress = _schoolNameLanguage == 'gu'
        ? _brandText(
            p['school_address_en'] ?? p['schoolAddressEn'] ?? p['address_en'])
        : _brandText(
            p['school_address_gu'] ?? p['schoolAddressGu'] ?? p['address_gu']);
    if (alternateAddress.isNotEmpty)
      return alternateAddress.replaceAll(RegExp(r'\s+'), ' ');
    final parts = <String>[];
    final village = _brandText(p['village']);
    final taluka = _brandText(p['taluka']);
    final district = _brandText(p['district']);
    if (village.isNotEmpty) parts.add('ગામ :- $village');
    if (taluka.isNotEmpty) parts.add('તાલુકો :- $taluka');
    if (district.isNotEmpty) parts.add('જિલ્લો :- $district');
    return parts.join('        |        ');
  }

  String get _reportCardAddressLine {
    final p = _brandingProfile;
    final guAddr = _brandText(
      p['school_address_gu'] ?? p['schoolAddressGu'] ?? p['address_gu'],
    );
    if (guAddr.isNotEmpty) return guAddr.replaceAll(RegExp(r'\s+'), ' ');
    final enAddr = _brandText(
      p['school_address_en'] ?? p['schoolAddressEn'] ?? p['address_en'],
    );
    if (enAddr.isNotEmpty && _gujaratiCharRegex.hasMatch(enAddr)) {
      return enAddr.replaceAll(RegExp(r'\s+'), ' ');
    }
    final parts = <String>[];
    final v = _frontPageVillage.trim().isNotEmpty
        ? _frontPageVillage.trim()
        : _brandText(p['village']);
    final t = _frontPageTaluka.trim().isNotEmpty
        ? _frontPageTaluka.trim()
        : _brandText(p['taluka']);
    final d = _frontPageDistrict.trim().isNotEmpty
        ? _frontPageDistrict.trim()
        : _brandText(p['district']);
    if (v.isNotEmpty) parts.add('મુ. $v');
    if (t.isNotEmpty) parts.add('તાલુકો - $t');
    if (d.isNotEmpty) parts.add('જિલ્લો - $d');
    if (parts.isNotEmpty) return parts.join(', ');
    return enAddr.replaceAll(RegExp(r'\s+'), ' ');
  }

  String get _reportCardPlaceName {
    final p = _brandingProfile;
    final guAddr = _brandText(
      p['school_address_gu'] ?? p['schoolAddressGu'] ?? p['address_gu'],
    );
    final muMatch = RegExp(r'મુ\.?\s*([^,|]+)').firstMatch(guAddr);
    if (muMatch != null) {
      final candidate = muMatch.group(1)!.trim();
      if (candidate.isNotEmpty) return candidate;
    }
    final v = _frontPageVillage.trim().isNotEmpty
        ? _frontPageVillage.trim()
        : _brandText(p['village']);
    if (v.isNotEmpty) {
      return v
          .replaceFirst(RegExp(r'^(ગામ\s*:-?\s*|મુ\.?\s*)'), '')
          .split('|')
          .first
          .trim();
    }
    return _schoolDisplayName;
  }

  String get _reportCardAuthorityLine {
    if (_frontPageEducationAuthority.trim().isNotEmpty) {
      return _frontPageEducationAuthority.trim();
    }
    final p = _brandingProfile;
    final auth = _brandText(
      p['education_authority'] ??
          p['educationAuthority'] ??
          p['front_page_education_authority'],
    );
    if (auth.isNotEmpty) return auth;
    final guAddr = _brandText(
      p['school_address_gu'] ?? p['schoolAddressGu'] ?? p['address_gu'],
    );
    final distMatch = RegExp(r'જિલ્લો\s*-?\s*([^,|]+)').firstMatch(guAddr);
    final dist = distMatch != null
        ? distMatch.group(1)!.trim()
        : (_frontPageDistrict.trim().isNotEmpty
            ? _frontPageDistrict.trim()
            : _brandText(p['district']));
    if (dist.isNotEmpty) {
      return '$dist જિલ્લા પંચાયત શિક્ષણ સમિતિ સંચાલિત';
    }
    return '';
  }

  static String _sectionToEnglishLetter(String rawSec) {
    final s = rawSec.trim();
    const guToEn = <String, String>{
      'અ': 'A',
      'બ': 'B',
      'ક': 'C',
      'ડ': 'D',
      'ઇ': 'E',
      'ઈ': 'F',
    };
    if (guToEn.containsKey(s)) return guToEn[s]!;
    return s.toUpperCase();
  }

  String get _shortClassWithSection {
    final selectedKey = (_selectedClass ?? '').trim();
    for (final klass in context.read<AppState>().allowedClasses) {
      if (klass.key == selectedKey) {
        final std = klass.standard.trim();
        final sec = _sectionToEnglishLetter(klass.section);
        if (std.isNotEmpty && sec.isNotEmpty) {
          return '$std - $sec';
        }
      }
    }
    final raw = _cleanClassCode.trim();
    if (raw.isEmpty) return '';
    final stripped = raw
        .replaceFirst(RegExp(r'^ધોરણ\s*-?\s*'), '')
        .replaceFirst(RegExp(r'^STD\.?\s*-?\s*', caseSensitive: false), '')
        .trim();
    final m = RegExp(r'^(\d{1,2})\s*[-_\s]\s*([A-Za-z\u0A80-\u0AFF]+)$')
        .firstMatch(stripped);
    if (m != null) {
      final std = m.group(1)!;
      final sec = _sectionToEnglishLetter(m.group(2)!);
      return sec.isNotEmpty ? '$std - $sec' : std;
    }
    final mKey = RegExp(r'^(?:CLASS[\s_-]*)?(\d{1,2})[\s_-]+([A-Za-z])$',
            caseSensitive: false)
        .firstMatch(selectedKey);
    if (mKey != null) {
      return '${mKey.group(1)!} - ${mKey.group(2)!.toUpperCase()}';
    }
    return stripped.isNotEmpty ? stripped : raw;
  }

  String get _reportCardGradeScaleText {
    final rules = _sortedGradeRules;
    if (rules.isEmpty) {
      return '80% કે તેથી વધારે = A ગ્રેડ     65% - 79.99% = B ગ્રેડ     50% - 64.99% = C ગ્રેડ     35% - 49.99% = D ગ્રેડ     35% થી ઓછા = E ગ્રેડ';
    }
    final parts = <String>[];
    for (var i = 0; i < rules.length; i++) {
      final label = _brandText(rules[i]['grade_label'] ?? rules[i]['label']);
      final minVal = _minimumPercent(rules[i]);
      final minStr = minVal.toStringAsFixed(minVal % 1 == 0 ? 0 : 2);
      if (i == 0) {
        parts.add('$minStr% કે તેથી વધારે = $label ગ્રેડ');
      } else if (i == rules.length - 1 && minVal == 0) {
        final prevMin = _minimumPercent(rules[i - 1]);
        final prevStr = prevMin.toStringAsFixed(prevMin % 1 == 0 ? 0 : 2);
        parts.add('$prevStr% થી ઓછા = $label ગ્રેડ');
      } else {
        final upper =
            (_minimumPercent(rules[i - 1]) - 0.01).clamp(0, 100).toDouble();
        parts.add('$minStr% - ${upper.toStringAsFixed(2)}% = $label ગ્રેડ');
      }
    }
    return parts.join('     ');
  }

  Future<Uint8List?> _normalizeLogoForPdf(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    if (isPng || isJpeg) return bytes;
    ui.Codec? codec;
    ui.Image? frameImage;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frameImage = frame.image;
      final data = await frameImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      return null;
    } finally {
      frameImage?.dispose();
      codec?.dispose();
    }
  }

  Future<void> _loadRegisteredSchoolBranding({bool force = false}) async {
    if (_schoolBrandingLoaded && !force) return;
    try {
      final client = Supabase.instance.client;
      var schoolRef = _brandText(
          _schoolProfile['school_ref'] ?? _schoolProfile['schoolRef']);
      if (schoolRef.isEmpty)
        schoolRef = _brandText(await client.rpc('current_school_ref'));
      if (schoolRef.isEmpty)
        throw StateError('Current school reference is unavailable.');

      Map<String, dynamic> schoolRow = <String, dynamic>{};
      try {
        final rawSchool = await client
            .from('schools')
            .select()
            .eq('id', schoolRef)
            .maybeSingle();
        if (rawSchool != null) schoolRow = Map<String, dynamic>.from(rawSchool);
      } catch (_) {}

      String logoPath = '';
      String logoDataUri = '';
      Map<String, dynamic> settingsConfig = <String, dynamic>{};
      try {
        final settingsRaw = await client
            .from('school_settings')
            .select('logo_path,logo_data_uri,config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        final settings = settingsRaw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(settingsRaw);
        logoPath = _brandText(settings['logo_path'] ?? settings['logo_url']);
        logoDataUri = _brandText(settings['logo_data_uri']);
        final rawConfig = settings['config'];
        if (rawConfig is Map) {
          settingsConfig =
              rawConfig.map((key, value) => MapEntry('$key', value));
        } else if (rawConfig is String && rawConfig.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(rawConfig);
            if (decoded is Map)
              settingsConfig =
                  decoded.map((key, value) => MapEntry('$key', value));
          } catch (_) {}
        }
      } catch (_) {}
      logoPath = logoPath.isNotEmpty
          ? logoPath
          : _brandText(settingsConfig['logo_path'] ??
              settingsConfig['logo_url'] ??
              schoolRow['logo_path'] ??
              schoolRow['logo_url']);
      // Older Admin Centre versions stored the printable address in school_settings.config.
      if (_brandText(schoolRow['school_address_gu'] ??
              schoolRow['schoolAddressGu'] ??
              schoolRow['address_gu'])
          .isEmpty) {
        final configuredAddress = _brandText(
            settingsConfig['school_address_gu'] ??
                settingsConfig['school_address'] ??
                settingsConfig['address']);
        if (configuredAddress.isNotEmpty)
          schoolRow['school_address_gu'] = configuredAddress;
      }
      if (_brandText(schoolRow['school_address_en'] ??
              schoolRow['schoolAddressEn'] ??
              schoolRow['address_en'])
          .isEmpty) {
        final configuredEnglishAddress = _brandText(
            settingsConfig['school_address_en'] ??
                settingsConfig['address_en']);
        if (configuredEnglishAddress.isNotEmpty)
          schoolRow['school_address_en'] = configuredEnglishAddress;
      }

      Uint8List? logoBytes;
      if (logoDataUri.startsWith('data:') && logoDataUri.contains(',')) {
        try {
          logoBytes = base64Decode(logoDataUri.split(',').last.trim());
        } catch (_) {
          logoBytes = null;
        }
      }
      if (logoBytes == null && logoPath.isNotEmpty) {
        try {
          if (logoPath.startsWith('https://') ||
              logoPath.startsWith('http://')) {
            final response = await http
                .get(Uri.parse(logoPath))
                .timeout(const Duration(seconds: 12));
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              logoBytes = Uint8List.fromList(response.bodyBytes);
            }
          } else {
            logoBytes = await client.storage
                .from('school-assets')
                .download(logoPath)
                .timeout(const Duration(seconds: 12));
          }
        } catch (_) {
          logoBytes = null;
        }
      }
      logoBytes = await _normalizeLogoForPdf(logoBytes);
      if (!mounted) return;
      setState(() {
        _loadedSchoolRef = schoolRef;
        _registeredSchoolBranding = schoolRow;
        _schoolLogoBytes = logoBytes;
        _cachedSchoolLogo =
            logoBytes == null ? null : pw.MemoryImage(logoBytes);
        _schoolBrandingLoaded = true;
      });
      await _loadSchoolNameLanguage();
    } catch (_) {
      _schoolBrandingLoaded = true;
      await _loadSchoolNameLanguage();
    }
  }

  bool _sem1Locked = false;
  bool _sem2Locked = false;
  bool get _isCurrentSemLocked => _isBothSemCombo
      ? (_sem1Locked || _sem2Locked)
      : (_selectedSem == '1' ? _sem1Locked : _sem2Locked);
  bool _loading = false;
  bool _saving = false;
  String? _alert;
  bool _alertIsError = false;

  List<String> _subjects = const [];
  List<String> _vvSentences = List<String>.from(kVv40Sentences);
  List<ResultStudentRow> _students = [];
  final Set<String> _sem2OnlySubjects = {};

  /// For Class 6 to 8: false = Enter सત્રાંત out of 40; true = Enter સત્રાંત out of 80 (auto-converts to full integer out of 40)
  bool _examEntryFrom80 = false;

  /// Teacher-customizable section max marks (Default: 40 + 40 + 20 = 100)
  int _maxPatrakA = 40;
  int _maxSatrant = 40;
  int _maxSwa = 20;
  int get _maxSubSemTotal => _maxPatrakA + _maxSatrant + _maxSwa;

  /// Teacher-customizable grade percentage thresholds (Default: 80=A, 65=B, 50=C, 35=D, <35=E)
  double _gradeAThreshold = 80;
  double _gradeBThreshold = 65;
  double _gradeCThreshold = 50;
  double _gradeDThreshold = 35;
  List<Map<String, dynamic>> _gradeRules = <Map<String, dynamic>>[
    <String, dynamic>{
      'grade_label': 'A',
      'minimum_percent': 80.0,
      'sort_order': 0
    },
    <String, dynamic>{
      'grade_label': 'B',
      'minimum_percent': 65.0,
      'sort_order': 1
    },
    <String, dynamic>{
      'grade_label': 'C',
      'minimum_percent': 50.0,
      'sort_order': 2
    },
    <String, dynamic>{
      'grade_label': 'D',
      'minimum_percent': 35.0,
      'sort_order': 3
    },
    <String, dynamic>{
      'grade_label': 'E',
      'minimum_percent': 0.0,
      'sort_order': 4
    },
  ];
  final List<_GradeRuleEditor> _gradeEditors = <_GradeRuleEditor>[];
  bool _gradeSettingsLoading = false;
  bool _gradeSettingsSaving = false;
  bool _gradeSettingsLoaded = false;
  String? _gradeSettingsError;

  // Step-by-Step New Student Entry Controllers (Tab 3)
  int _newStudentStep = 0;
  final _newRollCtrl = TextEditingController();
  final _newNameCtrl = TextEditingController();
  String _newCategory = 'બક્ષીપંચ';
  String _newGender = 'UNSPECIFIED';
  final _newGrCtrl = TextEditingController();
  final _newDdCtrl = TextEditingController();
  final _newMmCtrl = TextEditingController();
  final _newYyyyCtrl = TextEditingController();
  final _newUidCtrl = TextEditingController();
  final _newPenCtrl = TextEditingController();
  final _newMobileCtrl = TextEditingController();
  final _newFatherCtrl = TextEditingController();
  final _newMotherCtrl = TextEditingController();
  final _newAddressCtrl = TextEditingController();
  final _newPres1Ctrl = TextEditingController(text: '0');
  final _newPres2Ctrl = TextEditingController(text: '0');
  final _newStandardCtrl = TextEditingController();
  bool _newStudiedInSem2 = true;
  bool _newIsDivyang = false;

  bool _didInit = false;
  int _gridTick = 0;
  int _offlineDraftCount = 0;
  final Set<int> _modifiedStudents = {};
  final Map<int, Set<String>> _dirtyScopesByStudent = {};
  Timer? _localDraftTimer;
  bool _localDraftWriteInProgress = false;
  bool _localDraftWritePending = false;
  Completer<void>? _localDraftWriteCompleter;
  String _cachedLocalDraftKey = '';
  bool _resultExporting = false;
  bool _leavePresentDaysBlankInPrint = false;
  Map<String, int?> _printPresentDaysOverride = <String, int?>{};

  // Satrant Exam Date & Attendance / Absent (AB) state per (class, sem, subject)
  final Map<String, String> _subjectExamDates = <String, String>{};
  final Map<String, String> _subjectExamDateSources = <String, String>{};
  final Map<String, String> _subjectExamAttendanceModes = <String, String>{};
  final Set<String> _lateExamConfirmedStudentKeys = <String>{};
  DateTime? _lastMaxWarningAt;

  void _warnMaxMarkExceeded(int attempted, int max, {String? studentName}) {
    final now = DateTime.now();
    if (_lastMaxWarningAt != null &&
        now.difference(_lastMaxWarningAt!).inMilliseconds < 600) {
      return;
    }
    _lastMaxWarningAt = now;
    if (!mounted) return;
    final prefix = (studentName != null && studentName.trim().isNotEmpty)
        ? '"${studentName.trim()}" માટે '
        : '';
    showSnack(
      context,
      '⚠️ ${prefix}મહત્તમ ગુણ $max છે! "$attempted" ગુણ સ્વીકારવામાં આવશે નહીં ($max કે તેથી ઓછા ગુણ દાખલ કરો).',
      error: true,
    );
  }

  String _satrantExamKey(String subject, [String? semOverride]) {
    final sem = semOverride ?? (_selectedSem == 'Annual' ? '2' : _selectedSem);
    return '${_selectedClass ?? ""}_${sem}_${subject.trim()}';
  }

  String _satrantStdExamKey(String subject, [String? semOverride]) {
    final sem = semOverride ?? (_selectedSem == 'Annual' ? '2' : _selectedSem);
    return 'std_${_stdNumber}_${sem}_${subject.trim()}';
  }

  String _lookupSavedSatrantExamDate(String subject, [String? semOverride]) {
    final exactKey = _satrantExamKey(subject, semOverride);
    final stdKey = _satrantStdExamKey(subject, semOverride);
    final exactVal = (_subjectExamDates[exactKey] ?? '').trim();
    if (exactVal.isNotEmpty) return exactVal;
    final stdVal = (_subjectExamDates[stdKey] ?? '').trim();
    if (stdVal.isNotEmpty) {
      _subjectExamDates[exactKey] = stdVal;
      _subjectExamDateSources[exactKey] =
          _subjectExamDateSources[stdKey] ?? 'manual';
      return stdVal;
    }
    return '';
  }

  Future<void> _loadSavedSatrantExamDates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final client = Supabase.instance.client;
      var schoolRef = _loadedSchoolRef.trim();
      if (schoolRef.isEmpty) {
        schoolRef =
            (await client.rpc('current_school_ref') ?? '').toString().trim();
      }

      // 1. Load school-wide saved exam dates map from SharedPreferences
      final mapPrefKey =
          'psm_satrant_exam_dates_all_${schoolRef.isEmpty ? "default" : schoolRef}';
      final rawLocalMap = prefs.getString(mapPrefKey);
      if (rawLocalMap != null && rawLocalMap.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawLocalMap);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              final keyStr = '$k'.trim();
              final valStr = '$v'.trim();
              if (keyStr.isNotEmpty && valStr.isNotEmpty) {
                _subjectExamDates[keyStr] = valStr;
                _subjectExamDateSources.putIfAbsent(keyStr, () => 'manual');
              }
            });
          }
        } catch (_) {}
      }

      // 2. Load from Cloud school_settings.config['satrant_exam_dates']
      if (schoolRef.isNotEmpty) {
        final settingRow = await client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        final config = settingRow?['config'];
        Map<String, dynamic> configMap = <String, dynamic>{};
        if (config is Map) {
          configMap = config.map((k, v) => MapEntry('$k', v));
        } else if (config is String && config.trim().isNotEmpty) {
          try {
            final dec = jsonDecode(config);
            if (dec is Map) {
              configMap = dec.map((k, v) => MapEntry('$k', v));
            }
          } catch (_) {}
        }
        final cloudDates = configMap['satrant_exam_dates'];
        if (cloudDates is Map) {
          cloudDates.forEach((k, v) {
            final keyStr = '$k'.trim();
            final valStr = '$v'.trim();
            if (keyStr.isNotEmpty && valStr.isNotEmpty) {
              _subjectExamDates[keyStr] = valStr;
              _subjectExamDateSources[keyStr] = 'manual';
            }
          });
          await prefs.setString(mapPrefKey, jsonEncode(_subjectExamDates));
        }
      }

      // 3. Also check per-subject keys in SharedPreferences for current class & standard
      for (final sub in _subjects) {
        for (final sem in const <String>['1', '2']) {
          final exactKey = _satrantExamKey(sub, sem);
          final stdKey = _satrantStdExamKey(sub, sem);
          final pExact =
              (prefs.getString('psm_satrant_exam_date_$exactKey') ?? '').trim();
          final pStd =
              (prefs.getString('psm_satrant_exam_date_$stdKey') ?? '').trim();
          final resolved = pExact.isNotEmpty
              ? pExact
              : pStd.isNotEmpty
                  ? pStd
                  : (_subjectExamDates[exactKey] ??
                      _subjectExamDates[stdKey] ??
                      '');
          if (resolved.isNotEmpty) {
            _subjectExamDates[exactKey] = resolved;
            _subjectExamDates[stdKey] = resolved;
            _subjectExamDateSources.putIfAbsent(exactKey, () => 'manual');
            _subjectExamDateSources.putIfAbsent(stdKey, () => 'manual');
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _persistSatrantExamDate({
    required String subject,
    required String targetSem,
    required String formattedDate,
    String source = 'manual',
  }) async {
    final exactKey = _satrantExamKey(subject, targetSem);
    final stdKey = _satrantStdExamKey(subject, targetSem);
    _subjectExamDates[exactKey] = formattedDate;
    _subjectExamDates[stdKey] = formattedDate;
    _subjectExamDateSources[exactKey] = source;
    _subjectExamDateSources[stdKey] = source;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('psm_satrant_exam_date_$exactKey', formattedDate);
      await prefs.setString('psm_satrant_exam_date_$stdKey', formattedDate);

      final client = Supabase.instance.client;
      var schoolRef = _loadedSchoolRef.trim();
      if (schoolRef.isEmpty) {
        schoolRef =
            (await client.rpc('current_school_ref') ?? '').toString().trim();
      }
      final mapPrefKey =
          'psm_satrant_exam_dates_all_${schoolRef.isEmpty ? "default" : schoolRef}';
      final mergedMap = <String, String>{};
      final existingRaw = prefs.getString(mapPrefKey);
      if (existingRaw != null && existingRaw.trim().isNotEmpty) {
        try {
          final dec = jsonDecode(existingRaw);
          if (dec is Map) {
            dec.forEach((k, v) => mergedMap['$k'] = '$v');
          }
        } catch (_) {}
      }
      mergedMap.addAll(_subjectExamDates);
      mergedMap[exactKey] = formattedDate;
      mergedMap[stdKey] = formattedDate;
      await prefs.setString(mapPrefKey, jsonEncode(mergedMap));

      if (schoolRef.isNotEmpty) {
        final existingRow = await client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        Map<String, dynamic> config = <String, dynamic>{};
        final rawCfg = existingRow?['config'];
        if (rawCfg is Map) {
          config = rawCfg.map((k, v) => MapEntry('$k', v));
        } else if (rawCfg is String && rawCfg.trim().isNotEmpty) {
          try {
            final dec = jsonDecode(rawCfg);
            if (dec is Map) {
              config = dec.map((k, v) => MapEntry('$k', v));
            }
          } catch (_) {}
        }
        final cloudDates = <String, String>{};
        if (config['satrant_exam_dates'] is Map) {
          (config['satrant_exam_dates'] as Map).forEach((k, v) {
            cloudDates['$k'] = '$v';
          });
        }
        cloudDates[exactKey] = formattedDate;
        cloudDates[stdKey] = formattedDate;
        config['satrant_exam_dates'] = cloudDates;
        await client.from('school_settings').upsert(
          <String, dynamic>{
            'school_ref': schoolRef,
            'config': config,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'school_ref',
        );
        FirestoreQueryBuilder.invalidateCache('school_settings');
      }
    } catch (_) {}
  }

  String _lateExamConfirmKey(String subject, String sem, ResultStudentRow st) {
    return '${_selectedClass ?? ""}_${sem}_${subject.trim()}_${_studentPrintKey(st)}';
  }

  String _toAsciiDigitsLocal(String input) {
    const gu = '૦૧૨૩૪૫૬૭૮૯';
    var out = input;
    for (var i = 0; i < gu.length; i++) {
      out = out.replaceAll(gu[i], '$i');
    }
    return out;
  }

  bool _timetableStdMatchesCurrentClass(String stdLabel, int classStd) {
    if (classStd <= 0) return true;
    final norm = _toAsciiDigitsLocal(stdLabel).trim();
    if (norm.isEmpty) return true;
    final rangeMatch = RegExp(
      r'(\d+)\s*(?:થી|to|[-–])\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(norm);
    if (rangeMatch != null) {
      final start = int.tryParse(rangeMatch.group(1)!) ?? 0;
      final end = int.tryParse(rangeMatch.group(2)!) ?? 0;
      if (start > 0 && end >= start) {
        return classStd >= start && classStd <= end;
      }
    }
    final digits = RegExp(r'\d+')
        .allMatches(norm)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>()
        .toList();
    if (digits.isNotEmpty) {
      return digits.contains(classStd);
    }
    return false;
  }

  bool _timetableSubjectMatches(String rowSubject, String selectedSubject) {
    String clean(String s) => s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.\s()_-]+'), '');
    final a = clean(rowSubject);
    final b = clean(selectedSubject);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if ((a.contains('સાવિજ્ઞાન') || a.contains('સામાજિક')) &&
        (b.contains('સાવિજ્ઞાન') || b.contains('સામાજિક'))) {
      return true;
    }
    if ((a.contains('પર્યાવરણ') || a.contains('આસપાસ')) &&
        (b.contains('પર્યાવરણ') || b.contains('આસપાસ'))) {
      return true;
    }
    if ((a == 'વિજ્ઞાન' || a.contains('વિજ્ઞાનઅનેટેકનોલોજી')) &&
        (b == 'વિજ્ઞાન' || b.contains('વિજ્ઞાનઅનેટેકનોલોજી')) &&
        !a.contains('સા') &&
        !b.contains('સા')) {
      return true;
    }
    return false;
  }

  Future<String?> _fetchExamDateFromTimetableForSubject(String subject) async {
    final classStd = _stdNumber;
    List<Map<String, dynamic>> extractRows(dynamic rawPlan) {
      if (rawPlan is! Map) return const <Map<String, dynamic>>[];
      final rawTt = rawPlan['timetableRows'];
      if (rawTt is! List) return const <Map<String, dynamic>>[];
      return rawTt
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry('$k', v)))
          .toList();
    }

    String? findMatchInRows(List<Map<String, dynamic>> rows) {
      // First pass: exact standard + subject match (distinguishing 3-5 vs 6-8)
      for (final row in rows) {
        final sub = (row['subject'] ?? '').toString().trim();
        final stdLbl = (row['stdLabel'] ?? '').toString().trim();
        final dt = _toAsciiDigitsLocal((row['date'] ?? '').toString().trim());
        if (dt.isEmpty) continue;
        if (_timetableSubjectMatches(sub, subject) &&
            _timetableStdMatchesCurrentClass(stdLbl, classStd)) {
          return dt;
        }
      }
      return null;
    }

    try {
      final client = Supabase.instance.client;
      final schoolRef =
          (await client.rpc('current_school_ref') ?? '').toString().trim();
      if (schoolRef.isNotEmpty) {
        final settingRow = await client
            .from('school_settings')
            .select('config')
            .eq('school_ref', schoolRef)
            .maybeSingle();
        final config = settingRow?['config'];
        if (config is Map) {
          final savedExam = config['planning_exam_planning'];
          final rows = extractRows(savedExam);
          final found = findMatchInRows(rows);
          if (found != null && found.isNotEmpty) return found;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final rawLocal = (schoolRef.isNotEmpty
              ? prefs.getString('psm_exam_planning_autosave_$schoolRef')
              : null) ??
          prefs.getString('psm_exam_planning_autosave_v1');
      if (rawLocal != null && rawLocal.trim().isNotEmpty) {
        final decoded = jsonDecode(rawLocal);
        final rows = extractRows(decoded);
        final found = findMatchInRows(rows);
        if (found != null && found.isNotEmpty) return found;
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseDmyDate(String raw) {
    final clean = _toAsciiDigitsLocal(raw).trim();
    final m = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(clean);
    if (m != null) {
      final d = int.tryParse(m.group(1)!) ?? 1;
      final mo = int.tryParse(m.group(2)!) ?? 1;
      final y = int.tryParse(m.group(3)!) ?? 2026;
      return DateTime(y, mo, d);
    }
    return DateTime.tryParse(clean);
  }

  String _formatDmy(DateTime dt) =>
      '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';

  String _formatIso(DateTime dt) =>
      '${dt.year.toString().padLeft(4, "0")}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';

  Future<void> _verifyAttendanceOnExamDate({
    required String subject,
    required String dateDmy,
    String? semOverride,
  }) async {
    if (_selectedClass == null || subject.isEmpty || subject == kSubjectVV) {
      return;
    }
    final dt = _parseDmyDate(dateDmy);
    if (dt == null) return;
    final dateIso = _formatIso(dt);
    final targetSem =
        semOverride ?? (_selectedSem == 'Annual' ? '2' : _selectedSem);
    final examKey = _satrantExamKey(subject, targetSem);

    try {
      final client = Supabase.instance.client;
      final schoolRef =
          (await client.rpc('current_school_ref') ?? '').toString().trim();
      final classId =
          await SupabaseClassService().resolveClassId(_selectedClass!);
      if (schoolRef.isEmpty || classId.isEmpty) return;

      final dayRow = await client
          .from('attendance_days')
          .select('id,attendance_date,attendance_mode,student_details_saved')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_date', dateIso)
          .maybeSingle();

      if (dayRow == null) {
        if (!mounted) return;
        setState(() {
          _subjectExamAttendanceModes[examKey] = 'direct';
          _gridTick++;
        });
        return;
      }

      final mode = (dayRow['attendance_mode'] ?? '').toString().toLowerCase();
      final detailsSaved = dayRow['student_details_saved'] == true ||
          const <String>{'true', 't', '1'}.contains(
            (dayRow['student_details_saved'] ?? '').toString().toLowerCase(),
          );

      if (mode == 'student' && detailsSaved) {
        final dayId = (dayRow['id'] ?? '').toString().trim();
        final marks = await client
            .from('student_attendance')
            .select('student_id,present')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .eq('attendance_day_id', dayId);
        final presentMap = <String, bool>{};
        for (final raw in marks) {
          final r = Map<String, dynamic>.from(raw);
          final sid = (r['student_id'] ?? '').toString().trim();
          final pres = r['present'] == true ||
              const <String>{'true', 't', '1'}
                  .contains((r['present'] ?? '').toString().toLowerCase());
          if (sid.isNotEmpty) presentMap[sid] = pres;
        }
        if (!mounted) return;
        var absentCount = 0;
        setState(() {
          _subjectExamAttendanceModes[examKey] = 'student';
          for (var i = 0; i < _students.length; i++) {
            final st = _students[i];
            if (targetSem != '1' && !st.studiedInSem2) continue;
            final sid = st.studentId.trim();
            if (sid.isEmpty || !presentMap.containsKey(sid)) continue;
            final wasPresent = presentMap[sid] == true;
            final semMap = targetSem == '1' ? st.sem1 : st.sem2;
            final current = semMap[subject] ?? const SubjectMarks();
            final confirmKey = _lateExamConfirmKey(subject, targetSem, st);
            if (!wasPresent) {
              absentCount++;
              // Only auto-set AB if teacher has not already confirmed late exam or entered >0 marks
              if (!_lateExamConfirmedStudentKeys.contains(confirmKey) &&
                  current.satrant == 0 &&
                  !current.satrantAbsent) {
                semMap[subject] = current.copyWith(
                  satrant: 0,
                  satrantAbsent: true,
                  clearDirectTotal: targetSem == '1',
                );
                _markModified(i);
              }
            }
          }
          _gridTick++;
        });
        if (mounted && absentCount > 0) {
          showSnack(
            context,
            '📋 તારીખ $dateDmy ની Student-wise હાજરી મુજબ $absentCount ગેરહાજર વિદ્યાર્થી(ઓ) ના સત્રાંત ગુણમાં "AB" સેટ થયું છે.',
          );
        }
      } else {
        if (!mounted) return;
        setState(() {
          _subjectExamAttendanceModes[examKey] = 'direct';
          _gridTick++;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subjectExamAttendanceModes[examKey] = 'direct';
        _gridTick++;
      });
    }
  }

  Future<void> _pickSubjectExamDate({
    required String subject,
    String? semOverride,
  }) async {
    final targetSem =
        semOverride ?? (_selectedSem == 'Annual' ? '2' : _selectedSem);
    final existingDmy = _lookupSavedSatrantExamDate(subject, targetSem);
    final initial = _parseDmyDate(existingDmy) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '"$subject" સત્રાંત પરીક્ષાની તારીખ પસંદ કરો',
    );
    if (picked == null || !mounted) return;
    final formatted = _formatDmy(picked);
    setState(() {
      final exactKey = _satrantExamKey(subject, targetSem);
      final stdKey = _satrantStdExamKey(subject, targetSem);
      _subjectExamDates[exactKey] = formatted;
      _subjectExamDates[stdKey] = formatted;
      _subjectExamDateSources[exactKey] = 'manual';
      _subjectExamDateSources[stdKey] = 'manual';
      _gridTick++;
    });
    await _persistSatrantExamDate(
      subject: subject,
      targetSem: targetSem,
      formattedDate: formatted,
      source: 'manual',
    );
    await _verifyAttendanceOnExamDate(
      subject: subject,
      dateDmy: formatted,
      semOverride: targetSem,
    );
  }

  Future<void> _resolveAndVerifySubjectExamDate({
    required String subject,
    bool promptIfMissing = false,
  }) async {
    if (_selectedClass == null ||
        subject.trim().isEmpty ||
        subject == kSubjectVV) {
      return;
    }
    final targetSem = _selectedSem == 'Annual' ? '2' : _selectedSem;
    final examKey = _satrantExamKey(subject, targetSem);
    final stdKey = _satrantStdExamKey(subject, targetSem);

    // 1. Check already loaded in memory (exact class key or standard key)
    final inMemory = _lookupSavedSatrantExamDate(subject, targetSem);
    if (inMemory.isNotEmpty) {
      await _verifyAttendanceOnExamDate(
        subject: subject,
        dateDmy: inMemory,
        semOverride: targetSem,
      );
      return;
    }

    // 2. Check saved manual date in Cloud & SharedPreferences first so teacher-saved date is never lost
    await _loadSavedSatrantExamDates();
    final afterLoad = _lookupSavedSatrantExamDate(subject, targetSem);
    if (afterLoad.isNotEmpty) {
      if (mounted) setState(() => _gridTick++);
      await _verifyAttendanceOnExamDate(
        subject: subject,
        dateDmy: afterLoad,
        semOverride: targetSem,
      );
      return;
    }

    // 3. Check Exam Planning Timetable (distinguishing Std 3-5 vs Std 6-8)
    final ttDate = await _fetchExamDateFromTimetableForSubject(subject);
    if (ttDate != null && ttDate.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _subjectExamDates[examKey] = ttDate;
        _subjectExamDates[stdKey] = ttDate;
        _subjectExamDateSources[examKey] = 'timetable';
        _subjectExamDateSources[stdKey] = 'timetable';
        _gridTick++;
      });
      await _persistSatrantExamDate(
        subject: subject,
        targetSem: targetSem,
        formattedDate: ttDate,
        source: 'timetable',
      );
      await _verifyAttendanceOnExamDate(
        subject: subject,
        dateDmy: ttDate,
        semOverride: targetSem,
      );
      return;
    }

    // 4. If not found in Timetable or saved preferences, ask teacher to pick Exam Date
    if (promptIfMissing && mounted && (_showS || _isBothSemCombo)) {
      final pickNow = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '📅 "$subject" સત્રાંત પરીક્ષા તારીખ',
            style: guFont(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navy),
          ),
          content: Text(
            'પરીક્ષા આયોજન (Exam Timetable) માં $_stdDisplayLabel માટે "$subject" વિષયની પરીક્ષા તારીખ મળી નથી.\n\nસત્રાંત પરીક્ષાના ગુણ દાખલ કરતા પહેલાં પરીક્ષાની તારીખ પસંદ કરો, જેથી તે તારીખે હાજર અને ગેરહાજર (AB) વિદ્યાર્થીઓ ચકાસી શકાય.',
            style: guFont(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text('પછીથી પસંદ કરો',
                  style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dCtx, true),
              icon: const Icon(Icons.calendar_month),
              label: Text('📅 પરીક્ષા તારીખ પસંદ કરો',
                  style: guFont(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ],
        ),
      );
      if (pickNow == true && mounted) {
        await _pickSubjectExamDate(subject: subject, semOverride: targetSem);
      }
    }
  }

  Future<bool> _confirmAndUnlockAbsentStudentSatrant({
    required int index,
    required ResultStudentRow st,
    required String sub,
    required String targetSem,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '⚠️ ગેરહાજર (AB) વિદ્યાર્થીના ગુણ દાખલ કરવા અંગે',
          style: guFont(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: AppColors.rose),
        ),
        content: Text(
          'વિદ્યાર્થી "${st.name}" સત્રાંત પરીક્ષામાં ગેરહાજર (AB) નોંધાયેલ છે.\n\nશું આ વિદ્યાર્થીએ પાછળથી પરીક્ષા આપી છે અને તમારે "${st.name}" ના સત્રાંત ગુણ દાખલ કરવા છે?',
          style: guFont(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('ના, AB જ રાખો',
                style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.greenDeep),
            onPressed: () => Navigator.pop(dCtx, true),
            icon: const Icon(Icons.check_circle_outline),
            label: Text('હા, ગુણ દાખલ કરો',
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(() {
      _markModified(index);
      _lateExamConfirmedStudentKeys
          .add(_lateExamConfirmKey(sub, targetSem, st));
      final semMap = targetSem == '1' ? st.sem1 : st.sem2;
      final current = semMap[sub] ?? const SubjectMarks();
      semMap[sub] = current.copyWith(
        satrantAbsent: false,
        clearDirectTotal: targetSem == '1',
      );
      _gridTick++;
    });
    return true;
  }

  Future<void> _toggleStudentSatrantAttendance({
    required int index,
    required ResultStudentRow st,
    required String sub,
    required String targetSem,
  }) async {
    final canEdit =
        (!_isCurrentSemLocked || context.read<AppState>().isAdmin) &&
            _canUseResultEntry;
    if (!canEdit) return;
    final semMap = targetSem == '1' ? st.sem1 : st.sem2;
    final current = semMap[sub] ?? const SubjectMarks();
    if (current.satrantAbsent) {
      // Currently Absent (AB) -> require confirmation with student name before making Present / allowing marks
      await _confirmAndUnlockAbsentStudentSatrant(
        index: index,
        st: st,
        sub: sub,
        targetSem: targetSem,
      );
    } else {
      // Currently Present -> tap makes student Absent (AB) in Satrant exam
      setState(() {
        _markModified(index);
        _lateExamConfirmedStudentKeys
            .remove(_lateExamConfirmKey(sub, targetSem, st));
        semMap[sub] = current.copyWith(
          satrant: 0,
          satrantAbsent: true,
          clearDirectTotal: targetSem == '1',
        );
        _gridTick++;
      });
    }
  }

  Widget _buildSatrantAttendanceBadge({
    required int index,
    required ResultStudentRow st,
    required String sub,
    required String targetSem,
    String? semPrefix,
  }) {
    final semMap = targetSem == '1' ? st.sem1 : st.sem2;
    final marks = semMap[sub] ?? const SubjectMarks();
    final isAb = marks.satrantAbsent;
    final prefix = semPrefix != null ? '$semPrefix: ' : '';
    return InkWell(
      onTap: () => _toggleStudentSatrantAttendance(
        index: index,
        st: st,
        sub: sub,
        targetSem: targetSem,
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: isAb ? AppColors.roseLight : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isAb ? AppColors.rose : AppColors.greenDeep,
            width: 1.2,
          ),
        ),
        child: Text(
          isAb ? '${prefix}🚫 ગેરહાજર (AB)' : '${prefix}✅ હાજર',
          textAlign: TextAlign.center,
          style: guFont(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: isAb ? AppColors.rose : AppColors.greenDeep,
          ),
        ),
      ),
    );
  }

  Widget _buildSatrantExamDateBar() {
    final sub = _selectedSubject ?? '';
    if (sub.isEmpty || sub == kSubjectVV || !(_showS || _isBothSemCombo)) {
      return const SizedBox.shrink();
    }
    final targetSem = _selectedSem == 'Annual' ? '2' : _selectedSem;
    final examKey = _satrantExamKey(sub, targetSem);
    final examDate = _lookupSavedSatrantExamDate(sub, targetSem);
    final source = _subjectExamDateSources[examKey] ??
        _subjectExamDateSources[_satrantStdExamKey(sub, targetSem)] ??
        '';
    final attMode = _subjectExamAttendanceModes[examKey] ?? 'direct';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: examDate.isEmpty
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: examDate.isEmpty ? AppColors.gold : AppColors.greenDeep,
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.event_available,
            size: 19,
            color: examDate.isEmpty ? AppColors.gold : AppColors.greenDeep,
          ),
          Text(
            examDate.isEmpty
                ? '📅 "$sub" ($_stdDisplayLabel) સત્રાંત પરીક્ષા તારીખ પસંદ કરેલ નથી'
                : '📅 "$sub" ($_stdDisplayLabel) સત્રાંત પરીક્ષા તારીખ: $examDate ${source == "timetable" ? "(પરીક્ષા સમયપત્રક મુજબ)" : "(પસંદ કરેલ તારીખ)"}',
            style: guFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _pickSubjectExamDate(subject: sub, semOverride: targetSem),
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: Text(
              examDate.isEmpty ? 'પરીક્ષા તારીખ પસંદ કરો' : 'તારીખ બદલો',
              style: guFont(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            attMode == 'student'
                ? '• ✅ Student-wise હાજરી મુજબ ગેરહાજર વિદ્યાર્થી માટે AB સેટ (નામ પાસેના બટનથી હાજર/ગેરહાજર બદલી શકાશે)'
                : '• 👆 Direct Entry હાજરી: નામ અને ગુણ વચ્ચે [✅ હાજર / 🚫 ગેરહાજર (AB)] પર ટચ કરી ગેરહાજર સેટ કરો',
            style: guFont(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.navyMid,
            ),
          ),
        ],
      ),
    );
  }

  String _studentPrintKey(ResultStudentRow st) =>
      st.studentId.trim().isNotEmpty ? st.studentId.trim() : 'roll_${st.roll}';

  dynamic _resolvePresentDaysCellForPrint(
    ResultStudentRow st, {
    required bool isSem1,
  }) {
    if (_leavePresentDaysBlankInPrint) return '';
    final key = _studentPrintKey(st);
    if (_printPresentDaysOverride.containsKey(key)) {
      final v = _printPresentDaysOverride[key];
      return (v != null && v > 0) ? v : '';
    }
    final raw = !isSem1 && st.studiedInSem2 && st.presentDays2 > 0
        ? st.presentDays2
        : st.presentDays;
    return raw > 0 ? raw : '';
  }

  String _resolvePresentDaysTextForPrint(
    ResultStudentRow st, {
    required bool isSem1,
  }) {
    final val = _resolvePresentDaysCellForPrint(st, isSem1: isSem1);
    return val == '' ? '' : '$val';
  }

  Future<bool> _askAndPreparePresentDaysForResultPrint() async {
    final validStudents =
        _students.where((s) => s.name.trim().isNotEmpty).toList();
    if (validStudents.isEmpty) return false;

    final shouldAutoFill = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'હાજર દિવસો (Present Days)',
          style: guFont(
              fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy),
        ),
        content: Text(
          'તમારે પરિણામ પત્રકમાં વિદ્યાર્થીઓના હાજર દિવસો ઓટોમેટિક (Student-wise હાજરી અથવા દાખલ કરેલ વિગત પરથી) લખવા છે?',
          style: guFont(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('રદ કરો',
                style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('ના, ખાલી રાખો',
                style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('હા, આગળ વધો',
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (shouldAutoFill == null || !mounted) return false;
    if (!shouldAutoFill) {
      setState(() {
        _leavePresentDaysBlankInPrint = true;
        _printPresentDaysOverride = <String, int?>{};
      });
      return true;
    }

    final isSem1 = _selectedSem == '1';
    final defaults = <String, int?>{};
    for (final st in validStudents) {
      final key = _studentPrintKey(st);
      final existing = isSem1
          ? st.presentDays
          : (st.presentDays2 > 0 ? st.presentDays2 : st.presentDays);
      if (existing > 0) {
        defaults[key] = existing;
      }
    }

    var complete = false;
    var incompleteMonths = <String>[];
    try {
      final yearMatch = RegExp(r'(20\d{2})').firstMatch(_academicYear);
      final now = DateTime.now();
      final startYear = yearMatch != null
          ? (int.tryParse(yearMatch.group(1)!) ??
              (now.month >= 6 ? now.year : now.year - 1))
          : (now.month >= 6 ? now.year : now.year - 1);
      final fromDate = _selectedSem == '2'
          ? DateTime(startYear, 11, 1)
          : DateTime(startYear, 6, 1);
      final throughDate = _selectedSem == '1'
          ? DateTime(startYear, 10, 31)
          : DateTime(startYear + 1, 5, 15);
      final classId =
          await SupabaseClassService().resolveClassId(_selectedClass ?? '');
      final studentMaps = <Map<String, dynamic>>[
        for (final st in validStudents)
          <String, dynamic>{
            'id': _studentPrintKey(st),
            'roll_number': st.roll,
            'name': st.name,
            'present_days': defaults[_studentPrintKey(st)] ?? 0,
          },
      ];
      final data =
          await SupabaseHajariPatrakService().getPresentDaysForDateRange(
        classId: classId,
        fromDate: fromDate,
        throughDate: throughDate,
        students: studentMaps,
        includeAcademicYearOverrides: _selectedSem != '2',
      );
      complete = data['is_complete'] == true;
      if (data['incomplete_months'] is List) {
        incompleteMonths = (data['incomplete_months'] as List)
            .map((e) => '$e')
            .toSet()
            .toList()
          ..sort();
      }
      final rawDays = data['days_by_student_id'];
      if (rawDays is Map) {
        for (final entry in rawDays.entries) {
          final v = entry.value;
          final parsed = v is num ? v.toInt() : int.tryParse('$v');
          if (parsed != null && parsed > 0) {
            defaults['${entry.key}'] = parsed;
          }
        }
      }
    } catch (_) {}

    final warning = complete
        ? 'આ વર્ગની Student-wise હાજરી પૂર્ણ નોંધાયેલ છે અને કુલ હાજર દિવસો આપમેળે ગણાઈને ભરાઈ ગયા છે. જરૂર હોય તો Days સુધારીને આગળ વધો.'
        : 'સૂચના (Hajari Patrak મુજબ): ${incompleteMonths.isEmpty ? "આ સત્રના અમુક મહિનાની Student-wise હાજરી અધૂરી છે અથવા Direct Entry થી હાજરી લેવાયેલ છે" : "બાકી મહિના: ${incompleteMonths.join(", ")} (અથવા Direct Entry હાજરી)"}. જો તમે Direct Entry થી હાજરી લીધી હોય તો અહીં દરેક વિદ્યાર્થીના હાજર દિવસો (Present Days) દાખલ કરી શકો છો; જ્યાં ખાલી રાખશો ત્યાં પરિણામ પત્રકમાં ખાલી રહેશે.';

    final controllers = <TextEditingController>[
      for (final st in validStudents)
        TextEditingController(
          text: defaults[_studentPrintKey(st)] != null &&
                  defaults[_studentPrintKey(st)]! > 0
              ? '${defaults[_studentPrintKey(st)]}'
              : '',
        ),
    ];

    Map<String, int?>? edited;
    try {
      if (!mounted) return false;
      edited = await showDialog<Map<String, int?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final viewport = MediaQuery.sizeOf(context);
            return AlertDialog(
              title: Text(
                'પરિણામ પત્રક માટે હાજર દિવસો ચકાસો / દાખલ કરો',
                style: guFont(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy),
              ),
              content: SizedBox(
                width: viewport.width < 760 ? viewport.width * 0.78 : 700,
                height: viewport.height * 0.62,
                child: Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        warning,
                        style: guFont(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: complete ? AppColors.greenDeep : AppColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 76,
                            child: Text('રોલ નંબર',
                                style: guFont(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('વિદ્યાર્થીનું નામ',
                                style: guFont(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          SizedBox(
                            width: 112,
                            child: Text('Days',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: validStudents.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final st = validStudents[index];
                          final roll =
                              st.roll.trim().isEmpty ? '${index + 1}' : st.roll;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 76,
                                  child: Text(roll,
                                      style: guFont(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    st.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: guFont(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 102,
                                  child: TextField(
                                    controller: controllers[index],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      hintText: 'ખાલી',
                                    ),
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
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: Text('રદ કરો',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final candidate = <String, int?>{};
                    for (var i = 0; i < validStudents.length; i++) {
                      final key = _studentPrintKey(validStudents[i]);
                      final raw = controllers[i].text.trim();
                      final parsed = int.tryParse(raw);
                      candidate[key] =
                          (parsed != null && parsed > 0) ? parsed : null;
                    }
                    Navigator.of(dialogContext).pop(candidate);
                  },
                  icon: const Icon(Icons.check),
                  label: Text('સાચવો અને આગળ વધો',
                      style: guFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      for (final c in controllers) {
        c.dispose();
      }
    }
    if (edited == null || !mounted) return false;
    setState(() {
      _leavePresentDaysBlankInPrint = false;
      _printPresentDaysOverride = edited!;
      for (final st in validStudents) {
        final v = edited[_studentPrintKey(st)];
        if (v != null && v > 0) {
          if (isSem1) {
            st.presentDays = v;
          } else {
            st.presentDays2 = v;
          }
        }
      }
    });
    return true;
  }

  // Match Hajari Patrak's PDF-only layout controls (row height 12–36 px,
  // Gujarati font size 4–12 pt). Excel exports retain the official template.
  int _resultPdfRowHeight = 22;
  int _resultPdfFontSize = 7;
  bool _resultPdfSettingsLoaded = false;

  // Semester-specific immutable snapshots imported from the saved attendance register.
  int _activeRosterSemester = 1;
  bool _rosterStatusLoading = false;
  bool _rosterActionBusy = false;
  String? _rosterStatusError;
  Map<int, Map<String, dynamic>> _rosterSnapshotStatus = {};
  DateTime? _studentDataWriteAuthorizationExpiresAt;
  String? _studentDataWriteAuthorizationClass;

  bool get _hasCurrentRosterSnapshot =>
      _rosterSnapshotStatus[_activeRosterSemester]?['current'] is Map;
  bool get _canUseResultEntry =>
      _hasCurrentRosterSnapshot && !_rosterStatusLoading && !_rosterActionBusy;

  String _currentResultDirtyScope() {
    if (_activeTab == 1 || _activeTab == 2) return '__STUDENT_PROFILES__';
    final subject = (_selectedSubject ?? '').trim();
    return subject.isEmpty ? '__UNSCOPED__' : subject;
  }

  void _markModified(int index) {
    if (index < 0 || index >= _students.length) return;
    _modifiedStudents.add(index);
    _dirtyScopesByStudent
        .putIfAbsent(index, () => <String>{})
        .add(_currentResultDirtyScope());
    _scheduleLocalResultDraftWrite();
  }

  String _localResultDraftKey() {
    final state = context.read<AppState>();
    final schoolRef = state.schoolNameLanguageRef.trim();
    final classKey = (_selectedClass ?? '').trim();
    if (schoolRef.isEmpty || classKey.isEmpty) {
      _cachedLocalDraftKey = '';
      return '';
    }
    final schoolPart = Uri.encodeComponent(schoolRef);
    final classPart = Uri.encodeComponent(classKey);
    _cachedLocalDraftKey =
        'psm_result_local_draft_v1_${schoolPart}_${classPart}_${_selectedSem}';
    return _cachedLocalDraftKey;
  }

  Map<String, dynamic> _serializeResultStudent(ResultStudentRow st) {
    Map<String, dynamic> serializeSem(Map<String, SubjectMarks> values) => {
          for (final entry in values.entries)
            entry.key: <String, dynamic>{
              'a': entry.value.patrakA,
              's': entry.value.satrant,
              'sw': entry.value.swaAdhyayan,
              'directTotal': entry.value.directTotal,
              'directMode': entry.value.usesDirectTotal,
              'satrantAbsent': entry.value.satrantAbsent,
            },
        };
    return <String, dynamic>{
      'sheetRow': st.sheetRow,
      'studentId': st.studentId,
      'roll': st.roll,
      'name': st.name,
      'gr': st.gr,
      'dd': st.dd,
      'mm': st.mm,
      'yyyy': st.yyyy,
      'category': st.category,
      'gender': st.gender,
      'presentDays': st.presentDays,
      'presentDays2': st.presentDays2,
      'standard': st.standard,
      'isDivyang': st.isDivyang,
      'uid': st.uid,
      'pen': st.pen,
      'mobile': st.mobile,
      'fatherName': st.fatherName,
      'motherName': st.motherName,
      'address': st.address,
      'studiedInSem2': st.studiedInSem2,
      'caste': st.caste,
      'birthPlace': st.birthPlace,
      'dobWords': st.dobWords,
      'lastSchool': st.lastSchool,
      'sem1': serializeSem(st.sem1),
      'sem2': serializeSem(st.sem2),
      'vv1': st.vv1,
      'vv2': st.vv2,
      'vv1Sentences': st.vv1Sentences,
      'vv2Sentences': st.vv2Sentences,
    };
  }

  void _scheduleLocalResultDraftWrite() {
    _localDraftTimer?.cancel();
    _localDraftTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistLocalResultDraft());
    });
  }

  Future<void> _persistLocalResultDraft({String? keyOverride}) async {
    final key = (keyOverride ?? _cachedLocalDraftKey).isNotEmpty
        ? (keyOverride ?? _cachedLocalDraftKey)
        : _localResultDraftKey();
    if (key.isEmpty) return;

    // Serialize concurrent writes. If a user edits while a previous local
    // write is in progress, the newest snapshot is written immediately after
    // that write completes; it is never silently discarded.
    if (_localDraftWriteInProgress) {
      _localDraftWritePending = true;
      final activeWrite = _localDraftWriteCompleter?.future;
      if (activeWrite != null) await activeWrite;
      if (_localDraftWritePending) {
        _localDraftWritePending = false;
        await _persistLocalResultDraft(keyOverride: key);
      }
      return;
    }

    _localDraftWriteInProgress = true;
    _localDraftWriteCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = <Map<String, dynamic>>[];
      for (final index in _modifiedStudents) {
        if (index < 0 || index >= _students.length) continue;
        final student = _students[index];
        if (student.studentId.trim().isEmpty) continue;
        final scopes = (_dirtyScopesByStudent[index] ??
                <String>{_currentResultDirtyScope()})
            .toList()
          ..sort();
        rows.add(<String, dynamic>{
          ..._serializeResultStudent(student),
          'dirtyScopes': scopes,
        });
      }
      if (rows.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(
            key,
            jsonEncode(<String, dynamic>{
              'version': 2,
              'classKey': _selectedClass,
              'semester': _selectedSem,
              'savedAt': DateTime.now().toIso8601String(),
              'rows': rows,
            }));
      }
    } catch (_) {
      // Keep the in-memory modified set; a later edit/save will retry this write.
    } finally {
      _localDraftWriteInProgress = false;
      final completer = _localDraftWriteCompleter;
      _localDraftWriteCompleter = null;
      if (completer != null && !completer.isCompleted) completer.complete();
    }
  }

  Future<void> _restoreLocalResultDraft() async {
    final key = _localResultDraftKey();
    if (key.isEmpty || _students.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['rows'] is! List) return;
      final rows = (decoded['rows'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final indexById = <String, int>{
        for (var i = 0; i < _students.length; i++)
          if (_students[i].studentId.trim().isNotEmpty)
            _students[i].studentId: i,
      };
      final restored = <int>{};
      for (final row in rows) {
        final id = '${row['studentId'] ?? row['id'] ?? ''}'.trim();
        final index = indexById[id];
        if (id.isEmpty || index == null) continue;
        final draft = ResultStudentRow.fromJson(row);
        final target = _students[index];
        // Identity and row position always come from the immutable roster;
        // the device draft only overlays editable values for the same UUID.
        target.roll = draft.roll;
        target.name = draft.name;
        target.gr = draft.gr;
        target.dd = draft.dd;
        target.mm = draft.mm;
        target.yyyy = draft.yyyy;
        target.category = draft.category;
        target.gender = draft.gender;
        target.presentDays = draft.presentDays;
        target.presentDays2 = draft.presentDays2;
        target.standard = draft.standard;
        target.isDivyang = draft.isDivyang;
        target.uid = draft.uid;
        target.pen = draft.pen;
        target.mobile = draft.mobile;
        target.fatherName = draft.fatherName;
        target.motherName = draft.motherName;
        target.address = draft.address;
        target.studiedInSem2 = draft.studiedInSem2;
        target.caste = draft.caste;
        target.birthPlace = draft.birthPlace;
        target.dobWords = draft.dobWords;
        target.lastSchool = draft.lastSchool;
        target.sem1
          ..clear()
          ..addAll(draft.sem1);
        target.sem2
          ..clear()
          ..addAll(draft.sem2);
        target.vv1 = draft.vv1;
        target.vv2 = draft.vv2;
        target.vv1Sentences = List<int>.from(draft.vv1Sentences);
        target.vv2Sentences = List<int>.from(draft.vv2Sentences);
        final rawScopes = row['dirtyScopes'];
        final scopes = rawScopes is List
            ? rawScopes
                .map((value) => '$value'.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
            : <String>{_currentResultDirtyScope()};
        _dirtyScopesByStudent[index] =
            scopes.isEmpty ? <String>{_currentResultDirtyScope()} : scopes;
        restored.add(index);
      }
      if (restored.isNotEmpty && mounted) {
        setState(() {
          _modifiedStudents.addAll(restored);
          _gridTick++;
          _alertIsError = false;
          _alert =
              '📱 અધૂરા ગુણ આ ઉપકરણમાંથી પાછા મેળવ્યા છે. Firebase માં મોકલવા Save બટન દબાવો.';
        });
      }
    } catch (_) {
      // A malformed/outdated device draft must never block loading the roster.
    }
  }

  Future<void> _checkOfflineDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = prefs.getStringList('offline_marks_drafts') ?? [];
      if (mounted) setState(() => _offlineDraftCount = drafts.length);
    } catch (_) {}
  }

  Future<void> _syncOfflineDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = prefs.getStringList('offline_marks_drafts') ?? [];
    if (drafts.isEmpty) return;
    final containsProfileDraft = drafts.any((value) {
      try {
        final decoded = jsonDecode(value);
        return decoded is Map && decoded['subject'] == '__STUDENT_PROFILES__';
      } catch (_) {
        return false;
      }
    });
    if (!mounted) return;
    final resultApi = context.read<AppState>().resultApi;
    if (resultApi is SupabaseResultApiService && !_hasCurrentRosterSnapshot) {
      showSnack(context,
          'ઓફલાઇન Result ડેટા મોકલતાં પહેલાં આ સત્રનો register snapshot આયાત કરો.',
          error: true);
      return;
    }
    if (containsProfileDraft && !_hasCurrentRosterSnapshot) {
      showSnack(context,
          'ઓફલાઇન વિદ્યાર્થી-વિગત ડેટા મોકલતાં પહેલાં આ સત્રનો register snapshot આયાત કરો.',
          error: true);
      return;
    }
    if (containsProfileDraft &&
        !await _ensureStudentDataPasswordAuthorization(interactive: true))
      return;
    if (!mounted) return;

    setState(() {
      _saving = true;
      _alertIsError = false;
      _alert = '🔄 ઑફલાઇન સેવ થયેલો ડેટા અપલોડ થાય છે...';
    });

    final state = context.read<AppState>();
    List<String> remainingDrafts = [];
    int successCount = 0;

    for (final draftStr in drafts) {
      try {
        final draft = jsonDecode(draftStr);
        if (draft is Map && draft['subject'] == '__STUDENT_PROFILES__') {
          final draftClass = '${draft['className'] ?? ''}'.trim();
          if (draftClass.isEmpty ||
              draftClass != _selectedClass ||
              !_hasCurrentRosterSnapshot) {
            remainingDrafts.add(draftStr);
            continue;
          }
        }
        final res = await state.resultApi!.saveSubjectMarks(
          className: draft['className'],
          sem: draft['sem'],
          subject: draft['subject'],
          entryCombo: draft['entryCombo'],
          payload: List<Map<String, dynamic>>.from(draft['payload']),
        );
        if (res['result'] == 'success') {
          successCount++;
        } else {
          remainingDrafts.add(draftStr);
        }
      } catch (e) {
        remainingDrafts.add(draftStr);
      }
    }

    await prefs.setStringList('offline_marks_drafts', remainingDrafts);
    if (mounted) {
      setState(() {
        _saving = false;
        _offlineDraftCount = remainingDrafts.length;
        _alertIsError = remainingDrafts.isNotEmpty;
        if (remainingDrafts.isEmpty) {
          _alert =
              '✅ ઑફલાઇન સેવ થયેલો બધો જ ડેટા ($successCount બેચ) Supabase માં સફળતાપૂર્વક સેવ થયો!';
        } else {
          _alert =
              '⚠️ $successCount બેચ અપલોડ થઈ, પણ હજુ ${remainingDrafts.length} બાકી છે. (ઇન્ટરનેટ કનેક્શન તપાસો)';
        }
      });
    }
  }

  @override
  void dispose() {
    for (final editor in _gradeEditors) {
      editor.dispose();
    }
    _localDraftTimer?.cancel();
    if (_cachedLocalDraftKey.isNotEmpty) {
      unawaited(_persistLocalResultDraft(keyOverride: _cachedLocalDraftKey));
    }
    _newRollCtrl.dispose();
    _newNameCtrl.dispose();
    _newGrCtrl.dispose();
    _newDdCtrl.dispose();
    _newMmCtrl.dispose();
    _newYyyyCtrl.dispose();
    _newUidCtrl.dispose();
    _newPenCtrl.dispose();
    _newMobileCtrl.dispose();
    _newFatherCtrl.dispose();
    _newMotherCtrl.dispose();
    _newAddressCtrl.dispose();
    _newPres1Ctrl.dispose();
    _newPres2Ctrl.dispose();
    _newStandardCtrl.dispose();
    super.dispose();
  }

  bool get _showA =>
      _entryCombo == 'only_a' ||
      _entryCombo == 'a_s' ||
      _entryCombo == 'a_sw' ||
      _entryCombo == 'all_3' ||
      _entryCombo == 'both_sem_all_6';

  bool get _showS =>
      _entryCombo == 'only_s' ||
      _entryCombo == 'a_s' ||
      _entryCombo == 's_sw' ||
      _entryCombo == 'all_3' ||
      _entryCombo == 'both_sem_all_6';

  bool get _showSW =>
      _entryCombo == 'only_sw' ||
      _entryCombo == 'a_sw' ||
      _entryCombo == 's_sw' ||
      _entryCombo == 'all_3' ||
      _entryCombo == 'both_sem_all_6';

  bool get _isBothSemCombo =>
      (_selectedSem == '2' || _selectedSem == 'Annual') &&
      _entryCombo == 'both_sem_all_6';

  bool get _hasStoredDirectSem1Marks {
    final subject = _selectedSubject;
    if (subject == null || subject.isEmpty) return false;
    return _students
        .any((student) => student.sem1[subject]?.usesDirectTotal == true);
  }

  bool get _useSem1DirectOutOf100 =>
      _sem1DirectOutOf100 || _hasStoredDirectSem1Marks;

  bool get _hasStoredSplitSem1Marks {
    final subject = _selectedSubject;
    if (subject == null || subject.isEmpty) return false;
    return _students.any((student) =>
        student.sem1.containsKey(subject) &&
        student.sem1[subject]?.usesDirectTotal != true);
  }

  Future<void> _toggleSem1DirectOutOf100() async {
    if (!_isBothSemCombo || _selectedSubject == null) return;
    final hasDirect = _hasStoredDirectSem1Marks;
    if (_useSem1DirectOutOf100 && hasDirect) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('પ્રથમ સત્રના સીધા ગુણ દૂર કરવા?'),
          content: const Text(
            'સીધા 100 માંથી સેવ થયેલા પ્રથમ સત્રના ગુણ આપમેળે 40+40+20 માં વહેંચી શકાતા નથી. આ વિકલ્પ ચાલુ રાખવા માટે હાલના સીધા ગુણ ખાલી થશે અને ત્રણ ભાગના ગુણ ફરીથી દાખલ કરવા પડશે. આગળ વધવું છે?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રહેવા દો'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('હા, સીધા ગુણ ખાલી કરો'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        final subject = _selectedSubject!;
        for (var i = 0; i < _students.length; i++) {
          final marks = _students[i].sem1[subject];
          if (marks?.usesDirectTotal != true) continue;
          _markModified(i);
          _students[i].sem1[subject] = const SubjectMarks();
        }
        _sem1DirectOutOf100 = false;
        _gridTick++;
      });
      return;
    }

    if (_sem1DirectOutOf100) {
      setState(() {
        _sem1DirectOutOf100 = false;
        _gridTick++;
      });
      return;
    }

    final hasSplit = _hasStoredSplitSem1Marks;
    if (hasSplit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('સીધા 100 માંથી ગુણ દાખલ કરવા?'),
          content: const Text(
            'હાલના 40+40+20 ગુણનો કુલ જાળવીને તેને પ્રથમ સત્રના સીધા 100 ગુણમાં ફેરવવામાં આવશે. ત્રણ ભાગનો જૂનો અલગ-અલગ હિસાબ દૂર થશે. આ ફેરફાર પછી Save દબાવવો પડશે. આગળ વધવું છે?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રહેવા દો'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('હા, કુલ જાળવી ફેરવો'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        final subject = _selectedSubject!;
        for (var i = 0; i < _students.length; i++) {
          final marks = _students[i].sem1[subject];
          if (marks == null || marks.usesDirectTotal) continue;
          _markModified(i);
          _students[i].sem1[subject] = SubjectMarks(
            directTotal: marks.total.clamp(0, 100).toInt(),
            directMode: true,
          );
        }
        _sem1DirectOutOf100 = true;
        _gridTick++;
      });
      return;
    }

    setState(() {
      final subject = _selectedSubject!;
      for (var i = 0; i < _students.length; i++) {
        final marks = _students[i].sem1[subject];
        if (marks?.usesDirectTotal == true) continue;
        _markModified(i);
        _students[i].sem1[subject] = SubjectMarks(
          directTotal: marks == null ? null : marks.total.clamp(0, 100).toInt(),
          directMode: true,
        );
      }
      _sem1DirectOutOf100 = true;
      _gridTick++;
    });
  }

  bool get _isRegularSubjectSelected =>
      _selectedSubject != null && _selectedSubject != kSubjectVV;

  String get _cleanClassCode {
    final selectedKey = (_selectedClass ?? '').trim();
    if (selectedKey.isEmpty) return '';
    for (final klass in context.read<AppState>().allowedClasses) {
      if (klass.key == selectedKey) return klass.displayLabel;
    }
    return SchoolClass.formatDisplayLabel(key: selectedKey);
  }

  String get _semTag => _selectedSem == '1' ? 'FIRST SEM' : 'SECOND SEM';

  void _togglePartChip({bool? toggleA, bool? toggleS, bool? toggleSW}) {
    var a = toggleA ?? _showA;
    var s = toggleS ?? _showS;
    var sw = toggleSW ?? _showSW;
    if (!a && !s && !sw) a = true;

    String nextCombo = 'all_3';
    if (a && s && sw) {
      nextCombo = 'all_3';
    } else if (a && s) {
      nextCombo = 'a_s';
    } else if (a && sw) {
      nextCombo = 'a_sw';
    } else if (s && sw) {
      nextCombo = 's_sw';
    } else if (a) {
      nextCombo = 'only_a';
    } else if (s) {
      nextCombo = 'only_s';
    } else if (sw) {
      nextCombo = 'only_sw';
    }

    setState(() {
      _entryCombo = nextCombo;
      _gridTick++;
    });
  }

  String get _resultPdfSettingsKey {
    final profile = _schoolProfile;
    final schoolRef = _brandText(
      _loadedSchoolRef.isNotEmpty
          ? _loadedSchoolRef
          : (profile['schoolRef'] ??
              profile['school_ref'] ??
              profile['school_id'] ??
              profile['id'] ??
              _schoolDiseCode),
    );
    return 'psm_result_pdf_layout_${schoolRef.isEmpty ? 'default' : schoolRef}';
  }

  Future<void> _loadResultPdfSettings() async {
    if (_resultPdfSettingsLoaded) return;
    _resultPdfSettingsLoaded = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _resultPdfSettingsKey;
      final rowHeight =
          (preferences.getInt('${key}_row_height') ?? 22).clamp(12, 36).toInt();
      final fontSize =
          (preferences.getInt('${key}_font_size') ?? 7).clamp(4, 12).toInt();
      final useDivyang = preferences.getBool('${key}_use_divyang_rule') ?? true;
      if (!mounted) return;
      setState(() {
        _resultPdfRowHeight = rowHeight;
        _resultPdfFontSize = fontSize;
        _useDivyangRule = useDivyang;
      });
    } catch (_) {
      // Defaults remain usable even when local preferences are unavailable.
    }
  }

  Future<void> _saveResultPdfSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _resultPdfSettingsKey;
      await preferences.setInt('${key}_row_height', _resultPdfRowHeight);
      await preferences.setInt('${key}_font_size', _resultPdfFontSize);
      await preferences.setBool('${key}_use_divyang_rule', _useDivyangRule);
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      final state = context.read<AppState>();
      final allowed = state.allowedClasses;
      if (allowed.isNotEmpty) {
        final last = state.lastSelectedClass;
        _selectedClass =
            allowed.any((c) => c.key == last) ? last : allowed.first.key;
      }
      final savedSemester = state.lastSemester.trim();
      _selectedSem = const {'1', '2', 'Annual'}.contains(savedSemester)
          ? savedSemester
          : '1';
      if (_selectedSem == 'Annual') {
        _entryCombo = 'both_sem_all_6';
      }
      _examEntryFrom80 = _isStd6To8;
      _activeRosterSemester =
          _selectedSem == '2' || _selectedSem == 'Annual' ? 2 : 1;
      _selectedSubject =
          state.lastSubject == kSubjectVV ? null : state.lastSubject;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadRegisteredSchoolBranding());
        unawaited(_loadSchoolGradeSettings());
        unawaited(_loadResultPdfSettings());
        _checkOfflineDrafts();
        _loadData();
      });
    }
  }

  int get _stdNumber {
    final rawClean = _cleanClassCode;
    const guDigits = '૦૧૨૩૪૫૬૭૮૯';
    var normalized = rawClean;
    for (var i = 0; i < guDigits.length; i++) {
      normalized = normalized.replaceAll(guDigits[i], '$i');
    }
    if (normalized.contains('બાલ') ||
        normalized.toLowerCase().contains('balvatika')) {
      return 0;
    }
    final m = RegExp(r'(?:^|\D)([1-9]|1[0-2])(?:\D|$)').firstMatch(normalized);
    if (m != null) {
      return int.tryParse(m.group(1)!) ?? 0;
    }
    return 0;
  }

  String get _stdDisplayLabel =>
      _stdNumber > 0 ? 'ધોરણ $_stdNumber' : _cleanClassCode;

  bool get _isClass3Or4 => _stdNumber == 3 || _stdNumber == 4;
  int get _vvMaxPerSentence => (_stdNumber >= 6 && _stdNumber <= 8) ? 10 : 5;
  int get _vvMaxPerSemester => _vvMaxPerSentence * 40;

  // Admin can edit all saved subjects for the selected class, including retained
  // historical subjects. The data service supplies active class subjects to the
  // designated class teacher and only explicit class+subject assignments to other
  // teachers. V.V. behaviour assessment is deliberately kept out of this list.
  List<String> get _dropdownSubjects {
    final source =
        context.read<AppState>().isAdmin ? _subjects : _assignedSubjects;
    final seen = <String>{};
    return List<String>.unmodifiable(source.where((subject) {
      final value = subject.trim();
      // A second-semester-only subject is not entered in the first semester.
      if (_selectedSem == '1' && _sem2OnlySubjects.contains(value)) return false;
      return value.isNotEmpty && seen.add(value.toLowerCase());
    }).map((subject) => subject.trim()));
  }

  bool get _isStd6To8 => _stdNumber >= 6 && _stdNumber <= 8;

  double _minimumPercent(Map<String, dynamic> rule) {
    final value = rule['minimum_percent'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  List<Map<String, dynamic>> get _sortedGradeRules {
    final rules =
        _gradeRules.map((rule) => Map<String, dynamic>.from(rule)).toList();
    rules.sort((a, b) => _minimumPercent(b).compareTo(_minimumPercent(a)));
    return rules;
  }

  List<String> get _gradeLabels => _sortedGradeRules
      .map((rule) => _brandText(rule['grade_label'] ?? rule['label']))
      .where((label) => label.isNotEmpty)
      .toList();

  String _gradeFor(double percentage) {
    for (final rule in _sortedGradeRules) {
      if (percentage >= _minimumPercent(rule)) {
        final label = _brandText(rule['grade_label'] ?? rule['label']);
        if (label.isNotEmpty) return label;
      }
    }
    return _gradeLabels.isEmpty ? 'E' : _gradeLabels.last;
  }

  String get _gradeIndicatorText {
    final rules = _sortedGradeRules;
    if (rules.isEmpty)
      return 'ગ્રેડ સૂચક: A 80%+ | B 65%+ | C 50%+ | D 35%+ | E <35%';
    final parts = <String>[];
    for (var i = 0; i < rules.length; i++) {
      final label = _brandText(rules[i]['grade_label'] ?? rules[i]['label']);
      final minimum = _minimumPercent(rules[i]);
      if (i == 0) {
        parts.add(
            '$label ${minimum.toStringAsFixed(minimum % 1 == 0 ? 0 : 2)}–100%');
      } else if (i == rules.length - 1 && minimum == 0) {
        final upper = _minimumPercent(rules[i - 1]);
        parts.add('$label <${upper.toStringAsFixed(upper % 1 == 0 ? 0 : 2)}%');
      } else {
        final upper =
            (_minimumPercent(rules[i - 1]) - 0.01).clamp(0, 100).toDouble();
        parts.add(
            '$label ${minimum.toStringAsFixed(minimum % 1 == 0 ? 0 : 2)}–${upper.toStringAsFixed(2)}%');
      }
    }
    return 'ગ્રેડ સૂચક: ${parts.join('  |  ')}';
  }

  void _applyGradeRules(List<Map<String, dynamic>> rulesRaw) {
    final rules = rulesRaw
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList()
      ..sort((a, b) => _minimumPercent(b).compareTo(_minimumPercent(a)));
    if (rules.isEmpty) return;
    _gradeRules = rules;
    _gradeAThreshold = _minimumPercent(rules[0]);
    _gradeBThreshold =
        rules.length > 1 ? _minimumPercent(rules[1]) : _gradeAThreshold;
    _gradeCThreshold =
        rules.length > 2 ? _minimumPercent(rules[2]) : _gradeBThreshold;
    final positive = rules.where((rule) => _minimumPercent(rule) > 0).toList();
    _gradeDThreshold = positive.isEmpty
        ? 35
        : positive.map(_minimumPercent).reduce((a, b) => a < b ? a : b);
  }

  /// Passing percentage required in each subject's combined total:
  /// 20% if Divyang (Col R = YES), or _gradeDThreshold (35%) for Normal students.
  bool _useDivyangRule = true;

  double _passingPctForStudent(ResultStudentRow st) =>
      (_useDivyangRule && st.isDivyang) ? 20.0 : _gradeDThreshold;

  /// Evaluates Pass/Fail ("પાસ" / "નાપાસ") based on each inserted subject's TOTAL marks
  /// (e.g. Sem 1 [35] + Sem 2 [15+20=35] = 70/200 = 35% -> "પાસ"!).
  /// Result rule mode:
  /// - 'auto'         : 35% (or 20% Divyang when _useDivyangRule is true) -> 'પાસ' / 'નાપાસ'
  /// - 'one_sub_fail' : Fail if even 1 subject is below passing threshold
  /// - 'promote'      : If failed -> 'વર્ગ બઢતી આપેલ છે', else 'પાસ'
  /// - 'all_pass'     : Everyone is 'પાસ'
  String _parinamRuleMode = 'auto';
  int _minEGradesToFail = 2; // Default 2 વિષયમાં નાપાસ હોય તો જ Fail (1 = 1 વિષયમાં નાપાસ તો પણ નાપાસ)

  Map<String, String> get _parinamRuleModes => _useDivyangRule
      ? const <String, String>{
          'auto':
              '📊 નિયમ મુજબ: 1 વિષય E = ગ્રેસ; ડિફૉલ્ટ 2 E = નાપાસ (દિવ્યાંગ 20% પાસ)',
          'one_sub_fail':
              '❌ 1 વિષયમાં પણ 35 થી ઓછા ગુણ (દિવ્યાંગ 20% થી ઓછા) હોય તો નાપાસ (1 Subject Fail)',
          'promote': '🎓 નાપાસ થાય ત્યારે "વર્ગ બઢતી આપેલ છે"',
          'all_pass': '✅ બધા જ વિદ્યાર્થી "પાસ" (All Pass)',
        }
      : const <String, String>{
          'auto': '📊 નિયમ મુજબ: 1 વિષય E = ગ્રેસ; ડિફૉલ્ટ 2 E = નાપાસ',
          'one_sub_fail':
              '❌ 1 વિષયમાં પણ 35 થી ઓછા ગુણ (E ગ્રેડ) હોય તો નાપાસ (1 Subject Fail)',
          'promote': '🎓 નાપાસ થાય ત્યારે "વર્ગ બઢતી આપેલ છે"',
          'all_pass': '✅ બધા જ વિદ્યાર્થી "પાસ" (All Pass)',
        };

  String _evaluatePassFailForStudent(ResultStudentRow st,
      {required bool isSem1}) {
    // Semester 2 students marked "નામ કમી" must not be evaluated.
    if (!isSem1 && !st.studiedInSem2) return 'નામ કમી';

    // Keep the existing override options. All Pass deliberately overrides subject results.
    if (_parinamRuleMode == 'all_pass') return 'પાસ';

    final failLabel =
        _parinamRuleMode == 'promote' ? 'વર્ગ બઢતી આપેલ છે' : 'નાપાસ';
    final passThreshold = _passingPctForStudent(st);
    bool anySubjectInserted = false;
    int failedSubjectsCount = 0;

    final subjectsToEvaluate = _subjectsForCurrentReport;
    for (final sub in subjectsToEvaluate) {
      final s1 = st.sem1[sub]?.total ?? 0;
      final s2 = st.studiedInSem2 ? (st.sem2[sub]?.total ?? 0) : 0;
      // containsKey is intentional: zero marks count if a mark row was saved;
      // a subject with no saved row is skipped.
      final hasSem1 = _classHasSem1Marks(sub);
      final hasSem2 = st.studiedInSem2 && _classHasSem2Marks(sub);

      if (isSem1) {
        if (!hasSem1) continue;
        anySubjectInserted = true;
        final pct = (s1 / _maxSubSemTotal) * 100;
        if (pct < passThreshold) failedSubjectsCount++;
      } else {
        if (!hasSem1 && !hasSem2) continue;
        anySubjectInserted = true;
        final subTot = s1 + s2;
        final sem1Max = hasSem1 ? _sem1MaximumForSubject(st, sub) : 0;
        final subMax = hasSem1 && hasSem2
            ? sem1Max + _maxSubSemTotal
            : (hasSem1 ? sem1Max : _maxSubSemTotal);
        final pct = subMax > 0 ? (subTot / subMax) * 100 : 0.0;
        // Regular students use the configured E threshold (normally 35%);
        // Divyang students must reach at least 20% in each subject.
        if (pct < passThreshold) failedSubjectsCount++;
      }
    }

    if (!anySubjectInserted && (isSem1 ? st.vv1 : st.vvAvgBothSem) == 0) {
      return '-';
    }

    final effectiveMinFail =
        _parinamRuleMode == 'one_sub_fail' ? 1 : _minEGradesToFail;
    if (failedSubjectsCount >= effectiveMinFail) {
      return failLabel;
    }
    // Grace promotion is a final/second-semester outcome when 2+ subjects are required to fail.
    if (!isSem1 && failedSubjectsCount == 1 && effectiveMinFail > 1) {
      return 'ગ્રેસ સાથે વર્ગ બઢતી આપેલ છે';
    }
    return 'પાસ';
  }

  /// Logical Subject Max Marks:
  /// - If marks are NOT inserted in either semester -> returns 0 (subject is skipped!)
  /// - In Sem 1 -> returns _maxSubSemTotal (100) if s1 > 0, else 0
  /// - In Sem 2 / Annual -> returns 200 if marks are inserted in BOTH Sem 1 & Sem 2,
  ///   or 100 if marks are inserted in ONLY Sem 2 (or ONLY Sem 1).
  /// A subject counts for the whole class as soon as marks are saved for
  /// any one student: students without a saved row then count as 0 marks
  /// (totals, maximum, grade and result), not as "subject not taken".
  bool _classHasSem1Marks(String sub) =>
      !_sem2OnlySubjects.contains(sub) &&
      _students.any((s) => s.name.trim().isNotEmpty && s.sem1.containsKey(sub));

  bool _classHasSem2Marks(String sub) => _students.any((s) =>
      s.name.trim().isNotEmpty && s.studiedInSem2 && s.sem2.containsKey(sub));

  int _sem1MaximumForSubject(ResultStudentRow st, String sub) {
    final marks = st.sem1[sub];
    // Direct first-semester entry is explicitly out of 100. Split entry keeps
    // the school-configured 40+40+20 (normally 100) maximum.
    return marks?.usesDirectTotal == true ? 100 : _maxSubSemTotal;
  }

  int _logicalSubjectMax(ResultStudentRow st, String sub,
      {required bool isSem1}) {
    final hasSem1 = _classHasSem1Marks(sub);
    final hasSem2 = st.studiedInSem2 && _classHasSem2Marks(sub);
    final sem1Maximum = hasSem1 ? _sem1MaximumForSubject(st, sub) : 0;
    if (isSem1) return sem1Maximum;
    if (!hasSem1 && !hasSem2) return 0;
    if (hasSem1 && hasSem2) {
      return sem1Maximum + _maxSubSemTotal;
    }
    return hasSem1 ? sem1Maximum : _maxSubSemTotal;
  }

  void _replaceGradeEditors(List<Map<String, dynamic>> rules) {
    for (final editor in _gradeEditors) {
      editor.dispose();
    }
    _gradeEditors
      ..clear()
      ..addAll(rules.map((rule) => _GradeRuleEditor(
            label: _brandText(rule['grade_label'] ?? rule['label']),
            minimumPercent: _minimumPercent(rule)
                .toStringAsFixed(_minimumPercent(rule) % 1 == 0 ? 0 : 2),
          )));
  }

  Future<void> _loadSchoolGradeSettings({bool force = false}) async {
    if (_gradeSettingsLoading || (_gradeSettingsLoaded && !force)) return;
    if (mounted)
      setState(() {
        _gradeSettingsLoading = true;
        _gradeSettingsError = null;
      });
    try {
      final client = Supabase.instance.client;
      var schoolRef = _loadedSchoolRef;
      if (schoolRef.isEmpty)
        schoolRef = _brandText(await client.rpc('current_school_ref'));
      if (schoolRef.isEmpty)
        throw StateError('School reference is unavailable.');
      final rows = await client
          .from('school_result_grade_settings')
          .select('grade_label,minimum_percent,sort_order')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('minimum_percent', ascending: false);
      final loaded = rows
          .map<Map<String, dynamic>>((raw) {
            final row = Map<String, dynamic>.from(raw);
            return <String, dynamic>{
              'grade_label': _brandText(row['grade_label']),
              'minimum_percent': _minimumPercent(row),
              'sort_order': row['sort_order'] ?? 0,
            };
          })
          .where((row) => _brandText(row['grade_label']).isNotEmpty)
          .toList();
      final effective = loaded.isNotEmpty ? loaded : _gradeRules;
      if (!mounted) return;
      setState(() {
        _loadedSchoolRef = schoolRef;
        _applyGradeRules(effective);
        _replaceGradeEditors(_gradeRules);
        _gradeSettingsLoaded = true;
        _gradeSettingsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _gradeSettingsLoaded = true;
        _gradeSettingsError =
            'Grade settings are unavailable. Apply migration 20261028030000 and refresh. $error';
        _replaceGradeEditors(_gradeRules);
      });
    } finally {
      if (mounted) setState(() => _gradeSettingsLoading = false);
    }
  }

  Future<void> _saveSchoolGradeSettings() async {
    if (!context.read<AppState>().isAdmin) {
      showSnack(
          context, 'ગ્રેડ સેટિંગ્સ બદલવાનો અધિકાર માત્ર School Admin પાસે છે.',
          error: true);
      return;
    }
    if (!_canUseResultEntry) {
      showSnack(
          context, 'શાળા BLOCKED / READ ONLY છે. હાલ સેટિંગ્સ બદલી શકાશે નહિ.',
          error: true);
      return;
    }
    final payload = <Map<String, dynamic>>[];
    final labels = <String>{};
    final thresholds = <double>{};
    var hasZero = false;
    for (var i = 0; i < _gradeEditors.length; i++) {
      final label = _gradeEditors[i].labelController.text.trim();
      final minimum =
          double.tryParse(_gradeEditors[i].percentController.text.trim());
      if (label.isEmpty ||
          label.length > 20 ||
          minimum == null ||
          minimum < 0 ||
          minimum > 100) {
        showSnack(
            context, 'દરેક ગ્રેડનું નામ અને 0 થી 100 વચ્ચેની ટકાવારી દાખલ કરો.',
            error: true);
        return;
      }
      if (!labels.add(label.toLowerCase()) || !thresholds.add(minimum)) {
        showSnack(
            context, 'ગ્રેડનાં નામ અને minimum percentage અલગ-અલગ હોવા જોઈએ.',
            error: true);
        return;
      }
      if (minimum == 0) hasZero = true;
      payload.add(<String, dynamic>{
        'grade_label': label,
        'minimum_percent': minimum,
        'sort_order': i
      });
    }
    if (payload.length < 2 || payload.length > 20 || !hasZero) {
      showSnack(context,
          'ઓછામાં ઓછા 2 ગ્રેડ રાખો અને સૌથી નીચા ગ્રેડનું minimum 0 રાખો.',
          error: true);
      return;
    }
    setState(() {
      _gradeSettingsSaving = true;
      _gradeSettingsError = null;
    });
    try {
      await Supabase.instance.client.rpc('save_school_result_grade_settings',
          params: <String, dynamic>{'p_grades': payload});
      if (!mounted) return;
      final ordered = payload.map((r) => Map<String, dynamic>.from(r)).toList()
        ..sort((a, b) => _minimumPercent(b).compareTo(_minimumPercent(a)));
      setState(() {
        _applyGradeRules(ordered);
        _replaceGradeEditors(_gradeRules);
        _gradeSettingsLoaded = true;
        _gradeSettingsError = null;
        _alertIsError = false;
        _alert =
            '✅ Grade settings saved. All subsequent result cards will use these grade labels and percentages.';
      });
    } catch (error) {
      if (mounted)
        setState(() =>
            _gradeSettingsError = 'ગ્રેડ સેટિંગ્સ સેવ થઈ શકી નથી: $error');
    } finally {
      if (mounted) setState(() => _gradeSettingsSaving = false);
    }
  }

  Future<void> _openSubjectAndGradeSettingsDialog() async {
    final isAdmin = context.read<AppState>().isAdmin;
    if (!isAdmin) {
      showSnack(context,
          'શાળાના વિષયો Admin Setup માં સંચાલિત થાય છે. ગ્રેડ સેટિંગ્સ બદલવાનો અધિકાર માત્ર Admin પાસે છે.');
      return;
    }
    setState(() {
      _activeTab = 4;
      _gridTick++;
    });
    await _loadSchoolGradeSettings(force: true);
    if (!mounted) return;
    showSnack(context,
        'ગ્રેડ સેટિંગ્સ અહીં ખોલ્યાં છે. વિષયો ઉમેરવા/બદલવા Admin Setup → Subjects ખોલો.');
  }

  Widget _buildGradeRuleEditorCard(int index) {
    final editor = _gradeEditors[index];
    final removeButton = IconButton(
      tooltip: 'Remove grade',
      onPressed: _gradeEditors.length <= 2 ||
              _gradeSettingsSaving ||
              !_canUseResultEntry
          ? null
          : () => setState(() => _gradeEditors.removeAt(index).dispose()),
      icon: const Icon(Icons.delete_outline, color: AppColors.rose),
    );
    final gradeNameField = TextField(
      controller: editor.labelController,
      decoration: const InputDecoration(
          labelText: 'Grade label (A+, B+, …)', isDense: true),
      textCapitalization: TextCapitalization.characters,
      enabled: !_gradeSettingsSaving && _canUseResultEntry,
    );
    final minimumField = TextField(
      controller: editor.percentController,
      decoration: const InputDecoration(
          labelText: 'Minimum %', suffixText: '%', isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: !_gradeSettingsSaving && _canUseResultEntry,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 440) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  gradeNameField,
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: minimumField),
                    const SizedBox(width: 8),
                    removeButton,
                  ]),
                ]);
          }
          return Row(children: [
            Expanded(child: gradeNameField),
            const SizedBox(width: 10),
            SizedBox(width: 120, child: minimumField),
            removeButton,
          ]);
        }),
      ),
    );
  }

  Widget _buildGradeSettingsTab() {
    if (!context.watch<AppState>().isAdmin) {
      return const MessageState(
          text: 'ગ્રેડ સેટિંગ્સ બદલવાનો અધિકાર માત્ર School Admin પાસે છે.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('🎓 Grade Settings / ગ્રેડ સેટિંગ્સ',
          style: guFont(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.navy)),
      const SizedBox(height: 6),
      Text(
          'દરેક ગ્રેડ માટે minimum percentage આપો. A+, B+ જેવી કોઈપણ ગ્રેડ ઉમેરો. આ સેટિંગ્સ Result lock પછી પણ Admin બદલી શકે છે.',
          style: guFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate)),
      if (_gradeSettingsLoading) const LinearProgressIndicator(),
      if (_gradeSettingsError != null) ...[
        const SizedBox(height: 8),
        AlertBox(kind: AlertKind.error, text: _gradeSettingsError!),
      ],
      const SizedBox(height: 10),
      for (var i = 0; i < _gradeEditors.length; i++)
        _buildGradeRuleEditorCard(i),
      OutlinedButton.icon(
        onPressed: _gradeSettingsSaving ||
                !_canUseResultEntry ||
                _gradeEditors.length >= 20
            ? null
            : () => setState(() => _gradeEditors
                .add(_GradeRuleEditor(label: '', minimumPercent: '0'))),
        icon: const Icon(Icons.add),
        label: const Text('Add grade / ગ્રેડ ઉમેરો'),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
            color: AppColors.navy, borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(_gradeIndicatorText,
            style: guFont(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
      const SizedBox(height: 12),
      AppButton(
        label: _gradeSettingsSaving
            ? 'Saving grade settings…'
            : '💾 Save Grade Settings',
        background: AppColors.greenDeep,
        onPressed:
            _gradeSettingsSaving || _gradeSettingsLoading || !_canUseResultEntry
                ? null
                : _saveSchoolGradeSettings,
      ),
    ]);
  }

  /// Formats single-digit day/month (e.g. "3" -> "03") for printing
  String _pad2(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final n = int.tryParse(t);
    if (n != null && n >= 1 && n <= 9) return '0$n';
    return t;
  }

  String _formatDob2Digits(ResultStudentRow st) {
    final d = _pad2(st.dd);
    final m = _pad2(st.mm);
    final y = st.yyyy.trim();
    if (d.isEmpty && m.isEmpty && y.isEmpty) return '';
    return '$d/$m/$y';
  }

  String _normalizeCategoryBucket(String raw) {
    final s = raw.replaceAll(' ', '');
    if (s.contains('અ.જ.જા') || s.toUpperCase().contains('ST')) return 'ST';
    if (s.contains('અ.જા') || s.toUpperCase().contains('SC')) return 'SC';
    if (s.contains('બ.') ||
        s.contains('બક્ષી') ||
        s.toUpperCase().contains('OBC')) return 'OBC';
    return 'OTHER';
  }

  bool get _isSubjectTeacherOnly =>
      !context.read<AppState>().isAdmin && !_isClassTeacher;

  bool _hasInsertedMarksForSubject(String subject) {
    return _students.any((student) {
      if (student.name.trim().isEmpty) return false;
      final m1 = student.sem1[subject];
      final has1 = m1 != null &&
          (m1.total > 0 ||
              m1.patrakA > 0 ||
              m1.satrant > 0 ||
              m1.swaAdhyayan > 0 ||
              (m1.directTotal ?? 0) > 0);
      if (_selectedSem == '1') return has1;
      final m2 = student.studiedInSem2 ? student.sem2[subject] : null;
      final has2 = m2 != null &&
          (m2.total > 0 ||
              m2.patrakA > 0 ||
              m2.satrant > 0 ||
              m2.swaAdhyayan > 0 ||
              (m2.directTotal ?? 0) > 0);
      return has1 || has2;
    });
  }

  /// Subjects printed for the selected Result report.
  /// - For a Subject Teacher: prints only their taught subject(s).
  /// - For Class Teacher / Admin: prints only subjects that actually have inserted marks.
  /// Subjects whose marks are entered for the selected semester (second
  /// semester / annual: subjects with second-semester marks).
  bool _hasMarksInSelectedSemester(String subject) {
    bool has(SubjectMarks? m) =>
        m != null &&
        (m.total > 0 || m.patrakA > 0 || m.satrant > 0 || m.swaAdhyayan > 0 || (m.directTotal ?? 0) > 0);
    return _students.any((student) {
      if (student.name.trim().isEmpty) return false;
      if (_selectedSem == '1') return has(student.sem1[subject]);
      return student.studiedInSem2 && has(student.sem2[subject]);
    });
  }

  /// Subjects ticked for the student-wise result (null = not chosen yet).
  Set<String>? _reportCardSubjectSelection;
  String _reportCardSelectionKey = '';

  List<String> _defaultReportCardSubjects() {
    final base = _subjectsForCurrentReport;
    if (_isSubjectTeacherOnly || !_onlyMarksEnteredSubjects) return base;
    final entered = base.where(_hasMarksInSelectedSemester).toList();
    return entered.isNotEmpty ? entered : base;
  }

  /// Subjects printed on each student's result card.
  List<String> get _subjectsForStudentCards {
    final key = '$_selectedClass|$_selectedSem';
    if (_reportCardSelectionKey != key) {
      _reportCardSelectionKey = key;
      _reportCardSubjectSelection = null;
    }
    final chosen = _reportCardSubjectSelection;
    if (chosen == null) return _defaultReportCardSubjects();
    final ordered = _subjects.where(chosen.contains).toList();
    return ordered.isEmpty ? _defaultReportCardSubjects() : ordered;
  }

  List<String> get _subjectsForCurrentReport {
    final list = _subjectsForCurrentReportAll;
    if (_selectedSem != '1') return list;
    return list.where((s) => !_sem2OnlySubjects.contains(s)).toList();
  }

  List<String> get _subjectsForCurrentReportAll {
    if (_isSubjectTeacherOnly) {
      final taught = _dropdownSubjects;
      if (taught.isEmpty) return <String>[];
      final withMarks = taught.where(_hasInsertedMarksForSubject).toList();
      if (withMarks.isNotEmpty) return withMarks;
      if (_selectedSubject != null && taught.contains(_selectedSubject)) {
        return <String>[_selectedSubject!];
      }
      return List<String>.from(taught);
    }
    if (!_onlyMarksEnteredSubjects) return List<String>.from(_subjects);
    final withNonZeroMarks =
        _subjects.where(_hasInsertedMarksForSubject).toList();
    if (withNonZeroMarks.isNotEmpty) return withNonZeroMarks;
    return _subjects.where((subject) {
      return _students.any((student) {
        if (_selectedSem == '1') return student.sem1.containsKey(subject);
        return student.sem1.containsKey(subject) ||
            (student.studiedInSem2 && student.sem2.containsKey(subject));
      });
    }).toList();
  }

  int _classReportMaximum(List<String> subjects,
      {required bool firstSemesterOnly, required int vvMaximum}) {
    var maximum = vvMaximum;
    for (final subject in subjects) {
      final hasSem1 = _students.any((student) =>
          student.name.trim().isNotEmpty && student.sem1.containsKey(subject));
      final hasSem2 = _students.any((student) =>
          student.name.trim().isNotEmpty &&
          student.studiedInSem2 &&
          student.sem2.containsKey(subject));
      final sem1Maximum = hasSem1
          ? _students
              .where((student) =>
                  student.name.trim().isNotEmpty &&
                  student.sem1.containsKey(subject))
              .map((student) => _sem1MaximumForSubject(student, subject))
              .fold<int>(0, (maximum, value) => math.max(maximum, value))
          : 0;
      if (_sem2OnlySubjects.contains(subject)) {
        // Second-semester-only subject: 100 in the annual result, none in
        // the first semester.
        if (!firstSemesterOnly) maximum += _maxSubSemTotal;
      } else if (firstSemesterOnly) {
        maximum += sem1Maximum;
      } else if (hasSem1 || hasSem2) {
        maximum += sem1Maximum + (hasSem2 ? _maxSubSemTotal : 0);
      }
    }
    return maximum;
  }

  String get _sem2OnlyPrefsKey => '${_resultPdfSettingsKey}_sem2only_$_selectedClass';

  Future<void> _loadSavedSem2OnlySubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_sem2OnlyPrefsKey);
      if (saved == null || !mounted) return;
      setState(() {
        _sem2OnlySubjects
          ..clear()
          ..addAll(saved.where(_subjects.contains));
        _gridTick++;
      });
    } catch (_) {}
  }

  Future<void> _saveSem2OnlySubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_sem2OnlyPrefsKey, _sem2OnlySubjects.toList());
    } catch (_) {}
  }

  void _autoDetectSem2OnlySubjects() {
    _sem2OnlySubjects.clear();
    unawaited(_loadSavedSem2OnlySubjects());
    if (_students.isEmpty) return;
    for (final sub in _subjects) {
      final hasSem1 = _students.any((s) => s.sem1.containsKey(sub));
      final hasSem2 =
          _students.any((s) => s.studiedInSem2 && s.sem2.containsKey(sub));
      if (!hasSem1 && hasSem2) _sem2OnlySubjects.add(sub);
    }
  }

  void _prepareNewStudentFormDefaults() {
    _newRollCtrl.text = '${_students.length + 1}';
    _newNameCtrl.clear();
    _newCategory = 'બક્ષીપંચ';
    _newGender = context.read<AppState>().schoolType == 'boys'
        ? 'BOYS'
        : context.read<AppState>().schoolType == 'girls'
            ? 'GIRLS'
            : 'UNSPECIFIED';
    _newGrCtrl.clear();
    _newDdCtrl.clear();
    _newMmCtrl.clear();
    _newYyyyCtrl.clear();
    _newUidCtrl.clear();
    _newPenCtrl.clear();
    _newMobileCtrl.clear();
    _newFatherCtrl.clear();
    _newMotherCtrl.clear();
    _newAddressCtrl.clear();
    _newPres1Ctrl.text = '0';
    _newPres2Ctrl.text = '0';
    _newStandardCtrl.text = _cleanClassCode;
    _newStudiedInSem2 = true;
    _newIsDivyang = false;
    _newStudentStep = 0;
  }

  Future<void> _submitNewStudentAtLast() async {
    final state = context.read<AppState>();
    if (!state.isAdmin) {
      showSnack(
          context, 'નવો વિદ્યાર્થી ઉમેરવાનો અધિકાર માત્ર School Admin પાસે છે.',
          error: true);
      return;
    }
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, '⚠️ કૃપા કરી વિદ્યાર્થીનું નામ (Col B) દાખલ કરો.',
          error: true);
      return;
    }
    if (state.resultApi == null || _selectedClass == null) return;
    if (state.schoolType.toLowerCase() == 'coed' &&
        !['BOYS', 'GIRLS'].contains(_newGender)) {
      showSnack(context,
          '⚠️ Co-ed શાળામાં નવા વિદ્યાર્થી માટે Boys અથવા Girls પસંદ કરવું જરૂરી છે.',
          error: true);
      return;
    }

    setState(() {
      _saving = true;
      _alert = null;
    });

    final studentMap = <String, dynamic>{
      'roll': _newRollCtrl.text.trim().isEmpty
          ? '${_students.length + 1}'
          : _newRollCtrl.text.trim(),
      'name': name,
      'category': _newCategory,
      'gender': _newGender,
      'dd': _pad2(_newDdCtrl.text),
      'mm': _pad2(_newMmCtrl.text),
      'yyyy': _newYyyyCtrl.text.trim(),
      'uid': _newUidCtrl.text.trim(),
      'pen': _newPenCtrl.text.trim(),
      'mobile': _newMobileCtrl.text.trim(),
      'fatherName': _newFatherCtrl.text.trim(),
      'motherName': _newMotherCtrl.text.trim(),
      'address': _newAddressCtrl.text.trim(),
      'studiedInSem2': _newStudiedInSem2 ? 'Yes' : 'No',
      'gr': _newGrCtrl.text.trim(),
      'presentDays': int.tryParse(_newPres1Ctrl.text.trim()) ?? 0,
      'presentDays2': int.tryParse(_newPres2Ctrl.text.trim()) ?? 0,
      'standard': _newStandardCtrl.text.trim().isEmpty
          ? _cleanClassCode
          : _newStandardCtrl.text.trim(),
      'isDivyang': _newIsDivyang ? 'YES' : 'NO',
    };

    try {
      final res = await state.resultApi!.addNewStudent(
        className: _selectedClass!,
        studentData: studentMap,
      );
      if (!mounted) return;
      if (res['result'] == 'success') {
        final newStudentId = '${res['studentId'] ?? ''}'.trim();
        Map<String, dynamic>? rosterAddResult;
        if (newStudentId.isNotEmpty &&
            state.resultApi is SupabaseResultApiService) {
          rosterAddResult = await (state.resultApi as SupabaseResultApiService)
              .adminAddResultRosterMember(
            className: _selectedClass!,
            semester: _activeRosterSemester,
            studentId: newStudentId,
          );
        }
        final addedToCurrentRoster = rosterAddResult?['result'] == 'success';
        await _loadData();
        _prepareNewStudentFormDefaults();
        if (addedToCurrentRoster) setState(() => _activeTab = 0);
        setState(() {
          _saving = false;
          _alertIsError = rosterAddResult != null &&
              !addedToCurrentRoster &&
              rosterAddResult['result'] != 'no_snapshot';
          _alert = addedToCurrentRoster
              ? '✅ "$name" ઉમેરાયો. હાલના Result roster માં ઉમેરાયો; જૂના વિદ્યાર્થીઓના ગુણ તેમની ઓળખ પ્રમાણે જળવાયા છે.'
              : (rosterAddResult?['result'] == 'no_snapshot' ||
                      rosterAddResult == null
                  ? '✅ "$name" ઉમેરાયો. હાલના સત્રનો snapshot ન હોય તો હાજરી રજીસ્ટરની તારીખ પસંદ કરીને roster બનાવો.'
                  : '⚠️ "$name" ઉમેરાયો, પરંતુ Result roster અપડેટ ન થયું: ${rosterAddResult?['message'] ?? ''}');
        });
      } else {
        setState(() {
          _saving = false;
          _alertIsError = true;
          _alert = '❌ ${res['message'] ?? 'સેવ કરવામાં ભૂલ'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertIsError = true;
        _alert = '❌ ભૂલ: $e';
      });
    }
  }

  void _updateStudentVvTotal(ResultStudentRow st, String sem, int totalMarks) {
    final clamped = totalMarks.clamp(0, _vvMaxPerSemester);
    final random40 = generateRandom40Sentences(clamped, _vvMaxPerSentence);
    setState(() {
      if (sem == '1') {
        st.vv1 = clamped;
        st.vv1Sentences = random40;
      } else {
        st.vv2 = clamped;
        st.vv2Sentences = random40;
      }
    });
  }

  void _reshuffleAll40Sentences() {
    setState(() {
      for (int i = 0; i < _students.length; i++) {
        final st = _students[i];
        if (_selectedSem == '1') {
          st.vv1Sentences =
              generateRandom40Sentences(st.vv1, _vvMaxPerSentence);
          _markModified(i);
        } else if (st.studiedInSem2) {
          st.vv2Sentences =
              generateRandom40Sentences(st.vv2, _vvMaxPerSentence);
          _markModified(i);
        }
      }
      _gridTick++;
    });
    showSnack(context, '🎲 40 વિધાનોમાં ગુણ રેન્ડમલી ફરી વહેંચાઈ ગયા!');
  }

  Future<void> _configureResultUrl() async {
    if (!mounted) return;
    showSnack(context,
        'Result data and PDF generation use Supabase; no Web App URL is required.');
  }

  Future<bool> _ensureStudentDataPasswordAuthorization(
      {required bool interactive}) async {
    if (_selectedClass == null) return false;
    if (context.read<AppState>().isAdmin) return true;
    final expiry = _studentDataWriteAuthorizationExpiresAt;
    if (expiry != null &&
        DateTime.now().isBefore(expiry) &&
        _studentDataWriteAuthorizationClass == _selectedClass) {
      return true;
    }
    if (!interactive) return false;
    return _promptAndReauthenticateAccount(
      title: 'વિદ્યાર્થીની વિગતો બદલવા માટે પાસવર્ડ આપો',
      message:
          'સાચો લોગિન પાસવર્ડ આપ્યા પછી 5 મિનિટ સુધી આ વર્ગની વિદ્યાર્થી વિગતો સેવ થઈ શકશે.',
      rememberForStudentEdits: true,
    );
  }

  Future<bool> _promptAndReauthenticateAccount({
    required String title,
    required String message,
    bool rememberForStudentEdits = false,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final email = (user?.email ?? '').trim();
    if (user == null || email.isEmpty) {
      if (mounted)
        showSnack(context, 'લોગિન ઈમેલ મળ્યો નથી. ફરી લોગિન કરો.', error: true);
      return false;
    }
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: guFont(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navy)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message,
                  style: guFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate)),
              const SizedBox(height: 10),
              Text('Account: $email',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                onSubmitted: (value) => Navigator.pop(ctx, value),
                decoration: const InputDecoration(
                    labelText: 'Login password', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Confirm password')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty) return false;
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      if (rememberForStudentEdits) {
        _studentDataWriteAuthorizationExpiresAt =
            DateTime.now().add(const Duration(minutes: 5));
        _studentDataWriteAuthorizationClass = _selectedClass;
      }
      return true;
    } catch (_) {
      if (mounted)
        showSnack(context,
            'પાસવર્ડ ખોટો છે અથવા ફરી ચકાસણી નિષ્ફળ ગઈ. કોઈ ડેટા બદલાયો નથી.',
            error: true);
      return false;
    }
  }

  Future<void> _loadRosterSnapshotStatus() async {
    final className = _selectedClass;
    final api = context.read<AppState>().resultApi;
    if (className == null || api is! SupabaseResultApiService) return;
    if (mounted) setState(() => _rosterStatusLoading = true);
    final result = await api.getResultRosterStatus(className);
    if (!mounted || className != _selectedClass) return;
    final rawSemesters = result['semesters'];
    final parsed = <int, Map<String, dynamic>>{};
    if (rawSemesters is Map) {
      for (final semester in const [1, 2]) {
        final entry = rawSemesters['$semester'];
        if (entry is Map) parsed[semester] = Map<String, dynamic>.from(entry);
      }
    }
    setState(() {
      _rosterStatusLoading = false;
      _rosterStatusError = result['result'] == 'success'
          ? null
          : '${result['message'] ?? 'રજીસ્ટર સ્થિતિ મેળવી શકાઈ નથી.'}';
      _rosterSnapshotStatus = parsed;
    });
  }

  Future<void> _importRosterFromRegister() async {
    final className = _selectedClass;
    final api = context.read<AppState>().resultApi;
    if (className == null || api is! SupabaseResultApiService) {
      showSnack(context, 'Supabase પરિણામ સેવા ઉપલબ્ધ નથી.', error: true);
      return;
    }
    final semester = _activeRosterSemester;
    final isAdmin = context.read<AppState>().isAdmin;
    if (_modifiedStudents.isNotEmpty) {
      showSnack(context, 'પહેલાં હાલના ફેરફારો સેવ કરો; પછી રજીસ્ટર આયાત કરો.',
          error: true);
      return;
    }
    await _loadRosterSnapshotStatus();
    if (semester == 2 &&
        _rosterSnapshotStatus[1]?['current'] == null &&
        !isAdmin) {
      if (!mounted) return;
      showSnack(context,
          'પહેલાં પ્રથમ સત્રનો રજીસ્ટર snapshot બનાવો; પછી દ્વિતીય સત્ર આયાત કરો.',
          error: true);
      return;
    }
    final today = DateTime.now();
    if (!mounted) return;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'હાજરી રજીસ્ટરની તારીખ પસંદ કરો',
      cancelText: 'રદ કરો',
      confirmText: 'વિદ્યાર્થી તપાસો',
    );
    if (selectedDate == null || !mounted) return;
    setState(() {
      _rosterActionBusy = true;
      _alert = null;
    });
    try {
      final preview = await api.previewResultRosterFromRegister(
          className: className, sourceDate: selectedDate);
      if (!mounted) return;
      if (preview['result'] != 'success') {
        setState(() {
          _alertIsError = true;
          _alert =
              '${preview['message'] ?? 'આ તારીખનો વિદ્યાર્થી રજીસ્ટર ઉપલબ્ધ નથી.'}';
        });
        return;
      }
      final students = (preview['students'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
              semester == 1
                  ? 'પ્રથમ સત્રનો વિદ્યાર્થી રજીસ્ટર'
                  : 'દ્વિતીય સત્રનો વિદ્યાર્થી રજીસ્ટર',
              style: guFont(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    'વર્ગ: $className • તારીખ: ${preview['sourceDate']} • વિદ્યાર્થી: ${preview['count']}',
                    style: guFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                const SizedBox(height: 8),
                const Text(
                    'આ ફક્ત preview છે. પાસવર્ડ ચકાસ્યા પછી જ આ roster વર્તમાન સ્નેપશોટ બનશે. જૂના સ્નેપશોટ ડિલીટ નહીં થાય.'),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final student = students[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                            radius: 15,
                            child: Text('${student['roll_number'] ?? ''}',
                                style: const TextStyle(fontSize: 10))),
                        title: Text('${student['name'] ?? ''}',
                            style: guFont(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${student['category'] ?? ''} • ${student['gender'] ?? ''}',
                            style: const TextStyle(fontSize: 11)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('રદ કરો')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('આ યાદી વાપરો')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      // Always ask again before replacing a snapshot. The database independently enforces a recent auth_time.
      final passwordConfirmed = isAdmin
          ? true
          : await _promptAndReauthenticateAccount(
              title: 'રજીસ્ટર બદલવા માટે પાસવર્ડ જરૂરી',
              message:
                  'આ ક્રિયા પસંદ કરેલા સત્રનો વર્તમાન roster બદલી દેશે. સાચો પાસવર્ડ ન આપો તો કોઈ data rewrite થશે નહીં.',
            );
      if (!passwordConfirmed || !mounted) return;
      final committed = await api.replaceResultRosterFromRegister(
        className: className,
        semester: semester,
        sourceDate: selectedDate,
      );
      if (!mounted) return;
      if (committed['result'] != 'success') {
        setState(() {
          _alertIsError = true;
          _alert = '${committed['message'] ?? 'રજીસ્ટર સેવ કરવામાં ભૂલ.'}';
        });
        return;
      }
      await _loadData();
      await _loadRosterSnapshotStatus();
      if (!mounted) return;
      setState(() {
        _alertIsError = false;
        _alert =
            '✅ $className સત્ર-$semester માટે ${committed['count'] ?? preview['count']} વિદ્યાર્થી સેવ થયા. અગાઉના snapshots જાળવ્યા છે.';
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _alertIsError = true;
          _alert = '❌ રજીસ્ટર આયાત નિષ્ફળ: $error';
        });
    } finally {
      if (mounted) setState(() => _rosterActionBusy = false);
    }
  }

  Widget _buildSemesterRosterSelector(AppState state) {
    final status = _rosterSnapshotStatus[_activeRosterSemester] ??
        const <String, dynamic>{};
    final current = status['current'] is Map
        ? Map<String, dynamic>.from(status['current'] as Map)
        : null;
    final versionCount = status['versionCount'] is num
        ? (status['versionCount'] as num).toInt()
        : 0;
    final firstSnapshotReady = _rosterSnapshotStatus[1]?['current'] != null;
    final statusText = _rosterStatusLoading
        ? 'રજીસ્ટર સ્નેપશોટની સ્થિતિ તપાસાઈ રહી છે…'
        : current == null
            ? 'હજુ snapshot સેવ નથી. હાલ માત્ર જૂની roster દેખાઈ શકે છે; marks entry અને PDF માટે પહેલાં register snapshot આયાત કરો.'
            : 'હાલનો snapshot: ${current['source_date']} • ${current['roster_count'] ?? 0} વિદ્યાર્થી • સાચવેલી આવૃત્તિઓ: $versionCount';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.slateLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('વિદ્યાર્થી ડેટા રજીસ્ટર — સત્ર પ્રમાણે',
              style: guFont(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text('પ્રથમ સત્રના વિદ્યાર્થીઓ',
                  style: guFont(fontSize: 12, fontWeight: FontWeight.w800)),
              selected: _activeRosterSemester == 1,
              onSelected: _rosterActionBusy
                  ? null
                  : (selected) {
                      if (!selected || _activeRosterSemester == 1) return;
                      if (_modifiedStudents.isNotEmpty) {
                        showSnack(context,
                            'પહેલાં ફેરફાર સેવ કરો; પછી વિદ્યાર્થી ડેટા ટેબ બદલો.',
                            error: true);
                        return;
                      }
                      setState(() {
                        _activeRosterSemester = 1;
                        _selectedSem = '1';
                      });
                      state.setLastSemester('1');
                      _loadData();
                    },
            ),
            ChoiceChip(
              label: Text('દ્વિતીય સત્રના વિદ્યાર્થીઓ',
                  style: guFont(fontSize: 12, fontWeight: FontWeight.w800)),
              selected: _activeRosterSemester == 2,
              onSelected: _rosterActionBusy
                  ? null
                  : (selected) {
                      if (!selected || _activeRosterSemester == 2) return;
                      if (_modifiedStudents.isNotEmpty) {
                        showSnack(context,
                            'પહેલાં ફેરફાર સેવ કરો; પછી વિદ્યાર્થી ડેટા ટેબ બદલો.',
                            error: true);
                        return;
                      }
                      setState(() {
                        _activeRosterSemester = 2;
                        _selectedSem = '2';
                      });
                      state.setLastSemester('2');
                      _loadData();
                    },
            ),
          ]),
          const SizedBox(height: 6),
          Text(statusText,
              style: guFont(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate)),
          const SizedBox(height: 4),
          Text(
            'નોંધ: Student Database માં નવા સક્રિય વિદ્યાર્થી ઉમેરાય તો Result માં આપમેળે ખાલી ગુણ સાથે દેખાશે. વિદ્યાર્થીની સુધારેલી વિગતો ફરી લોડ થશે; જૂના roster snapshots અને સાચવેલા ગુણ જળવાશે.',
            style: guFont(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.slate),
          ),
          if (_rosterStatusError != null) ...[
            const SizedBox(height: 4),
            Text(_rosterStatusError!,
                style: guFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rose)),
          ],
          if (_activeRosterSemester == 2 &&
              !firstSnapshotReady &&
              !state.isAdmin) ...[
            const SizedBox(height: 4),
            Text('દ્વિતીય સત્ર પહેલાં પ્રથમ સત્રનો snapshot બનાવવો જરૂરી છે.',
                style: guFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.rose)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: _rosterActionBusy
                  ? 'રજીસ્ટર ચકાસી/સેવ થઈ રહ્યું છે…'
                  : '📅 હાજરી રજીસ્ટરની તારીખ પસંદ કરો અને વિદ્યાર્થી ડેટા મેળવો (પાસવર્ડ જરૂરી)',
              background: AppColors.teal,
              loading: _rosterActionBusy,
              onPressed: (_rosterActionBusy || _loading || _saving)
                  ? null
                  : _importRosterFromRegister,
            ),
          ),
          const SizedBox(height: 4),
          Text(
              'જૂના snapshots ક્યારેય ડિલીટ થતા નથી. દ્વિતીય સત્રના રજીસ્ટરમાં નામ ન હોય તો વિદ્યાર્થી પ્રથમ સત્રમાં રહેશે અને દ્વિતીય સત્રમાં “નામ કમી” ગણાશે.',
              style: guFont(
                  fontSize: 10.8,
                  fontWeight: FontWeight.w500,
                  color: AppColors.slate)),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    if (_selectedClass == null) return;
    await _loadRegisteredSchoolBranding();
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.resultApi == null) {
      setState(() {
        _loading = false;
        _alertIsError = true;
        _alert =
            '⚠️ Supabase પરિણામ સેવા ઉપલબ્ધ નથી. એપ ફરી શરૂ કરીને ફરી પ્રયાસ કરો.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _alert = null;
    });

    try {
      final data = state.resultApi is SupabaseResultApiService
          ? await (state.resultApi as SupabaseResultApiService)
              .getResultDataForSemester(_selectedClass!,
                  rosterSemester: _activeRosterSemester)
          : await state.resultApi!.getResultData(_selectedClass!);
      if (!mounted) return;
      for (final st in data.students) {
        final cleanCat = st.category.replaceAll(' ', '');
        if (cleanCat.contains('અ.જ.જા')) {
          st.category = 'અ.જ.જા.';
        } else if (cleanCat.contains('અ.જા')) {
          st.category = 'અ.જા.';
        } else if (cleanCat.contains('બક્ષી') || cleanCat.contains('બ.')) {
          st.category = 'બક્ષીપંચ';
        } else if (cleanCat.contains('અન્ય')) {
          st.category = 'અન્ય';
        }
        if (st.vv1 > 0 && st.vv1Sentences.every((e) => e == 0)) {
          st.vv1Sentences =
              generateRandom40Sentences(st.vv1, _vvMaxPerSentence);
        }
        if (st.studiedInSem2 &&
            st.vv2 > 0 &&
            st.vv2Sentences.every((e) => e == 0)) {
          st.vv2Sentences =
              generateRandom40Sentences(st.vv2, _vvMaxPerSentence);
        }
      }
      setState(() {
        _loading = false;
        _subjects = data.subjects;
        _assignedSubjects = data.assignedSubjects;
        _isClassTeacher = data.isClassTeacher;
        _vvSentences = data.vvSentences.length == 40
            ? List<String>.from(data.vvSentences)
            : List<String>.from(kVv40Sentences);
        _students = List<ResultStudentRow>.from(data.students)
          ..sort((a, b) {
            final rollA = int.tryParse(a.roll.trim());
            final rollB = int.tryParse(b.roll.trim());
            if (rollA != null && rollB != null) {
              final result = rollA.compareTo(rollB);
              if (result != 0) return result;
            } else if (rollA != null) {
              return -1;
            } else if (rollB != null) {
              return 1;
            }
            final byRoll = a.roll.toLowerCase().compareTo(b.roll.toLowerCase());
            if (byRoll != 0) return byRoll;
            final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            if (byName != 0) return byName;
            return a.studentId.compareTo(b.studentId);
          });
        // Class teacher, school name and class are sourced automatically.
        _classTeacherName = data.teacherName;
        _firstSemResultDate = data.firstSemResultDate.trim().isNotEmpty
            ? data.firstSemResultDate.trim()
            : ResultSheetData.defaultFirstSemResultDateForNow();
        _resultDate = data.resultDate.trim().isNotEmpty
            ? data.resultDate.trim()
            : ResultSheetData.defaultSecondSemResultDateForNow();
        _academicYear = data.academicYear;
        _frontPageDistrict = data.frontPageDistrict.trim().isNotEmpty
            ? data.frontPageDistrict
            : _brandText(_brandingProfile['district'] ??
                _brandingProfile['district_name'] ??
                _brandingProfile['districtName']);
        _frontPageEducationAuthority =
            data.frontPageEducationAuthority.trim().isNotEmpty
                ? data.frontPageEducationAuthority
                : _brandText(_brandingProfile['education_authority_name'] ??
                    _brandingProfile['educationAuthorityName']);
        _frontPageVillage = data.frontPageVillage.trim().isNotEmpty
            ? data.frontPageVillage
            : _brandText(_brandingProfile['village']);
        _frontPageTaluka = data.frontPageTaluka.trim().isNotEmpty
            ? data.frontPageTaluka
            : _brandText(_brandingProfile['taluka']);
        _frontPagePayCenter = data.frontPagePayCenter.trim().isNotEmpty
            ? data.frontPagePayCenter
            : _brandText(_brandingProfile['centerName'] ??
                _brandingProfile['center_name'] ??
                _brandingProfile['pay_center']);
        _frontPageCrc = data.frontPageCrc.trim().isNotEmpty
            ? data.frontPageCrc
            : _brandText(
                _brandingProfile['crcName'] ?? _brandingProfile['crc_name']);
        _frontPageSettingsRevision++;
        _sem1Locked = data.sem1Locked; // નવું
        _sem2Locked = data.sem2Locked; // નવું
        _autoDetectSem2OnlySubjects();
        if (_selectedSubject == kSubjectVV &&
            !(_isClassTeacher || state.isAdmin)) {
          _selectedSubject = null;
        }
        if (_selectedSubject != kSubjectVV &&
            (_selectedSubject == null ||
                !_dropdownSubjects.contains(_selectedSubject))) {
          _selectedSubject =
              _dropdownSubjects.isNotEmpty ? _dropdownSubjects.first : null;
        }
        _newRollCtrl.text = '${_students.length + 1}';
        _modifiedStudents.clear();
        _dirtyScopesByStudent.clear();
        _gridTick++;
      });
      await _loadRosterSnapshotStatus();
      await _restoreLocalResultDraft();
      await _autoFetchStudentWisePresentDaysForResult();
      await _loadSavedSatrantExamDates();
      if (_selectedSubject != null && _selectedSubject != kSubjectVV) {
        unawaited(_resolveAndVerifySubjectExamDate(
          subject: _selectedSubject!,
          promptIfMissing: false,
        ));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _alertIsError = true;
        _alert = '❌ ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _alertIsError = true;
        _alert = '❌ Error: $e';
      });
    }
  }

  Future<void> _autoFetchStudentWisePresentDaysForResult() async {
    if (_students.isEmpty || (_selectedClass ?? '').trim().isEmpty) return;
    try {
      final yearMatch = RegExp(r'(20\d{2})').firstMatch(_academicYear);
      final now = DateTime.now();
      final startYear = yearMatch != null
          ? (int.tryParse(yearMatch.group(1)!) ??
              (now.month >= 6 ? now.year : now.year - 1))
          : (now.month >= 6 ? now.year : now.year - 1);
      final classId =
          await SupabaseClassService().resolveClassId(_selectedClass ?? '');
      if (classId.trim().isEmpty) return;

      final studentMaps = <Map<String, dynamic>>[
        for (final st in _students)
          if (st.name.trim().isNotEmpty)
            <String, dynamic>{
              'id': _studentPrintKey(st),
              'roll_number': st.roll,
              'name': st.name,
              'present_days': st.presentDays,
            },
      ];
      if (studentMaps.isEmpty) return;

      final sem1Data =
          await SupabaseHajariPatrakService().getPresentDaysForDateRange(
        classId: classId,
        fromDate: DateTime(startYear, 6, 1),
        throughDate: DateTime(startYear, 10, 31),
        students: studentMaps,
        includeAcademicYearOverrides: true,
      );
      final sem2Data =
          await SupabaseHajariPatrakService().getPresentDaysForDateRange(
        classId: classId,
        fromDate: DateTime(startYear, 11, 1),
        throughDate: DateTime(startYear + 1, 5, 15),
        students: studentMaps,
        includeAcademicYearOverrides: false,
      );

      final rawSem1 = sem1Data['days_by_student_id'];
      final rawSem2 = sem2Data['days_by_student_id'];
      var changed = false;
      for (final st in _students) {
        final key = _studentPrintKey(st);
        if (rawSem1 is Map) {
          final v1 = rawSem1[key];
          final p1 = v1 is num ? v1.toInt() : int.tryParse('$v1');
          if (p1 != null && p1 > 0 && st.presentDays <= 0) {
            st.presentDays = p1;
            changed = true;
          }
        }
        if (rawSem2 is Map) {
          final v2 = rawSem2[key];
          final p2 = v2 is num ? v2.toInt() : int.tryParse('$v2');
          if (p2 != null && p2 > 0 && st.presentDays2 <= 0) {
            st.presentDays2 = p2;
            changed = true;
          }
        }
      }
      if (changed && mounted) {
        setState(() => _gridTick++);
      }
    } catch (_) {}
  }

  Map<int, String> _captureModifiedStudentVersions({required String scope}) {
    return <int, String>{
      for (final index in _modifiedStudents)
        if (index >= 0 &&
            index < _students.length &&
            _students[index].studentId.trim().isNotEmpty &&
            ((_dirtyScopesByStudent[index]?.isEmpty ?? true) ||
                _dirtyScopesByStudent[index]!.contains(scope)))
          index: jsonEncode(_serializeResultStudent(_students[index])),
    };
  }

  void _clearUnchangedModifiedStudents(
    Map<int, String> capturedVersions, {
    required String scope,
  }) {
    for (final entry in capturedVersions.entries) {
      final index = entry.key;
      if (index < 0 || index >= _students.length) continue;
      final current = jsonEncode(_serializeResultStudent(_students[index]));
      // Do not clear a changed row during an in-flight save. Also retain any
      // other subject's/device draft scope until that subject is explicitly saved.
      if (current != entry.value) continue;
      final scopes = _dirtyScopesByStudent[index];
      scopes?.remove(scope);
      if (scopes == null || scopes.isEmpty) {
        _dirtyScopesByStudent.remove(index);
        _modifiedStudents.remove(index);
      }
    }
  }

  Future<void> _saveCurrentData({bool isAutoSave = false}) async {
    // A cloud write is never triggered by a timer. Only the visible Save button
    // may call this method; all pre-save edits are held in SharedPreferences.
    if (isAutoSave) return;
    if (_selectedClass == null || _saving || _activeTab == 4) return;
    final state = context.read<AppState>();
    if (state.resultApi == null) return;
    if (state.resultApi is SupabaseResultApiService &&
        !_hasCurrentRosterSnapshot) {
      showSnack(context,
          'પહેલાં ઉપરથી આ સત્ર માટે હાજરી રજીસ્ટર તારીખ પસંદ કરી પાસવર્ડથી roster સેવ કરો.',
          error: true);
      return;
    }
    if (_activeTab == 0 && _selectedSubject == null) {
      showSnack(context,
          'ગુણ સેવ કરવા પહેલાં ફાળવેલ વિષય પસંદ કરો અથવા વર્ગશિક્ષક મૂલ્યાંકન પસંદ કરો.',
          error: true);
      return;
    }
    if (_activeTab == 1 || _activeTab == 2 || _activeTab == 3) {
      if (!await _ensureStudentDataPasswordAuthorization(interactive: true))
        return;
    }
    if (_activeTab == 3) {
      await _submitNewStudentAtLast();
      return;
    }

    // Capture exact row versions so changes typed during an in-flight save
    // remain as an unsent local draft instead of being cleared accidentally.
    final saveScope = (_activeTab == 1 || _activeTab == 2)
        ? '__STUDENT_PROFILES__'
        : (_selectedSubject ?? '').trim();
    final syncingVersions = _captureModifiedStudentVersions(scope: saveScope);
    final Set<int> syncingStudents = syncingVersions.keys.toSet();
    if (syncingStudents.isEmpty) {
      if (!mounted) return;
      showSnack(context, 'આ વિષય/વિગતો માટે ઉપકરણમાં કોઈ નવો ફેરફાર નથી.');
      return;
    }
    if ((_activeTab == 1 || _activeTab == 2) &&
        state.schoolType.toLowerCase() == 'coed') {
      final missingGender = syncingStudents
          .where((i) =>
              i >= 0 &&
              i < _students.length &&
              !['BOYS', 'GIRLS'].contains(_students[i].gender.toUpperCase()))
          .toList();
      if (missingGender.isNotEmpty) {
        if (!mounted) return;
        showSnack(context,
            '⚠️ વિગતો સેવ કરતાં પહેલાં દરેક પસંદ કરેલા વિદ્યાર્થીનું Gender (Boys/Girls) નોંધો.',
            error: true);
        return;
      }
    }

    setState(() {
      _saving = true;
      if (!isAutoSave) _alert = null;
    });
    // First commit the pending draft to this device. If the network fails,
    // the user's last edits remain recoverable after closing or refreshing.
    await _persistLocalResultDraft();

    try {
      late final String apiSubject;
      late final List<Map<String, dynamic>> payload;

      if (_activeTab == 1 || _activeTab == 2) {
        final allItems = <Map<String, dynamic>>[
          {
            'isMeta': true,
            'teacherName': _classTeacherName,
            'resultDate': _resultDate,
            'academicYear': _academicYear,
          },
          for (int i = 0; i < _students.length; i++)
            if (_students[i].name.trim().isNotEmpty &&
                syncingStudents.contains(i))
              {
                'idx': i,
                'sheetRow': 2 + i,
                'studentId': _students[i].studentId,
                'roll':
                    _students[i].roll.isEmpty ? '${i + 1}' : _students[i].roll,
                'name': _students[i].name.trim(),
                'category': _students[i].category.trim(),
                'gender': _students[i].gender.trim(),
                'dd': _pad2(_students[i].dd),
                'mm': _pad2(_students[i].mm),
                'yyyy': _students[i].yyyy.trim(),
                'uid': _students[i].uid.trim(),
                'pen': _students[i].pen.trim(),
                'mobile': _students[i].mobile.trim(),
                'fatherName': _students[i].fatherName.trim(),
                'motherName': _students[i].motherName.trim(),
                'address': _students[i].address.trim(),
                'studiedInSem2': _students[i].studiedInSem2 ? 'Yes' : 'No',
                'gr': _students[i].gr.trim(),
                'presentDays': _students[i].presentDays,
                'presentDays2': _students[i].presentDays2,
                'standard': _students[i].standard.trim(),
                'isDivyang': _students[i].isDivyang ? 'YES' : 'NO',
              },
        ];

        // Send in small batches of 6 items so the GET URL never exceeds Google's length limit (Fixes HTTP 400!)
        const int batchSize = 6;
        Map<String, dynamic> lastRes = {'result': 'success'};
        bool networkError = false;

        for (int start = 0; start < allItems.length; start += batchSize) {
          final isLastBatch = (start + batchSize) >= allItems.length;
          final chunk = allItems.sublist(
              start, isLastBatch ? allItems.length : (start + batchSize));
          try {
            lastRes = await state.resultApi!.saveSubjectMarks(
              className: _selectedClass!,
              sem: _selectedSem == 'Annual' ? '2' : _selectedSem,
              subject: '__STUDENT_PROFILES__',
              entryCombo: isLastBatch ? 'chunk_final' : 'chunk_part',
              payload: chunk,
            );
            if (lastRes['result'] != 'success') break;
          } catch (e) {
            networkError = true;
          }
        }

        if (!mounted) return;
        if (!networkError && lastRes['result'] == 'success') {
          _clearUnchangedModifiedStudents(syncingVersions, scope: saveScope);
          await _persistLocalResultDraft();
        }
        setState(() {
          _saving = false;
          if (networkError) {
            _alertIsError = true;
            _alert =
                '❌ Firebase સાથે કનેક્શન થયું નથી. તમારી વિગતો આ ઉપકરણમાં સુરક્ષિત છે; નેટવર્ક આવ્યા પછી ફરી Save દબાવો.';
          } else {
            _alertIsError = lastRes['result'] != 'success';
            final timeStr = TimeOfDay.now().format(context);
            _alert = lastRes['result'] == 'success'
                ? '✅ $_cleanClassCode ની વિગતો Firebase માં સેવ થઈ ગઈ! ($timeStr)'
                : '❌ ${lastRes['message'] ?? 'Save error'}';
          }
        });
        return;
      } else {
        final sub = _selectedSubject!;

        final modifiedList = _students
            .asMap()
            .entries
            .where((e) => syncingStudents.contains(e.key))
            .map((e) => e.value)
            .toList();

        if (modifiedList.isEmpty) {
          setState(() {
            _saving = false;
            _alertIsError = false;
            _alert = '✅ કોઈ નવો ફેરફાર નથી (Already up to date)!';
          });
          return;
        }

        if (sub == kSubjectVV) {
          apiSubject = kSubjectVV;
          payload = modifiedList.map((st) {
            final isSem2 = _selectedSem != '1';
            final activeVal = isSem2 ? (st.studiedInSem2 ? st.vv2 : 0) : st.vv1;
            var sentences = isSem2 ? st.vv2Sentences : st.vv1Sentences;
            if (activeVal > 0 &&
                sentences.fold<int>(0, (a, b) => a + b) != activeVal) {
              sentences =
                  generateRandom40Sentences(activeVal, _vvMaxPerSentence);
            }
            var sentences1 = st.vv1Sentences;
            if (st.vv1 > 0 &&
                sentences1.fold<int>(0, (a, b) => a + b) != st.vv1) {
              sentences1 =
                  generateRandom40Sentences(st.vv1, _vvMaxPerSentence);
            }
            return {
              'sheetRow': st.sheetRow,
              'studentId': st.studentId,
              'vv': activeVal,
              'vv1': st.vv1,
              'vv2': st.studiedInSem2 ? st.vv2 : 0,
              'avg': st.vvAvgBothSem,
              'sentences': sentences,
              'sentences1': sentences1,
            };
          }).toList();
        } else if (_isBothSemCombo) {
          apiSubject = sub;
          payload = modifiedList.map((st) {
            final m1 = st.sem1[sub] ?? const SubjectMarks();
            final m2 = st.sem2[sub] ?? const SubjectMarks();
            return {
              'sheetRow': st.sheetRow,
              'studentId': st.studentId,
              'a1': m1.patrakA,
              's1': m1.satrantAbsent ? 0 : m1.satrant,
              'satrantAbsent1': m1.satrantAbsent,
              'sw1': m1.swaAdhyayan,
              'directTotal1': m1.directTotal,
              'directMode1': _useSem1DirectOutOf100 || m1.usesDirectTotal,
              'a2': st.studiedInSem2 ? m2.patrakA : 0,
              's2': st.studiedInSem2 ? (m2.satrantAbsent ? 0 : m2.satrant) : 0,
              'satrantAbsent2': st.studiedInSem2 ? m2.satrantAbsent : false,
              'sw2': st.studiedInSem2 ? m2.swaAdhyayan : 0,
            };
          }).toList();
        } else {
          apiSubject = sub;
          payload = modifiedList.map((st) {
            final m = (_selectedSem == '1' ? st.sem1[sub] : st.sem2[sub]) ??
                const SubjectMarks();
            return {
              'sheetRow': st.sheetRow,
              'studentId': st.studentId,
              'a': (_selectedSem != '1' && !st.studiedInSem2) ? 0 : m.patrakA,
              's': (_selectedSem != '1' && !st.studiedInSem2)
                  ? 0
                  : (m.satrantAbsent ? 0 : m.satrant),
              'satrantAbsent': (_selectedSem != '1' && !st.studiedInSem2)
                  ? false
                  : m.satrantAbsent,
              'sw': (_selectedSem != '1' && !st.studiedInSem2)
                  ? 0
                  : m.swaAdhyayan,
              'directTotal': _selectedSem == '1' ? m.directTotal : null,
              'directMode': _selectedSem == '1' && m.usesDirectTotal,
            };
          }).toList();
        }
      }

      // Send in safe batches when saving 40-sentence Vyaktitva Vikas so URL never hits HTTP 400 on mobile
      final int markBatchSize = apiSubject == kSubjectVV ? 8 : 25;
      Map<String, dynamic> res = {'result': 'success'};
      bool networkError = false;

      for (int start = 0; start < payload.length; start += markBatchSize) {
        final end = (start + markBatchSize) > payload.length
            ? payload.length
            : (start + markBatchSize);
        final chunk = payload.sublist(start, end);
        try {
          res = await state.resultApi!.saveSubjectMarks(
            className: _selectedClass!,
            sem: _selectedSem == 'Annual' ? '2' : _selectedSem,
            subject: apiSubject,
            entryCombo: _entryCombo,
            payload: chunk,
          );
          if (res['result'] != 'success') break;
        } catch (e) {
          networkError = true;
        }
      }

      if (!mounted) return;
      if (!networkError && res['result'] == 'success') {
        _clearUnchangedModifiedStudents(syncingVersions, scope: saveScope);
        await _persistLocalResultDraft();
      }
      setState(() {
        _saving = false;
        if (networkError) {
          _alertIsError = true;
          _alert =
              '❌ Firebase સાથે કનેક્શન થયું નથી. તમારા ગુણ આ ઉપકરણમાં સુરક્ષિત છે; નેટવર્ક આવ્યા પછી ફરી Save દબાવો.';
        } else {
          _alertIsError = res['result'] != 'success';
          final timeStr = TimeOfDay.now().format(context);
          _alert = res['result'] == 'success'
              ? '✅ $_cleanClassCode નો ડેટા Firebase માં સેવ થઈ ગયો! ($timeStr)'
              : '❌ ${res['message'] ?? 'Save error'}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertIsError = true;
        _alert = '❌ Error: $e';
      });
    }
  }

  Future<void> _pasteFromExcel() async {
    if (_activeTab == 0 && _selectedSubject == null) {
      showSnack(
          context, 'પહેલાં ફાળવેલ વિષય અથવા વર્ગશિક્ષક મૂલ્યાંકન પસંદ કરો.',
          error: true);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (!mounted) return;
      showSnack(context, 'Clipboard ખાલી છે! પહેલા Excel માંથી Copy કરો.',
          error: true);
      return;
    }

    final lines =
        raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

    setState(() {
      if (_activeTab == 1) {
        for (int i = 0; i < lines.length && i < _students.length; i++) {
          final cols = lines[i].split('\t').map((c) => c.trim()).toList();
          if (cols.isEmpty) continue;
          _markModified(i);
          final st = _students[i];
          switch (_selectedDetailField) {
            case 'roll_name':
              st.roll = cols[0];
              if (cols.length > 1) st.name = cols[1];
              break;
            case 'gr':
              st.gr = cols[0];
              break;
            case 'dob':
              if (cols.length >= 3) {
                st.dd = cols[0];
                st.mm = cols[1];
                st.yyyy = cols[2];
              } else if (cols[0].contains('/') || cols[0].contains('-')) {
                final parts = cols[0].split(RegExp(r'[/-]'));
                if (parts.length == 3) {
                  st.dd = parts[0];
                  st.mm = parts[1];
                  st.yyyy = parts[2];
                }
              }
              break;
            case 'present':
              final d = int.tryParse(cols[0]) ?? 0;
              if (_selectedSem == '1') {
                st.presentDays = d;
              } else {
                st.presentDays2 = d;
              }
              break;
            case 'category':
              st.category = cols[0];
              break;
            case 'gender':
              final v = cols[0].toUpperCase().trim();
              st.gender = (v == 'BOYS' || v == 'BOY' || v == 'છોકરો')
                  ? 'BOYS'
                  : (v == 'GIRLS' || v == 'GIRL' || v == 'છોકરી')
                      ? 'GIRLS'
                      : 'UNSPECIFIED';
              break;
            case 'uid_pen':
              st.uid = cols[0];
              if (cols.length > 1) st.pen = cols[1];
              break;
            case 'parents':
              st.mobile = cols[0];
              if (cols.length > 1) st.fatherName = cols[1];
              if (cols.length > 2) st.motherName = cols[2];
              if (cols.length > 3) st.address = cols[3];
              break;
            case 'sem2_status':
              final v = cols[0].toLowerCase();
              st.studiedInSem2 =
                  !(v == 'no' || v == 'ના' || v == 'નામ કમી' || v == '0');
              break;
            case 'divyang':
              final v = cols[0].toLowerCase();
              st.isDivyang = (v == 'yes' ||
                  v == 'y' ||
                  v == 'હા' ||
                  v == '1' ||
                  v == 'true');
              break;
          }
        }
      } else if (_activeTab == 2) {
        for (int i = 0; i < lines.length; i++) {
          final cols = lines[i].split('\t').map((c) => c.trim()).toList();
          if (cols.isEmpty) continue;
          _markModified(i);
          if (i >= _students.length) {
            _students.add(
              ResultStudentRow(
                sheetRow: 2 + i,
                roll: '${i + 1}',
                name: '',
                gr: '',
                dd: '',
                mm: '',
                yyyy: '',
                category: 'બક્ષીપંચ',
                presentDays: 0,
                sem1: {},
                sem2: {},
              ),
            );
          }
          final st = _students[i];
          if (cols.isNotEmpty && cols[0].isNotEmpty) st.roll = cols[0];
          if (cols.length > 1) st.name = cols[1];
          if (cols.length > 2) st.category = cols[2];
          if (cols.length > 3) st.dd = cols[3];
          if (cols.length > 4) st.mm = cols[4];
          if (cols.length > 5) st.yyyy = cols[5];
          if (cols.length > 6) st.uid = cols[6];
          if (cols.length > 7) st.pen = cols[7];
          if (cols.length > 8) st.mobile = cols[8];
          if (cols.length > 9) st.fatherName = cols[9];
          if (cols.length > 10) st.motherName = cols[10];
          if (cols.length > 11) st.address = cols[11];
          if (cols.length > 12) {
            final mVal = cols[12].toLowerCase();
            st.studiedInSem2 =
                !(mVal == 'no' || mVal == 'ના' || mVal == 'નામ કમી');
          }
          if (cols.length > 13) st.gr = cols[13];
          if (cols.length > 14) st.presentDays = int.tryParse(cols[14]) ?? 0;
          if (cols.length > 15) st.presentDays2 = int.tryParse(cols[15]) ?? 0;
          if (cols.length > 16) st.standard = cols[16];
          if (cols.length > 17) {
            final rVal = cols[17].toLowerCase();
            st.isDivyang = (rVal == 'yes' ||
                rVal == 'y' ||
                rVal == 'હા' ||
                rVal == '1' ||
                rVal == 'true');
          }
          if (cols.length > 18) {
            final gender = cols[18].toUpperCase();
            st.gender = (gender == 'BOYS' ||
                    gender == 'BOY' ||
                    gender == 'છોકરો')
                ? 'BOYS'
                : (gender == 'GIRLS' || gender == 'GIRL' || gender == 'છોકરી')
                    ? 'GIRLS'
                    : 'UNSPECIFIED';
          }
        }
      }
      _gridTick++;
    });

    if (_activeTab == 0 && _selectedSubject != null) {
      final sub = _selectedSubject!;
      final satrantMax = _examEntryFrom80 ? 80 : _maxSatrant;
      final overMaxWarnings = <String>[];
      final absentStudentsWithMarks = <String>[];

      bool isAbToken(String token) {
        final t = token.trim().toUpperCase();
        return t == 'AB' || t == 'ABSENT' || t == 'ગેરહાજર';
      }

      // Pre-scan for Absent (AB) students who have numeric Satrant marks in Excel paste
      if (sub != kSubjectVV && (_showS || _isBothSemCombo)) {
        for (int i = 0; i < lines.length && i < _students.length; i++) {
          final st = _students[i];
          if (!_isBothSemCombo && _selectedSem != '1' && !st.studiedInSem2) {
            continue;
          }
          final rawCols =
              lines[i].split('\t').map((c) => _toAsciiDigitsLocal(c.trim())).toList();
          if (rawCols.isEmpty) continue;
          if (_isBothSemCombo) {
            final prev1 = st.sem1[sub] ?? const SubjectMarks();
            final prev2 = st.sem2[sub] ?? const SubjectMarks();
            final s1Idx = _useSem1DirectOutOf100 ? -1 : 1;
            final s2Idx = _useSem1DirectOutOf100 ? 2 : 4;
            final s1Val = (s1Idx >= 0 && s1Idx < rawCols.length)
                ? (int.tryParse(rawCols[s1Idx]) ?? 0)
                : 0;
            final s2Val = (s2Idx >= 0 && s2Idx < rawCols.length)
                ? (int.tryParse(rawCols[s2Idx]) ?? 0)
                : 0;
            if ((prev1.satrantAbsent && s1Val > 0) ||
                (prev2.satrantAbsent && s2Val > 0)) {
              absentStudentsWithMarks.add('${st.roll}. ${st.name}');
            }
          } else {
            final prev = (_selectedSem == '1' ? st.sem1[sub] : st.sem2[sub]) ??
                const SubjectMarks();
            int cursor = _showA ? 1 : 0;
            if (_showS && cursor < rawCols.length) {
              final sVal = int.tryParse(rawCols[cursor]) ?? 0;
              if (prev.satrantAbsent && sVal > 0) {
                absentStudentsWithMarks.add('${st.roll}. ${st.name}');
              }
            }
          }
        }
      }

      bool allowAbsentStudentMarks = false;
      if (absentStudentsWithMarks.isNotEmpty && mounted) {
        final confirmAbsent = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dCtx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '⚠️ ગેરહાજર (AB) વિદ્યાર્થીઓ માટે ચેતવણી',
              style: guFont(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.rose),
            ),
            content: SingleChildScrollView(
              child: Text(
                'નીચેના વિદ્યાર્થી(ઓ) સત્રાંત પરીક્ષામાં ગેરહાજર (AB) નોંધાયેલ હતા:\n\n• ${absentStudentsWithMarks.join("\n• ")}\n\nશું તેમણે પાછળથી પરીક્ષા આપી છે અને તેમના સત્રાંત ગુણ સ્વીકારવા છે કે AB જ રાખવા છે?',
                style: guFont(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: Text('ના, AB જ રાખો',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.greenDeep),
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text('હા, ગુણ સ્વીકારો',
                    style: guFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
        );
        allowAbsentStudentMarks = confirmAbsent == true;
      }

      int checkCap({
        required String studentName,
        required String partLabel,
        required int value,
        required int max,
        required int fallback,
      }) {
        if (value > max) {
          overMaxWarnings
              .add('$studentName ($partLabel): $value ગુણ [મહત્તમ $max]');
          return fallback;
        }
        return value < 0 ? 0 : value;
      }

      setState(() {
        for (int i = 0; i < lines.length && i < _students.length; i++) {
          final rawCols =
              lines[i].split('\t').map((c) => _toAsciiDigitsLocal(c.trim())).toList();
          if (rawCols.isEmpty) continue;
          final cols = rawCols.map((c) => int.tryParse(c) ?? 0).toList();
          _markModified(i);
          final st = _students[i];
          if (!_isBothSemCombo && _selectedSem != '1' && !st.studiedInSem2) {
            continue;
          }

          if (sub == kSubjectVV) {
            final prevVv = _selectedSem == '1' ? st.vv1 : st.vv2;
            final tot = checkCap(
              studentName: st.name,
              partLabel: 'વ્યક્તિત્વ વિકાસ',
              value: cols[0],
              max: _vvMaxPerSemester,
              fallback: prevVv,
            );
            if (_selectedSem == '1') {
              st.vv1 = tot;
              st.vv1Sentences =
                  generateRandom40Sentences(tot, _vvMaxPerSentence);
            } else {
              st.vv2 = tot;
              st.vv2Sentences =
                  generateRandom40Sentences(tot, _vvMaxPerSentence);
            }
          } else if (_isBothSemCombo) {
            final prev1 = st.sem1[sub] ?? const SubjectMarks();
            final prev2 = st.sem2[sub] ?? const SubjectMarks();
            if (_useSem1DirectOutOf100) {
              final d1 = cols.isNotEmpty
                  ? checkCap(
                      studentName: st.name,
                      partLabel: 'પ્રથમ સત્ર (100)',
                      value: cols[0],
                      max: 100,
                      fallback: prev1.total,
                    )
                  : prev1.total;
              st.sem1[sub] = SubjectMarks(directTotal: d1, directMode: true);
              if (st.studiedInSem2) {
                final a2 = cols.length > 1
                    ? checkCap(
                        studentName: st.name,
                        partLabel: 'બીજું રચનાત્મક',
                        value: cols[1],
                        max: _maxPatrakA,
                        fallback: prev2.patrakA,
                      )
                    : prev2.patrakA;
                final isAb2 = (rawCols.length > 2 && isAbToken(rawCols[2])) ||
                    (prev2.satrantAbsent && !allowAbsentStudentMarks);
                int s2 = prev2.satrant;
                if (isAb2) {
                  s2 = 0;
                } else if (cols.length > 2) {
                  final checkedS2 = checkCap(
                    studentName: st.name,
                    partLabel: 'બીજું સત્રાંત',
                    value: cols[2],
                    max: satrantMax,
                    fallback:
                        _examEntryFrom80 ? prev2.satrant * 2 : prev2.satrant,
                  );
                  s2 = _examEntryFrom80 ? (checkedS2 / 2).round() : checkedS2;
                }
                final sw2 = cols.length > 3
                    ? checkCap(
                        studentName: st.name,
                        partLabel: 'બીજું સ્વ-અધ્યયન',
                        value: cols[3],
                        max: _maxSwa,
                        fallback: prev2.swaAdhyayan,
                      )
                    : prev2.swaAdhyayan;
                st.sem2[sub] = SubjectMarks(
                  patrakA: a2,
                  satrant: s2,
                  swaAdhyayan: sw2,
                  satrantAbsent: isAb2,
                );
              }
            } else {
              final a1 = cols.isNotEmpty
                  ? checkCap(
                      studentName: st.name,
                      partLabel: 'પ્રથમ રચનાત્મક',
                      value: cols[0],
                      max: _maxPatrakA,
                      fallback: prev1.patrakA,
                    )
                  : prev1.patrakA;
              final isAb1 = (rawCols.length > 1 && isAbToken(rawCols[1])) ||
                  (prev1.satrantAbsent && !allowAbsentStudentMarks);
              int s1 = prev1.satrant;
              if (isAb1) {
                s1 = 0;
              } else if (cols.length > 1) {
                final checkedS1 = checkCap(
                  studentName: st.name,
                  partLabel: 'પ્રથમ સત્રાંત',
                  value: cols[1],
                  max: satrantMax,
                  fallback:
                      _examEntryFrom80 ? prev1.satrant * 2 : prev1.satrant,
                );
                s1 = _examEntryFrom80 ? (checkedS1 / 2).round() : checkedS1;
              }
              final sw1 = cols.length > 2
                  ? checkCap(
                      studentName: st.name,
                      partLabel: 'પ્રથમ સ્વ-અધ્યયન',
                      value: cols[2],
                      max: _maxSwa,
                      fallback: prev1.swaAdhyayan,
                    )
                  : prev1.swaAdhyayan;
              st.sem1[sub] = SubjectMarks(
                patrakA: a1,
                satrant: s1,
                swaAdhyayan: sw1,
                satrantAbsent: isAb1,
              );
              if (st.studiedInSem2) {
                final a2 = cols.length > 3
                    ? checkCap(
                        studentName: st.name,
                        partLabel: 'બીજું રચનાત્મક',
                        value: cols[3],
                        max: _maxPatrakA,
                        fallback: prev2.patrakA,
                      )
                    : prev2.patrakA;
                final isAb2 = (rawCols.length > 4 && isAbToken(rawCols[4])) ||
                    (prev2.satrantAbsent && !allowAbsentStudentMarks);
                int s2 = prev2.satrant;
                if (isAb2) {
                  s2 = 0;
                } else if (cols.length > 4) {
                  final checkedS2 = checkCap(
                    studentName: st.name,
                    partLabel: 'બીજું સત્રાંત',
                    value: cols[4],
                    max: satrantMax,
                    fallback:
                        _examEntryFrom80 ? prev2.satrant * 2 : prev2.satrant,
                  );
                  s2 = _examEntryFrom80 ? (checkedS2 / 2).round() : checkedS2;
                }
                final sw2 = cols.length > 5
                    ? checkCap(
                        studentName: st.name,
                        partLabel: 'બીજું સ્વ-અધ્યયન',
                        value: cols[5],
                        max: _maxSwa,
                        fallback: prev2.swaAdhyayan,
                      )
                    : prev2.swaAdhyayan;
                st.sem2[sub] = SubjectMarks(
                  patrakA: a2,
                  satrant: s2,
                  swaAdhyayan: sw2,
                  satrantAbsent: isAb2,
                );
              }
            }
          } else if (_selectedSem == '1' && _useSem1DirectOutOf100) {
            final prev1 = st.sem1[sub] ?? const SubjectMarks();
            final d1 = cols.isNotEmpty
                ? checkCap(
                    studentName: st.name,
                    partLabel: 'પ્રથમ સત્ર (100)',
                    value: cols[0],
                    max: 100,
                    fallback: prev1.total,
                  )
                : prev1.total;
            st.sem1[sub] = SubjectMarks(directTotal: d1, directMode: true);
          } else {
            final prev = (_selectedSem == '1' ? st.sem1[sub] : st.sem2[sub]) ??
                const SubjectMarks();
            int colCursor = 0;
            final newA = _showA && colCursor < cols.length
                ? checkCap(
                    studentName: st.name,
                    partLabel: 'રચનાત્મક',
                    value: cols[colCursor++],
                    max: _maxPatrakA,
                    fallback: prev.patrakA,
                  )
                : prev.patrakA;
            bool isAb = prev.satrantAbsent;
            int rawS = prev.satrant;
            if (_showS && colCursor < cols.length) {
              final rawStr = rawCols[colCursor];
              final numVal = cols[colCursor++];
              if (isAbToken(rawStr) ||
                  (prev.satrantAbsent && !allowAbsentStudentMarks && numVal > 0)) {
                isAb = true;
                rawS = 0;
              } else {
                isAb = false;
                final checkedS = checkCap(
                  studentName: st.name,
                  partLabel: 'સત્રાંત',
                  value: numVal,
                  max: satrantMax,
                  fallback: _examEntryFrom80 ? prev.satrant * 2 : prev.satrant,
                );
                rawS = _examEntryFrom80 ? (checkedS / 2).round() : checkedS;
              }
            }
            final newSW = _showSW && colCursor < cols.length
                ? checkCap(
                    studentName: st.name,
                    partLabel: 'સ્વ-અધ્યયન',
                    value: cols[colCursor++],
                    max: _maxSwa,
                    fallback: prev.swaAdhyayan,
                  )
                : prev.swaAdhyayan;

            final updated = SubjectMarks(
              patrakA: newA,
              satrant: isAb ? 0 : rawS,
              swaAdhyayan: newSW,
              satrantAbsent: isAb,
            );
            if (_selectedSem == '1') {
              st.sem1[sub] = updated;
            } else {
              st.sem2[sub] = updated;
            }
          }
        }
        _gridTick++;
      });

      if (overMaxWarnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dCtx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              '⚠️ મહત્તમ ગુણ કરતાં વધુ ગુણ સ્વીકાર્યા નથી',
              style: guFont(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.rose),
            ),
            content: SingleChildScrollView(
              child: Text(
                'નીચેના વિદ્યાર્થીઓ માટે મહત્તમ મર્યાદા કરતાં વધુ ગુણ હોવાથી તે ગુણ સ્વીકારવામાં આવ્યા નથી:\n\n• ${overMaxWarnings.join("\n• ")}',
                style: guFont(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dCtx),
                child: Text('સમજાયું (OK)',
                    style: guFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
        );
      }
    }

    if (mounted) {
      showSnack(
          context, '✅ ${lines.length} હરોળ પેસ્ટ થઈ ગઈ! હવે સેવ બટન દબાવો.');
    }
  }

  /// Downloads & opens the server-rendered local Supabase-mode PDF (100% native Gujarati font
  /// + exact A4/Legal Portrait/Landscape page setup).
  Future<bool> _tryServerSideSheetPdf(String pdfType) async {
    final state = context.read<AppState>();
    if (state.resultApi == null || _selectedClass == null) return false;

    showBusyDialog(
        context, '📄 PDF તૈયાર થાય છે (Page Setup & Gujarati Font)…');
    try {
      final res = await state.resultApi!.exportResultPdf(
        className: _selectedClass!,
        sem: _selectedSem == '1' ? '1' : '2',
        pdfType: pdfType,
        showParinam: _showParinamInReportCard,
        parinamMode: '${_parinamRuleMode}_$_minEGradesToFail',
      );
      if (!mounted) return true;
      hideBusyDialog(context);

      if (res['result'] == 'supabase_local_pdf') {
        // There is no server-side local Supabase-mode PDF endpoint in Supabase mode.
        // Continue into this screen's existing Gujarati-aware local PDF builder.
        return false;
      }

      if (res['result'] == 'success' && res['pdfBase64'] != null) {
        final bytes = base64Decode(res['pdfBase64'].toString());
        final fileName =
            (res['fileName'] ?? '$_cleanClassCode $_semTag.pdf').toString();
        await Printing.layoutPdf(
          name: fileName,
          onLayout: (_) async => bytes,
        );
        return true;
      }

      if (res['result'] == 'redirect_pdf' && res['pdfUrl'] != null) {
        final uri = Uri.parse(res['pdfUrl'].toString());
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }

      showSnack(context, '❌ PDF Error: ${res['message'] ?? 'Unknown error'}',
          error: true);
      return true;
    } catch (e) {
      if (mounted) {
        hideBusyDialog(context);
        showSnack(context, '❌ PDF Error: $e', error: true);
      }
      return true;
    }
  }

  // ===========================================================================
  // ULTRA-FAST & LIGHTWEIGHT INDIVIDUAL STUDENT REPORT CARD PDF
  // - Pure numbers & English grades render as 0-KB Vector Text (Instant)
  // - Gujarati words render at optimized 1.75x DPI and stay cached in RAM
  // - Neutral tenant-independent report background & fonts load only ONCE per session
  // ===========================================================================
  final Map<String, ({pw.MemoryImage image, double width, double height})>
      _guWordCache = {};
  static final RegExp _gujaratiCharRegex = RegExp(r'[\u0A80-\u0AFF]');

  bool _localGujaratiFontLoaded = false;
  String _selectedTemplateAsset =
      'generic'; // Neutral, school-independent report card background
  bool _showParinamInReportCard = false;
  bool _onlyMarksEnteredSubjects =
      true; // Default: print only class subjects where at least 1 student has marks entered

  pw.MemoryImage? _cachedBgProvider;
  String? _cachedBgAssetPath;
  pw.MemoryImage? _cachedWmProvider;
  pw.Font? _cachedPdfRegularFont;
  pw.Font? _cachedPdfBoldFont;

  Future<void> _ensureFastPdfResourcesLoaded() async {
    if (!_localGujaratiFontLoaded) {
      try {
        final loader = FontLoader('NotoSansGujaratiLocal');
        loader.addFont(
            rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf'));
        loader
            .addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
        await loader.load();
        _localGujaratiFontLoaded = true;
      } catch (_) {}
    }
    if (_cachedPdfRegularFont == null || _cachedPdfBoldFont == null) {
      final regData =
          await rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf');
      _cachedPdfRegularFont = pw.Font.ttf(regData);
      _cachedPdfBoldFont = pw.Font.ttf(boldData);
    }
  }

  /// Renders numbers/grades as instant 0-KB vector text, and caches only Gujarati words
  Future<pw.Widget> _makeShapedTextWidget({
    required String text,
    required double fontSize,
    required Color textColor,
    Color? bgColor,
    bool bold = true,
    int maxLines = 1,
    double? maxWidth,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return pw.SizedBox();

    // FAST PATH: If text has NO Gujarati letters (e.g. "1", "100", "200", "A", "B", GR No),
    // use native vector pw.Text (0ms CPU time, 0 KB image size!)
    if (!_gujaratiCharRegex.hasMatch(trimmed)) {
      return pw.Text(
        trimmed,
        maxLines: maxLines,
        style: pw.TextStyle(
          font: bold ? _cachedPdfBoldFont : _cachedPdfRegularFont,
          fontSize: fontSize,
          color: PdfColor.fromInt(textColor.toARGB32()),
        ),
      );
    }

    final bgKey = bgColor?.toARGB32() ?? 0;
    final key =
        '$trimmed|$fontSize|${bold ? "B" : "R"}|${textColor.toARGB32()}|$bgKey|$maxLines|$maxWidth';
    var cached = _guWordCache[key];

    if (cached == null) {
      const double dpr =
          1.75; // Sharp print quality with 50% less memory & 2x faster encoding
      final baseStyle = guFont(
        fontSize: fontSize * dpr,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: textColor,
      );
      final style = _localGujaratiFontLoaded
          ? baseStyle.copyWith(
              fontFamily: 'NotoSansGujaratiLocal',
              fontFamilyFallback: const ['Noto Sans Gujarati'],
            )
          : baseStyle;

      final tp = TextPainter(
        text: TextSpan(text: trimmed, style: style),
        textDirection: ui.TextDirection.ltr,
        textAlign: maxLines > 1 ? TextAlign.center : TextAlign.start,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth != null ? maxWidth * dpr : double.infinity);

      final int imgW = (tp.width.ceil() + 4).clamp(6, 1200);
      final int imgH = (tp.height.ceil() + 4).clamp(6, 200);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()));
      // 100% transparent PNG with balanced vertical offset
      tp.paint(canvas, const Offset(2, 2));

      final picture = recorder.endRecording();
      final img = await picture.toImage(imgW, imgH);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();

      cached = (
        image: pw.MemoryImage(byteData!.buffer.asUint8List()),
        width: imgW / dpr,
        height: imgH / dpr,
      );
      _guWordCache[key] = cached;
    }

    return pw.Image(cached.image, width: cached.width, height: cached.height);
  }

  Future<ui.Image?> _decodeUiImageFromAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Builds a neutral, school-independent background. School-specific text/logo are
  /// rendered from the tenant's live profile instead of being baked into an image.
  Future<pw.MemoryImage?> _buildFlattenedBackgroundImage({
    required String preferredPath,
    required int subjectRowCount,
    required bool withMarks,
    required bool showParinam,
  }) async {
    // preferredPath remains in the signature for backwards compatibility, but
    // no legacy school-specific image is loaded into a multi-school report.
    final _ = preferredPath;

    // Scale factor from PDF A4 points (595.28 x 841.89) to high-res canvas (900 x 1273)
    const double pdfW = 595.28;
    const double pdfH = 841.89;
    const int targetW = 900;
    const int targetH = 1273;
    const double sx = targetW / pdfW;
    const double sy = targetH / pdfH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
        recorder, const Rect.fromLTWH(0, 0, targetW * 1.0, targetH * 1.0));

    // 1. Solid White + Cream base so background can NEVER turn black
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, targetW * 1.0, targetH * 1.0),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, targetW * 1.0, targetH * 1.0),
      Paint()..color = const Color(0xFFFBF3DC),
    );

    // Draw a restrained neutral border, then the colored pill boxes in PDF coordinates.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 12, targetW - 24.0, targetH - 24.0),
        const Radius.circular(18),
      ),
      Paint()
        ..color = const Color(0xFF8793A1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Draw all colored pill boxes onto the canvas in PDF point coordinates
    canvas.save();
    canvas.scale(sx, sy);

    void drawCanvasPill(double x, double y, double w, double h, Color fill,
        {bool border = true}) {
      final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), const Radius.circular(5));
      // 82% opacity so background texture + watermark blend nicely
      canvas.drawRRect(rrect, Paint()..color = fill.withValues(alpha: 0.82));
      if (border) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFF7A6E67)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.65,
        );
      }
    }

    const cPinkLabel = Color(0xFFF4BEEE);
    const cLavValue = Color(0xFFE4BAFA);
    const cHdrGreen = Color(0xFF8FD6AE);
    const cHdrRose = Color(0xFFDDA5B6);
    const cHdrGold = Color(0xFFF9C663);
    const cHdrBlue = Color(0xFFA7D3DF);
    const cHdrTan = Color(0xFFE2B29A);
    const cSumGreen = Color(0xFF8AE2B0);
    const cSumTan = Color(0xFFDCA98E);
    const cRowGreen = Color(0xFFDCF2E4);
    const cRowPink = Color(0xFFF5E1E6);
    const cRowYellow = Color(0xFFFCEAD2);
    const cRowBlue = Color(0xFFE2F0F5);
    const cRowPeach = Color(0xFFF7E5DC);

    const double leftX = 32.0;
    // Top Student Name & Info Pills (matching exact Column layout)
    // Compact header ends at y=164 + 8 gap -> y = 172.0
    double curY = 172.0;
    drawCanvasPill(leftX, curY, 122, 23, cPinkLabel, border: false);
    drawCanvasPill(leftX + 127, curY, 404, 23, cLavValue, border: false);
    curY += 23 + 6;

    // Row 2: Std, GR, Roll
    drawCanvasPill(leftX, curY, 66, 22, cPinkLabel, border: false);
    drawCanvasPill(leftX + 70, curY, 62, 22, cLavValue, border: false);
    drawCanvasPill(leftX + 140, curY, 184, 22, cPinkLabel, border: false);
    drawCanvasPill(leftX + 328, curY, 62, 22, cLavValue, border: false);
    drawCanvasPill(leftX + 398, curY, 85, 22, cPinkLabel, border: false);
    drawCanvasPill(leftX + 487, curY, 44, 22, cLavValue, border: false);
    curY += 22 + 12;

    // Table Rows
    if (withMarks) {
      // 5-Column X offsets (total width = 531.28 across 32..563.28)
      const double x0 = leftX;
      const double x1 = leftX + 45.5;
      const double x2 = leftX + 228.0;
      const double x3 = leftX + 331.5;
      const double x4 = leftX + 435.0;

      drawCanvasPill(x0, curY, 38, 26, cHdrGreen);
      drawCanvasPill(x1, curY, 175, 26, cHdrRose);
      drawCanvasPill(x2, curY, 96, 26, cHdrGold);
      drawCanvasPill(x3, curY, 96, 26, cHdrBlue);
      drawCanvasPill(x4, curY, 96, 26, cHdrTan);
      curY += 26 + 3.5;

      for (int i = 0; i < subjectRowCount; i++) {
        drawCanvasPill(x0, curY, 38, 25, cRowGreen);
        drawCanvasPill(x1, curY, 175, 25, cRowPink);
        drawCanvasPill(x2, curY, 96, 25, cRowYellow);
        drawCanvasPill(x3, curY, 96, 25, cRowBlue);
        drawCanvasPill(x4, curY, 96, 25, cRowPeach);
        curY += 25 + 3.5;
      }

      // કુલ ગુણ Row
      drawCanvasPill(x0, curY, 220.5, 26, cHdrRose);
      drawCanvasPill(x2, curY, 96, 26, cHdrGold);
      drawCanvasPill(x3, curY, 96, 26, cHdrBlue);
      drawCanvasPill(x4, curY, 96, 26, cSumTan);
      curY += 26 + 3.5;

      // મેળવેલ એકંદર ગ્રેડ Row
      drawCanvasPill(x0, curY, 324, 26, cSumGreen);
      drawCanvasPill(x3, curY, 199.5, 26, cSumTan);
      curY += 26 + 3.5;

      if (showParinam) {
        drawCanvasPill(x0, curY, 324, 26, cSumGreen);
        drawCanvasPill(x3, curY, 199.5, 26, cSumTan);
      }
    } else {
      const double x0 = leftX;
      const double x1 = leftX + 45.0;
      const double x2 = leftX + 227.0;

      drawCanvasPill(x0, curY, 38, 26, cHdrGreen);
      drawCanvasPill(x1, curY, 175, 26, cHdrRose);
      drawCanvasPill(x2, curY, 304, 26, cHdrTan);
      curY += 26 + 3.5;

      for (int i = 0; i < subjectRowCount; i++) {
        drawCanvasPill(x0, curY, 38, 25, cRowGreen);
        drawCanvasPill(x1, curY, 175, 25, cRowPink);
        drawCanvasPill(x2, curY, 304, 25, cRowPeach);
        curY += 25 + 3.5;
      }

      drawCanvasPill(x0, curY, 220, 26, cSumGreen);
      drawCanvasPill(x2, curY, 304, 26, cSumTan);
      curY += 26 + 3.5;

      if (showParinam) {
        drawCanvasPill(x0, curY, 220, 26, cSumGreen);
        drawCanvasPill(x2, curY, 304, 26, cSumTan);
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final flattened = await picture.toImage(targetW, targetH);
    final byteData = await flattened.toByteData(format: ui.ImageByteFormat.png);
    flattened.dispose();
    picture.dispose();

    return pw.MemoryImage(byteData!.buffer.asUint8List());
  }

  List<Widget> _buildParinamAndDivyangRuleControls(
    StateSetter setDialogState, {
    required bool isClassSheet,
  }) {
    // Only subjects whose marks are entered can be failed in.
    final enteredSubjects = _subjects.where(_hasInsertedMarksForSubject).length;
    final maxSubjects = enteredSubjects > 0
        ? enteredSubjects
        : (_subjects.isNotEmpty ? _subjects.length : 1);
    final currentModes = _parinamRuleModes;
    final effectiveMode =
        currentModes.containsKey(_parinamRuleMode) ? _parinamRuleMode : 'auto';
    return <Widget>[
      Material(
        color: _showParinamInReportCard
            ? const Color(0xFFDCFCE7)
            : AppColors.slateLight,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setDialogState(() {
            _showParinamInReportCard = !_showParinamInReportCard;
            _cachedBgProvider = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _showParinamInReportCard
                    ? AppColors.greenDeep
                    : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _showParinamInReportCard
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: _showParinamInReportCard
                      ? AppColors.greenDeep
                      : AppColors.navy,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isClassSheet
                        ? (_showParinamInReportCard
                            ? '✅ હા, પરિણામ (પાસ / નાપાસ) કોલમ ઉમેરવામાં આવશે'
                            : 'પરિણામ (પાસ / નાપાસ) કોલમ ઉમેરવી છે? (ચાલુ/બંધ)')
                        : (_showParinamInReportCard
                            ? '✅ પરિણામ (પાસ / નાપાસ) બોક્સ દેખાશે'
                            : 'પરિણામ (પાસ / નાપાસ) બોક્સ ઉમેરો (ચાલુ/બંધ)'),
                    style: guFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _showParinamInReportCard
                          ? AppColors.greenDeep
                          : AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_showParinamInReportCard) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _useDivyangRule
                ? const Color(0xFFFEF3C7)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _useDivyangRule
                  ? const Color(0xFFD97706)
                  : AppColors.border,
              width: 1.3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '♿ દિવ્યાંગ 20% પાસનો નિયમ ઉમેરવો છે? (Do you want to add Divyang 20% pass rule?)',
                style: guFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setDialogState(() => _useDivyangRule = true);
                        unawaited(_saveResultPdfSettings());
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: _useDivyangRule
                              ? AppColors.greenDeep
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _useDivyangRule
                                ? AppColors.greenDeep
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          '✅ હા (દિવ્યાંગ 20% પાસ)',
                          textAlign: TextAlign.center,
                          style: guFont(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _useDivyangRule
                                ? Colors.white
                                : AppColors.navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setDialogState(() => _useDivyangRule = false);
                        unawaited(_saveResultPdfSettings());
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: !_useDivyangRule
                              ? AppColors.rose
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !_useDivyangRule
                                ? AppColors.rose
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          '🚫 ના (દિવ્યાંગ નિયમ દૂર કરો)',
                          textAlign: TextAlign.center,
                          style: guFont(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: !_useDivyangRule
                                ? Colors.white
                                : AppColors.navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: effectiveMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'પરિણામનો નિયમ પસંદ કરો',
            isDense: true,
          ),
          items: currentModes.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: guFont(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setDialogState(() {
                _parinamRuleMode = v;
                if (v == 'one_sub_fail') {
                  _minEGradesToFail = 1;
                }
              });
            }
          },
        ),
        if (_parinamRuleMode != 'all_pass') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: (_parinamRuleMode == 'one_sub_fail' ? 1 : _minEGradesToFail)
                .clamp(1, maxSubjects)
                .toInt(),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _useDivyangRule
                  ? 'કેટલા વિષયમાં E ગ્રેડ (35 થી ઓછા / દિવ્યાંગ 20% થી ઓછા) હોય ત્યારે નાપાસ ગણવા?'
                  : 'કેટલા વિષયમાં E ગ્રેડ (35 થી ઓછા ગુણ) હોય ત્યારે નાપાસ ગણવા?',
              isDense: true,
            ),
            items: List.generate(maxSubjects, (i) => i + 1)
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(
                        n == 1
                            ? (_useDivyangRule
                                ? '1 વિષયમાં પણ 35 થી ઓછા ગુણ (દિવ્યાંગ 20% થી ઓછા) હોય તો નાપાસ (1 Subject Fail)'
                                : '1 વિષયમાં પણ E ગ્રેડ (35 થી ઓછા ગુણ) હોય તો નાપાસ (1 Subject Fail)')
                            : '$n કે તેથી વધુ વિષયમાં E ગ્રેડ હોય તો જ નાપાસ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: guFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.rose,
                        ),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setDialogState(() {
                  _minEGradesToFail = v;
                  if (v == 1 && _parinamRuleMode == 'auto') {
                    _parinamRuleMode = 'one_sub_fail';
                  } else if (v > 1 && _parinamRuleMode == 'one_sub_fail') {
                    _parinamRuleMode = 'auto';
                  }
                });
              }
            },
          ),
        ],
      ],
    ];
  }

  Future<void> _promptAndGenerateStudentReportCards() async {
    if (_students.isEmpty) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget templateOption(String assetPath, String label) {
            final selected = _selectedTemplateAsset == assetPath;
            return Expanded(
              child: InkWell(
                onTap: () => setDialogState(() {
                  _selectedTemplateAsset = assetPath;
                  _cachedBgProvider = null;
                }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFE0F2FE) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.teal : AppColors.border,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        height: 85,
                        child: Center(
                          child: Icon(Icons.description_outlined,
                              size: 58, color: AppColors.teal),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: guFont(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: selected ? AppColors.teal : AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            title: Text(
              '🎓 વિદ્યાર્થી પરિણામ પત્રક (Fast PDF)',
              style: guFont(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy),
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '૧. બેકગ્રાઉન્ડ ટેમ્પલેટ પસંદ કરો:',
                      style: guFont(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        templateOption('generic', 'Generic school template'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._buildParinamAndDivyangRuleControls(
                      setDialogState,
                      isClassSheet: false,
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: _onlyMarksEnteredSubjects
                          ? const Color(0xFFE0F2FE)
                          : AppColors.slateLight,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setDialogState(() {
                          _onlyMarksEnteredSubjects =
                              !_onlyMarksEnteredSubjects;
                          _reportCardSubjectSelection = null;
                          _cachedBgProvider = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _onlyMarksEnteredSubjects
                                  ? AppColors.teal
                                  : AppColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _onlyMarksEnteredSubjects
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: _onlyMarksEnteredSubjects
                                    ? AppColors.teal
                                    : AppColors.navy,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _onlyMarksEnteredSubjects
                                      ? '✅ માત્ર ગુણ દાખલ કરેલ વિષયો જ બતાવો (બધા વિષયો નહીં)'
                                      : '📚 વર્ગના બધા જ વિષયો બતાવો (All Subjects)',
                                  style: guFont(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: _onlyMarksEnteredSubjects
                                        ? AppColors.teal
                                        : AppColors.navy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'પરિણામ પત્રકમાં છાપવાના વિષયો (ગુણ દાખલ થયેલ વિષયો પહેલેથી પસંદ છે):',
                      style: guFont(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    const SizedBox(height: 6),
                    Builder(builder: (context) {
                      final current = _subjectsForStudentCards.toSet();
                      final options = _isSubjectTeacherOnly ? _subjectsForCurrentReport : _subjects;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final subject in options)
                            FilterChip(
                              label: Text(subject, style: guFont(fontSize: 12, fontWeight: FontWeight.w700)),
                              selected: current.contains(subject),
                              onSelected: (on) => setDialogState(() {
                                final next = Set<String>.from(current);
                                if (on) {
                                  next.add(subject);
                                } else if (next.length > 1) {
                                  next.remove(subject);
                                }
                                _reportCardSubjectSelection = next;
                              }),
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: 14),
                    Text(
                      '૨. પરિણામ પત્રકનો પ્રકાર પસંદ કરો:',
                      style: guFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.slate),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: '🅰️️ માત્ર ગ્રેડ (Only Grade)',
                      background: AppColors.teal,
                      onPressed: () => Navigator.pop(ctx, 'grade_only'),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: '📊 ગુણ અને ગ્રેડ સાથે (With Marks)',
                      background: AppColors.greenDeep,
                      onPressed: () => Navigator.pop(ctx, 'with_marks'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('રદ કરો (Cancel)',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );

    if (mode == null || !mounted) return;
    await _generateIndividualReportCardsPdf(withMarks: mode == 'with_marks');
  }

  int _countStudentVisibleSubjectRows(ResultStudentRow student,
      {required bool isSem1}) {
    final _ = (student, isSem1);
    final reportSubjects = _subjectsForStudentCards;
    return reportSubjects.length + 1;
  }

  Future<void> _generateIndividualReportCardsPdf(
      {required bool withMarks}) async {
    final validStudents =
        _students.where((s) => s.name.trim().isNotEmpty).toList();
    if (validStudents.isEmpty) return;

    if (withMarks) {
      final presentOk = await _askAndPreparePresentDaysForResultPrint();
      if (!presentOk || !mounted) return;
    }

    showBusyDialog(context, '⚡ પરિણામ પત્રક PDF તૈયાર થાય છે…');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    try {
      await _loadRegisteredSchoolBranding();
      await _loadSchoolGradeSettings();
      await _ensureFastPdfResourcesLoaded();

      final isSem1 = _selectedSem == '1';
      final cleanClass = _cleanClassCode;
      final bgByRowCount = <int, pw.MemoryImage?>{};

      final doc = pw.Document(compress: true);
      for (final st in validStudents) {
        final rowCount = _countStudentVisibleSubjectRows(st, isSem1: isSem1);
        if (!bgByRowCount.containsKey(rowCount)) {
          bgByRowCount[rowCount] = await _buildFlattenedBackgroundImage(
            preferredPath: _selectedTemplateAsset,
            subjectRowCount: rowCount,
            withMarks: withMarks,
            showParinam: _showParinamInReportCard,
          );
        }

        final pageWidget = await _buildSingleShapedReportCardPage(
          student: st,
          bgProvider: bgByRowCount[rowCount],
          wmProvider: null,
          isSem1: isSem1,
          withMarks: withMarks,
          cleanClass: cleanClass,
        );
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pageWidget,
          ),
        );
      }

      final pdfBytes = await doc.save();
      if (!mounted) return;
      hideBusyDialog(context);

      final suffix = withMarks ? 'WITH_MARKS' : 'ONLY_GRADE';
      final fileName = '$cleanClass $_semTag STUDENT RESULT ($suffix).pdf';

      try {
        final printed = await Printing.layoutPdf(
          name: fileName,
          format: PdfPageFormat.a4,
          onLayout: (_) async => pdfBytes,
        );
        if (!printed && mounted) {
          await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
        }
      } catch (_) {
        await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        hideBusyDialog(context);
        showSnack(context, '❌ Report Card PDF Error: $e', error: true);
      }
    }
  }

  Future<pw.Widget> _buildSingleShapedReportCardPage({
    required ResultStudentRow student,
    required pw.MemoryImage? bgProvider,
    required pw.MemoryImage? wmProvider,
    required bool isSem1,
    required bool withMarks,
    required String cleanClass,
  }) async {
    const cLabelRed = Color(0xFFA61B1B);

    // Centers text vertically (top: 2.5 offset fixes Gujarati matra ascent) and horizontally
    Future<pw.Widget> pillBox({
      required double width,
      double height = 25,
      required String text,
      required Color fillColor,
      Color textColor = Colors.black,
      double fontSize = 13.5,
      bool bold = true,
      bool showBorder = true,
      pw.Alignment align = pw.Alignment.center,
      double hPad = 6,
    }) async {
      final childWidget = await _makeShapedTextWidget(
        text: text,
        fontSize: fontSize,
        textColor: textColor,
        bgColor: null,
        bold: bold,
      );
      final isTransparent =
          fillColor.toARGB32() == Colors.transparent.toARGB32();
      return pw.Container(
        width: width,
        height: height,
        padding: pw.EdgeInsets.fromLTRB(hPad, 2.5, hPad, 0),
        alignment: align,
        decoration: pw.BoxDecoration(
          // Keep transparent cells transparent so the pastel cells in the
          // flattened A4 template remain visible behind their text.
          color: isTransparent ? null : PdfColor.fromInt(fillColor.toARGB32()),
          border: showBorder
              ? pw.Border.all(color: PdfColor.fromInt(0xFFB8B8B8), width: 0.65)
              : null,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: childWidget,
      );
    }

    final reportSubjects = _subjectsForStudentCards;
    final rowsData =
        <({String sr, String subject, int max, int obtained, String grade})>[];
    int grandMax = 0;
    int grandObtained = 0;

    for (final sub in reportSubjects) {
      final int s1 = (student.sem1[sub]?.total ?? 0).toInt();
      final int s2 =
          student.studiedInSem2 ? (student.sem2[sub]?.total ?? 0).toInt() : 0;
      final bool hasS1 = _classHasSem1Marks(sub);
      final bool hasS2 = student.studiedInSem2 && _classHasSem2Marks(sub);

      if (_selectedSem == '1') {
        final int maxMarks =
            hasS1 ? _sem1MaximumForSubject(student, sub) : _maxSubSemTotal;
        final double pct = maxMarks > 0 ? (s1 / maxMarks) * 100 : 0;
        grandMax += maxMarks;
        grandObtained += s1;
        rowsData.add((
          sr: '${rowsData.length + 1}',
          subject: sub,
          max: maxMarks,
          obtained: s1,
          grade: _gradeFor(pct)
        ));
      } else if (_selectedSem == '2') {
        if (!student.studiedInSem2) continue;
        final int obtained = s1 + s2;
        final int maxMarks = (hasS1 || hasS2)
            ? ((hasS1 ? _sem1MaximumForSubject(student, sub) : 0) +
                (hasS2 ? _maxSubSemTotal : 0))
            : (_maxSubSemTotal * 2);
        final double pct = maxMarks > 0 ? (obtained / maxMarks) * 100 : 0;
        grandMax += maxMarks;
        grandObtained += obtained;
        rowsData.add((
          sr: '${rowsData.length + 1}',
          subject: sub,
          max: maxMarks,
          obtained: obtained,
          grade: _gradeFor(pct)
        ));
      } else {
        // Annual report uses the union of S1/S2 class subjects and their combined marks.
        final int obtained = !student.studiedInSem2 ? s1 : (s1 + s2);
        final int maxMarks = (hasS1 || hasS2)
            ? ((hasS1 ? _sem1MaximumForSubject(student, sub) : 0) +
                (hasS2 ? _maxSubSemTotal : 0))
            : (_maxSubSemTotal * 2);
        final double pct = maxMarks > 0 ? (obtained / maxMarks) * 100 : 0;
        grandMax += maxMarks;
        grandObtained += obtained;
        rowsData.add((
          sr: '${rowsData.length + 1}',
          subject: sub,
          max: maxMarks,
          obtained: obtained,
          grade: !student.studiedInSem2 ? 'નામ કમી' : _gradeFor(pct)
        ));
      }
    }

    final int dynamicVvMax =
        _selectedSem == 'Annual' ? (_vvMaxPerSemester * 2) : _vvMaxPerSemester;
    final int dynamicVvObt = _selectedSem == '1'
        ? student.vv1
        : (_selectedSem == '2'
            ? student.vvAvgBothSem.toInt()
            : (student.vv1 + student.vv2));

    {
      final String vvGrade = (_selectedSem != '1' && !student.studiedInSem2)
          ? 'નામ કમી'
          : _gradeFor(
              dynamicVvMax > 0 ? (dynamicVvObt / dynamicVvMax) * 100 : 0);
      grandMax += dynamicVvMax;
      grandObtained += dynamicVvObt;
      rowsData.add((
        sr: '${rowsData.length + 1}',
        subject: 'વ્યક્તિત્ત્વ વિકાસ',
        max: dynamicVvMax,
        obtained: dynamicVvObt,
        grade: vvGrade,
      ));
    }

    final double overallPct =
        grandMax > 0 ? (grandObtained / grandMax) * 100 : 0;
    final String overallGrade =
        (!isSem1 && !student.studiedInSem2) ? 'નામ કમી' : _gradeFor(overallPct);
    final String passFailText =
        _evaluatePassFailForStudent(student, isSem1: isSem1);
    final stdDisplay = _shortClassWithSection.isNotEmpty
        ? _shortClassWithSection
        : (student.standard.trim().isNotEmpty
            ? student.standard.trim()
            : cleanClass);

    final semTitleWidget = await _makeShapedTextWidget(
      text: _selectedSem == '1'
          ? 'પ્રથમ સત્ર'
          : (_selectedSem == 'Annual'
              ? 'વાર્ષિક પરિણામ પત્રક'
              : 'દ્વિતીય સત્ર'),
      fontSize: 17.5,
      textColor: Colors.black,
      bgColor: null,
      bold: true,
    );

    // Student Name starts from LEFT (align: pw.Alignment.centerLeft) with slightly bigger font (13.5)
    final nameRow = pw.Row(
      children: [
        await pillBox(
          width: 122,
          height: 23,
          text: 'વિદ્યાર્થીનું નામ :-',
          fillColor: Colors.transparent,
          textColor: cLabelRed,
          fontSize: 12.5,
          showBorder: false,
        ),
        pw.SizedBox(width: 5),
        await pillBox(
          width: 404,
          height: 23,
          text: student.name,
          fillColor: Colors.transparent,
          fontSize: 13.5,
          showBorder: false,
          align: pw.Alignment.centerLeft,
          hPad: 8,
        ),
      ],
    );

    final infoRow = pw.Row(
      children: [
        await pillBox(
            width: 66,
            height: 22,
            text: 'ધોરણ :-',
            fillColor: Colors.transparent,
            textColor: cLabelRed,
            fontSize: 12.5,
            showBorder: false),
        pw.SizedBox(width: 4),
        await pillBox(
            width: 62,
            height: 22,
            text: stdDisplay,
            fillColor: Colors.transparent,
            fontSize: 13,
            showBorder: false),
        pw.SizedBox(width: 8),
        await pillBox(
            width: 184,
            height: 22,
            text: 'સામાન્ય વયપત્રક નંબર :-',
            fillColor: Colors.transparent,
            textColor: cLabelRed,
            fontSize: 12.5,
            showBorder: false),
        pw.SizedBox(width: 4),
        await pillBox(
            width: 62,
            height: 22,
            text: student.gr,
            fillColor: Colors.transparent,
            fontSize: 13,
            showBorder: false),
        pw.SizedBox(width: 8),
        await pillBox(
            width: 85,
            height: 22,
            text: 'રોલ નંબર :-',
            fillColor: Colors.transparent,
            textColor: cLabelRed,
            fontSize: 12.5,
            showBorder: false),
        pw.SizedBox(width: 4),
        await pillBox(
            width: 44,
            height: 22,
            text: student.roll,
            fillColor: Colors.transparent,
            fontSize: 13,
            showBorder: false),
      ],
    );

    final tableWidgets = <pw.Widget>[];
    if (withMarks) {
      tableWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            await pillBox(
                width: 38,
                height: 26,
                text: 'ક્રમ',
                fillColor: Colors.transparent,
                fontSize: 13),
            await pillBox(
                width: 175,
                height: 26,
                text: 'વિષય',
                fillColor: Colors.transparent,
                fontSize: 13.5),
            await pillBox(
                width: 96,
                height: 26,
                text: 'કુલ ગુણ',
                fillColor: Colors.transparent,
                fontSize: 13),
            await pillBox(
                width: 96,
                height: 26,
                text: 'મેળવેલ ગુણ',
                fillColor: Colors.transparent,
                fontSize: 13),
            await pillBox(
                width: 96,
                height: 26,
                text: 'મેળવેલ ગ્રેડ',
                fillColor: Colors.transparent,
                fontSize: 13),
          ],
        ),
      );
      tableWidgets.add(pw.SizedBox(height: 3.5));

      for (final r in rowsData) {
        tableWidgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              await pillBox(
                  width: 38,
                  height: 25,
                  text: r.sr,
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 175,
                  height: 25,
                  text: r.subject,
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 96,
                  height: 25,
                  text: '${r.max}',
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 96,
                  height: 25,
                  text: '${r.obtained}',
                  fillColor: Colors.transparent,
                  fontSize: 14),
              await pillBox(
                  width: 96,
                  height: 25,
                  text: r.grade,
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
            ],
          ),
        );
        tableWidgets.add(pw.SizedBox(height: 3.5));
      }

      tableWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            await pillBox(
                width: 221,
                height: 26,
                text: 'કુલ ગુણ',
                fillColor: Colors.transparent,
                fontSize: 13.5),
            await pillBox(
                width: 96,
                height: 26,
                text: '$grandMax',
                fillColor: Colors.transparent,
                fontSize: 14),
            await pillBox(
                width: 96,
                height: 26,
                text: '$grandObtained',
                fillColor: Colors.transparent,
                fontSize: 14),
            await pillBox(
                width: 96,
                height: 26,
                text: overallGrade,
                fillColor: Colors.transparent,
                fontSize: 14),
          ],
        ),
      );
      tableWidgets.add(pw.SizedBox(height: 3.5));

      tableWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            await pillBox(
                width: 325,
                height: 26,
                text: 'મેળવેલ એકંદર ગ્રેડ',
                fillColor: Colors.transparent,
                fontSize: 13.5),
            await pillBox(
                width: 200,
                height: 26,
                text: overallGrade,
                fillColor: Colors.transparent,
                fontSize: 14),
          ],
        ),
      );

      if (_showParinamInReportCard) {
        tableWidgets.add(pw.SizedBox(height: 3.5));
        tableWidgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              await pillBox(
                  width: 325,
                  height: 26,
                  text: 'પરિણામ',
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 200,
                  height: 26,
                  text: passFailText,
                  fillColor: Colors.transparent,
                  fontSize: 14),
            ],
          ),
        );
      }
    } else {
      tableWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            await pillBox(
                width: 38,
                height: 26,
                text: 'ક્રમ',
                fillColor: Colors.transparent,
                fontSize: 13),
            await pillBox(
                width: 175,
                height: 26,
                text: 'વિષય',
                fillColor: Colors.transparent,
                fontSize: 13.5),
            await pillBox(
                width: 304,
                height: 26,
                text: 'મેળવેલ ગ્રેડ',
                fillColor: Colors.transparent,
                fontSize: 13.5),
          ],
        ),
      );
      tableWidgets.add(pw.SizedBox(height: 3.5));

      for (final r in rowsData) {
        tableWidgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              await pillBox(
                  width: 38,
                  height: 25,
                  text: r.sr,
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 175,
                  height: 25,
                  text: r.subject,
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 304,
                  height: 25,
                  text: r.grade,
                  fillColor: Colors.transparent,
                  fontSize: 14),
            ],
          ),
        );
        tableWidgets.add(pw.SizedBox(height: 3.5));
      }

      tableWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            await pillBox(
                width: 221,
                height: 26,
                text: 'મેળવેલ એકંદર ગ્રેડ',
                fillColor: Colors.transparent,
                fontSize: 13.5),
            await pillBox(
                width: 304,
                height: 26,
                text: overallGrade,
                fillColor: Colors.transparent,
                fontSize: 14),
          ],
        ),
      );

      if (_showParinamInReportCard) {
        tableWidgets.add(pw.SizedBox(height: 3.5));
        tableWidgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              await pillBox(
                  width: 221,
                  height: 26,
                  text: 'પરિણામ',
                  fillColor: Colors.transparent,
                  fontSize: 13.5),
              await pillBox(
                  width: 304,
                  height: 26,
                  text: passFailText,
                  fillColor: Colors.transparent,
                  fontSize: 14),
            ],
          ),
        );
      }
    }

    final placeWidget = await _makeShapedTextWidget(
      text: 'સ્થળ  :- $_reportCardPlaceName',
      fontSize: 13.0,
      textColor: Colors.black,
      bgColor: null,
      bold: true,
    );
    final dateWidget = await _makeShapedTextWidget(
      text: 'તારીખ:- $_activeSemResultDate',
      fontSize: 13.0,
      textColor: Colors.black,
      bgColor: null,
      bold: true,
    );

    pw.Widget? divyangNoteWidget;
    if (student.isDivyang && _useDivyangRule) {
      divyangNoteWidget = await _makeShapedTextWidget(
        text:
            'આ વિદ્યાર્થી દિવ્યાંગ હોવાથી ૨૦% ગુણ પાસ થવા માટેના ગુણ ગણેલ છે.',
        fontSize: 10.5,
        textColor: const Color(0xFF8B0000),
        bgColor: null,
        bold: true,
        maxLines: 2,
        maxWidth: 260,
      );
    }

    final authorityText = _reportCardAuthorityLine;
    final addressText = _reportCardAddressLine;

    return pw.Stack(
      fit: pw.StackFit.expand,
      children: [
        if (bgProvider != null)
          pw.Positioned.fill(
            child: pw.Image(bgProvider, fit: pw.BoxFit.fill),
          ),
        pw.Positioned.fill(
          child: pw.Container(
            margin: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                  color: PdfColor.fromInt(0xFF7A6E67), width: 1.1),
              borderRadius: pw.BorderRadius.circular(7),
            ),
          ),
        ),
        // Faded Center Watermark behind the marks table (matching image_db469e.jpg)
        pw.Positioned(
          left: 80,
          right: 80,
          top: 295,
          child: pw.Opacity(
            opacity: 0.10,
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (_cachedSchoolLogo != null)
                  pw.Container(
                    width: 115,
                    height: 115,
                    alignment: pw.Alignment.center,
                    child:
                        pw.Image(_cachedSchoolLogo!, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(height: 4),
                await _makeShapedTextWidget(
                  text: _schoolDisplayName,
                  fontSize: 16,
                  textColor: const Color(0xFF7A1C1C),
                  bold: true,
                  maxLines: 1,
                  maxWidth: 420,
                ),
                if (addressText.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  await _makeShapedTextWidget(
                    text: addressText,
                    fontSize: 8.5,
                    textColor: Colors.black,
                    bold: true,
                    maxLines: 1,
                    maxWidth: 420,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Top Header (matching image_db469e.jpg)
        pw.Positioned(
          left: 24,
          right: 24,
          top: 15,
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (authorityText.isNotEmpty)
                await _makeShapedTextWidget(
                  text: authorityText,
                  fontSize: 13.0,
                  textColor: const Color(0xFF1E293B),
                  bold: true,
                  maxLines: 1,
                  maxWidth: 530,
                ),
              pw.SizedBox(height: 2),
              await _makeShapedTextWidget(
                text: _schoolDisplayName,
                fontSize: 25.5,
                textColor: const Color(0xFF7A1C1C),
                bold: true,
                maxLines: 1,
                maxWidth: 540,
              ),
              if (addressText.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                await _makeShapedTextWidget(
                  text: addressText,
                  fontSize: 10.8,
                  textColor: const Color(0xFF1E293B),
                  bold: true,
                  maxLines: 1,
                  maxWidth: 540,
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Left: White rounded card with School / PM SHRI Logo
                  pw.Container(
                    width: 130,
                    height: 42,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(
                          color: PdfColor.fromInt(0xFFCBD5E1), width: 0.9),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    alignment: pw.Alignment.center,
                    child: _cachedSchoolLogo != null
                        ? pw.Image(_cachedSchoolLogo!, fit: pw.BoxFit.contain)
                        : pw.SizedBox(),
                  ),
                  // Center: Double-bordered maroon/red badge with gold પરિણામ પત્રક text
                  pw.Container(
                    width: 245,
                    height: 40,
                    padding: const pw.EdgeInsets.all(2.2),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFFFFBEB),
                      border: pw.Border.all(
                          color: PdfColor.fromInt(0xFF7A1C1C), width: 1.6),
                      borderRadius: pw.BorderRadius.circular(9),
                    ),
                    child: pw.Container(
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFB91C1C),
                        borderRadius: pw.BorderRadius.circular(6.5),
                      ),
                      child: await _makeShapedTextWidget(
                        text: 'પરિણામ પત્રક',
                        fontSize: 20.5,
                        textColor: const Color(0xFFFFEA00),
                        bold: true,
                        maxWidth: 230,
                      ),
                    ),
                  ),
                  // Right: White rounded card with શાળા DISE કોડ
                  pw.Container(
                    width: 130,
                    height: 42,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(
                          color: PdfColor.fromInt(0xFFCBD5E1), width: 0.9),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    alignment: pw.Alignment.center,
                    child: _schoolDiseCode.isNotEmpty
                        ? pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              await _makeShapedTextWidget(
                                text: 'શાળા DISE કોડ',
                                fontSize: 10.0,
                                textColor: const Color(0xFF1E293B),
                                bold: true,
                                maxLines: 1,
                                maxWidth: 118,
                              ),
                              pw.SizedBox(height: 1),
                              await _makeShapedTextWidget(
                                text: _schoolDiseCode,
                                fontSize: 13.5,
                                textColor: Colors.black,
                                bold: true,
                                maxLines: 1,
                                maxWidth: 118,
                              ),
                            ],
                          )
                        : pw.SizedBox(),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Center(child: semTitleWidget),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(32, 172, 32, 65),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              nameRow,
              pw.SizedBox(height: 6),
              infoRow,
              pw.SizedBox(height: 12),
              ...tableWidgets,
              pw.SizedBox(height: 14),
              pw.Align(alignment: pw.Alignment.centerLeft, child: placeWidget),
              pw.SizedBox(height: 4),
              pw.Align(alignment: pw.Alignment.centerLeft, child: dateWidget),
            ],
          ),
        ),
        if (divyangNoteWidget != null)
          pw.Positioned(
              left: 165,
              right: 165,
              bottom: 60,
              child: pw.Center(child: divyangNoteWidget)),
        pw.Positioned(
          left: 44,
          right: 44,
          bottom: 34,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              await _makeShapedTextWidget(
                  text: 'વર્ગ શિક્ષકની સહી',
                  fontSize: 13.0,
                  textColor: Colors.black,
                  bold: true,
                  maxWidth: 170),
              await _makeShapedTextWidget(
                  text: 'આચાર્યની સહી',
                  fontSize: 13.0,
                  textColor: Colors.black,
                  bold: true,
                  maxWidth: 170),
            ],
          ),
        ),
        pw.Positioned(
          left: 14,
          right: 14,
          bottom: 10,
          child: pw.Container(
            height: 19,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF7A1C1C),
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: await _makeShapedTextWidget(
                text: _reportCardGradeScaleText,
                fontSize: 9.2,
                textColor: Colors.white,
                bold: true,
                maxLines: 1,
                maxWidth: 555),
          ),
        ),
      ],
    );
  }

  // Sem 1 -> Portrait A4 | Sem 2 -> Portrait Legal
  // ===========================================================================
  Map<String, dynamic> _buildResultFrontPageValues(
      {required bool isSem1, required List<String> reportSubjects}) {
    if (_gradeLabels.length > 5) {
      throw StateError(
        'આ Result front-page template માં વધુમાં વધુ 5 grade columns ઉપલબ્ધ છે. Grade settings ને A થી E સુધી ગોઠવો અથવા અપડેટેડ template અપલોડ કરો.',
      );
    }
    final coedSchool = _resultSchoolType == 'coed';
    final configuredGender = _resultSchoolType == 'boys' ? 'BOYS' : 'GIRLS';
    final buckets = const ['SC', 'ST', 'OBC', 'OTHER'];
    final regByGender = <String, Map<String, int>>{
      for (final bucket in buckets)
        bucket: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0},
    };
    final gradeByGender = <String, Map<String, Map<String, int>>>{
      for (final bucket in buckets)
        bucket: {
          for (final grade in _gradeLabels)
            grade: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0},
        },
    };

    for (final st in _students) {
      if (st.name.trim().isEmpty) continue;
      if (!isSem1 && !st.studiedInSem2) continue;
      final bucket = _normalizeCategoryBucket(st.category);
      final rawGender = st.gender.toUpperCase().trim();
      final gender = !coedSchool
          ? configuredGender
          : (rawGender == 'BOYS' || rawGender == 'BOY')
              ? 'BOYS'
              : (rawGender == 'GIRLS' || rawGender == 'GIRL')
                  ? 'GIRLS'
                  : 'UNSPECIFIED';
      regByGender[bucket]![gender] = (regByGender[bucket]![gender] ?? 0) + 1;

      var sum = 0;
      var studentMax = 0;
      for (final subject in reportSubjects) {
        final s1 = st.sem1[subject]?.total ?? 0;
        final s2 = st.studiedInSem2 ? (st.sem2[subject]?.total ?? 0) : 0;
        final hasS1 = _classHasSem1Marks(subject);
        final hasS2 = st.studiedInSem2 && _classHasSem2Marks(subject);
        if (isSem1) {
          if (hasS1) {
            sum += s1;
            studentMax += _sem1MaximumForSubject(st, subject);
          }
        } else if (hasS1 || hasS2) {
          sum += st.studiedInSem2 ? s1 + s2 : s1;
          studentMax += (hasS1 ? _sem1MaximumForSubject(st, subject) : 0) +
              (hasS2 ? _maxSubSemTotal : 0);
        }
      }
      final isAnnual = _selectedSem == 'Annual';
      final vv =
          isSem1 ? st.vv1 : (isAnnual ? st.vv1 + st.vv2 : st.vvAvgBothSem);
      sum += vv;
      studentMax += isAnnual ? _vvMaxPerSemester * 2 : _vvMaxPerSemester;
      if (sum > 0 && studentMax > 0) {
        final grade = _gradeFor((sum / studentMax) * 100);
        final grades = gradeByGender[bucket]![grade];
        if (grades != null) grades[gender] = (grades[gender] ?? 0) + 1;
      }
    }

    final values = <String, dynamic>{
      if (_frontPageEducationAuthority.trim().isNotEmpty)
        'B2': _frontPageEducationAuthority.trim(),
      'B6': 'શાળાનું નામ :- $_schoolDisplayName',
      'B7': 'ગામ :- $_frontPageVillage',
      'H7': 'તાલુકો :- $_frontPageTaluka',
      'O7': 'જિલ્લો :- $_frontPageDistrict',
      'B8': 'ધોરણ:- ${ClassLabel.bare(_cleanClassCode)}',
      'H8': 'પરિણામની તારીખ :- ${isSem1 ? _effectiveFirstSemResultDate : _effectiveSecondSemResultDate}',
      'B9': 'પે સેન્ટર :- $_frontPagePayCenter',
      'B10': 'વર્ગ શિક્ષકનું નામ :- $_classTeacherName',
      'B11': 'સી. આર. સી. :- $_frontPageCrc',
      'N11': 'વર્ષ :- $_academicYear',
    };

    var totalBoys = 0;
    var totalGirls = 0;
    var totalUnspecified = 0;
    final totalGradeByGender = <String, Map<String, int>>{
      for (final grade in _gradeLabels)
        grade: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0},
    };
    for (var rowIndex = 0; rowIndex < buckets.length; rowIndex++) {
      final bucket = buckets[rowIndex];
      final row = 17 + rowIndex;
      final boys = regByGender[bucket]!['BOYS'] ?? 0;
      final girls = regByGender[bucket]!['GIRLS'] ?? 0;
      final unspecified = regByGender[bucket]!['UNSPECIFIED'] ?? 0;
      totalBoys += boys;
      totalGirls += girls;
      totalUnspecified += unspecified;

      final boysSchool = _resultSchoolType == 'boys';
      final registered = coedSchool
          ? boys + girls
          : (regByGender[bucket]![configuredGender] ?? 0);
      values['C$row'] = coedSchool ? boys : (boysSchool ? registered : '-');
      values['D$row'] = coedSchool ? girls : (boysSchool ? '-' : registered);
      values['E$row'] = registered;

      final unspecifiedGrades = <String>[];
      for (var gradeIndex = 0; gradeIndex < _gradeLabels.length; gradeIndex++) {
        final grade = _gradeLabels[gradeIndex];
        final gradeCounts = gradeByGender[bucket]![grade]!;
        final gradeBoys = gradeCounts['BOYS'] ?? 0;
        final gradeGirls = gradeCounts['GIRLS'] ?? 0;
        final gradeUnspecified = gradeCounts['UNSPECIFIED'] ?? 0;
        totalGradeByGender[grade]!['BOYS'] =
            (totalGradeByGender[grade]!['BOYS'] ?? 0) + gradeBoys;
        totalGradeByGender[grade]!['GIRLS'] =
            (totalGradeByGender[grade]!['GIRLS'] ?? 0) + gradeGirls;
        totalGradeByGender[grade]!['UNSPECIFIED'] =
            (totalGradeByGender[grade]!['UNSPECIFIED'] ?? 0) + gradeUnspecified;
        if (gradeUnspecified > 0) {
          unspecifiedGrades.add('$grade: $gradeUnspecified');
        }
        final startColumn = 6 + (gradeIndex * 3);
        if (coedSchool) {
          values['${_excelColumnName(startColumn)}$row'] = gradeBoys;
          values['${_excelColumnName(startColumn + 1)}$row'] = gradeGirls;
          values['${_excelColumnName(startColumn + 2)}$row'] =
              gradeBoys + gradeGirls;
        } else {
          final count = gradeCounts[configuredGender] ?? 0;
          values['${_excelColumnName(startColumn)}$row'] = boysSchool ? count : '-';
          values['${_excelColumnName(startColumn + 1)}$row'] = boysSchool ? '-' : count;
          values['${_excelColumnName(startColumn + 2)}$row'] = count;
        }
      }
      if (coedSchool) {
        final notes = <String>[
          if (unspecified > 0) 'લિંગ નોંધાયેલ નથી: $unspecified',
          ...unspecifiedGrades,
        ];
        values['U$row'] = notes.join(' | ');
      } else {
        values['U$row'] = '';
      }
    }

    final totalRow = 21;
    final boysSchool = _resultSchoolType == 'boys';
    final totalRegistered =
        coedSchool ? totalBoys + totalGirls : totalBoys + totalGirls;
    values['C$totalRow'] = coedSchool
        ? totalBoys
        : (boysSchool ? totalRegistered : '-');
    values['D$totalRow'] = coedSchool
        ? totalGirls
        : (boysSchool ? '-' : totalRegistered);
    values['E$totalRow'] = totalRegistered;
    for (var gradeIndex = 0; gradeIndex < _gradeLabels.length; gradeIndex++) {
      final grade = _gradeLabels[gradeIndex];
      final gradeBoys = totalGradeByGender[grade]!['BOYS'] ?? 0;
      final gradeGirls = totalGradeByGender[grade]!['GIRLS'] ?? 0;
      final startColumn = 6 + (gradeIndex * 3);
      if (coedSchool) {
        values['${_excelColumnName(startColumn)}$totalRow'] = gradeBoys;
        values['${_excelColumnName(startColumn + 1)}$totalRow'] = gradeGirls;
        values['${_excelColumnName(startColumn + 2)}$totalRow'] =
            gradeBoys + gradeGirls;
      } else {
        final count = totalGradeByGender[grade]![configuredGender] ?? 0;
        values['${_excelColumnName(startColumn)}$totalRow'] = boysSchool ? count : '-';
        values['${_excelColumnName(startColumn + 1)}$totalRow'] = boysSchool ? '-' : count;
        values['${_excelColumnName(startColumn + 2)}$totalRow'] = count;
      }
    }
    if (coedSchool) {
      final notes = <String>[
        if (totalUnspecified > 0) 'લિંગ નોંધાયેલ નથી: $totalUnspecified',
        ..._gradeLabels
            .where(
                (grade) => (totalGradeByGender[grade]!['UNSPECIFIED'] ?? 0) > 0)
            .map((grade) =>
                '$grade: ${totalGradeByGender[grade]!['UNSPECIFIED']}'),
      ];
      values['U$totalRow'] = notes.join(' | ');
    } else {
      values['U$totalRow'] = '';
    }
    return values;
  }

  static String _excelColumnName(int number) {
    var value = number;
    final output = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      output.writeCharCode(65 + remainder);
      value = (value - 1) ~/ 26;
    }
    return output.toString().split('').reversed.join();
  }

  List<Map<String, dynamic>> _buildResultTemplateStudentRows(
      {required bool isSem1, required List<String> reportSubjects}) {
    final vvMax = _vvMaxPerSemester;
    final grandMax = _classReportMaximum(
      reportSubjects,
      firstSemesterOnly: isSem1,
      vvMaximum: vvMax,
    );
    final rows = <Map<String, dynamic>>[];
    for (final st
        in _students.where((student) => student.name.trim().isNotEmpty)) {
      final presentDaysCell =
          _resolvePresentDaysCellForPrint(st, isSem1: isSem1);
      final base = <dynamic>[
        st.roll,
        st.name,
        st.category,
        if (_resultSchoolType == 'coed')
          (st.gender.toUpperCase() == 'BOYS' ||
                  st.gender.toUpperCase() == 'BOY')
              ? 'કુમાર'
              : (st.gender.toUpperCase() == 'GIRLS' ||
                      st.gender.toUpperCase() == 'GIRL')
                  ? 'કન્યા'
                  : '',
        st.gr,
        _pad2(st.dd),
        _pad2(st.mm),
        st.yyyy,
        presentDaysCell,
      ];

      final groups = <List<dynamic>>[];
      if (isSem1) {
        for (final subject in reportSubjects) {
          final marks = st.sem1[subject] ?? const SubjectMarks();
          final directMode = marks.usesDirectTotal ||
              _students.any(
                  (student) => student.sem1[subject]?.usesDirectTotal == true);
          groups.add(<dynamic>[
            directMode ? marks.total : marks.patrakA,
            directMode ? '' : (marks.satrantAbsent ? 'AB' : marks.satrant),
            directMode ? '' : marks.swaAdhyayan,
            marks.total,
            _gradeFor(marks.total *
                100 /
                (directMode ? 100 : _sem1MaximumForSubject(st, subject))),
            directMode,
          ]);
        }
      } else {
        for (final subject in reportSubjects) {
          final first = st.sem1[subject] ?? const SubjectMarks();
          if (!st.studiedInSem2) {
            final directMode = first.usesDirectTotal ||
                _students.any((student) =>
                    student.sem1[subject]?.usesDirectTotal == true);
            groups.add(<dynamic>[
              directMode ? first.total : first.patrakA,
              directMode ? '' : (first.satrantAbsent ? 'AB' : first.satrant),
              directMode ? '' : first.swaAdhyayan,
              'નામ',
              'કમી',
              '-',
              first.total,
              'નામ કમી',
              directMode,
            ]);
          } else {
            final second = st.sem2[subject] ?? const SubjectMarks();
            final isSem2Only = _sem2OnlySubjects.contains(subject);
            final total =
                isSem2Only ? second.total : first.total + second.total;
            final directMode = first.usesDirectTotal ||
                _students.any((student) =>
                    student.sem1[subject]?.usesDirectTotal == true);
            final maximum = isSem2Only
                ? _maxSubSemTotal
                : (directMode ? 100 : _sem1MaximumForSubject(st, subject)) +
                    _maxSubSemTotal;
            groups.add(<dynamic>[
              isSem2Only ? '-' : (directMode ? first.total : first.patrakA),
              isSem2Only ? '-' : (directMode ? '' : (first.satrantAbsent ? 'AB' : first.satrant)),
              isSem2Only ? '-' : (directMode ? '' : first.swaAdhyayan),
              second.patrakA,
              second.satrantAbsent ? 'AB' : second.satrant,
              second.swaAdhyayan,
              total,
              _gradeFor(total * 100 / maximum),
              directMode && !isSem2Only,
            ]);
          }
        }
      }

      final List<dynamic> tail;
      if (isSem1) {
        final dispVv = st.vv1;
        final subSum = reportSubjects.fold<int>(
          0,
          (sum, subject) => sum + (st.sem1[subject]?.total ?? 0),
        );
        final grandObt = subSum + dispVv;
        final percentage = grandMax > 0 ? grandObt * 100 / grandMax : 0.0;
        tail = <dynamic>[
          dispVv,
          _gradeFor(dispVv * 100 / vvMax),
          grandObt,
          _gradeFor(percentage),
          percentage,
          if (_showParinamInReportCard)
            _evaluatePassFailForStudent(st, isSem1: true),
          st.uid,
          st.pen,
        ];
      } else if (!st.studiedInSem2) {
        tail = <dynamic>[
          st.vv1,
          'નામ કમી',
          '-',
          'નામ કમી',
          '',
          _showParinamInReportCard ? 'નામ કમી' : '',
          st.uid,
          st.pen,
        ];
      } else {
        final subSum = reportSubjects.fold<int>(0, (sum, subject) {
          final first = st.sem1[subject]?.total ?? 0;
          final second = st.sem2[subject]?.total ?? 0;
          return sum +
              (_sem2OnlySubjects.contains(subject) ? second : first + second);
        });
        final vvAverage = st.vvAvgBothSem;
        final grandObt = subSum + vvAverage;
        final percentage = grandMax > 0 ? grandObt * 100 / grandMax : 0.0;
        tail = <dynamic>[
          vvAverage,
          _gradeFor(vvAverage * 100 / _vvMaxPerSemester),
          grandObt,
          _gradeFor(percentage),
          percentage,
          _showParinamInReportCard
              ? _evaluatePassFailForStudent(st, isSem1: false)
              : '',
          st.uid,
          st.pen,
        ];
      }
      rows.add(<String, dynamic>{
        'base': base,
        'groups': groups,
        'tail': tail,
      });
    }
    return rows;
  }

  Future<Uint8List> _buildResultTemplateWorkbook() async {
    if (!_schoolBrandingLoaded || _schoolLogoBytes == null) {
      await _loadRegisteredSchoolBranding(force: _schoolLogoBytes == null);
    }
    final isSem1 = _selectedSem == '1';
    final subjects = _subjectsForCurrentReport;
    if (subjects.isEmpty) {
      throw StateError('આ સત્રમાં પરિણામ માટે ગુણ સેવ થયેલા વિષયો મળ્યા નથી.');
    }
    final vvMax = _vvMaxPerSemester;
    final grandMax = _classReportMaximum(
      subjects,
      firstSemesterOnly: isSem1,
      vvMaximum: vvMax,
    );
    final includeTail = !_isSubjectTeacherOnly;
    final rows = _buildResultTemplateStudentRows(
      isSem1: isSem1,
      reportSubjects: subjects,
    );
    final frontValues = includeTail
        ? _buildResultFrontPageValues(
            isSem1: isSem1,
            reportSubjects: subjects,
          )
        : const <String, dynamic>{};
    return ResultXlsxTemplateExporter().build(
      semester: isSem1 ? 1 : 2,
      schoolType: _resultSchoolType,
      classLabel: _cleanClassCode,
      subjects: subjects,
      frontPageValues: frontValues,
      studentRows: rows,
      schoolLogoBytes: _schoolLogoBytes,
      removeUnusedSubjectGroups: true,
      includeTailColumns: includeTail,
      showParinamColumn: _showParinamInReportCard,
      vvMaxOverride: vvMax,
      grandMaxOverride: grandMax,
      sem2OnlySubjects: _sem2OnlySubjects,
    );
  }

  Future<Uint8List> _buildVyaktitvaVikasTemplateWorkbook({bool? sem1}) async {
    final isSem1 = sem1 ?? _selectedSem == '1';
    final validStudents =
        _students.where((student) => student.name.trim().isNotEmpty).toList();
    if (validStudents.isEmpty) {
      throw StateError('આ વર્ગમાં વ્યક્તિત્વ વિકાસ માટે કોઈ વિદ્યાર્થી નથી.');
    }

    final sentenceTitles = _vvSentences.length == 40
        ? List<String>.from(_vvSentences)
        : List<String>.from(kVv40Sentences);
    final rows = <Map<String, dynamic>>[];

    for (final student in validStudents) {
      if (!isSem1 && !student.studiedInSem2) {
        rows.add(<String, dynamic>{
          'roll': student.roll,
          'name': student.name,
          'sentences': List<dynamic>.generate(
            40,
            (index) => index == 19 ? 'નામ' : (index == 20 ? 'કમી' : '-'),
          ),
          'total': 'નામ કમી',
          'firstSemesterTotal': student.vv1,
          'average': 'નામ કમી',
        });
        continue;
      }

      final total = isSem1 ? student.vv1 : student.vv2;
      final storedSentences =
          isSem1 ? student.vv1Sentences : student.vv2Sentences;
      var sentenceMarks = storedSentences.length == 40
          ? List<int>.from(storedSentences)
          : List<int>.filled(40, 0);
      final sentenceTotal =
          sentenceMarks.fold<int>(0, (sum, mark) => sum + mark);
      if (sentenceTotal != total) {
        sentenceMarks = total > 0
            ? generateRandom40Sentences(total, _vvMaxPerSentence)
            : List<int>.filled(40, 0);
      }

      rows.add(<String, dynamic>{
        'roll': student.roll,
        'name': student.name,
        'sentences': sentenceMarks,
        'total': total,
        'firstSemesterTotal': student.vv1,
        'average': student.vvAvgBothSem,
      });
    }

    return ResultXlsxTemplateExporter().buildVyaktitvaVikas(
      semester: isSem1 ? 1 : 2,
      classLabel: _cleanClassCode,
      schoolName: _schoolDisplayName,
      academicYear: _academicYear,
      sentenceTitles: sentenceTitles,
      studentRows: rows,
    );
  }

  Future<bool> _tryResultTemplatePdf(String view) async {
    if (_students.isEmpty) return true;
    if (view != 'vv' && _subjectsForCurrentReport.isEmpty) {
      showSnack(context, 'આ સત્રમાં પરિણામ માટે ગુણ સેવ થયેલા વિષયો મળ્યા નથી.',
          error: true);
      return true;
    }
    if (_resultExporting) return true;
    if (view != 'vv') {
      final presentOk = await _askAndPreparePresentDaysForResultPrint();
      if (!presentOk || !mounted) return true;
    }
    setState(() => _resultExporting = true);
    try {
      final workbookBytes = view == 'vv'
          ? await _buildVyaktitvaVikasTemplateWorkbook()
          : await _buildResultTemplateWorkbook();
      if (view == 'front' && (_schoolLogoBytes == null || !_schoolBrandingLoaded)) {
        await _loadRegisteredSchoolBranding(force: _schoolLogoBytes == null);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final job = TemplatePrintPlans.result(
        workbookBytes: workbookBytes,
        view: view,
        rowHeightPx: _resultPdfRowHeight,
        fontPt: _resultPdfFontSize,
        logoBytes: _schoolLogoBytes,
        title: '${_cleanClassCode}_${_semTag}_${view.toUpperCase()}',
      );
      if (!mounted) return true;
      await TemplatePrintService.printJob(context, job);
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Result પ્રિન્ટ તૈયાર થઈ શકી નથી: $error',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _resultExporting = false);
    }
    return true;
  }

  Future<void> _downloadResultExcel() async {
    if (_students.isEmpty || _resultExporting) return;
    if (_subjectsForCurrentReport.isEmpty) {
      showSnack(context, 'આ સત્રમાં પરિણામ માટે ગુણ સેવ થયેલા વિષયો મળ્યા નથી.',
          error: true);
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '📊 $_cleanClassCode $_semTag EXCEL સેટિંગ્સ',
            style: guFont(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navy),
          ),
          content: SizedBox(
            width: 410,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildParinamAndDivyangRuleControls(
                  setDialogState,
                  isClassSheet: true,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('રદ કરો',
                  style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            AppButton(
              label: '📊 EXCEL ડાઉનલોડ કરો',
              background: AppColors.greenDeep,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (proceed != true || !mounted) return;
    final presentOk = await _askAndPreparePresentDaysForResultPrint();
    if (!presentOk || !mounted) return;
    setState(() => _resultExporting = true);
    try {
      final bytes = await _buildResultTemplateWorkbook();
      final semNumber = _selectedSem == '1' ? 1 : 2;
      final safeClass =
          _cleanClassCode.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filename = 'RESULT_${safeClass}_SEM$semNumber.xlsx';
      const mime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      if (kIsWeb) {
        final blob = html.Blob(<Object>[bytes], mime);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        await SharePlus.instance.share(ShareParams(
          files: <XFile>[
            XFile.fromData(bytes, name: filename, mimeType: mime),
          ],
          subject: filename,
        ));
      }
      if (mounted) showSnack(context, '✅ Excel ફાઇલ તૈયાર છે: $filename');
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Excel export થઈ શક્યો નથી: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _resultExporting = false);
    }
  }

  Future<void> _generateFrontPagePdf() async {
    if (_students.isEmpty) return;
    if (await _tryResultTemplatePdf('front')) return;

    final fontRegular = await PdfGoogleFonts.notoSansGujaratiRegular();
    final fontBold = await PdfGoogleFonts.notoSansGujaratiBold();
    final doc = pw.Document();

    final cleanClass = _cleanClassCode;
    final isSem1 = _selectedSem == '1';
    final coedSchool = _resultSchoolType == 'coed';
    final configuredGender = _resultSchoolType == 'boys' ? 'BOYS' : 'GIRLS';
    final pageFormat = isSem1 ? PdfPageFormat.a4 : PdfPageFormat.legal;
    final vvMax = _vvMaxPerSemester;
    final reportSubjects = _subjectsForCurrentReport;
    if (reportSubjects.isEmpty) {
      if (!mounted) return;
      showSnack(context, 'આ સત્રમાં પરિણામ માટે ગુણ સેવ થયેલા વિષયો મળ્યા નથી.',
          error: true);
      return;
    }

    final buckets = ['SC', 'ST', 'OBC', 'OTHER'];
    final labels = {
      'SC': 'અનુ. જાતિ',
      'ST': 'અનુ. જ. જાતિ',
      'OBC': 'બક્ષીપંચ',
      'OTHER': 'અન્ય',
    };
    final regByGender = {
      for (final b in buckets) b: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0}
    };
    final gradeByGender = {
      for (final b in buckets)
        b: {
          for (final g in _gradeLabels)
            g: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0}
        }
    };

    for (final st in _students) {
      if (st.name.trim().isEmpty) continue;
      if (!isSem1 && !st.studiedInSem2) continue;
      final b = _normalizeCategoryBucket(st.category);
      final gender = !coedSchool
          ? configuredGender
          : st.gender.toUpperCase() == 'BOYS' ||
                  st.gender.toUpperCase() == 'BOY'
              ? 'BOYS'
              : st.gender.toUpperCase() == 'GIRLS' ||
                      st.gender.toUpperCase() == 'GIRL'
                  ? 'GIRLS'
                  : 'UNSPECIFIED';
      regByGender[b]![gender] = (regByGender[b]![gender] ?? 0) + 1;

      int sum = 0;
      int studentMax = 0;
      for (final sub in reportSubjects) {
        final int s1 = (st.sem1[sub]?.total ?? 0).toInt();
        final int s2 =
            st.studiedInSem2 ? (st.sem2[sub]?.total ?? 0).toInt() : 0;
        final bool hasS1 = _classHasSem1Marks(sub);
        final bool hasS2 = st.studiedInSem2 && _classHasSem2Marks(sub);
        if (isSem1) {
          if (hasS1) {
            sum += s1;
            studentMax += _sem1MaximumForSubject(st, sub);
          }
        } else if (hasS1 || hasS2) {
          sum += st.studiedInSem2 ? s1 + s2 : s1;
          studentMax += (hasS1 ? _sem1MaximumForSubject(st, sub) : 0) +
              (hasS2 ? _maxSubSemTotal : 0);
        }
      }
      final bool annual = _selectedSem == 'Annual';
      final int vv = isSem1
          ? st.vv1
          : (annual ? st.vv1 + st.vv2 : st.vvAvgBothSem.toInt());
      sum += vv;
      studentMax += annual ? vvMax * 2 : vvMax;

      if (sum > 0 && studentMax > 0) {
        final g = _gradeFor((sum / studentMax) * 100);
        gradeByGender[b]![g]![gender] =
            (gradeByGender[b]![g]![gender] ?? 0) + 1;
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(14),
        build: (ctx) {
          pw.Widget cell(String t,
              {bool bold = false,
              double size = 10,
              pw.Alignment align = pw.Alignment.center}) {
            return pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
              child: pw.Align(
                alignment: align,
                child: pw.Text(t,
                    style: pw.TextStyle(
                        font: bold ? fontBold : fontRegular, fontSize: size)),
              ),
            );
          }

          final tarijRows = <pw.TableRow>[
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: coedSchool
                  ? [
                      cell('જાતિ', bold: true),
                      cell('રજી.\nકુમાર', bold: true, size: 8.5),
                      cell('કન્યા', bold: true, size: 8.5),
                      cell('કુલ', bold: true, size: 8.5),
                      for (final g in _gradeLabels) ...[
                        cell('$g\nકુમાર', bold: true, size: 8.5),
                        cell('$g\nકન્યા', bold: true, size: 8.5),
                        cell('$g\nકુલ', bold: true, size: 8.5),
                      ],
                      cell('નોંધ', bold: true),
                    ]
                  : [
                      cell('જાતિ', bold: true),
                      cell(_resultSchoolType == 'boys' ? 'રજી.\nકુમાર' : 'રજી.\nકન્યા', bold: true, size: 8.5),
                      for (final g in _gradeLabels)
                        cell('$g\n(${_resultSchoolType == "boys" ? "કુમાર" : "કન્યા"})', bold: true, size: 8.5),
                      cell('નોંધ', bold: true),
                    ],
            ),
          ];

          int totalBoys = 0;
          int totalGirls = 0;
          int totalUnspecified = 0;
          final totalGradeByGender = {
            for (final g in _gradeLabels)
              g: {'BOYS': 0, 'GIRLS': 0, 'UNSPECIFIED': 0}
          };

          for (final b in buckets) {
            final boys = regByGender[b]!['BOYS'] ?? 0;
            final girls = regByGender[b]!['GIRLS'] ?? 0;
            final unspecified = regByGender[b]!['UNSPECIFIED'] ?? 0;
            // All displayed totals in this table must equal Boys + Girls.
            // Students whose gender is not recorded are disclosed separately.
            final r = boys + girls;
            totalBoys += boys;
            totalGirls += girls;
            totalUnspecified += unspecified;
            for (final g in _gradeLabels) {
              for (final gender in ['BOYS', 'GIRLS', 'UNSPECIFIED']) {
                totalGradeByGender[g]![gender] =
                    (totalGradeByGender[g]![gender] ?? 0) +
                        (gradeByGender[b]![g]![gender] ?? 0);
              }
            }
            final unassignedGrades = _gradeLabels
                .map((grade) => MapEntry(
                    grade, gradeByGender[b]![grade]!['UNSPECIFIED'] ?? 0))
                .where((entry) => entry.value > 0)
                .map((entry) => '${entry.key}: ${entry.value}')
                .toList();
            final noteParts = <String>[];
            if (unspecified > 0)
              noteParts.add('લિંગ નોંધાયેલ નથી: $unspecified');
            if (unassignedGrades.isNotEmpty)
              noteParts.add('ગ્રેડ: ${unassignedGrades.join(', ')}');
            tarijRows.add(
              pw.TableRow(
                children: coedSchool
                    ? [
                        cell(labels[b]!,
                            bold: true, align: pw.Alignment.centerLeft),
                        cell('$boys', bold: true),
                        cell('$girls', bold: true),
                        cell('$r', bold: true),
                        for (final g in _gradeLabels) ...[
                          cell('${gradeByGender[b]![g]!['BOYS'] ?? 0}'),
                          cell('${gradeByGender[b]![g]!['GIRLS'] ?? 0}'),
                          cell(
                              '${(gradeByGender[b]![g]!['BOYS'] ?? 0) + (gradeByGender[b]![g]!['GIRLS'] ?? 0)}',
                              bold: true),
                        ],
                        cell(noteParts.join(' | ')),
                      ]
                    : [
                        cell(labels[b]!,
                            bold: true, align: pw.Alignment.centerLeft),
                        cell('${regByGender[b]![configuredGender] ?? 0}',
                            bold: true),
                        for (final g in _gradeLabels)
                          cell(
                              '${gradeByGender[b]![g]![configuredGender] ?? 0}'),
                        cell(''),
                      ],
              ),
            );
          }

          final singleSexRegistered = regByGender.values
              .fold<int>(0, (n, g) => n + (g[configuredGender] ?? 0));
          tarijRows.add(
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: coedSchool
                  ? [
                      cell('કુલ', bold: true),
                      cell('$totalBoys', bold: true),
                      cell('$totalGirls', bold: true),
                      cell('${totalBoys + totalGirls}', bold: true),
                      for (final g in _gradeLabels) ...[
                        cell('${totalGradeByGender[g]!['BOYS'] ?? 0}',
                            bold: true),
                        cell('${totalGradeByGender[g]!['GIRLS'] ?? 0}',
                            bold: true),
                        cell(
                            '${(totalGradeByGender[g]!['BOYS'] ?? 0) + (totalGradeByGender[g]!['GIRLS'] ?? 0)}',
                            bold: true),
                      ],
                      cell([
                        if (totalUnspecified > 0)
                          'લિંગ નોંધાયેલ નથી: $totalUnspecified',
                        ..._gradeLabels
                            .where((g) =>
                                (totalGradeByGender[g]!['UNSPECIFIED'] ?? 0) >
                                0)
                            .map((g) =>
                                '$g: ${totalGradeByGender[g]!['UNSPECIFIED']}'),
                      ].join(' | ')),
                    ]
                  : [
                      cell('કુલ', bold: true),
                      cell('$singleSexRegistered', bold: true),
                      for (final g in _gradeLabels)
                        cell('${totalGradeByGender[g]![configuredGender] ?? 0}',
                            bold: true),
                      cell(''),
                    ],
            ),
          );

          final logoRowHeight =
              isSem1 ? _excelSem1LogoRowHeight : _excelSem2LogoRowHeight;
          final logoSourceRowHeight =
              isSem1 ? _excelSem1LogoRowHeight : _excelSem2LogoRowHeight;
          final logoSourceWidth =
              isSem1 ? _excelSem1LogoImageWidth : _excelSem2LogoImageWidth;
          final logoSourceHeight =
              isSem1 ? _excelSem1LogoImageHeight : _excelSem2LogoImageHeight;
          final logoScale = logoRowHeight / logoSourceRowHeight;
          final logoWidth = logoSourceWidth * logoScale;
          final logoHeight = logoSourceHeight * logoScale;
          final authorityTitle = _frontPageEducationAuthority.trim().isEmpty
              ? _schoolDisplayName
              : _frontPageEducationAuthority.trim();

          pw.Widget frontPageTitleHeader() {
            final titleStack = pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('પરિશિષ્ટ - ક',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontBold, fontSize: 15)),
                pw.SizedBox(height: 5),
                pw.Text(authorityTitle,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontBold, fontSize: 18)),
                pw.SizedBox(height: 5),
                pw.Text('પરિણામ પત્રક',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontBold, fontSize: 21)),
              ],
            );
            if (_cachedSchoolLogo == null) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text('પરિશિષ્ટ - ક',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fontBold, fontSize: 16)),
                  pw.Text(authorityTitle,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fontBold, fontSize: 20)),
                  pw.SizedBox(height: 6),
                  pw.Text('પરિણામ પત્રક',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fontBold, fontSize: 24)),
                ],
              );
            }
            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: logoWidth,
                  height: logoHeight,
                  alignment: pw.Alignment.center,
                  child: pw.Image(_cachedSchoolLogo!, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(child: titleStack),
              ],
            );
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              frontPageTitleHeader(),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 1.5),
                        borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Text('ધોરણ:- ${ClassLabel.bare(cleanClass)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 15)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 1.5),
                        borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Text('વર્ષ - $_academicYear',
                        style: pw.TextStyle(font: fontBold, fontSize: 15)),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text(_schoolDisplayName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 20,
                      color: PdfColors.indigo900)),
              pw.Text(
                  _frontPageLocationLine.isEmpty
                      ? _schoolDisplayName
                      : _frontPageLocationLine,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              if ((_schoolProfile['schoolDiseCode'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
                pw.Text('શાળા DISE કોડ - ${_schoolProfile['schoolDiseCode']}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontBold, fontSize: 13)),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(width: 1.2),
                children: [
                  pw.TableRow(children: [
                    cell('શાળાનું નામ :- $_schoolDisplayName',
                        bold: true, align: pw.Alignment.centerLeft, size: 11)
                  ]),
                  pw.TableRow(children: [
                    cell(
                        _frontPageLocationLine.isEmpty
                            ? 'ગામ / તાલુકો / જિલ્લો'
                            : _frontPageLocationLine,
                        bold: true,
                        align: pw.Alignment.centerLeft,
                        size: 11)
                  ]),
                  pw.TableRow(children: [
                    cell(
                        'ધોરણ:- ${ClassLabel.bare(cleanClass)}        |        પરિણામની તારીખ :- $_activeSemResultDate',
                        bold: true,
                        align: pw.Alignment.centerLeft,
                        size: 11)
                  ]),
                  pw.TableRow(children: [
                    cell('પે સેન્ટર :- $_frontPagePayCenter',
                        bold: true, align: pw.Alignment.centerLeft, size: 11)
                  ]),
                  pw.TableRow(children: [
                    cell('વર્ગ શિક્ષકનું નામ :- $_classTeacherName',
                        bold: true, align: pw.Alignment.centerLeft, size: 11)
                  ]),
                  pw.TableRow(children: [
                    cell('સી. આર. સી. :- $_frontPageCrc',
                        bold: true, align: pw.Alignment.centerLeft, size: 11)
                  ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text('પરિણામની તારીજ',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: 16)),
              pw.SizedBox(height: 8),
              pw.Table(
                  border: pw.TableBorder.all(width: 1), children: tarijRows),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('વર્ગ શિક્ષકશ્રી',
                      style: pw.TextStyle(font: fontBold, fontSize: 12)),
                  pw.Text('આચાર્યશ્રી',
                      style: pw.TextStyle(font: fontBold, fontSize: 12)),
                  pw.Text('ચકાસણી કરનાર',
                      style: pw.TextStyle(font: fontBold, fontSize: 12)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name: '$cleanClass $_semTag FRONT PAGE.pdf',
      format: pageFormat,
      onLayout: (_) async => doc.save(),
    );
  }

  // ===========================================================================
  // PDF 2: FIRST SEM RESULT (A4 Portrait) & SECOND SEM RESULT (Legal Portrait, Max Page Area)
  // ===========================================================================
  Future<void> _generateRegisterSheetPdf() async {
    if (_students.isEmpty) return;

    // Ask in BOTH First Sem and Second Sem / Annual Class Result whether to insert
    // the પરિણામ column, whether to apply the Divyang 20% Pass rule, and which Pass/Fail rule to use.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '📄 $_cleanClassCode $_semTag RESULT પ્રિન્ટ સેટિંગ્સ',
            style: guFont(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navy),
          ),
          content: SizedBox(
            width: 410,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildParinamAndDivyangRuleControls(
                  setDialogState,
                  isClassSheet: true,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('રદ કરો',
                  style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            AppButton(
              label: '📄 RESULT PDF જનરેટ કરો',
              background: AppColors.rose,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (proceed != true || !mounted) return;
    final presentOk = await _askAndPreparePresentDaysForResultPrint();
    if (!presentOk || !mounted) return;

    if (await _tryResultTemplatePdf('result')) return;

    final fontRegular = await PdfGoogleFonts.notoSansGujaratiRegular();
    final fontBold = await PdfGoogleFonts.notoSansGujaratiBold();
    final doc = pw.Document();

    final cleanClass = _cleanClassCode;
    final isSem1 = _selectedSem == '1';
    final reportSubjects = _subjectsForCurrentReport;
    if (reportSubjects.isEmpty) {
      if (!mounted) return;
      showSnack(context, 'આ સત્રમાં પરિણામ માટે ગુણ સેવ થયેલા વિષયો મળ્યા નથી.',
          error: true);
      return;
    }
    final pageFormat = isSem1 ? PdfPageFormat.a4 : PdfPageFormat.legal;
    final vvMax = _vvMaxPerSemester;
    final grandMax = _classReportMaximum(reportSubjects,
        firstSemesterOnly: isSem1, vvMaximum: vvMax);

    pw.Widget tCell(String text,
        {bool bold = false,
        double size = 7.5,
        pw.Alignment align = pw.Alignment.center}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: pw.Align(
          alignment: align,
          child: pw.Text(text,
              style: pw.TextStyle(
                  font: bold ? fontBold : fontRegular, fontSize: size)),
        ),
      );
    }

    pw.Widget vHeader(String text, {double height = 95, double size = 7}) {
      return pw.Container(
        height: height,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(1.5),
        child: pw.Transform.rotateBox(
          angle: 1.57079632679,
          child: pw.Text(text,
              style: pw.TextStyle(font: fontBold, fontSize: size)),
        ),
      );
    }

    final validStudents =
        _students.where((s) => s.name.trim().isNotEmpty).toList();
    final double availStudentPt = isSem1 ? 580.0 : 745.0;
    final double rowScaleFactor = _resultPdfRowHeight / 22.0;
    final double estRowHeightPt = math.max(
      12.0,
      math.min(42.0, math.max(16.5 * rowScaleFactor, _resultPdfFontSize * 1.75)),
    );
    final int studentsPerBatch = math.max(10, (availStudentPt ~/ estRowHeightPt));
    final includeTail = !_isSubjectTeacherOnly;

    // Over, then Down pagination: complete all horizontal pages for each 30-student
    // batch (e.g. Roll 1-30) before starting the next student batch (Roll 31-60).
    for (int batchStart = 0;
        batchStart < validStudents.length;
        batchStart += studentsPerBatch) {
      final batchStudents =
          validStudents.skip(batchStart).take(studentsPerBatch).toList();

      if (isSem1) {
        final sub0 = reportSubjects.first;
        doc.addPage(
          pw.MultiPage(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(8),
            build: (ctx) => [
              pw.Table(
                border: pw.TableBorder.all(width: 0.6),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      tCell('ક્રમ\n(1)', bold: true),
                      tCell('વિદ્યાર્થીનું નામ\n(2)', bold: true),
                      tCell('કેટેગરી\n(3)', bold: true),
                      if (_isSubjectTeacherOnly)
                        tCell('જાતિ\n(Caste)', bold: true),
                      tCell('GR નં.\n(4)', bold: true),
                      tCell('જન્મ તારીખ\nDD/MM/YYYY (5)', bold: true),
                      vHeader('પ્રથમ સત્રનાં હાજર દિવસો (6)'),
                      vHeader('$sub0 - રચનાત્મક મૂલ્યાંકન (40) (7)'),
                      vHeader('$sub0 - સત્રાંત મૂલ્યાંકન (40) (8)'),
                      vHeader('$sub0 - સ્વ-અધ્યયન મૂલ્યાંકન (20) (9)'),
                      vHeader('$sub0 - કુલ ગુણ 100 માંથી (10)'),
                      vHeader('$sub0 - ગ્રેડ (11)'),
                    ],
                  ),
                  for (final st in batchStudents)
                    () {
                      final m = st.sem1[sub0] ?? const SubjectMarks();
                      return pw.TableRow(
                        children: [
                          tCell(st.roll, bold: true),
                          tCell(st.name,
                              bold: true, align: pw.Alignment.centerLeft),
                          tCell(st.category),
                          if (_isSubjectTeacherOnly) tCell(st.caste),
                          tCell(st.gr),
                          tCell(_formatDob2Digits(st)),
                          tCell(_resolvePresentDaysTextForPrint(st, isSem1: true)),
                          tCell('${m.patrakA}'),
                          tCell(m.satrantAbsent ? 'AB' : '${m.satrant}'),
                          tCell('${m.swaAdhyayan}'),
                          tCell('${m.total}', bold: true),
                          tCell(_gradeFor(m.total.toDouble()), bold: true),
                        ],
                      );
                    }(),
                ],
              ),
            ],
          ),
        );

        for (int startSub = 1;
            startSub < reportSubjects.length;
            startSub += 3) {
          final chunk = reportSubjects.skip(startSub).take(3).toList();
          doc.addPage(
            pw.MultiPage(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(8),
              build: (ctx) => [
                pw.Table(
                  border: pw.TableBorder.all(width: 0.6),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        tCell('ક્રમ\n(1)', bold: true),
                        tCell('વિદ્યાર્થીનું નામ\n(2)', bold: true),
                        for (final sub in chunk) ...[
                          vHeader('$sub - રચનાત્મક (40)'),
                          vHeader('$sub - સત્રાંત (40)'),
                          vHeader('$sub - સ્વ-અધ્યયન (20)'),
                          vHeader('$sub - કુલ ગુણ 100 માંથી'),
                          vHeader('$sub - ગ્રેડ'),
                        ],
                      ],
                    ),
                    for (final st in batchStudents)
                      pw.TableRow(
                        children: [
                          tCell(st.roll, bold: true),
                          tCell(st.name,
                              bold: true, align: pw.Alignment.centerLeft),
                          for (final sub in chunk)
                            ...() {
                              final m = st.sem1[sub] ?? const SubjectMarks();
                              return [
                                tCell('${m.patrakA}'),
                                tCell(m.satrantAbsent ? 'AB' : '${m.satrant}'),
                                tCell('${m.swaAdhyayan}'),
                                tCell('${m.total}', bold: true),
                                tCell(_gradeFor(m.total.toDouble()),
                                    bold: true),
                              ];
                            }(),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
        }

        if (includeTail) {
          doc.addPage(
            pw.MultiPage(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(8),
              build: (ctx) => [
                pw.Table(
                  border: pw.TableBorder.all(width: 0.6),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        tCell('ક્રમ\n(1)', bold: true),
                        tCell('વિદ્યાર્થીનું નામ\n(2)', bold: true),
                        vHeader('પત્રક-B વ્યક્તિત્વ વિકાસ ($vvMax ગુણ)'),
                        vHeader('ગ્રેડ'),
                        vHeader('તમામ વિષયોના + પત્રક-B કુલ ($grandMax)'),
                        vHeader('સરેરાશ ગ્રેડ'),
                        vHeader('સરેરાશ ગુણ ટકામાં'),
                        if (_showParinamInReportCard) vHeader('પરિણામ'),
                        vHeader('વિદ્યાર્થી U.I.D. નંબર'),
                        vHeader('વિદ્યાર્થી PEN નંબર'),
                      ],
                    ),
                    for (final st in batchStudents)
                      () {
                        int subSum = 0;
                        for (final s in reportSubjects) {
                          subSum += (st.sem1[s]?.total ?? 0).toInt();
                        }
                        final dispVv = st.vv1;
                        final grandObt = subSum + dispVv;
                        final vvGrade = _gradeFor((dispVv / vvMax) * 100);
                        final pct =
                            grandMax > 0 ? (grandObt / grandMax) * 100 : 0.0;
                        final ovGrade = _gradeFor(pct);
                        return pw.TableRow(
                          children: [
                            tCell(st.roll, bold: true),
                            tCell(st.name,
                                bold: true, align: pw.Alignment.centerLeft),
                            tCell('$dispVv', bold: true),
                            tCell(vvGrade, bold: true),
                            tCell('$grandObt', bold: true),
                            tCell(ovGrade, bold: true),
                            tCell(pct.toStringAsFixed(2), bold: true),
                            if (_showParinamInReportCard)
                              tCell(
                                _evaluatePassFailForStudent(st, isSem1: true),
                                bold: true,
                              ),
                            tCell(st.uid),
                            tCell(st.pen),
                          ],
                        );
                      }(),
                  ],
                ),
              ],
            ),
          );
        }
      } else {
        for (int startSub = 0;
            startSub < reportSubjects.length;
            startSub += 2) {
          final chunk = reportSubjects.skip(startSub).take(2).toList();
          final includeBioCols = startSub == 0;
          doc.addPage(
            pw.MultiPage(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(6),
              build: (ctx) => [
                pw.Table(
                  border: pw.TableBorder.all(width: 0.55),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        tCell('ક્રમ', bold: true, size: 6.5),
                        tCell('વિદ્યાર્થીનું નામ', bold: true, size: 7),
                        if (includeBioCols) ...[
                          tCell('કેટેગરી', bold: true, size: 6.5),
                          if (_isSubjectTeacherOnly)
                            tCell('જાતિ', bold: true, size: 6.5),
                          tCell('GR નં.', bold: true, size: 6.5),
                          tCell('જન્મ તારીખ', bold: true, size: 6.5),
                          vHeader('હાજર દિવસો', height: 85, size: 6.2),
                        ],
                        for (final sub in chunk) ...[
                          vHeader('$sub પ્રથમ સત્ર રચનાત્મક (40)',
                              height: 85, size: 6.2),
                          vHeader('$sub પ્રથમ સત્ર સત્રાંત (40)',
                              height: 85, size: 6.2),
                          vHeader('$sub પ્રથમ સત્ર સ્વ-અધ્યયન (20)',
                              height: 85, size: 6.2),
                          vHeader('$sub દ્વિતિય સત્ર રચનાત્મક (40)',
                              height: 85, size: 6.2),
                          vHeader('$sub દ્વિતિય સત્ર સત્રાંત (40)',
                              height: 85, size: 6.2),
                          vHeader('$sub દ્વિતિય સત્ર સ્વ-અધ્યયન (20)',
                              height: 85, size: 6.2),
                          vHeader('$sub કુલ ગુણ 200 માંથી',
                              height: 85, size: 6.2),
                          vHeader('$sub ગ્રેડ', height: 85, size: 6.2),
                        ],
                      ],
                    ),
                    for (final st in batchStudents)
                      pw.TableRow(
                        children: [
                          tCell(st.roll, bold: true, size: 7),
                          tCell(st.name,
                              bold: true,
                              size: 7,
                              align: pw.Alignment.centerLeft),
                          if (includeBioCols) ...[
                            tCell(st.category, size: 6.5),
                            if (_isSubjectTeacherOnly)
                              tCell(st.caste, size: 6.5),
                            tCell(st.gr, size: 6.5),
                            tCell(_formatDob2Digits(st), size: 6.5),
                            tCell(
                                _resolvePresentDaysTextForPrint(st, isSem1: false),
                                size: 6.5),
                          ],
                          for (final sub in chunk)
                            ...() {
                              final m1 = st.sem1[sub] ?? const SubjectMarks();
                              if (!st.studiedInSem2) {
                                return [
                                  if (m1.usesDirectTotal) ...[
                                    tCell('', size: 7),
                                    tCell('${m1.total}', bold: true, size: 7),
                                    tCell('', size: 7),
                                  ] else ...[
                                    tCell('${m1.patrakA}', size: 7),
                                    tCell(m1.satrantAbsent ? 'AB' : '${m1.satrant}', size: 7),
                                    tCell('${m1.swaAdhyayan}', size: 7),
                                  ],
                                  tCell('નામ', bold: true, size: 6.5),
                                  tCell('કમી', bold: true, size: 6.5),
                                  tCell('-', bold: true, size: 6.5),
                                  tCell('${m1.total}', bold: true, size: 7),
                                  tCell('નામ કમી', bold: true, size: 6),
                                ];
                              }
                              final m2 = st.sem2[sub] ?? const SubjectMarks();
                              final isSem2Only =
                                  _sem2OnlySubjects.contains(sub);
                              final subMax = isSem2Only
                                  ? _maxSubSemTotal
                                  : (_classHasSem1Marks(sub)
                                          ? _sem1MaximumForSubject(st, sub)
                                          : 0) +
                                      _maxSubSemTotal;
                              final tot =
                                  isSem2Only ? m2.total : (m1.total + m2.total);
                              return [
                                if (isSem2Only || !m1.usesDirectTotal) ...[
                                  tCell('${m1.patrakA}', size: 7),
                                  tCell(m1.satrantAbsent ? 'AB' : '${m1.satrant}', size: 7),
                                  tCell('${m1.swaAdhyayan}', size: 7),
                                ] else ...[
                                  tCell('', size: 7),
                                  tCell('${m1.total}', bold: true, size: 7),
                                  tCell('', size: 7),
                                ],
                                tCell('${m2.patrakA}', size: 7),
                                tCell(m2.satrantAbsent ? 'AB' : '${m2.satrant}', size: 7),
                                tCell('${m2.swaAdhyayan}', size: 7),
                                tCell('$tot', bold: true, size: 7),
                                tCell(_gradeFor((tot / subMax) * 100),
                                    bold: true, size: 7),
                              ];
                            }(),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
        }

        if (includeTail) {
          doc.addPage(
            pw.MultiPage(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(6),
              build: (ctx) => [
                pw.Table(
                  border: pw.TableBorder.all(width: 0.6),
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        tCell('ક્રમ\n(1)', bold: true),
                        tCell('વિદ્યાર્થીનું નામ\n(2)', bold: true),
                        vHeader('પત્રક-B વ્યક્તિત્વ વિકાસ ($vvMax ગુણ)'),
                        vHeader('ગ્રેડ'),
                        vHeader('તમામ વિષયોના + પત્રક-B કુલ ($grandMax)'),
                        vHeader('સરેરાશ ગ્રેડ'),
                        vHeader('સરેરાશ ગુણ'),
                        if (_showParinamInReportCard) vHeader('પરિણામ'),
                        vHeader('વિદ્યાર્થીનો U.I.D. નંબર'),
                        vHeader('વિદ્યાર્થીનો PEN નંબર'),
                      ],
                    ),
                    for (final st in batchStudents)
                      () {
                        int subSum = 0;
                        for (final s in reportSubjects) {
                          subSum += (st.sem1[s]?.total ?? 0).toInt() +
                              (st.studiedInSem2
                                  ? (st.sem2[s]?.total ?? 0).toInt()
                                  : 0);
                        }
                        if (!st.studiedInSem2) {
                          return pw.TableRow(
                            children: [
                              tCell(st.roll, bold: true),
                              tCell(st.name,
                                  bold: true, align: pw.Alignment.centerLeft),
                              tCell('${st.vv1}', bold: true),
                              tCell('નામ કમી', bold: true),
                              tCell('-', bold: true),
                              tCell('નામ કમી', bold: true),
                              tCell('', bold: true),
                              if (_showParinamInReportCard)
                                tCell('નામ કમી', bold: true),
                              tCell(st.uid),
                              tCell(st.pen),
                            ],
                          );
                        }
                        final vvAvg = st.vvAvgBothSem;
                        final grandObt = subSum + vvAvg;
                        final vvGrade = _gradeFor((vvAvg / vvMax) * 100);
                        final pct =
                            grandMax > 0 ? (grandObt / grandMax) * 100 : 0.0;
                        final ovGrade = _gradeFor(pct);
                        final passFail =
                            _evaluatePassFailForStudent(st, isSem1: false);
                        return pw.TableRow(
                          children: [
                            tCell(st.roll, bold: true),
                            tCell(st.name,
                                bold: true, align: pw.Alignment.centerLeft),
                            tCell('$vvAvg', bold: true),
                            tCell(vvGrade, bold: true),
                            tCell('$grandObt', bold: true),
                            tCell(ovGrade, bold: true),
                            tCell(pct.toStringAsFixed(2), bold: true),
                            if (_showParinamInReportCard)
                              tCell(passFail, bold: true),
                            tCell(st.uid),
                            tCell(st.pen),
                          ],
                        );
                      }(),
                  ],
                ),
              ],
            ),
          );
        }
      }
    }

    await Printing.layoutPdf(
      name: '$cleanClass $_semTag RESULT.pdf',
      format: pageFormat,
      onLayout: (_) async => doc.save(),
    );
  }

  // ===========================================================================
  // PDF 3: VYAKTITV VIKAS.pdf (Legal Page Landscape for Both Semesters)
  // ===========================================================================
  Future<void> _generateVyaktitvaVikasPdf() async {
    if (_students.isEmpty) return;

    String selectedScope = 'both';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            '📄 વ્યક્તિત્વ વિકાસ પ્રિન્ટ (ટેમ્પ્લેટ)',
            style: guFont(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'વ્યક્તિત્વ વિકાસ પત્રક ટેમ્પ્લેટ મુજબ આખા પેજમાં પ્રિન્ટ થશે (પ્રથમ સત્ર A4, દ્વિતીય સત્ર Legal). Font size અને row height ઉપરના settings મુજબ લાગુ થશે. કયા સત્રનું પત્રક પ્રિન્ટ કરવું છે?',
                  style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: 'both',
                  groupValue: selectedScope,
                  title: Text(
                    '🌟 બંને સત્ર સાથે (પ્રથમ સત્ર અને દ્વિતીય સત્ર)',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  onChanged: (v) => setDialogState(() => selectedScope = v ?? 'both'),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: 'sem1',
                  groupValue: selectedScope,
                  title: Text(
                    '૧. ફક્ત પ્રથમ સત્ર (First Semester — A4)',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onChanged: (v) => setDialogState(() => selectedScope = v ?? 'sem1'),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: 'sem2',
                  groupValue: selectedScope,
                  title: Text(
                    '૨. ફક્ત દ્વિતીય સત્ર (Second Semester — Legal)',
                    style: guFont(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onChanged: (v) => setDialogState(() => selectedScope = v ?? 'sem2'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('રદ કરો', style: guFont(fontWeight: FontWeight.w700)),
            ),
            AppButton(
              label: '🖨️ પ્રિન્ટ કરો',
              background: AppColors.greenDeep,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_resultExporting) return;
    setState(() => _resultExporting = true);
    try {
      final jobs = <PrintJob>[];
      for (final sem in [
        if (selectedScope != 'sem2') true,
        if (selectedScope != 'sem1') false,
      ]) {
        final bytes = await _buildVyaktitvaVikasTemplateWorkbook(sem1: sem);
        jobs.add(TemplatePrintPlans.result(
          workbookBytes: bytes,
          view: 'vv',
          rowHeightPx: _resultPdfRowHeight,
          fontPt: _resultPdfFontSize,
          title: '${_cleanClassCode}_${sem ? 'SEM1' : 'SEM2'}_VYAKTITV_VIKAS',
        ));
      }
      if (!mounted) return;
      await TemplatePrintService.printJobs(context, jobs);
    } catch (error) {
      if (mounted) {
        showSnack(context, 'વ્યક્તિત્વ વિકાસ પ્રિન્ટ તૈયાર થઈ શકી નથી: $error',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _resultExporting = false);
    }
  }

  /// Vyaktitva Vikas in the official Excel template (one file per semester).
  Future<void> _downloadVyaktitvaVikasExcel() async {
    if (_students.isEmpty || _resultExporting) return;
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('📊 વ્યક્તિત્વ વિકાસ Excel',
            style: guFont(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'sem1'),
            child: Text('૧. પ્રથમ સત્ર', style: guFont(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'sem2'),
            child: Text('૨. દ્વિતીય સત્ર', style: guFont(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    setState(() => _resultExporting = true);
    try {
      final sem1 = scope == 'sem1';
      final bytes = await _buildVyaktitvaVikasTemplateWorkbook(sem1: sem1);
      final filename =
          '${_cleanClassCode}_${sem1 ? 'SEM1' : 'SEM2'}_VYAKTITV_VIKAS.xlsx'.replaceAll(RegExp(r'[\\/:*?"<>| ]+'), '_');
      const mime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      if (kIsWeb) {
        final blob = html.Blob(<Object>[bytes], mime);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        await SharePlus.instance.share(ShareParams(
          files: <XFile>[XFile.fromData(bytes, name: filename, mimeType: mime)],
          subject: filename,
        ));
      }
      if (mounted) showSnack(context, '✅ Excel ફાઇલ તૈયાર છે: $filename');
    } catch (error) {
      if (mounted) showSnack(context, 'Excel export થઈ શક્યો નથી: $error', error: true);
    } finally {
      if (mounted) setState(() => _resultExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allowed = state.allowedClasses;

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else if (_activeTab != 0) {
            setState(() {
              _activeTab = 0;
              _gridTick++;
            });
          } else {
            state.setActiveModule('menu');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'પાછા જાઓ / Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                state.setActiveModule('menu');
              }
            },
          ),
          title: Text(
            '$_schoolDisplayName - પરિણામ પત્રક',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: guFont(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.navy),
          ),
          actions: const [],
        ),
        body: Stack(
          children: [
            Positioned.fill(
                child: DecoratedBox(decoration: AppTheme.backgroundGradient)),
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSchoolNameLanguagePanel(),
                              const SizedBox(height: 12),
                              CardTitleRow(
                                emoji: '📊',
                                title:
                                    '$_cleanClassCode $_semTag - પરિણામ પત્રક',
                              ),
                              const SizedBox(height: 10),
                              _buildSemesterRosterSelector(state),
                              const SizedBox(height: 10),
                              _buildTopModeTabs(),
                              if (_isCurrentSemLocked && !state.isAdmin) ...[
                                const SizedBox(height: 10),
                                const AlertBox(
                                    kind: AlertKind.lock,
                                    text:
                                        '🔒 આ સત્રનું પરિણામ લોક કરેલ છે. તમે પ્રિન્ટ કાઢી શકો છો, પણ માર્ક્સ સેવ કરી શકશો નહિ.'),
                              ],
                              const SizedBox(height: 14),
                              const SizedBox(height: 14),
                              if (_activeTab != 4)
                                _buildSelectors(allowed, state),
                              if (_activeTab == 0 &&
                                  _isRegularSubjectSelected) ...[
                                const SizedBox(height: 8),
                                _buildSubjectPermissionBanner(state),
                              ],
                              if (_activeTab == 0 &&
                                  _isRegularSubjectSelected &&
                                  (_selectedSem != 'Annual' ||
                                      _isBothSemCombo)) ...[
                                const SizedBox(height: 10),
                                _buildCombinationChipsBar(),
                                const SizedBox(height: 8),
                                _buildSatrantExamDateBar(),
                              ],
                              if (_activeTab == 0 &&
                                  _selectedSubject == kSubjectVV) ...[
                                const SizedBox(height: 10),
                                InfoBanner(
                                  title:
                                      '🧑‍🏫 $_cleanClassCode $_semTag વર્ગશિક્ષકનું વ્યક્તિગત વિકાસ / વર્તન મૂલ્યાંકન (40 વિધાનો × $_vvMaxPerSentence ગુણ = $_vvMaxPerSemester ગુણ)',
                                  hint:
                                      'કુલ ગુણ દાખલ કરતા જ 40 વિધાનોમાં આપોઆપ રેન્ડમ ગુણ વહેંચાઈ જશે.',
                                ),
                              ],
                              if (state.isAdmin) ...[
                                const SizedBox(height: 10),
                                _buildFrontPageMetaEditor(),
                              ],
                              if (_activeTab == 0 &&
                                  _isRegularSubjectSelected) ...[
                                const SizedBox(height: 8),
                                _buildClass3And4Sem2OnlyToggle(),
                              ],
                              if (_activeTab != 3 && _activeTab != 4) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    if (_offlineDraftCount > 0)
                                      AppButton(
                                        label:
                                            '☁️ ઑફલાઇન સેવ થયેલો ડેટા મોકલો ($_offlineDraftCount)',
                                        background: AppColors.rose,
                                        onPressed: (_saving || _loading)
                                            ? null
                                            : _syncOfflineDrafts,
                                      ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: AppColors.teal.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: AppColors.teal
                                                .withOpacity(0.22)),
                                      ),
                                      child: Text(
                                        '📱 ગુણ અને વિગતો પહેલા આ ઉપકરણમાં જ સેવ થાય છે. સેવ કરવા માટે નીચે આપેલ 💾 સેવ બટન દબાવો.',
                                        style: guFont(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.navy),
                                      ),
                                    ),
                                    AppButton(
                                      label: '📋 Excel માંથી પેસ્ટ',
                                      background: AppColors.teal,
                                      onPressed: (_saving ||
                                              _loading ||
                                              !_canUseResultEntry ||
                                              _selectedSubject == null)
                                          ? null
                                          : _pasteFromExcel,
                                    ),
                                    if (_activeTab == 0 &&
                                        _selectedSubject == kSubjectVV) ...[
                                      AppButton(
                                        label: '🎲 40 વિધાનોમાં ફરી વહેંચો',
                                        background: AppColors.navyMid,
                                        onPressed: (_loading ||
                                                _students.isEmpty ||
                                                !_canUseResultEntry)
                                            ? null
                                            : _reshuffleAll40Sentences,
                                      ),
                                    ],
                                    if (_activeTab == 0 && state.isAdmin)
                                      AppButton(
                                        label: '✏️ 40 વિધાનો બદલો (Edit 40 Sentences)',
                                        background: AppColors.navy,
                                        onPressed: _loading
                                            ? null
                                            : _openEdit40SentencesDialog,
                                      ),
                                    if (!_isSubjectTeacherOnly)
                                      AppButton(
                                        label:
                                            '📄 $_cleanClassCode $_semTag FRONT PAGE',
                                        background: AppColors.gold,
                                        onPressed: (_loading ||
                                                _resultExporting ||
                                                _students.isEmpty)
                                            ? null
                                            : _generateFrontPagePdf,
                                      ),
                                    AppButton(
                                      label: _isSubjectTeacherOnly
                                          ? '📄 $_cleanClassCode $_semTag SUBJECT PDF (${_selectedSubject ?? "વિષય"})'
                                          : '📄 $_cleanClassCode $_semTag RESULT',
                                      background: AppColors.rose,
                                      onPressed: (_loading ||
                                              _resultExporting ||
                                              _students.isEmpty ||
                                              (_isSubjectTeacherOnly &&
                                                  _dropdownSubjects.isEmpty))
                                          ? null
                                          : _generateRegisterSheetPdf,
                                    ),
                                    AppButton(
                                      label: _isSubjectTeacherOnly
                                          ? '📊 Subject Excel ડાઉનલોડ કરો'
                                          : '📊 Result Excel ડાઉનલોડ કરો',
                                      background: AppColors.teal,
                                      onPressed: (_loading ||
                                              _resultExporting ||
                                              _students.isEmpty ||
                                              (_isSubjectTeacherOnly &&
                                                  _dropdownSubjects.isEmpty))
                                          ? null
                                          : _downloadResultExcel,
                                    ),
                                    if (!_isSubjectTeacherOnly) ...[
                                      AppButton(
                                        label:
                                            '📄 $_cleanClassCode $_semTag VYAKTITV VIKAS',
                                        background: AppColors.greenDeep,
                                        onPressed: (_loading ||
                                                _students.isEmpty)
                                            ? null
                                            : _generateVyaktitvaVikasPdf,
                                      ),
                                      AppButton(
                                        label:
                                            '📊 $_cleanClassCode VYAKTITV VIKAS Excel',
                                        background: AppColors.teal,
                                        onPressed: (_loading ||
                                                _resultExporting ||
                                                _students.isEmpty)
                                            ? null
                                            : _downloadVyaktitvaVikasExcel,
                                      ),
                                      AppButton(
                                        label:
                                            '🎓 વિદ્યાર્થી પરિણામ પત્રક PDF (With Marks / Only Grade)',
                                        background: AppColors.navyMid,
                                        onPressed: (_loading ||
                                                _students.isEmpty)
                                            ? null
                                            : _promptAndGenerateStudentReportCards,
                                      ),
                                    ],
                                    AppButton(
                                      label: '🔄 Reload',
                                      background: AppColors.slate,
                                      onPressed: _loading ? null : _loadData,
                                    ),
                                  ],
                                ),
                                if (_activeTab == 0) ...[
                                  const SizedBox(height: 10),
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            '🖨️ Result PDF Print Setup',
                                            style: guFont(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.navy,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'આ options માત્ર Result/V.V. PDF માટે છે. મોટા font અથવા row height માટે વધુ vertical pages બનશે. Excelમાં તમામ official columns અને મૂળ template formatting યથાવત્ રહેશે.',
                                            style: guFont(fontSize: 11.5),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Row height / વિદ્યાર્થીની લાઇન ઊંચાઈ',
                                                  style: guFont(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                              ),
                                              Text('$_resultPdfRowHeight px',
                                                  style: guFont(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ],
                                          ),
                                          Slider(
                                            value:
                                                _resultPdfRowHeight.toDouble(),
                                            min: 12,
                                            max: 36,
                                            divisions: 24,
                                            label: '$_resultPdfRowHeight px',
                                            onChanged: _resultExporting
                                                ? null
                                                : (value) => setState(() =>
                                                    _resultPdfRowHeight =
                                                        value.round()),
                                            onChangeEnd: (_) => unawaited(
                                                _saveResultPdfSettings()),
                                          ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Font size / અક્ષરનું માપ',
                                                  style: guFont(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                              ),
                                              Text('$_resultPdfFontSize pt',
                                                  style: guFont(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ],
                                          ),
                                          Slider(
                                            value:
                                                _resultPdfFontSize.toDouble(),
                                            min: 4,
                                            max: 12,
                                            divisions: 8,
                                            label: '$_resultPdfFontSize pt',
                                            onChanged: _resultExporting
                                                ? null
                                                : (value) => setState(() =>
                                                    _resultPdfFontSize =
                                                        value.round()),
                                            onChangeEnd: (_) => unawaited(
                                                _saveResultPdfSettings()),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              if (_alert != null) ...[
                                const SizedBox(height: 10),
                                AlertBox(
                                  kind: _alertIsError
                                      ? AlertKind.error
                                      : AlertKind.success,
                                  text: _alert!,
                                ),
                              ],
                              const SizedBox(height: 14),
                              if (_loading)
                                const LoadingState()
                              else if (_activeTab == 4)
                                _buildGradeSettingsTab()
                              else if (_activeTab == 3)
                                _buildNewStudentStepperForm()
                              else if (_activeTab != 4 &&
                                  !_hasCurrentRosterSnapshot)
                                const MessageState(
                                  text:
                                      'આ સત્ર માટે પરિણામ એન્ટ્રી શરૂ કરવા પહેલાં ઉપરથી હાજરી રજીસ્ટરની તારીખ પસંદ કરી વિદ્યાર્થી ડેટા મેળવો. પાસવર્ડ ચકાસ્યા પછી snapshot સક્રિય થશે.',
                                )
                              else if (_students.isEmpty)
                                const MessageState(
                                  text:
                                      'આ રજીસ્ટર snapshot માં કોઈ વિદ્યાર્થી નથી. બીજી સાચવેલી student-wise attendance તારીખ પસંદ કરો.',
                                )
                              else if (_activeTab == 0)
                                _buildFocusedMarksEntryList()
                              else if (_activeTab == 1)
                                _buildFocusedDetailSelectionList()
                              else
                                _buildFullInlineMasterTableWithStickyName(),
                              if (!_loading &&
                                  _activeTab != 4 &&
                                  (_activeTab == 3 ||
                                      _students.isNotEmpty)) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: AppButton(
                                    label: _saving
                                        ? 'સેવ થાય છે…'
                                        : (_activeTab == 3
                                            ? '💾 નવો વિદ્યાર્થી વર્ગ શીટમાં છેલ્લે સેવ કરો ($_cleanClassCode)'
                                            : '💾 સેવ કરો (Save - $_cleanClassCode)'),
                                    loading: _saving,
                                    background: AppColors.greenDeep,
                                    onPressed: (_saving ||
                                            _loading ||
                                            (_isCurrentSemLocked &&
                                                !state.isAdmin) ||
                                            !_canUseResultEntry ||
                                            _selectedSubject == null)
                                        ? null
                                        : _saveCurrentData,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopModeTabs() {
    // This screen is for Result Marks Entry only. Student corrections/additions
    // are performed in the Student Database and then loaded through the roster.
    final tabs = <(int, String)>[
      (0, '📝 ગુણ એન્ટ્રી'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: AppColors.slateLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final tab in tabs)
          ChoiceChip(
            label: Text(tab.$2,
                style: guFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color:
                        _activeTab == tab.$1 ? Colors.white : AppColors.navy)),
            selected: _activeTab == tab.$1,
            selectedColor: AppColors.navy,
            backgroundColor: Colors.white,
            onSelected: !_canUseResultEntry
                ? null
                : (selected) {
                    if (!selected) return;
                    setState(() {
                      _activeTab = 0;
                      _gridTick++;
                    });
                  },
          ),
      ]),
    );
  }

  void _scheduleClassSelectionCorrection(
    String? correctedClass,
    AppState state,
  ) {
    if (_classSelectionCorrectionPending) return;
    _classSelectionCorrectionPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _classSelectionCorrectionPending = false;
      if (!mounted || correctedClass == _selectedClass) return;
      setState(() {
        _selectedClass = correctedClass;
        _examEntryFrom80 = _isStd6To8;
        _students = <ResultStudentRow>[];
        _modifiedStudents.clear();
        _rosterSnapshotStatus = <int, Map<String, dynamic>>{};
        _rosterStatusError = null;
        _rosterStatusLoading = true;
        _gridTick++;
      });
      if (correctedClass != null && correctedClass.isNotEmpty) {
        await state.setLastSelectedClass(correctedClass);
        await _loadData();
      }
    });
  }

  Widget _buildSelectors(List<SchoolClass> allowed, AppState state) {
    // Defensively deduplicate class keys at the point of rendering too. This
    // protects the teacher login when old/duplicate class rows exist remotely.
    final seenClassKeys = <String>{};
    final classOptions = allowed.where((schoolClass) {
      final key = schoolClass.key.trim();
      return key.isNotEmpty && seenClassKeys.add(key.toLowerCase());
    }).toList(growable: false);
    final validClassValue = classOptions.any((c) => c.key == _selectedClass)
        ? _selectedClass
        : (classOptions.isEmpty ? null : classOptions.first.key);
    if (validClassValue != _selectedClass) {
      _scheduleClassSelectionCorrection(validClassValue, state);
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 190,
          child: LabeledField(
            label: '🏫 Class (ધોરણ)',
            child: DropdownButtonFormField<String>(
              value: validClassValue,
              isExpanded: true,
              items: classOptions
                  .map((c) => DropdownMenuItem(
                        value: c.key,
                        child: Text(c.displayLabel,
                            style: guFont(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedClass = v;
                  _examEntryFrom80 = _isStd6To8;
                  // Start each class with all three subject mark components visible (or both sem in Annual).
                  _entryCombo =
                      _selectedSem == 'Annual' ? 'both_sem_all_6' : 'all_3';
                  _sem1DirectOutOf100 = false;
                  _rosterSnapshotStatus = {};
                  _rosterStatusError = null;
                  _rosterStatusLoading = true;
                  _studentDataWriteAuthorizationExpiresAt = null;
                  _studentDataWriteAuthorizationClass = null;
                });
                state.setLastSelectedClass(v);
                unawaited(_loadRosterSnapshotStatus());
                _loadData();
              },
            ),
          ),
        ),
        SizedBox(
          width: 195,
          child: LabeledField(
            label: '📅 Semester (સત્ર)',
            child: DropdownButtonFormField<String>(
              value: _selectedSem,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: '1',
                  child: Text('FIRST SEM (પ્રથમ સત્ર)',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                DropdownMenuItem(
                  value: '2',
                  child: Text('SECOND SEM (દ્વિતિય સત્ર)',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                DropdownMenuItem(
                  value: 'Annual',
                  child: Text('Annual (વાર્ષિક 200)',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                if (_modifiedStudents.isNotEmpty) {
                  showSnack(
                      context, 'પહેલાં હાલના ફેરફારો સેવ કરો; પછી સત્ર બદલો.',
                      error: true);
                  return;
                }
                setState(() {
                  _selectedSem = v;
                  // Selecting Annual automatically opens both-semester single-window entry.
                  _entryCombo = v == 'Annual' ? 'both_sem_all_6' : 'all_3';
                  _sem1DirectOutOf100 = false;
                  _activeRosterSemester = v == '1' ? 1 : 2;
                  _gridTick++;
                });
                state.setLastSemester(v);
                _loadData();
              },
            ),
          ),
        ),
        if (_activeTab == 0 &&
            _dropdownSubjects.isNotEmpty &&
            _selectedSubject != kSubjectVV)
          SizedBox(
            width: 260,
            child: LabeledField(
              label: '📚 ફાળવેલ વિષય',
              child: DropdownButtonFormField<String>(
                value: _dropdownSubjects.contains(_selectedSubject)
                    ? _selectedSubject
                    : _dropdownSubjects.first,
                isExpanded: true,
                items: _dropdownSubjects
                    .map((subjectName) => DropdownMenuItem<String>(
                          value: subjectName,
                          child: Text(subjectName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: guFont(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedSubject = value;
                    // Keep both-semester mode when in Annual or Both-Sem combo.
                    _entryCombo = (_selectedSem == 'Annual' ||
                            _entryCombo == 'both_sem_all_6')
                        ? 'both_sem_all_6'
                        : 'all_3';
                    _sem1DirectOutOf100 = false;
                    _gridTick++;
                  });
                  state.setLastSubject(value);
                  unawaited(_resolveAndVerifySubjectExamDate(
                    subject: value,
                    promptIfMissing: true,
                  ));
                },
              ),
            ),
          ),
        if (_activeTab == 0 && (_isClassTeacher || state.isAdmin))
          SizedBox(
            width: 300,
            child: LabeledField(
              label: '🧑‍🏫 વર્ગશિક્ષક મૂલ્યાંકન',
              child: OutlinedButton.icon(
                icon: Icon(_selectedSubject == kSubjectVV
                    ? Icons.arrow_back
                    : Icons.fact_check_outlined),
                onPressed: () {
                  setState(() {
                    _selectedSubject = _selectedSubject == kSubjectVV
                        ? (_dropdownSubjects.isNotEmpty
                            ? _dropdownSubjects.first
                            : null)
                        : kSubjectVV;
                    _gridTick++;
                  });
                  state.setLastSubject(_selectedSubject ?? '');
                },
                label: Text(_selectedSubject == kSubjectVV
                    ? 'ગુણ એન્ટ્રી પર પાછા જાઓ'
                    : 'વ્યક્તિગત વિકાસ / વર્તન મૂલ્યાંકન'),
              ),
            ),
          ),
        if (_activeTab == 0 && !_isClassTeacher && _dropdownSubjects.isEmpty)
          SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                  'આ વર્ગમાં તમને કોઈ વિષય ફાળવાયો નથી. School Admin પાસે teacher subject assignment કરાવો.',
                  style: guFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.rose)),
            ),
          ),
        if (_activeTab == 0 && _isRegularSubjectSelected)
          SizedBox(
            width: 280,
            child: LabeledField(
              label: '🎯 એન્ટ્રી વિકલ્પ (Only Each / Combination)',
              child: DropdownButtonFormField<String>(
                value: _entryCombo,
                isExpanded: true,
                items: kEntryCombinations.entries
                    .where((e) =>
                        e.key != 'both_sem_all_6' ||
                        _selectedSem == '2' ||
                        _selectedSem == 'Annual')
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: guFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyMid),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  if (v == 'both_sem_all_6' &&
                      _selectedSem != '2' &&
                      _selectedSem != 'Annual') return;
                  setState(() {
                    _entryCombo = v;
                    _gridTick++;
                  });
                },
              ),
            ),
          ),
        if (_activeTab == 1)
          SizedBox(
            width: 340,
            child: LabeledField(
              label:
                  '🎯 કઈ વિગત ઉમેરવી/સુધારવી છે? (માત્ર નામ + પસંદ કરેલ વિગત જ દેખાશે)',
              child: DropdownButtonFormField<String>(
                value: _selectedDetailField,
                isExpanded: true,
                items: kDetailFieldModes.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: guFont(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.teal),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedDetailField = v;
                    _gridTick++;
                  });
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFocusedMarksEntryList() {
    final sub = _selectedSubject ?? '';
    final isVV = sub == kSubjectVV;
    final satrantMaxInput = _examEntryFrom80 ? 80 : _maxSatrant;
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Narrow screens use student cards with the mark fields below the name,
    // instead of forcing teachers to pan a very wide spreadsheet horizontally.
    if (screenWidth < 620) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _students.length; i++)
            _buildMobileFocusedMarksStudentCard(
                i, _students[i], sub, isVV, satrantMaxInput),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: screenWidth - 48),
        child: Container(
          key: ValueKey(
              'focused-marks-$_selectedClass-$_selectedSem-$sub-$_entryCombo-$_examEntryFrom80-$_gridTick'),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                color: AppColors.navy,
                child: Row(
                  children: [
                    SizedBox(
                        width: 38,
                        child: Text('ક્રમ',
                            style: guFont(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white))),
                    SizedBox(
                        width: 150,
                        child: Text('વિદ્યાર્થીનું નામ (Col B)',
                            style: guFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white))),
                    if (!isVV && (_showS || _isBothSemCombo))
                      SizedBox(
                        width: _isBothSemCombo ? 132 : 92,
                        child: Text(
                          'સત્રાંત હાજરી\n(Present/AB)',
                          textAlign: TextAlign.center,
                          style: guFont(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.goldLight,
                          ),
                        ),
                      ),
                    if (isVV) ...[
                      if (_selectedSem != '1')
                        SizedBox(
                          width: 120,
                          child: Text(
                            'સત્ર-૧ ગુણ\n($_vvMaxPerSemester)',
                            textAlign: TextAlign.center,
                            style: guFont(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.goldLight),
                          ),
                        ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          _selectedSem == '1'
                              ? 'સત્ર-૧ ગુણ\n($_vvMaxPerSemester)'
                              : 'સત્ર-૨ ગુણ\n($_vvMaxPerSemester)',
                          textAlign: TextAlign.center,
                          style: guFont(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
                      if (_selectedSem != '1')
                        SizedBox(
                            width: 85,
                            child: Text('બંને સત્રની\nસરેરાશ ($_vvMaxPerSemester)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))),
                    ] else if (_isBothSemCombo) ...[
                      if (_useSem1DirectOutOf100)
                        SizedBox(
                          width: 300,
                          child: Text(
                            'પ્રથમ સત્ર • સીધા 100 માંથી',
                            textAlign: TextAlign.center,
                            style: guFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.goldLight),
                          ),
                        )
                      else ...[
                        SizedBox(
                            width: 95,
                            child: Text('પ્રથમ A (40)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))),
                        SizedBox(
                            width: 110,
                            child: Text(
                                _examEntryFrom80
                                    ? 'પ્રથમ સત્રાંત (80)\n[Sheet માં 40]'
                                    : 'પ્રથમ સત્રાંત (40)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: _examEntryFrom80
                                        ? AppColors.goldLight
                                        : Colors.white))),
                        SizedBox(
                            width: 95,
                            child: Text('પ્રથમ સ્વ-અધ્યયન (20)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))),
                      ],
                      SizedBox(
                          width: 95,
                          child: Text('બીજું A (40)',
                              textAlign: TextAlign.center,
                              style: guFont(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white))),
                      SizedBox(
                          width: 110,
                          child: Text(
                              _examEntryFrom80
                                  ? 'બીજું સત્રાંત (80)\n[Sheet માં 40]'
                                  : 'બીજું સત્રાંત (40)',
                              textAlign: TextAlign.center,
                              style: guFont(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: _examEntryFrom80
                                      ? AppColors.goldLight
                                      : Colors.white))),
                      SizedBox(
                          width: 95,
                          child: Text('બીજું સ્વ-અધ્યયન (20)',
                              textAlign: TextAlign.center,
                              style: guFont(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white))),
                      SizedBox(
                          width: 100,
                          child: Text('કુલ ગુણ / ગ્રેડ',
                              textAlign: TextAlign.center,
                              style: guFont(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.goldLight))),
                    ] else if (_selectedSem == '1' &&
                        _useSem1DirectOutOf100 &&
                        !_sem2OnlySubjects.contains(sub)) ...[
                      SizedBox(
                        width: 300,
                        child: Text('પ્રથમ સત્ર • સીધા 100 માંથી',
                            textAlign: TextAlign.center,
                            style: guFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.goldLight)),
                      ),
                      SizedBox(
                        width: 95,
                        child: Text('કુલ ગુણ / ગ્રેડ',
                            textAlign: TextAlign.center,
                            style: guFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.goldLight)),
                      ),
                    ] else ...[
                      if (_showA)
                        SizedBox(
                            width: 95,
                            child: Text('રચનાત્મક\n($_maxPatrakA)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))),
                      if (_showS)
                        SizedBox(
                          width: 110,
                          child: Text(
                            _examEntryFrom80
                                ? 'સત્રાંત (80)\n[Sheet માં 40]'
                                : 'સત્રાંત\n($_maxSatrant)',
                            textAlign: TextAlign.center,
                            style: guFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _examEntryFrom80
                                    ? AppColors.goldLight
                                    : Colors.white),
                          ),
                        ),
                      if (_showSW)
                        SizedBox(
                            width: 95,
                            child: Text('સ્વ-અધ્યયન\n($_maxSwa)',
                                textAlign: TextAlign.center,
                                style: guFont(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))),
                      SizedBox(
                          width: 95,
                          child: Text('કુલ ગુણ\n(ગ્રેડ)',
                              textAlign: TextAlign.center,
                              style: guFont(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.goldLight))),
                    ],
                  ],
                ),
              ),
              for (int i = 0; i < _students.length; i++)
                _buildFocusedMarksStudentRow(
                    i, _students[i], sub, isVV, satrantMaxInput),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileFocusedMarksStudentCard(
    int index,
    ResultStudentRow st,
    String sub,
    bool isVV,
    int satrantMaxInput,
  ) {
    final isBoth = _isBothSemCombo;
    final semMap = _selectedSem == '1' ? st.sem1 : st.sem2;
    final current = semMap[sub] ?? const SubjectMarks();
    final first = st.sem1[sub] ?? const SubjectMarks();
    final second = st.sem2[sub] ?? const SubjectMarks();
    final directSem1 = (isBoth || _selectedSem == '1') &&
        _useSem1DirectOutOf100 &&
        !_sem2OnlySubjects.contains(sub);
    final isNamKami = _selectedSem != '1' && !st.studiedInSem2;
    final semTotal = isBoth
        ? (_sem2OnlySubjects.contains(sub)
            ? second.total
            : first.total + (st.studiedInSem2 ? second.total : 0))
        : current.total;
    final combinedTotal = _selectedSem == '1'
        ? current.total
        : ((st.sem1[sub]?.total ?? 0) +
            (st.studiedInSem2 ? (st.sem2[sub]?.total ?? 0) : 0));
    final logicalMax = isBoth
        ? (_sem2OnlySubjects.contains(sub)
            ? _maxSubSemTotal
            : (directSem1 ? 100 : _sem1MaximumForSubject(st, sub)) +
                (st.studiedInSem2 ? _maxSubSemTotal : 0))
        : _logicalSubjectMax(st, sub, isSem1: _selectedSem == '1');
    final percent = logicalMax > 0
        ? (isBoth ? semTotal : combinedTotal) * 100 / logicalMax
        : 0.0;
    final canEdit =
        (!_isCurrentSemLocked || context.read<AppState>().isAdmin) &&
            _canUseResultEntry;
    final fieldWidth = ((MediaQuery.sizeOf(context).width - 68) / 2)
        .clamp(110.0, 220.0)
        .toDouble();

    Widget markField({
      required String label,
      required int initial,
      required int maximum,
      required ValueChanged<int> onChanged,
      String? helper,
      double? width,
      Key? fieldKey,
      bool enabled = true,
      bool isSatrantAbsent = false,
      VoidCallback? onTapAbsent,
    }) {
      if (isSatrantAbsent) {
        return SizedBox(
          width: width ?? fieldWidth,
          child: InkWell(
            onTap: canEdit && enabled ? onTapAbsent : null,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                helperText: 'ગેરહાજર (ગુણ ઉમેરવા ટચ કરો)',
                helperMaxLines: 1,
                isDense: true,
                filled: true,
                fillColor: AppColors.roseLight,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.rose, width: 1.5),
                ),
              ),
              child: Text(
                'AB',
                textAlign: TextAlign.center,
                style: guFont(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.rose,
                ),
              ),
            ),
          ),
        );
      }
      final over = initial > maximum;
      return SizedBox(
        width: width ?? fieldWidth,
        child: TextFormField(
          key: fieldKey,
          initialValue: initial == 0 ? '' : '$initial',
          enabled: canEdit && enabled,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            _MaxMarkInputFormatter(
              max: maximum,
              onExceeded: (attempted, maxVal) => _warnMaxMarkExceeded(
                attempted,
                maxVal,
                studentName: st.name,
              ),
            ),
          ],
          textAlign: TextAlign.center,
          style: guFont(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: over ? AppColors.rose : AppColors.navy),
          decoration: InputDecoration(
            labelText: label,
            helperText: helper ?? 'મહત્તમ $maximum',
            helperMaxLines: 1,
            isDense: true,
            filled: true,
            fillColor: over ? AppColors.roseLight : AppColors.slateLight,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value.trim()) ?? 0;
            if (parsed > maximum) {
              _warnMaxMarkExceeded(parsed, maximum, studentName: st.name);
              return;
            }
            onChanged(parsed);
          },
        ),
      );
    }

    Widget sem1Fields() {
      if (_sem2OnlySubjects.contains(sub)) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.slateLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.slate),
          ),
          child: Text('આ વિષય માત્ર બીજા સત્રમાં છે.',
              textAlign: TextAlign.center,
              style: guFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy)),
        );
      }
      if (directSem1) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            markField(
              label: 'પ્રથમ સત્ર • સીધા 100 માંથી',
              initial: first.directTotal ?? first.total,
              maximum: 100,
              width: fieldWidth * 2 + 10,
              fieldKey: ValueKey('mobile-s1-direct-${st.studentId}-$sub'),
              onChanged: (value) => setState(() {
                _markModified(index);
                st.sem1[sub] = SubjectMarks(
                    directTotal: value.clamp(0, 100).toInt(), directMode: true);
              }),
            ),
          ],
        );
      }
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          markField(
            label: 'પ્રથમ રચનાત્મક (40)',
            initial: first.patrakA,
            maximum: _maxPatrakA,
            fieldKey: ValueKey('mobile-s1-a-${st.studentId}-$sub'),
            onChanged: (value) => setState(() {
              _markModified(index);
              st.sem1[sub] =
                  first.copyWith(patrakA: value, clearDirectTotal: true);
            }),
          ),
          markField(
            label: _examEntryFrom80
                ? 'પ્રથમ સત્રાંત (80 માંથી)'
                : 'પ્રથમ સત્રાંત ($_maxSatrant)',
            initial: _examEntryFrom80 ? first.satrant * 2 : first.satrant,
            maximum: satrantMaxInput,
            helper: _examEntryFrom80 ? 'સંગ્રહ 40 માંથી થશે' : null,
            fieldKey: ValueKey(
                'mobile-s1-s-${st.studentId}-$sub-$_examEntryFrom80-${first.satrantAbsent}'),
            isSatrantAbsent: first.satrantAbsent,
            onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
              index: index,
              st: st,
              sub: sub,
              targetSem: '1',
            ),
            onChanged: (value) => setState(() {
              _markModified(index);
              final stored = _examEntryFrom80 ? (value / 2).round() : value;
              st.sem1[sub] = first.copyWith(
                  satrant: stored,
                  satrantAbsent: false,
                  clearDirectTotal: true);
            }),
          ),
          markField(
            label: 'પ્રથમ સ્વ-અધ્યયન (20)',
            initial: first.swaAdhyayan,
            maximum: _maxSwa,
            fieldKey: ValueKey('mobile-s1-sw-${st.studentId}-$sub'),
            onChanged: (value) => setState(() {
              _markModified(index);
              st.sem1[sub] =
                  first.copyWith(swaAdhyayan: value, clearDirectTotal: true);
            }),
          ),
        ],
      );
    }

    Widget sem2Fields() {
      if (!st.studiedInSem2) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.roseLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.rose),
          ),
          child: Text('સત્ર-૨: નામ કમી',
              style: guFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.rose)),
        );
      }
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          markField(
            label: 'બીજું રચનાત્મક (40)',
            initial: second.patrakA,
            maximum: _maxPatrakA,
            fieldKey: ValueKey('mobile-s2-a-${st.studentId}-$sub'),
            onChanged: (value) => setState(() {
              _markModified(index);
              st.sem2[sub] = second.copyWith(patrakA: value);
            }),
          ),
          markField(
            label: _examEntryFrom80
                ? 'બીજું સત્રાંત (80 માંથી)'
                : 'બીજું સત્રાંત ($_maxSatrant)',
            initial: _examEntryFrom80 ? second.satrant * 2 : second.satrant,
            maximum: satrantMaxInput,
            helper: _examEntryFrom80 ? 'સંગ્રહ 40 માંથી થશે' : null,
            fieldKey: ValueKey(
                'mobile-s2-s-${st.studentId}-$sub-$_examEntryFrom80-${second.satrantAbsent}'),
            isSatrantAbsent: second.satrantAbsent,
            onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
              index: index,
              st: st,
              sub: sub,
              targetSem: '2',
            ),
            onChanged: (value) => setState(() {
              _markModified(index);
              final stored = _examEntryFrom80 ? (value / 2).round() : value;
              st.sem2[sub] =
                  second.copyWith(satrant: stored, satrantAbsent: false);
            }),
          ),
          markField(
            label: 'બીજું સ્વ-અધ્યયન (20)',
            initial: second.swaAdhyayan,
            maximum: _maxSwa,
            fieldKey: ValueKey('mobile-s2-sw-${st.studentId}-$sub'),
            onChanged: (value) => setState(() {
              _markModified(index);
              st.sem2[sub] = second.copyWith(swaAdhyayan: value);
            }),
          ),
        ],
      );
    }

    return Card(
      key: ValueKey(
          'mobile-marks-${st.studentId}-$_selectedSem-$sub-$_entryCombo-$_examEntryFrom80-$_useSem1DirectOutOf100'),
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.navy,
                  child: FittedBox(
                      child: Text(st.roll,
                          style: guFont(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(st.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: guFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy)),
                ),
                if (!isVV)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            '$semTotal / ${isBoth || (_selectedSem == '1' && directSem1) ? logicalMax : _maxSubSemTotal}',
                            style: guFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppColors.greenDeep)),
                        Text(
                            _gradeFor(isBoth ||
                                    (_selectedSem == '1' && directSem1)
                                ? percent
                                : (_selectedSem == '1'
                                    ? (current.total * 100 / _maxSubSemTotal)
                                    : percent)),
                            style: guFont(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy)),
                      ],
                    ),
                  ),
              ],
            ),
            if (!isVV && (_showS || isBoth) && !isNamKami) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'સત્રાંત હાજરી:',
                    style: guFont(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyMid),
                  ),
                  if (isBoth) ...[
                    if (!_sem2OnlySubjects.contains(sub) && !directSem1)
                      _buildSatrantAttendanceBadge(
                        index: index,
                        st: st,
                        sub: sub,
                        targetSem: '1',
                        semPrefix: 'સત્ર-૧',
                      ),
                    if (st.studiedInSem2)
                      _buildSatrantAttendanceBadge(
                        index: index,
                        st: st,
                        sub: sub,
                        targetSem: '2',
                        semPrefix: 'સત્ર-૨',
                      ),
                  ] else
                    _buildSatrantAttendanceBadge(
                      index: index,
                      st: st,
                      sub: sub,
                      targetSem: _selectedSem == '1' ? '1' : '2',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (isVV)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_selectedSem != '1')
                    markField(
                      label: 'વ્યક્તિત્વ વિકાસ • સત્ર 1 ($_vvMaxPerSemester)',
                      initial: st.vv1,
                      maximum: _vvMaxPerSemester,
                      onChanged: (value) => setState(() {
                        _markModified(index);
                        _updateStudentVvTotal(st, '1', value);
                      }),
                    ),
                  markField(
                    label: _selectedSem == '1'
                        ? 'વ્યક્તિત્વ વિકાસ • સત્ર 1 ($_vvMaxPerSemester)'
                        : 'વ્યક્તિત્વ વિકાસ • સત્ર 2 ($_vvMaxPerSemester)',
                    initial: _selectedSem == '1' ? st.vv1 : st.vv2,
                    maximum: _vvMaxPerSemester,
                    onChanged: (value) => setState(() {
                      _markModified(index);
                      _updateStudentVvTotal(
                          st, _selectedSem == '1' ? '1' : '2', value);
                    }),
                  ),
                  if (_selectedSem != '1')
                    SizedBox(
                      width: fieldWidth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                            labelText: 'બંને સત્રની સરેરાશ ($_vvMaxPerSemester)',
                            isDense: true,
                            border: const OutlineInputBorder()),
                        child: Text('${st.vvAvgBothSem}',
                            style: guFont(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppColors.greenDeep)),
                      ),
                    ),
                ],
              )
            else if (isBoth) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('પ્રથમ સત્રનાં ગુણ',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
              ),
              const SizedBox(height: 6),
              sem1Fields(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('બીજા સત્રનાં ગુણ',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
              ),
              const SizedBox(height: 6),
              sem2Fields(),
            ] else if (_selectedSem == '1' && directSem1)
              sem1Fields()
            else if (isNamKami)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.roseLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.rose)),
                child: Text(
                    'નામ કમી • પ્રથમ સત્રના ગુણ: ${isVV ? st.vv1 : (st.sem1[sub]?.total ?? 0)}',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.rose)),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_showA)
                    markField(
                      label: 'રચનાત્મક (${_maxPatrakA})',
                      initial: current.patrakA,
                      maximum: _maxPatrakA,
                      onChanged: (value) => setState(() {
                        _markModified(index);
                        semMap[sub] = current.copyWith(
                            patrakA: value,
                            clearDirectTotal: _selectedSem == '1');
                      }),
                    ),
                  if (_showS)
                    markField(
                      label: _examEntryFrom80
                          ? 'સત્રાંત (80 માંથી)'
                          : 'સત્રાંત (${_maxSatrant})',
                      initial: _examEntryFrom80
                          ? current.satrant * 2
                          : current.satrant,
                      maximum: satrantMaxInput,
                      helper: _examEntryFrom80 ? 'સંગ્રહ 40 માંથી થશે' : null,
                      fieldKey: ValueKey(
                          'mobile-single-s-${st.studentId}-$sub-$_examEntryFrom80-${current.satrantAbsent}'),
                      isSatrantAbsent: current.satrantAbsent,
                      onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
                        index: index,
                        st: st,
                        sub: sub,
                        targetSem: _selectedSem == '1' ? '1' : '2',
                      ),
                      onChanged: (value) => setState(() {
                        _markModified(index);
                        final stored =
                            _examEntryFrom80 ? (value / 2).round() : value;
                        semMap[sub] = current.copyWith(
                            satrant: stored,
                            satrantAbsent: false,
                            clearDirectTotal: _selectedSem == '1');
                      }),
                    ),
                  if (_showSW)
                    markField(
                      label: 'સ્વ-અધ્યયન (${_maxSwa})',
                      initial: current.swaAdhyayan,
                      maximum: _maxSwa,
                      onChanged: (value) => setState(() {
                        _markModified(index);
                        semMap[sub] = current.copyWith(
                            swaAdhyayan: value,
                            clearDirectTotal: _selectedSem == '1');
                      }),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedMarksStudentRow(
    int index,
    ResultStudentRow st,
    String sub,
    bool isVV,
    int satrantMaxInput,
  ) {
    final bg = index.isOdd ? const Color(0xFFF8FAFC) : Colors.white;
    final isBoth = _isBothSemCombo;
    final isSem2LockedNamKami = _selectedSem != '1' && !st.studiedInSem2;
    final semMap = _selectedSem == '1' ? st.sem1 : st.sem2;
    final currentMarks = semMap[sub] ?? const SubjectMarks();
    final first = st.sem1[sub] ?? const SubjectMarks();
    final second = st.sem2[sub] ?? const SubjectMarks();
    final directSem1 = (isBoth || _selectedSem == '1') &&
        _useSem1DirectOutOf100 &&
        !_sem2OnlySubjects.contains(sub);

    final canEditLockedResult =
        !_isCurrentSemLocked || context.read<AppState>().isAdmin;
    Widget compactMarkBox({
      required int initial,
      required int max,
      required double width,
      required ValueChanged<int> onChanged,
      String? helperBadge,
      String? fieldId,
      bool enabled = true,
      bool isSatrantAbsent = false,
      VoidCallback? onTapAbsent,
    }) {
      if (isSatrantAbsent) {
        return Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: (canEditLockedResult && _canUseResultEntry && enabled)
                    ? onTapAbsent
                    : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.roseLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.rose, width: 1.5),
                  ),
                  child: Text(
                    'AB',
                    textAlign: TextAlign.center,
                    style: guFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.rose,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'ગેરહાજર (ટચ કરો)',
                  style: guFont(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.rose),
                ),
              ),
            ],
          ),
        );
      }
      final over = initial > max;
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: fieldId == null
                  ? null
                  : ValueKey('desktop-${st.studentId}-$sub-$fieldId'),
              initialValue: initial == 0 ? '' : '$initial',
              enabled: canEditLockedResult && _canUseResultEntry && enabled,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                _MaxMarkInputFormatter(
                  max: max,
                  onExceeded: (attempted, maxVal) => _warnMaxMarkExceeded(
                    attempted,
                    maxVal,
                    studentName: st.name,
                  ),
                ),
              ],
              textAlign: TextAlign.center,
              style: guFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: over ? AppColors.rose : AppColors.navy),
              decoration: InputDecoration(
                hintText: '0',
                isDense: true,
                filled: true,
                fillColor: over ? AppColors.roseLight : AppColors.slateLight,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v.trim()) ?? 0;
                if (parsed > max) {
                  _warnMaxMarkExceeded(parsed, max, studentName: st.name);
                  return;
                }
                onChanged(parsed);
              },
            ),
            if (helperBadge != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  helperBadge,
                  style: guFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teal),
                ),
              ),
          ],
        ),
      );
    }

    final semTotal = currentMarks.total;
    final combinedTotal = _sem2OnlySubjects.contains(sub)
        ? second.total
        : first.total + (st.studiedInSem2 ? second.total : 0);
    final combinedMax = _sem2OnlySubjects.contains(sub)
        ? _maxSubSemTotal
        : (directSem1 ? 100 : _sem1MaximumForSubject(st, sub)) +
            (st.studiedInSem2 ? _maxSubSemTotal : 0);
    final logicalMax = _logicalSubjectMax(st, sub, isSem1: _selectedSem == '1');
    final combTotal = _selectedSem == '1' ? semTotal : combinedTotal;
    final gradePct = (isBoth ? combinedMax : logicalMax) > 0
        ? (isBoth ? combinedTotal / combinedMax : combTotal / logicalMax) * 100
        : 0.0;

    Widget sem1NotApplicable() => Container(
          width: 300,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.slateLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.slate),
          ),
          child: Text('પ્રથમ સત્રમાં લાગુ પડતું નથી',
              style: guFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy)),
        );

    Widget sem1SplitFields() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            compactMarkBox(
              initial: first.patrakA,
              max: _maxPatrakA,
              width: 95,
              fieldId: 's1-a',
              onChanged: (v) => setState(() {
                _markModified(index);
                st.sem1[sub] =
                    first.copyWith(patrakA: v, clearDirectTotal: true);
              }),
            ),
            compactMarkBox(
              initial: _examEntryFrom80 ? first.satrant * 2 : first.satrant,
              max: satrantMaxInput,
              width: 110,
              fieldId: 's1-s-$_examEntryFrom80-${first.satrantAbsent}',
              helperBadge:
                  _examEntryFrom80 ? '40 માંથી: ${first.satrant}' : null,
              isSatrantAbsent: first.satrantAbsent,
              onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
                index: index,
                st: st,
                sub: sub,
                targetSem: '1',
              ),
              onChanged: (v) => setState(() {
                _markModified(index);
                final stored = _examEntryFrom80 ? (v / 2).round() : v;
                st.sem1[sub] = first.copyWith(
                    satrant: stored,
                    satrantAbsent: false,
                    clearDirectTotal: true);
              }),
            ),
            compactMarkBox(
              initial: first.swaAdhyayan,
              max: _maxSwa,
              width: 95,
              fieldId: 's1-sw',
              onChanged: (v) => setState(() {
                _markModified(index);
                st.sem1[sub] =
                    first.copyWith(swaAdhyayan: v, clearDirectTotal: true);
              }),
            ),
          ],
        );

    Widget sem2Fields() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            compactMarkBox(
              initial: second.patrakA,
              max: _maxPatrakA,
              width: 95,
              fieldId: 's2-a',
              onChanged: (v) => setState(() {
                _markModified(index);
                st.sem2[sub] = second.copyWith(patrakA: v);
              }),
            ),
            compactMarkBox(
              initial: _examEntryFrom80 ? second.satrant * 2 : second.satrant,
              max: satrantMaxInput,
              width: 110,
              fieldId: 's2-s-$_examEntryFrom80-${second.satrantAbsent}',
              helperBadge:
                  _examEntryFrom80 ? '40 માંથી: ${second.satrant}' : null,
              isSatrantAbsent: second.satrantAbsent,
              onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
                index: index,
                st: st,
                sub: sub,
                targetSem: '2',
              ),
              onChanged: (v) => setState(() {
                _markModified(index);
                final stored = _examEntryFrom80 ? (v / 2).round() : v;
                st.sem2[sub] =
                    second.copyWith(satrant: stored, satrantAbsent: false);
              }),
            ),
            compactMarkBox(
              initial: second.swaAdhyayan,
              max: _maxSwa,
              width: 95,
              fieldId: 's2-sw',
              onChanged: (v) => setState(() {
                _markModified(index);
                st.sem2[sub] = second.copyWith(swaAdhyayan: v);
              }),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            child: Text(st.roll,
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy)),
          ),
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                st.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    height: 1.25),
              ),
            ),
          ),
          if (!isVV && (_showS || isBoth))
            SizedBox(
              width: isBoth ? 132 : 92,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: (isSem2LockedNamKami && !isBoth)
                    ? const SizedBox.shrink()
                    : isBoth
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_sem2OnlySubjects.contains(sub) && !directSem1)
                                _buildSatrantAttendanceBadge(
                                  index: index,
                                  st: st,
                                  sub: sub,
                                  targetSem: '1',
                                  semPrefix: 'સ-૧',
                                ),
                              if (!_sem2OnlySubjects.contains(sub) &&
                                  !directSem1 &&
                                  st.studiedInSem2)
                                const SizedBox(height: 3),
                              if (st.studiedInSem2)
                                _buildSatrantAttendanceBadge(
                                  index: index,
                                  st: st,
                                  sub: sub,
                                  targetSem: '2',
                                  semPrefix: 'સ-૨',
                                ),
                            ],
                          )
                        : _buildSatrantAttendanceBadge(
                            index: index,
                            st: st,
                            sub: sub,
                            targetSem: _selectedSem == '1' ? '1' : '2',
                          ),
              ),
            ),
          if (isSem2LockedNamKami && !isBoth)
            Container(
              width: 280,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.roseLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.rose),
              ),
              child: Text(
                '🚫 નામ કમી (સત્ર-૧ ગુણ: ${isVV ? st.vv1 : first.total})',
                style: guFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.rose),
              ),
            )
          else if (isVV) ...[
            if (_selectedSem != '1')
              compactMarkBox(
                initial: st.vv1,
                max: _vvMaxPerSemester,
                width: 120,
                fieldId: 'vv1-in-sem2',
                onChanged: (v) {
                  _markModified(index);
                  _updateStudentVvTotal(st, '1', v);
                },
              ),
            compactMarkBox(
              initial: _selectedSem == '1' ? st.vv1 : st.vv2,
              max: _vvMaxPerSemester,
              width: 120,
              fieldId: 'vv',
              onChanged: (v) {
                _markModified(index);
                _updateStudentVvTotal(st, _selectedSem == '1' ? '1' : '2', v);
              },
            ),
            if (_selectedSem != '1')
              SizedBox(
                width: 85,
                child: Text(
                  '${st.vvAvgBothSem}',
                  textAlign: TextAlign.center,
                  style: guFont(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.greenDeep),
                ),
              ),
          ] else if (isBoth) ...[
            if (_sem2OnlySubjects.contains(sub))
              sem1NotApplicable()
            else if (directSem1)
              compactMarkBox(
                initial: first.directTotal ?? first.total,
                max: 100,
                width: 300,
                fieldId: 's1-direct',
                onChanged: (v) => setState(() {
                  _markModified(index);
                  st.sem1[sub] = SubjectMarks(
                      directTotal: v.clamp(0, 100).toInt(), directMode: true);
                }),
              )
            else
              sem1SplitFields(),
            if (st.studiedInSem2)
              sem2Fields()
            else
              Container(
                width: 300,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.roseLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.rose),
                ),
                child: Text('સત્ર-૨: નામ કમી',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.rose)),
              ),
            SizedBox(
              width: 100,
              child: Text(
                '$combinedTotal / $combinedMax\\n(${_gradeFor(gradePct)})',
                textAlign: TextAlign.center,
                style: guFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.greenDeep),
              ),
            ),
          ] else if (_selectedSem == '1' && directSem1) ...[
            compactMarkBox(
              initial: first.directTotal ?? first.total,
              max: 100,
              width: 300,
              fieldId: 's1-direct',
              onChanged: (v) => setState(() {
                _markModified(index);
                st.sem1[sub] = SubjectMarks(
                    directTotal: v.clamp(0, 100).toInt(), directMode: true);
              }),
            ),
            SizedBox(
              width: 95,
              child: Text(
                '${first.total} / 100\n(${_gradeFor(gradePct)})',
                textAlign: TextAlign.center,
                style: guFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.greenDeep),
              ),
            ),
          ] else ...[
            if (_showA)
              compactMarkBox(
                initial: currentMarks.patrakA,
                max: _maxPatrakA,
                width: 95,
                fieldId: 'a',
                onChanged: (v) => setState(() {
                  _markModified(index);
                  semMap[sub] = currentMarks.copyWith(
                      patrakA: v, clearDirectTotal: _selectedSem == '1');
                }),
              ),
            if (_showS)
              compactMarkBox(
                initial: _examEntryFrom80
                    ? (currentMarks.satrant * 2)
                    : currentMarks.satrant,
                max: satrantMaxInput,
                width: 110,
                fieldId: 's-$_examEntryFrom80-${currentMarks.satrantAbsent}',
                helperBadge: _examEntryFrom80
                    ? '40 માંથી: ${currentMarks.satrant}'
                    : null,
                isSatrantAbsent: currentMarks.satrantAbsent,
                onTapAbsent: () => _confirmAndUnlockAbsentStudentSatrant(
                  index: index,
                  st: st,
                  sub: sub,
                  targetSem: _selectedSem == '1' ? '1' : '2',
                ),
                onChanged: (v) => setState(() {
                  _markModified(index);
                  final storedOut40 =
                      _examEntryFrom80 ? (v / 2).round() : v;
                  semMap[sub] = currentMarks.copyWith(
                      satrant: storedOut40,
                      satrantAbsent: false,
                      clearDirectTotal: _selectedSem == '1');
                }),
              ),
            if (_showSW)
              compactMarkBox(
                initial: currentMarks.swaAdhyayan,
                max: _maxSwa,
                width: 95,
                fieldId: 'sw',
                onChanged: (v) => setState(() {
                  _markModified(index);
                  semMap[sub] = currentMarks.copyWith(
                      swaAdhyayan: v, clearDirectTotal: _selectedSem == '1');
                }),
              ),
            SizedBox(
              width: 95,
              child: Text(
                semTotal == 0 && combinedTotal == 0
                    ? '-'
                    : '$semTotal / $_maxSubSemTotal\\n(${_gradeFor(_selectedSem == "1" ? (semTotal / _maxSubSemTotal) * 100 : gradePct)})',
                textAlign: TextAlign.center,
                style: guFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.greenDeep),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: MOBILE-FRIENDLY 3-ROW NAME + HORIZONTALLY SCROLLABLE DETAIL ENTRY
  // ===========================================================================
  Widget _buildFocusedDetailSelectionList() {
    final double rightColWidth = switch (_selectedDetailField) {
      'parents' => 480.0,
      'roll_name' => 320.0,
      'dob' => 270.0,
      'delete_student' => 160.0,
      'uid_pen' => 330.0,
      'sem2_status' => 290.0,
      'present' => 230.0,
      _ => 210.0,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 48,
        ),
        child: Container(
          key: ValueKey(
              'focused-detail-$_selectedClass-$_selectedDetailField-$_gridTick'),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                color: AppColors.navy,
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Text('ક્રમ',
                          style: guFont(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    SizedBox(
                      width: 150,
                      child: Text('વિદ્યાર્થીનું નામ (Col B)',
                          style: guFont(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    SizedBox(
                      width: rightColWidth,
                      child: Text(
                        kDetailFieldModes[_selectedDetailField] ?? '',
                        textAlign: TextAlign.center,
                        style: guFont(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.goldLight),
                      ),
                    ),
                  ],
                ),
              ),
              for (int i = 0; i < _students.length; i++)
                _buildFocusedDetailStudentRow(i, _students[i], rightColWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusedDetailStudentRow(
      int index, ResultStudentRow st, double rightColWidth) {
    final bg = index.isOdd ? const Color(0xFFF8FAFC) : Colors.white;

    Widget box({
      required String initial,
      required String hint,
      required ValueChanged<String> onChanged,
      TextInputType keyboard = TextInputType.text,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: TextFormField(
          initialValue: initial,
          enabled: (!_isCurrentSemLocked || context.read<AppState>().isAdmin) &&
              _canUseResultEntry,
          keyboardType: keyboard,
          style: guFont(
              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppColors.slateLight,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onChanged: (v) {
            _markModified(index);
            onChanged(v);
          },
        ),
      );
    }

    late final Widget fieldWidget;
    switch (_selectedDetailField) {
      case 'delete_student':
        fieldWidget = Center(
          child: AppButton(
            label: '🗑️ Delete',
            background: AppColors.rose,
            onPressed: () => _confirmDeleteStudent(index, st),
          ),
        );
        break;
      case 'roll_name':
        fieldWidget = Row(
          children: [
            SizedBox(
              width: 80,
              child: box(
                initial: st.roll,
                hint: 'રોલ નં.',
                keyboard: TextInputType.number,
                onChanged: (v) => st.roll = v,
              ),
            ),
            Expanded(
              child: box(
                initial: st.name,
                hint: 'વિદ્યાર્થીનું નામ',
                onChanged: (v) => st.name = v,
              ),
            ),
          ],
        );
        break;
      case 'gr':
        fieldWidget = box(
          initial: st.gr,
          hint: 'GR નંબર દાખલ કરો',
          keyboard: TextInputType.number,
          onChanged: (v) => st.gr = v,
        );
        break;
      case 'dob':
        fieldWidget = Row(
          children: [
            Expanded(
              child: box(
                initial: st.dd,
                hint: 'DD',
                keyboard: TextInputType.number,
                onChanged: (v) => st.dd = v,
              ),
            ),
            Expanded(
              child: box(
                initial: st.mm,
                hint: 'MM',
                keyboard: TextInputType.number,
                onChanged: (v) => st.mm = v,
              ),
            ),
            Expanded(
              flex: 2,
              child: box(
                initial: st.yyyy,
                hint: 'YYYY',
                keyboard: TextInputType.number,
                onChanged: (v) => st.yyyy = v,
              ),
            ),
          ],
        );
        break;
      case 'present':
        fieldWidget = Row(
          children: [
            Expanded(
              child: box(
                initial: '${st.presentDays}',
                hint: 'સત્ર-૧ હાજર',
                keyboard: TextInputType.number,
                onChanged: (v) => st.presentDays = int.tryParse(v.trim()) ?? 0,
              ),
            ),
            Expanded(
              child: box(
                initial: '${st.presentDays2}',
                hint: 'સત્ર-૨ હાજર',
                keyboard: TextInputType.number,
                onChanged: (v) => st.presentDays2 = int.tryParse(v.trim()) ?? 0,
              ),
            ),
          ],
        );
        break;
      case 'category':
        final currentCat =
            kCategoryOptions.contains(st.category) ? st.category : 'બક્ષીપંચ';
        fieldWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: DropdownButtonFormField<String>(
            value: currentCat,
            isExpanded: true,
            items: kCategoryOptions
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c,
                          style: guFont(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null)
                setState(() {
                  _markModified(index);
                  st.category = v;
                });
            },
          ),
        );
        break;
      case 'gender':
        final currentGender =
            ['BOYS', 'GIRLS', 'UNSPECIFIED'].contains(st.gender)
                ? st.gender
                : 'UNSPECIFIED';
        fieldWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: DropdownButtonFormField<String>(
            value: currentGender,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'BOYS', child: Text('છોકરો / Boys')),
              DropdownMenuItem(value: 'GIRLS', child: Text('છોકરી / Girls')),
              DropdownMenuItem(
                  value: 'UNSPECIFIED', child: Text('નક્કી નથી / Not set')),
            ],
            onChanged: (v) {
              if (v != null)
                setState(() {
                  _markModified(index);
                  st.gender = v;
                });
            },
          ),
        );
        break;
      case 'uid_pen':
        fieldWidget = Row(
          children: [
            Expanded(
              child: box(
                initial: st.uid,
                hint: 'UID નંબર (Col G)',
                keyboard: TextInputType.number,
                onChanged: (v) => st.uid = v,
              ),
            ),
            Expanded(
              child: box(
                initial: st.pen,
                hint: 'PEN નંબર (Col H)',
                keyboard: TextInputType.number,
                onChanged: (v) => st.pen = v,
              ),
            ),
          ],
        );
        break;
      case 'parents':
        fieldWidget = Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 190,
                  child: box(
                    initial: st.mobile,
                    hint: 'મોબાઈલ નંબર (Col I)',
                    keyboard: TextInputType.phone,
                    onChanged: (v) => st.mobile = v,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: box(
                    initial: st.fatherName,
                    hint: 'પિતાનું નામ (Col J)',
                    onChanged: (v) => st.fatherName = v,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 190,
                  child: box(
                    initial: st.motherName,
                    hint: 'માતાનું નામ (Col K)',
                    onChanged: (v) => st.motherName = v,
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: box(
                    initial: st.address,
                    hint: 'સરનામું (Col L)',
                    onChanged: (v) => st.address = v,
                  ),
                ),
              ],
            ),
          ],
        );
        break;
      case 'divyang':
        fieldWidget = Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            ChoiceChip(
              label: Text('♿ YES (દિવ્યાંગ - 20% પાસિંગ)',
                  style: guFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: st.isDivyang ? Colors.white : AppColors.navy)),
              selected: st.isDivyang,
              selectedColor: AppColors.teal,
              onSelected: (_) => setState(() {
                _markModified(index);
                st.isDivyang = true;
              }),
            ),
            ChoiceChip(
              label: Text('NO (સામાન્ય - 35% પાસિંગ)',
                  style: guFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: !st.isDivyang ? Colors.white : AppColors.navy)),
              selected: !st.isDivyang,
              selectedColor: AppColors.navy,
              onSelected: (_) => setState(() {
                _markModified(index);
                st.isDivyang = false;
              }),
            ),
          ],
        );
        break;
      case 'sem2_status':
      default:
        fieldWidget = Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            ChoiceChip(
              label: Text('✅ Yes (સત્ર-૨ ચાલુ)',
                  style: guFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: st.studiedInSem2 ? Colors.white : AppColors.navy)),
              selected: st.studiedInSem2,
              selectedColor: AppColors.greenDeep,
              onSelected: (_) => setState(() {
                _markModified(index);
                st.studiedInSem2 = true;
              }),
            ),
            ChoiceChip(
              label: Text('🚫 No (નામ કમી)',
                  style: guFont(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color:
                          !st.studiedInSem2 ? Colors.white : AppColors.navy)),
              selected: !st.studiedInSem2,
              selectedColor: AppColors.rose,
              onSelected: (_) => setState(() {
                _markModified(index);
                st.studiedInSem2 = false;
              }),
            ),
          ],
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            child: Text(st.roll,
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy)),
          ),
          // 3-Line Mobile-Friendly Student Name Box
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                st.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: guFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    height: 1.25),
              ),
            ),
          ),
          SizedBox(
            width: rightColWidth,
            child: fieldWidget,
          ),
        ],
      ),
    );
  }

  /// Tab 2: સંપૂર્ણ વિગત (એક લાઈનમાં Col A થી Col R)
  /// Fully scrollable left-to-right on mobile with 3-line student name support!
  Future<void> _confirmDeleteStudent(int index, ResultStudentRow st) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('⚠️ વિદ્યાર્થી કાઢી નાખો',
            style: guFont(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.rose)),
        content: Text(
          'શું તમે ખરેખર "${st.name}" નો તમામ ડેટા (બંને સત્રના ગુણ અને વિગતો) કાઢી નાખવા માંગો છો?\n\nઆ ક્રિયા પાછી નહીં ખેંચી શકાય!',
          style: guFont(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('રદ કરો', style: guFont(fontSize: 13))),
          AppButton(
              label: '🗑️ હા, કાઢી નાખો',
              background: AppColors.rose,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _saving = true;
      _alertIsError = false;
      _alert = '🗑️ વિદ્યાર્થી કાઢી નાખવામાં આવી રહ્યો છે...';
    });
    try {
      final state = context.read<AppState>();
      final res = await state.resultApi!.saveSubjectMarks(
        className: _selectedClass!,
        sem: '1',
        subject: '__DELETE_STUDENT__',
        entryCombo: 'all_3',
        payload: [
          {'idx': index}
        ],
      );

      if (!mounted) return;
      if (res['result'] == 'success') {
        await _loadData();
        setState(() {
          _saving = false;
          _alertIsError = false;
          _alert =
              '✅ વિદ્યાર્થી સફળતાપૂર્વક કાઢી નાખવામાં આવ્યો અને રોલ નંબર ગોઠવાઈ ગયા!';
        });
      } else {
        setState(() {
          _saving = false;
          _alertIsError = true;
          _alert = '❌ ${res['message']}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertIsError = true;
        _alert = '❌ Error: $e';
      });
    }
  }

  Widget _buildFullInlineMasterTableWithStickyName() {
    const double rowHeight = 68;

    Widget headerBox(String text, double width, {Color? bg}) {
      return Container(
        width: width,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        color: bg ?? AppColors.navy,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: guFont(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      );
    }

    Widget cellInput(
      String initial,
      double width,
      ValueChanged<String> onChanged, {
      String hint = '',
      int maxLines = 1,
      TextInputType keyboard = TextInputType.text,
    }) {
      return Container(
        width: width,
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        alignment: Alignment.center,
        child: TextFormField(
          initialValue: initial,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: guFont(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.2),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppColors.slateLight,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onChanged: onChanged,
        ),
      );
    }

    return Container(
      key: ValueKey('full-inline-$_selectedClass-$_gridTick'),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                headerBox('ક્રમ\n(Col A)', 58),
                headerBox('વિદ્યાર્થીનું નામ (Col B)\n(3 લાઈન)', 175),
                headerBox('કેટેગરી\n(Col C)', 125),
                headerBox('DD\n(Col D)', 66),
                headerBox('MM\n(Col E)', 66),
                headerBox('YYYY\n(Col F)', 82),
                headerBox('U.I.D. નંબર\n(Col G)', 155, bg: AppColors.teal),
                headerBox('PEN નંબર\n(Col H)', 155, bg: AppColors.greenDeep),
                headerBox('મોબાઈલ\n(Col I)', 135),
                headerBox('પિતાનું નામ\n(Col J)', 160),
                headerBox('માતાનું નામ\n(Col K)', 160),
                headerBox('સરનામું\n(Col L)', 175),
                headerBox('સત્ર-૨ ચાલુ?\n(Col M)', 130, bg: AppColors.rose),
                headerBox('GR નં.\n(Col N)', 95),
                headerBox('હાજર-૧\n(Col O)', 85),
                headerBox('હાજર-૨\n(Col P)', 85),
                headerBox('ધોરણ\n(Col Q)', 90, bg: AppColors.navyMid),
                headerBox('દિવ્યાંગ?\n(Col R)', 130, bg: AppColors.teal),
              ],
            ),
            for (int i = 0; i < _students.length; i++)
              () {
                final st = _students[i];
                return Container(
                  height: rowHeight,
                  decoration: BoxDecoration(
                    color: i.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
                    border: const Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: [
                      cellInput(st.roll, 58, (v) {
                        _markModified(i);
                        st.roll = v;
                      }, keyboard: TextInputType.number),
                      cellInput(st.name, 175, (v) {
                        _markModified(i);
                        st.name = v;
                      }, hint: 'નામ', maxLines: 3),
                      cellInput(st.category, 125, (v) {
                        _markModified(i);
                        st.category = v;
                      }),
                      cellInput(st.dd, 66, (v) {
                        _markModified(i);
                        st.dd = v;
                      }, hint: 'DD', keyboard: TextInputType.number),
                      cellInput(st.mm, 66, (v) {
                        _markModified(i);
                        st.mm = v;
                      }, hint: 'MM', keyboard: TextInputType.number),
                      cellInput(st.yyyy, 82, (v) {
                        _markModified(i);
                        st.yyyy = v;
                      }, hint: 'YYYY', keyboard: TextInputType.number),
                      cellInput(st.uid, 155, (v) {
                        _markModified(i);
                        st.uid = v;
                      }, hint: 'UID', keyboard: TextInputType.number),
                      cellInput(st.pen, 155, (v) {
                        _markModified(i);
                        st.pen = v;
                      }, hint: 'PEN', keyboard: TextInputType.number),
                      cellInput(st.mobile, 135, (v) {
                        _markModified(i);
                        st.mobile = v;
                      }, hint: 'Mobile', keyboard: TextInputType.phone),
                      cellInput(st.fatherName, 160, (v) {
                        _markModified(i);
                        st.fatherName = v;
                      }, hint: 'પિતાનું નામ', maxLines: 2),
                      cellInput(st.motherName, 160, (v) {
                        _markModified(i);
                        st.motherName = v;
                      }, hint: 'માતાનું નામ', maxLines: 2),
                      cellInput(st.address, 175, (v) {
                        _markModified(i);
                        st.address = v;
                      }, hint: 'સરનામું', maxLines: 2),
                      Container(
                        width: 130,
                        height: rowHeight,
                        alignment: Alignment.center,
                        child: SwitchListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            st.studiedInSem2 ? 'Yes' : 'નામ કમી',
                            style: guFont(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: st.studiedInSem2
                                  ? AppColors.greenDeep
                                  : AppColors.rose,
                            ),
                          ),
                          value: st.studiedInSem2,
                          onChanged: (v) => setState(() {
                            _markModified(i);
                            st.studiedInSem2 = v;
                          }),
                        ),
                      ),
                      cellInput(st.gr, 95, (v) {
                        _markModified(i);
                        st.gr = v;
                      }, hint: 'GR', keyboard: TextInputType.number),
                      cellInput('${st.presentDays}', 85, (v) {
                        _markModified(i);
                        st.presentDays = int.tryParse(v) ?? 0;
                      }, keyboard: TextInputType.number),
                      cellInput('${st.presentDays2}', 85, (v) {
                        _markModified(i);
                        st.presentDays2 = int.tryParse(v) ?? 0;
                      }, keyboard: TextInputType.number),
                      cellInput(
                          st.standard.isEmpty ? _cleanClassCode : st.standard,
                          90, (v) {
                        _markModified(i);
                        st.standard = v;
                      }, hint: 'ધોરણ'),
                      Container(
                        width: 130,
                        height: rowHeight,
                        alignment: Alignment.center,
                        child: SwitchListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            st.isDivyang ? '♿ YES' : 'NO',
                            style: guFont(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: st.isDivyang
                                  ? AppColors.teal
                                  : AppColors.slate,
                            ),
                          ),
                          value: st.isDivyang,
                          onChanged: (v) => setState(() {
                            _markModified(i);
                            st.isDivyang = v;
                          }),
                        ),
                      ),
                    ],
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }

  /// Tab 3: નવો વિદ્યાર્થી ઉમેરો — All fields (Col A to Col R) visible Up-to-Down on one screen!
  Widget _buildNewStudentStepperForm() {
    if (_newStandardCtrl.text.isEmpty) {
      _newStandardCtrl.text = _cleanClassCode;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '➕ નવો વિદ્યાર્થી ઉમેરો — બધી વિગતો ઉપરથી નીચે (Col A થી Col R)',
            style: guFont(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.navy),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 130,
                child: LabeledField(
                  label: '૧. ક્રમ / Roll (Col A)',
                  child: TextField(
                      controller: _newRollCtrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 320,
                child: LabeledField(
                  label: '૨. વિદ્યાર્થીનું નામ (Col B) *',
                  child: TextField(
                    controller: _newNameCtrl,
                    decoration:
                        const InputDecoration(hintText: 'પૂરું નામ લખો'),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: LabeledField(
                  label: '૩. કેટેગરી (Col C)',
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _newCategory,
                    items: kCategoryOptions
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _newCategory = v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: LabeledField(
                  label: '૪. લિંગ / Gender',
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _newGender,
                    items: const [
                      DropdownMenuItem(
                          value: 'BOYS', child: Text('છોકરો / Boys')),
                      DropdownMenuItem(
                          value: 'GIRLS', child: Text('છોકરી / Girls')),
                      DropdownMenuItem(
                          value: 'UNSPECIFIED',
                          child: Text('નક્કી નથી / Not set')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _newGender = v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: LabeledField(
                  label: '૫. જન્મ DD (Col D)',
                  child: TextField(
                    controller: _newDdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'DD'),
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: LabeledField(
                  label: '૫. જન્મ MM (Col E)',
                  child: TextField(
                    controller: _newMmCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'MM'),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: LabeledField(
                  label: '૬. જન્મ YYYY (Col F)',
                  child: TextField(
                    controller: _newYyyyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'YYYY'),
                  ),
                ),
              ),
              SizedBox(
                width: 230,
                child: LabeledField(
                  label: '૭. વિદ્યાર્થી U.I.D. નંબર (Col G)',
                  child: TextField(
                      controller: _newUidCtrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 230,
                child: LabeledField(
                  label: '૮. વિદ્યાર્થી PEN નંબર (Col H)',
                  child: TextField(
                      controller: _newPenCtrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 200,
                child: LabeledField(
                  label: '૯. મોબાઈલ નંબર (Col I)',
                  child: TextField(
                      controller: _newMobileCtrl,
                      keyboardType: TextInputType.phone),
                ),
              ),
              SizedBox(
                width: 240,
                child: LabeledField(
                  label: '૧૦. પિતાનું નામ (Col J)',
                  child: TextField(controller: _newFatherCtrl),
                ),
              ),
              SizedBox(
                width: 240,
                child: LabeledField(
                  label: '૧૧. માતાનું નામ (Col K)',
                  child: TextField(controller: _newMotherCtrl),
                ),
              ),
              SizedBox(
                width: 280,
                child: LabeledField(
                  label: '૧૨. સરનામું (Col L)',
                  child: TextField(controller: _newAddressCtrl),
                ),
              ),
              SizedBox(
                width: 160,
                child: LabeledField(
                  label: '૧૩. GR નંબર (Col N)',
                  child: TextField(
                      controller: _newGrCtrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 155,
                child: LabeledField(
                  label: '૧૪. પ્રથમ સત્ર હાજર (Col O)',
                  child: TextField(
                      controller: _newPres1Ctrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 155,
                child: LabeledField(
                  label: '૧૫. દ્વિતિય સત્ર હાજર (Col P)',
                  child: TextField(
                      controller: _newPres2Ctrl,
                      keyboardType: TextInputType.number),
                ),
              ),
              SizedBox(
                width: 140,
                child: LabeledField(
                  label: '૧૬. ધોરણ (Col Q)',
                  child: TextField(controller: _newStandardCtrl),
                ),
              ),
              SizedBox(
                width: 280,
                child: LabeledField(
                  label: '૧૭. સત્ર-૨ માં અભ્યાસ ચાલુ? (Col M)',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('✅ Yes (ચાલુ)'),
                        selected: _newStudiedInSem2,
                        onSelected: (_) =>
                            setState(() => _newStudiedInSem2 = true),
                      ),
                      ChoiceChip(
                        label: const Text('🚫 No (નામ કમી)'),
                        selected: !_newStudiedInSem2,
                        onSelected: (_) =>
                            setState(() => _newStudiedInSem2 = false),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 280,
                child: LabeledField(
                  label: '૧૮. દિવ્યાંગ વિદ્યાર્થી? (Col R: 20% પાસિંગ)',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('♿ YES (દિવ્યાંગ)'),
                        selected: _newIsDivyang,
                        onSelected: (_) => setState(() => _newIsDivyang = true),
                      ),
                      ChoiceChip(
                        label: const Text('NO (સામાન્ય)'),
                        selected: !_newIsDivyang,
                        onSelected: (_) =>
                            setState(() => _newIsDivyang = false),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFrontPageMetaEditor() {
    if (!context.read<AppState>().isAdmin) return const SizedBox.shrink();

    Widget field({
      required String label,
      required String value,
      required String keyName,
      required ValueChanged<String> onChanged,
      double width = 220,
    }) =>
        SizedBox(
          width: width,
          child: LabeledField(
            label: label,
            child: TextFormField(
              key: ValueKey(
                  '$keyName-$_selectedClass-$_frontPageSettingsRevision'),
              initialValue: value,
              enabled: !_savingFrontPageSettings,
              style: guFont(fontSize: 13, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(isDense: true),
              onChanged: onChanged,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        initiallyExpanded: _showFrontPageSettings,
        onExpansionChanged: (value) =>
            setState(() => _showFrontPageSettings = value),
        leading: const Icon(Icons.edit_note, color: AppColors.navy),
        title: Text('🧾 Front Page Settings / ફ્રન્ટ પેજ વિગતો (માત્ર Admin)',
            style: guFont(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.navy)),
        subtitle: Text(
            'શાળાનું નામ, વર્ગ, વર્ગનો ડેટા અને વર્ગશિક્ષક દરેક વર્ગ મુજબ આપમેળે આવશે. અહીં સેવ કરેલ તારીખ અને અન્ય વિગતો સમગ્ર શાળાના બધા જ વર્ગોમાં આપમેળે લાગુ પડશે.',
            style: guFont(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.slate)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text('શાળાનું નામ (આપમેળે): $_schoolDisplayName',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                Text('વર્ગ (આપમેળે): ${_cleanClassCode}',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                Text(
                    'વર્ગશિક્ષક (આપમેળે): ${_classTeacherName.isEmpty ? 'વર્ગશિક્ષક ફાળવેલ નથી' : _classTeacherName}',
                    style: guFont(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              field(
                  label: '📅 પ્રથમ સત્ર પરિણામ તારીખ (Sem-1)',
                  value: _effectiveFirstSemResultDate,
                  keyName: 'front-sem1-date',
                  onChanged: (v) => _firstSemResultDate = v,
                  width: 220),
              field(
                  label: '📅 દ્વિતીય સત્ર પરિણામ તારીખ (Sem-2 • વર્ગ બઢતી)',
                  value: _effectiveSecondSemResultDate,
                  keyName: 'front-date',
                  onChanged: (v) => _resultDate = v,
                  width: 255),
              field(
                  label: '🎓 શૈક્ષણિક વર્ષ',
                  value: _academicYear,
                  keyName: 'front-year',
                  onChanged: (v) => _academicYear = v,
                  width: 190),
              field(
                  label: '🏛️ જિલ્લા પંચાયત / શિક્ષણ સમિતિનું નામ',
                  value: _frontPageEducationAuthority,
                  keyName: 'front-authority',
                  onChanged: (v) => _frontPageEducationAuthority = v,
                  width: 300),
              field(
                  label: 'ગામ',
                  value: _frontPageVillage,
                  keyName: 'front-village',
                  onChanged: (v) => _frontPageVillage = v,
                  width: 180),
              field(
                  label: 'તાલુકો',
                  value: _frontPageTaluka,
                  keyName: 'front-taluka',
                  onChanged: (v) => _frontPageTaluka = v,
                  width: 180),
              field(
                  label: 'જિલ્લો',
                  value: _frontPageDistrict,
                  keyName: 'front-district',
                  onChanged: (v) => _frontPageDistrict = v,
                  width: 180),
              field(
                  label: 'પે સેન્ટર',
                  value: _frontPagePayCenter,
                  keyName: 'front-pay-center',
                  onChanged: (v) => _frontPagePayCenter = v,
                  width: 220),
              field(
                  label: 'સી. આર. સી.',
                  value: _frontPageCrc,
                  keyName: 'front-crc',
                  onChanged: (v) => _frontPageCrc = v,
                  width: 220),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: _savingFrontPageSettings
                  ? 'સેવ થાય છે…'
                  : '💾 ફ્રન્ટ પેજ વિગતો સેવ કરો',
              background: AppColors.greenDeep,
              loading: _savingFrontPageSettings,
              onPressed:
                  _savingFrontPageSettings ? null : _saveFrontPageSettings,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFrontPageSettings() async {
    final state = context.read<AppState>();
    if (!state.isAdmin) {
      showSnack(context,
          'ફ્રન્ટ પેજની વિગતો બદલવાનો અધિકાર માત્ર School Admin પાસે છે.',
          error: true);
      return;
    }
    final className = _selectedClass;
    if (className == null || state.resultApi is! SupabaseResultApiService) {
      showSnack(context, 'Supabase Result સેવા અથવા વર્ગ ઉપલબ્ધ નથી.',
          error: true);
      return;
    }
    if (_resultDate.trim().isEmpty) {
      _resultDate = ResultSheetData.defaultSecondSemResultDateForNow();
    }
    if (_firstSemResultDate.trim().isEmpty) {
      _firstSemResultDate = ResultSheetData.defaultFirstSemResultDateForNow();
    }
    if (_academicYear.trim().isEmpty) {
      showSnack(context, 'પરિણામની તારીખ અને શૈક્ષણિક વર્ષ ભરો.', error: true);
      return;
    }
    setState(() => _savingFrontPageSettings = true);
    try {
      final response = await (state.resultApi as SupabaseResultApiService)
          .saveFrontPageSettings(
        className: className,
        firstSemResultDate: _firstSemResultDate,
        resultDate: _resultDate,
        academicYear: _academicYear,
        district: _frontPageDistrict,
        educationAuthority: _frontPageEducationAuthority,
        village: _frontPageVillage,
        taluka: _frontPageTaluka,
        payCenter: _frontPagePayCenter,
        crc: _frontPageCrc,
      );
      if (!mounted) return;
      if (response['result'] != 'success') {
        throw StateError(
            '${response['message'] ?? 'Front page settings could not be saved.'}');
      }
      setState(() => _frontPageSettingsRevision++);
      showSnack(
          context, '✅ ફ્રન્ટ પેજની વિગતો સમગ્ર શાળાના તમામ વર્ગો માટે સેવ થઈ ગઈ! (દરેક વર્ગમાં વર્ગ, વર્ગ ડેટા અને વર્ગશિક્ષક આપમેળે બદલાશે)');
    } catch (error) {
      if (mounted)
        showSnack(context, 'ફ્રન્ટ પેજની વિગતો સેવ થઈ શકી નથી: $error',
            error: true);
    } finally {
      if (mounted) setState(() => _savingFrontPageSettings = false);
    }
  }

  Widget _buildSchoolNameLanguagePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slateLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
            child: Text(
              'શાળાનું નામ: $_schoolDisplayName',
              style: guFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy),
            ),
          ),
          SizedBox(
            width: 270,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'School name language / શાળાના નામની ભાષા',
                  style: guFont(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: _schoolNameLanguage,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                        value: 'gu', child: Text('ગુજરાતી')),
                    DropdownMenuItem<String>(
                        value: 'en', child: Text('English')),
                  ],
                  onChanged: _saving ? null : _changeSchoolNameLanguage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectPermissionBanner(AppState state) {
    final String roleMessage;
    if (state.isAdmin) {
      roleMessage =
          'School Admin: આ વર્ગના બધા વિષયના ગુણ દાખલ / સુધારી શકો છો.';
    } else if (_isClassTeacher) {
      roleMessage =
          'વર્ગશિક્ષક: આ વર્ગના બધા સક્રિય વિષયના ગુણ દાખલ / સુધારી શકો છો.';
    } else {
      roleMessage =
          'વિષયશિક્ષક: ફક્ત આ વર્ગમાં તમને ફાળવેલા વિષયના ગુણ દાખલ / સુધારી શકો છો.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.greenDeep, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$roleMessage પસંદ કરેલા વિષયમાં રચનાત્મક, સત્રાંત, અને સ્વ-અધ્યયનના ત્રણેય ગુણ ઘટક ઉપલબ્ધ છે. જરૂર હોય તો નીચેના વિકલ્પથી જુદી એન્ટ્રી પસંદ કરી શકો છો.',
              style: guFont(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinationChipsBar() {
    Widget chip({
      required String label,
      required bool active,
      required VoidCallback onTap,
      Color activeColor = AppColors.navyMid,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: active ? activeColor : AppColors.slateLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? activeColor : AppColors.border, width: 1.3),
          ),
          child: Text(
            label,
            style: guFont(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : AppColors.navy,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('⚡ Quick Select:',
              style: guFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyMid)),
          chip(
            label: '${_showA && !_isBothSemCombo ? "✅" : "⬜"} રચનાત્મક A (40)',
            active: _showA && !_isBothSemCombo,
            onTap: () => _togglePartChip(toggleA: !_showA),
          ),
          chip(
            label: '${_showS && !_isBothSemCombo ? "✅" : "⬜"} સત્રાંત (40)',
            active: _showS && !_isBothSemCombo,
            onTap: () => _togglePartChip(toggleS: !_showS),
          ),
          chip(
            label: '${_showSW && !_isBothSemCombo ? "✅" : "⬜"} સ્વ-અધ્યયન (20)',
            active: _showSW && !_isBothSemCombo,
            onTap: () => _togglePartChip(toggleSW: !_showSW),
          ),
          chip(
            label: '💯 ત્રણેય સાથે (100)',
            active: _entryCombo == 'all_3',
            activeColor: AppColors.greenDeep,
            onTap: () => setState(() {
              _entryCombo = 'all_3';
              _gridTick++;
            }),
          ),
          if (_selectedSem == '2' || _selectedSem == 'Annual') ...[
            chip(
              label: '🌟 બંને સત્ર સાથે (${_maxSubSemTotal * 2})',
              active: _isBothSemCombo,
              activeColor: AppColors.teal,
              onTap: () => setState(() {
                _entryCombo = _isBothSemCombo ? 'all_3' : 'both_sem_all_6';
                _gridTick++;
              }),
            ),
            if (!_sem2OnlySubjects.contains(_selectedSubject))
              chip(
                label: '🆕 નવા દાખલ વિદ્યાર્થી માટે સત્ર-૧ ગુણ ઉમેરો (100 માંથી)',
                active: _isBothSemCombo && _useSem1DirectOutOf100,
                activeColor: AppColors.rose,
                onTap: () => setState(() {
                  _entryCombo = 'both_sem_all_6';
                  _sem1DirectOutOf100 = true;
                  _gridTick++;
                }),
              ),
          ],
          if (_isBothSemCombo && !_sem2OnlySubjects.contains(_selectedSubject))
            chip(
              label: _useSem1DirectOutOf100
                  ? '💯 પ્રથમ સત્ર: સીધા 100 માંથી'
                  : '🧮 પ્રથમ સત્ર: 40 + 40 + 20',
              active: _useSem1DirectOutOf100,
              activeColor: AppColors.greenDeep,
              onTap: _toggleSem1DirectOutOf100,
            ),
          if (_isBothSemCombo && _useSem1DirectOutOf100)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.greenDeep.withOpacity(0.08),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.greenDeep.withOpacity(0.3)),
              ),
              child: Text(
                'પ્રથમ સત્રના ત્રણ ગુણના કોષ એક જ કોષ તરીકે દેખાશે; કુલ ગુણ વચ્ચે રહેશે.',
                style: guFont(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy),
              ),
            ),
          if (_showS || _isBothSemCombo) ...[
            chip(
              label: _examEntryFrom80
                  ? '🔢 સત્રાંત: 80 માંથી એન્ટ્રી (આપોઆપ 40 માંથી પૂર્ણાંકમાં ફેરવાશે)'
                  : '🔢 સત્રાંત: $_maxSatrant માંથી એન્ટ્રી (80 માંથી કરવા અહીં દબાવો)',
              active: _examEntryFrom80,
              activeColor: AppColors.rose,
              onTap: () => setState(() {
                _examEntryFrom80 = !_examEntryFrom80;
                _gridTick++;
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClass3And4Sem2OnlyToggle() {
    final sub = _selectedSubject!;
    final isSem2Only = _sem2OnlySubjects.contains(sub);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSem2Only,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _sem2OnlySubjects.add(sub);
                } else {
                  _sem2OnlySubjects.remove(sub);
                }
                _gridTick++;
              });
              unawaited(_saveSem2OnlySubjects());
            },
          ),
          Expanded(
            child: Text(
              'Annual Rule: "$sub" માત્ર દ્વિતિય સત્રનો વિષય છે (વાર્ષિકમાં કુલ ગુણ 200 ને બદલે 100)',
              style: guFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyMid),
            ),
          ),
        ],
      ),
    );
  }
}
