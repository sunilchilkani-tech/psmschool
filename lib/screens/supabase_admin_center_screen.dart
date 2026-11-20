import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as ec;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import 'supabase_id_card_studio_screen.dart';
import 'supabase_library_screen.dart';
import 'supabase_rojmel_screen.dart';
import 'supabase_class_teacher_assignments_screen.dart';
import 'supabase_leave_report_pdf_screen.dart';
import 'supabase_leave_rules_screen.dart';
import 'archived_students_screen.dart';
import 'student_bulk_import_screen.dart';
import 'supabase_hajari_patrak_screen.dart';
import '../services/school_class_order.dart';
import 'package:share_plus/share_plus.dart';
import '../services/school_export_service.dart';
import 'supabase_whole_school_result_summary_screen.dart';
import '../services/datewise_report_columns.dart';
import '../services/supabase_report_export_service.dart';

import '../services/psm_file_export_helper.dart';
import '../services/supabase_leave_pdf_service.dart';
import '../theme/display_scale.dart';
import 'package:pmshri_attendance/services/class_label.dart';
import '../theme/responsive.dart';
import '../widgets/admin_daily_attendance_dashboard.dart';

/// Supabase-native Admin Centre. All write operations are additionally guarded
/// by the existing table/storage RLS policies; hiding buttons is not the only guard.
class SupabaseAdminCenterScreen extends StatefulWidget {
  const SupabaseAdminCenterScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<SupabaseAdminCenterScreen> createState() =>
      _SupabaseAdminCenterScreenState();
}

class _SupabaseAdminCenterScreenState extends State<SupabaseAdminCenterScreen> {
  Map<String, dynamic> get profile => widget.profile;
  List<Map<String, dynamic>> _devSharedFiles = <Map<String, dynamic>>[];

  /// Selected main tab of the Admin Centre ('all' = every tool).
  String _adminGroup = 'all';

  static const List<(String, String, IconData)> _adminGroups =
      <(String, String, IconData)>[
    ('all', 'બધું / All', Icons.apps_rounded),
    ('setup', 'શાળા સેટઅપ / Setup', Icons.settings_rounded),
    ('students', 'વિદ્યાર્થી / Students', Icons.groups_rounded),
    ('attendance', 'હાજરી / Attendance', Icons.fact_check_rounded),
    ('accounts', 'હિસાબ અને કાર્ડ / Accounts & Cards', Icons.account_balance_wallet_rounded),
    ('leave', 'રજા / Leave', Icons.event_available_rounded),
    ('data', 'ડેટા અને બેકઅપ / Data', Icons.backup_rounded),
  ];

  /// Main-tab bucket for an Admin Centre tool.
  static String _groupForFeature(_AdminFeature f) {
    final t = f.title.toLowerCase();
    if (t.contains('rojmel') || t.contains('id card') || t.contains('library')) {
      return 'accounts';
    }
    if (t.contains('leave')) return 'leave';
    if (t.contains('attendance')) return 'attendance';
    if (t.contains('backup') || t.contains('export')) return 'data';
    if (t.contains('student') || t.contains('promote') || t.contains('section')) {
      return 'students';
    }
    return 'setup';
  }

  @override
  void initState() {
    super.initState();
    _loadDeveloperSharedFiles();
  }

  Future<void> _loadDeveloperSharedFiles() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'psm_get_developer_shared_files',
      );
      if (!mounted) return;
      final list = res is List
          ? res
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() => _devSharedFiles = list);
      if (list.isNotEmpty) {
        await _checkAndShowDeveloperFilesPopupInAdminCenter(list);
      }
    } catch (_) {}
  }

  bool _adminCenterPopupShowing = false;

  Future<void> _checkAndShowDeveloperFilesPopupInAdminCenter(
    List<Map<String, dynamic>> files,
  ) async {
    if (!mounted || _adminCenterPopupShowing || files.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final schoolId = '${profile['school_id'] ?? profile['school_ref'] ?? "default"}'.trim();
      final prefKey = 'psm_admin_seen_dev_files_v2_$schoolId';
      final seenSet = (prefs.getStringList(prefKey) ?? const <String>[]).toSet();
      final unseenFiles = files.where((f) {
        final id = '${f['id'] ?? ''}'.trim();
        final stamp = '${f['updated_at'] ?? f['created_at'] ?? ''}'.trim();
        final token = stamp.isEmpty ? id : '${id}_$stamp';
        return id.isNotEmpty && !seenSet.contains(token);
      }).toList();
      if (unseenFiles.isEmpty || !mounted) return;
      _adminCenterPopupShowing = true;

      final openNow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.cloud_download_rounded,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('ડેવલપર તરફથી નવી ફાઈલ (Developer Shared File)'),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ડેવલપર દ્વારા શાળા Admin માટે ${unseenFiles.length} ફાઈલ શેર કરવામાં આવી છે:',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final f in unseenFiles)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          '${f['title'] ?? f['file_name'] ?? 'File'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${f['file_name'] ?? ''}${'${f['description'] ?? ''}'.trim().isNotEmpty ? '\n${f['description']}' : ''}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('પછીથી (OK)'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.download),
              label: const Text('ફાઈલ જુઓ / ડાઉનલોડ કરો'),
            ),
          ],
        ),
      );

      for (final f in unseenFiles) {
        final id = '${f['id'] ?? ''}'.trim();
        final stamp = '${f['updated_at'] ?? f['created_at'] ?? ''}'.trim();
        final token = stamp.isEmpty ? id : '${id}_$stamp';
        if (id.isNotEmpty) seenSet.add(token);
      }
      await prefs.setStringList(prefKey, seenSet.toList());

      if (openNow == true && mounted) {
        _push(context, const SupabaseDeveloperSharedFilesAdminScreen());
      }
    } catch (_) {
    } finally {
      _adminCenterPopupShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = '${profile['role'] ?? ''}'.trim().toLowerCase();
    if (role != 'admin' && role != 'developer') {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Centre')),
        body: const Center(
          child: Text('School Admin access is required for this page.'),
        ),
      );
    }

    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          labelStyle: baseTheme.inputDecorationTheme.labelStyle?.copyWith(
            fontFamily: 'NotoSansGujaratiLocal',
          ),
          hintStyle: baseTheme.inputDecorationTheme.hintStyle?.copyWith(
            fontFamily: 'NotoSansGujaratiLocal',
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Admin Centre / શાળા સંચાલન'),
              Text(
                'School setup, records and tools',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          actions: [DisplayScale.menuButton(color: Colors.white)],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 650
                ? 2
                : 1;
            final features = <_AdminFeature>[
              _AdminFeature(
                Icons.dashboard_customize_rounded,
                'દૈનિક હાજરી, પીએમ પોષણ અને અલ્પાહાર ડેશબોર્ડ / Daily Attendance Live Dashboard',
                'રિપોર્ટ જનરેટ કર્યા વગર લાઈવ દૈનિક અહેવાલ જુઓ, કયા વર્ગની હાજરી / પીએમ પોષણ / અલ્પાહાર બાકી છે તે જુઓ અને ૧ ક્લિકથી શિક્ષકને WhatsApp રીમાઈન્ડર મોકલો.',
                () => _push(
                  context,
                  SupabaseAdminDailyDashboardScreen(profile: profile),
                ),
              ),
              _AdminFeature(
                Icons.verified_user_outlined,
                'Teacher Attendance Permission / શિક્ષક હાજરી પૂરવાની પરવાનગી (4 Modes + Leave Charge)',
                'નક્કી કરો કે કયા શિક્ષક હાજરી (PM POSHAN અને અલ્પાહાર સાથે) પૂરી શકે: (1) માત્ર વર્ગ શિક્ષક, (2) ધોરણના વિભાગવાર વર્ગ શિક્ષકો (6A, 6B, 6C...), (3) વિષય + વર્ગ શિક્ષક, કે (4) કોઈપણ શિક્ષક (રજા ચાર્જ નિયમ સાથે).',
                () => _push(context, const SupabaseAttendancePermissionScreen()),
              ),
              _AdminFeature(
                Icons.analytics_rounded,
                'સમગ્ર શાળાનું સત્રવાર પરિણામ સારાંશ (All 3 Formats)',
                '૧ ક્લિકમાં સમગ્ર શાળાના ત્રણેય પરિણામ સારાંશ પત્રકો (Class-Section, Category-Grade અને Whole School Performance) શાળાના લોગો સાથે પ્રિન્ટ / Excel કરો.',
                () => _push(
                  context,
                  SupabaseWholeSchoolResultSummaryScreen(profile: profile),
                ),
              ),
              _AdminFeature(
                Icons.sim_card_download_outlined,
                'સંપૂર્ણ શાળા ડેટા ડાઉનલોડ / Download Whole School Data (Excel)',
                'વિદ્યાર્થીઓ, હાજરી, પરિણામ, રોજમેળ, પુસ્તકાલય, શિક્ષકો અને શાળાના તમામ પત્રકોનો સંપૂર્ણ બેકઅપ Excel (.xlsx) ફાઈલમાં ડાઉનલોડ કરો.',
                () => _downloadWholeSchoolData(context),
              ),
              if (_devSharedFiles.isNotEmpty)
                _AdminFeature(
                  Icons.cloud_download_outlined,
                  'Developer Files / ડેવલપર ફાઈલ ડાઉનલોડ (${_devSharedFiles.length})',
                  'Download files shared by the Developer (${_devSharedFiles.length} available). This tab hides automatically when no files are shared.',
                  () {
                    _push(
                      context,
                      const SupabaseDeveloperSharedFilesAdminScreen(),
                    );
                    if (mounted) _loadDeveloperSharedFiles();
                  },
                ),
              _AdminFeature(
                Icons.image_outlined,
                'School Logo / શાળાનો લોગો',
                'Upload and save the school logo for future reports and certificates.',
                () => _push(context, const SupabaseSchoolLogoScreen()),
              ),
              _AdminFeature(
                Icons.badge_outlined,
                'ID Card Studio / ઓળખપત્ર',
                'Design ID cards from the student database or any Excel file (DOB as DD/MM/YYYY), add photos and export print-ready PDF.',
                () => _push(context, const SupabaseIdCardStudioScreen()),
              ),
              _AdminFeature(
                Icons.campaign_outlined,
                'Messages & Holidays / સંદેશ અને રજાઓ',
                'Post school messages; add, import and export holidays. Both support Excel files.',
                () => _push(context, const SupabaseAdminRecordsScreen()),
              ),
              _AdminFeature(
                Icons.local_library_outlined,
                'Digital Library / ડિજિટલ પુસ્તકાલય',
                'Manage books, issue and return records, and download school, class and teacher reports. Bulk book import and archive are restricted to the School Admin.',
                () => _push(context, SupabaseLibraryScreen(profile: profile)),
              ),
              if (role == 'admin')
                _AdminFeature(
                  Icons.account_balance_wallet_outlined,
                  'Rojmel / \u0ab0\u0acb\u0a9c\u0aae\u0ac7\u0ab3 \u0a85\u0aa8\u0ac7 \u0ab8\u0ab0\u0a95\u0abe\u0ab0\u0ac0 \u0a93\u0aa1\u0abf\u0a9f',
                  'School Admin only. Cloud-saved accounts, grant heads, transactions, cashbook, 21 government audit reports, calculation checks and export.',
                  () => _push(context, SupabaseRojmelScreen(profile: profile)),
                ),
              _AdminFeature(
                Icons.people_alt_outlined,
                'Class Teacher Assignment / વર્ગ શિક્ષક ફાળવણી',
                'Choose a teacher account for each created class. The assignment fills the class automatically on leave applications.',
                () => _push(
                  context,
                  const SupabaseClassTeacherAssignmentsScreen(),
                ),
              ),
              _AdminFeature(
                Icons.event_available_outlined,
                'Approve Leave / રજા મંજૂરી',
                'Review pending teacher leave requests and approve or reject them.',
                () => _push(context, const SupabaseLeaveApprovalsScreen()),
              ),
              _AdminFeature(
                Icons.event_repeat_outlined,
                'Leave Month Settings / રજા મહિના અને મર્યાદા',
                'Set CL and Marajiyat annual caps, plus allowed months and a day cap for Valtar leave.',
                () => _push(context, const SupabaseLeaveRulesScreen()),
              ),
              _AdminFeature(
                Icons.upload_file_outlined,
                'Whole-school Student Upload / સમગ્ર શાળા વિદ્યાર્થી અપલોડ',
                'Upload student Excel data for the entire school at once (auto-routed by ધોરણ column or sheet name) or for any selected class.',
                () async {
                  final schoolType = '${profile['school_type'] ?? profile['schoolType'] ?? 'mixed'}';
                  _push(
                    context,
                    StudentBulkImportScreen(
                      classId: '',
                      classLabel: 'સમગ્ર શાળા (All Classes / Whole School)',
                      schoolType: schoolType,
                    ),
                  );
                },
              ),
              _AdminFeature(
                Icons.settings_backup_restore_outlined,
                'Active / Deactive Students / સક્રિય - નિષ્ક્રિય વિદ્યાર્થીઓ',
                'Admin Only: View Active / Deactive students, restore deactivated students by selecting which class to restore into, or move students between classes.',
                () async {
                  final ref = await _schoolRef(Supabase.instance.client);
                  if (!context.mounted) return;
                  _push(
                    context,
                    ArchivedStudentsScreen(
                      schoolRef: ref,
                      classId: '',
                      classLabel: 'સમગ્ર શાળા (All Classes / Whole School)',
                    ),
                  );
                },
              ),
              _AdminFeature(
                Icons.file_download_outlined,
                'Whole-school Student Export & Import',
                'Export selected headers or upload full-school / GR-matched partial-column Excel files.',
                () => _push(context, const SupabaseSchoolDataExportScreen()),
              ),
              _AdminFeature(
                Icons.tune_outlined,
                'Custom Headers / કસ્ટમ હેડર',
                'Configure up to 11 school fields. The saved labels appear in student forms and exports.',
                () => _push(context, const SupabaseCustomHeadersScreen()),
              ),
              _AdminFeature(
                Icons.rule_folder_outlined,
                'Attendance Modes & Unfreeze / હાજરી મોડ અને અનફ્રીઝ',
                'Turn 3-step save and Direct Entry on/off, configure teacher attendance permissions, and unfreeze submitted attendance.',
                () => _push(context, const SupabaseAttendanceFreezeManageScreen()),
              ),
              _AdminFeature(
                Icons.trending_up_outlined,
                'Class Promote & Promoted Excel / વર્ગ બઢતી અને ધોરણ-8 કમી Excel',
                'Balvatika -> Std 1 -> ... -> Std 8 (+1 logic), remove Std 8 for Class 9, change section during promotion, and export full-data Promoted Excel.',
                () => _push(context, const SupabaseClassPromotionScreen(initialTab: 0)),
              ),
              _AdminFeature(
                Icons.swap_horiz_outlined,
                'Section Change (A ↔ B ↔ C) / વર્ગ વિભાગ બદલો',
                'Change student section (A to B, B to C, C to A) anytime during the month without altering Present Days, DOB, or Enrollment School data.',
                () => _push(context, const SupabaseClassPromotionScreen(initialTab: 1)),
              ),
              _AdminFeature(
                Icons.person_search_outlined,
                'Student Search (GR / Roll / Name — Whole Data) / વિદ્યાર્થી શોધો',
                'Admin Only: Search any student by GR Number, Roll Number, or any part of Surname / Name / Father Name (including Promoted & Class 8 -> 9 students) and download Whole Data Excel.',
                () => _push(context, SupabaseAdminGlobalStudentSearchScreen(profile: profile)),
              ),
              _AdminFeature(
                Icons.fact_check_outlined,
                'Recorded Attendance Register / ભરેલ હાજરીપત્રક',
                'Admin Only: Recorded Hajari Patrak in the same template (correct Gujarati font) with daily present, absent, PM POSHAN and breakfast totals, plus student-wise Excel.',
                () => _push(context, SupabaseHajariPatrakScreen(profile: profile)),
              ),
              _AdminFeature(
                Icons.backup_table_outlined,
                'One-by-One Excel Backup & Delete Data / બેકઅપ અને ડેટા ડિલીટ',
                'Admin Only: Auto-download Ekandar Reports, Students Data, Library Book List & Library Register one-by-one in Excel first, then delete Attendance, Student, Library or All Data.',
                () => _push(context, SupabaseAdminBackupAndResetScreen(profile: profile)),
              ),
            ];
            final shown = _adminGroup == 'all'
                ? features
                : features
                    .where((f) => _groupForFeature(f) == _adminGroup)
                    .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'School Admin Toolkit',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_cleanSchoolLabel(profile['school_name'] ?? 'School')}  |  ${profile['school_id'] ?? ''}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Excel imports/exports and school settings are scoped to the signed-in school.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final g in _adminGroups)
                        if (g.$1 == 'all' ||
                            features.any((f) => _groupForFeature(f) == g.$1))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(g.$3, size: 18),
                              label: Text(
                                g.$1 == 'all'
                                    ? '${g.$2} (${features.length})'
                                    : '${g.$2} (${features.where((f) => _groupForFeature(f) == g.$1).length})',
                              ),
                              selected: _adminGroup == g.$1,
                              onSelected: (_) =>
                                  setState(() => _adminGroup = g.$1),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shown.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 158,
                  ),
                  itemBuilder: (context, index) =>
                      _AdminFeatureCard(feature: shown[index]),
                ),
                const SizedBox(height: 18),
                AdminDailyAttendanceDashboard(
                  profile: profile,
                  initiallyExpanded: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _cleanSchoolLabel(dynamic value) {
    return (value ?? '')
        .toString()
        .replaceAll('\u00e2\u20ac\u00a2', '-')
        .replaceAll('\u00e2\u20ac\u00a6', '...')
        .replaceAll('\u00e2\u20ac\u2122', "'")
        .replaceAll('\u00e2\u20ac\u0153', '"')
        .replaceAll('\u00e2\u20ac\u009d', '"');
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _downloadWholeSchoolData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('સંપૂર્ણ શાળાનો ડેટા તૈયાર થઈ રહ્યો છે (Preparing Whole School Excel Backup)...'),
      ),
    );
    try {
      final bundle = await SchoolExportService().exportForCurrentUser(
        includePrivateDetails: true,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              bundle.bytes,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: bundle.fileName,
            ),
          ],
          text: bundle.fileName,
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('સંપૂર્ણ શાળાનો ડેટા ડાઉનલોડ થયો: ${bundle.fileName}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Export failed: $e'),
        ),
      );
    }
  }
}

class _AdminFeature {
  const _AdminFeature(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.disabled = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool disabled;
}

class _AdminFeatureCard extends StatelessWidget {
  const _AdminFeatureCard({required this.feature});
  final _AdminFeature feature;

  /// Accent colour per main tab, so each group is recognisable at a glance.
  static Color _accent(_AdminFeature f) {
    final t = f.title.toLowerCase();
    if (t.contains('rojmel')) return const Color(0xFF123A6B);
    if (t.contains('id card')) return const Color(0xFF2563EB);
    if (t.contains('library')) return const Color(0xFF65A30D);
    if (t.contains('leave')) return const Color(0xFFDB2777);
    if (t.contains('attendance')) return const Color(0xFF0F766E);
    if (t.contains('backup') || t.contains('export')) return const Color(0xFF7C3AED);
    if (t.contains('student') || t.contains('promote') || t.contains('section')) {
      return const Color(0xFF059669);
    }
    return const Color(0xFF475569);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = feature.disabled ? scheme.outline : _accent(feature);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: feature.onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.09), Colors.white],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(feature.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: Text(
                          feature.subtitle,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(
                          feature.disabled ? Icons.lock_outline : Icons.arrow_forward_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String> _schoolRef(SupabaseClient client) async {
  final result = await client.rpc('current_school_ref');
  if (result == null || '$result'.trim().isEmpty)
    throw StateError('The signed-in account has no active school.');
  return '$result';
}

Future<String> _teacherId(SupabaseClient client) async {
  final result = await client.rpc('current_teacher_id');
  if (result == null || '$result'.trim().isEmpty)
    throw StateError('The signed-in account has no active teacher identity.');
  return '$result';
}

String _dateIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(String input) {
  final text = input.trim();
  final direct = DateTime.tryParse(text);
  if (direct != null) return DateTime(direct.year, direct.month, direct.day);
  final pieces = text.split(RegExp(r'[-/.]')).map((v) => v.trim()).toList();
  if (pieces.length != 3) return null;
  int? a = int.tryParse(pieces[0]);
  int? b = int.tryParse(pieces[1]);
  int? c = int.tryParse(pieces[2]);
  if (a == null || b == null || c == null) return null;
  if (pieces[0].length == 4) return DateTime(a, b, c);
  if (pieces[2].length == 4) return DateTime(c, b, a);
  return null;
}

String _excelTextSpanToPlainText(ec.TextSpan span) {
  final buffer = StringBuffer(span.text ?? '');
  for (final child in span.children ?? const <ec.TextSpan>[]) {
    buffer.write(_excelTextSpanToPlainText(child));
  }
  return buffer.toString();
}

String _cellText(ec.CellValue? value) {
  if (value == null) return '';
  if (value is ec.TextCellValue) return _excelTextSpanToPlainText(value.value);
  if (value is ec.IntCellValue) return '${value.value}';
  if (value is ec.DoubleCellValue) return '${value.value}';
  if (value is ec.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
  if (value is ec.DateCellValue)
    return _dateIso(DateTime(value.year, value.month, value.day));
  if (value is ec.DateTimeCellValue)
    return _dateIso(DateTime(value.year, value.month, value.day));
  if (value is ec.FormulaCellValue) return value.formula;
  return value.toString();
}

void _putText(ec.Sheet sheet, int rowIndex, int columnIndex, String value) {
  sheet
      .cell(
        ec.CellIndex.indexByColumnRow(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
        ),
      )
      .value = ec.TextCellValue(
    value,
  );
}

Future<void> _shareXlsx(
  List<int> bytes,
  String filename,
  BuildContext context,
) async {
  await PsmFileExportHelper.saveOrShare(
    bytes: Uint8List.fromList(bytes),
    filename: filename,
    title: filename,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}

Future<PlatformFile?> _pickWorkbook() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['xlsx'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  return result.files.first;
}

List<List<String>> _readWorkbookRows(PlatformFile file) {
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty)
    throw StateError('The selected workbook could not be read.');
  final workbook = ec.Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty)
    throw StateError('The workbook does not contain a worksheet.');
  final sheet = workbook.tables.values.first;
  return sheet.rows
      .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
      .toList();
}

Future<void> _showError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Operation failed'),
      content: SelectableText(
        '$error'
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class SupabaseSchoolLogoScreen extends StatefulWidget {
  const SupabaseSchoolLogoScreen({super.key});

  @override
  State<SupabaseSchoolLogoScreen> createState() =>
      _SupabaseSchoolLogoScreenState();
}

class _SupabaseSchoolLogoScreenState extends State<SupabaseSchoolLogoScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  bool _uploading = false;
  String? _school;
  String _logoPath = '';
  String _logoUrl = '';
  Uint8List? _logoBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final row = await _client
          .from('school_settings')
          .select('logo_path,logo_data_uri')
          .eq('school_ref', school)
          .maybeSingle();
      final path = '${row?['logo_path'] ?? ''}'.trim();
      final dataUri = '${row?['logo_data_uri'] ?? ''}'.trim();
      Uint8List? bytes;
      if (dataUri.startsWith('data:')) {
        final comma = dataUri.indexOf(',');
        if (comma >= 0) {
          try {
            bytes = base64Decode(dataUri.substring(comma + 1));
          } catch (_) {}
        }
      }
      if (bytes == null && path.isNotEmpty) {
        try {
          bytes = await _client.storage.from('school-assets').download(path);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _school = school;
        _logoPath = path;
        _logoBytes = bytes;
        _logoUrl = path.isEmpty
            ? ''
            : _client.storage.from('school-assets').getPublicUrl(path);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _chooseAndUpload() async {
    try {
      final file = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (file == null || file.files.isEmpty) return;
      final picked = file.files.first;
      final bytes = picked.bytes;
      final school = _school ?? await _schoolRef(_client);
      if (bytes == null || bytes.isEmpty)
        throw StateError('The selected image has no readable bytes.');
      final extension = (picked.extension ?? 'png').toLowerCase();
      final ext =
          const <String>{'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
          ? extension
          : 'png';
      final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/$ext';
      final path = '$school/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';
      setState(() {
        _uploading = true;
        _error = null;
      });
      await _client.storage
          .from('school-assets')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      final existing = await _client
          .from('school_settings')
          .select('school_ref')
          .eq('school_ref', school)
          .maybeSingle();
      if (existing == null) {
        await _client.from('school_settings').insert(<String, dynamic>{
          'school_ref': school,
          'logo_path': path,
        });
      } else {
        await _client
            .from('school_settings')
            .update(<String, dynamic>{
              'logo_path': path,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('school_ref', school);
      }
      if (!mounted) return;
      setState(() {
        _logoPath = path;
        _logoBytes = bytes;
        _logoUrl = _client.storage.from('school-assets').getPublicUrl(path);
        _uploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School logo uploaded and saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      final raw = '$error';
      final message = raw.toLowerCase().contains('bucket not found')
          ? 'Supabase Storage bucket "school-assets" is missing. Run `npx supabase db push` from the project root to apply the Admin Centre storage migration, then retry.'
          : raw;
      setState(() {
        _error = message;
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('School Logo / શાળાનો લોગો')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (_logoBytes != null && _logoBytes!.isNotEmpty)
                          Image.memory(
                            _logoBytes!,
                            height: 180,
                            fit: BoxFit.contain,
                          )
                        else if (_logoUrl.isNotEmpty)
                          Image.network(
                            _logoUrl,
                            height: 180,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              size: 100,
                            ),
                          )
                        else
                          const Icon(Icons.account_balance_outlined, size: 100),
                        const SizedBox(height: 12),
                        Text(
                          _logoPath.isEmpty
                              ? 'No school logo uploaded yet'
                              : 'Logo saved for this school',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_logoPath.isNotEmpty)
                          SelectableText(
                            _logoPath,
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _uploading ? null : _chooseAndUpload,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(
                            _uploading
                                ? 'Uploading...'
                                : 'Upload / Change Logo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    "PNG, JPG or WebP is recommended. The image is stored in this school's own folder in Supabase Storage. The logo asset is publicly readable for report rendering; uploads are Admin-only for active, unblocked schools.",
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SupabaseAdminRecordsScreen extends StatelessWidget {
  const SupabaseAdminRecordsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Messages & Holidays / સંદેશ અને રજાઓ'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.campaign_outlined), text: 'School Messages'),
            Tab(icon: Icon(Icons.event_busy_outlined), text: 'Holidays'),
          ],
        ),
      ),
      body: const TabBarView(
            physics: const NeverScrollableScrollPhysics(),
        children: [SupabaseAdminMessagesTab(), SupabaseAdminHolidaysTab()],
      ),
    ),
  );
}

class SupabaseAdminMessagesTab extends StatefulWidget {
  const SupabaseAdminMessagesTab({super.key});
  @override
  State<SupabaseAdminMessagesTab> createState() =>
      _SupabaseAdminMessagesTabState();
}

class _SupabaseAdminMessagesTabState extends State<SupabaseAdminMessagesTab> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _message = TextEditingController();
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final collected = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await _client
            .from('school_admin_messages')
            .select('id,message_date,message,updated_at')
            .eq('school_ref', school)
            .order('message_date', ascending: false)
            .range(offset, offset + 999);
        if (page.isEmpty) break;
        collected.addAll(page.map((row) => Map<String, dynamic>.from(row)));
        offset += page.length;
      }
      final nowIst =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final todayIso = _dateIso(nowIst);
      final activeRecords = <Map<String, dynamic>>[];
      for (final row in collected) {
        final mDate = '${row['message_date'] ?? ''}'.trim();
        if (mDate.length >= 10 && mDate.substring(0, 10).compareTo(todayIso) < 0) {
          try {
            await _client
                .from('school_admin_messages')
                .delete()
                .eq('school_ref', school)
                .eq('message_date', mDate);
          } catch (_) {}
          continue;
        }
        activeRecords.add(row);
      }
      if (!mounted) return;
      setState(() {
        _records = activeRecords;
        _loading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a message.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final teacher = await _teacherId(_client);
      await _client.from('school_admin_messages').upsert(<String, dynamic>{
        'school_ref': school,
        'message_date': _dateIso(_date),
        'message': _message.text.trim(),
        'created_by_teacher': teacher,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref,message_date');
      _message.clear();
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('School message saved.')));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    try {
      final workbook = ec.Excel.createExcel();
      final sheet = workbook['Sheet1'];
      _putText(sheet, 0, 0, 'Date');
      _putText(sheet, 0, 1, 'Message');
      for (var i = 0; i < _records.length; i++) {
        _putText(sheet, i + 1, 0, '${_records[i]['message_date'] ?? ''}');
        _putText(sheet, i + 1, 1, '${_records[i]['message'] ?? ''}');
      }
      final bytes = workbook.encode(); // encode(): no extra auto-download on web
      if (bytes == null)
        throw StateError('Could not create the Excel workbook.');
      await _shareXlsx(bytes, 'School_Messages.xlsx', context);
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  Future<void> _import() async {
    try {
      final file = await _pickWorkbook();
      if (file == null) return;
      final rows = _readWorkbookRows(file);
      if (rows.length < 2)
        throw StateError(
          'The workbook needs a header row and at least one message.',
        );
      final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
      final dateIndex = headers.indexWhere(
        (v) => v.contains('date') || v.contains('તારીખ'),
      );
      final msgIndex = headers.indexWhere(
        (v) => v.contains('message') || v.contains('સંદેશ'),
      );
      final d = dateIndex < 0 ? 0 : dateIndex;
      final m = msgIndex < 0 ? 1 : msgIndex;
      final school = await _schoolRef(_client);
      final teacher = await _teacherId(_client);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final payload = <Map<String, dynamic>>[];
      for (final row in rows.skip(1)) {
        if (row.length <= d || row.length <= m) continue;
        final date = _parseDate(row[d]);
        final message = row[m].trim();
        if (date == null || message.isEmpty) continue;
        payload.add(<String, dynamic>{
          'school_ref': school,
          'message_date': _dateIso(date),
          'message': message,
          'created_by_teacher': teacher,
          'updated_at': nowIso,
        });
      }
      if (payload.isNotEmpty) {
        await _client
            .from('school_admin_messages')
            .upsert(payload, onConflict: 'school_ref,message_date');
      }
      final imported = payload.length;
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported/updated $imported messages.')),
        );
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Create or replace a message for a selected date. Teachers can read school messages under their signed-in school.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Message date: ${_dateIso(_date)}'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Message for teachers',
                hintText: 'Enter the school message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Message'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Recent messages',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_records.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('No messages saved yet.'),
                ),
              ),
            for (final row in _records)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.message_outlined),
                  ),
                  title: Text('${row['message_date'] ?? ''}'),
                  subtitle: Text(
                    '${row['message'] ?? ''}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    final date = _parseDate('${row['message_date']}');
                    setState(() {
                      if (date != null) _date = date;
                      _message.text = '${row['message'] ?? ''}';
                    });
                  },
                ),
              ),
          ],
        );
}

class SupabaseAdminHolidaysTab extends StatefulWidget {
  const SupabaseAdminHolidaysTab({super.key});
  @override
  State<SupabaseAdminHolidaysTab> createState() =>
      _SupabaseAdminHolidaysTabState();
}

class _SupabaseAdminHolidaysTabState extends State<SupabaseAdminHolidaysTab> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _reason = TextEditingController();
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final collected = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = await _client
            .from('school_holidays')
            .select('id,holiday_date,reason')
            .eq('school_ref', school)
            .order('holiday_date', ascending: false)
            .range(offset, offset + 999);
        if (page.isEmpty) break;
        collected.addAll(page.map((row) => Map<String, dynamic>.from(row)));
        offset += page.length;
      }
      if (mounted)
        setState(() {
          _records = collected;
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final teacher = await _teacherId(_client);
      await _client.from('school_holidays').upsert(<String, dynamic>{
        'school_ref': school,
        'holiday_date': _dateIso(_date),
        'reason': _reason.text.trim(),
        'created_by_teacher': teacher,
      }, onConflict: 'school_ref,holiday_date');
      _reason.clear();
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Holiday saved.')));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    try {
      final workbook = ec.Excel.createExcel();
      final sheet = workbook['Sheet1'];
      _putText(sheet, 0, 0, 'Date');
      _putText(sheet, 0, 1, 'Reason');
      for (var i = 0; i < _records.length; i++) {
        _putText(sheet, i + 1, 0, '${_records[i]['holiday_date'] ?? ''}');
        _putText(sheet, i + 1, 1, '${_records[i]['reason'] ?? ''}');
      }
      final bytes = workbook.encode(); // encode(): no extra auto-download on web
      if (bytes == null)
        throw StateError('Could not create the Excel workbook.');
      await _shareXlsx(bytes, 'School_Holidays.xlsx', context);
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  Future<void> _import() async {
    try {
      final file = await _pickWorkbook();
      if (file == null) return;
      final rows = _readWorkbookRows(file);
      if (rows.length < 2)
        throw StateError(
          'The workbook needs a header row and at least one holiday.',
        );
      final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
      final dateIndex = headers.indexWhere(
        (v) => v.contains('date') || v.contains('તારીખ'),
      );
      final reasonIndex = headers.indexWhere(
        (v) => v.contains('reason') || v.contains('રજા'),
      );
      final d = dateIndex < 0 ? 0 : dateIndex;
      final r = reasonIndex < 0 ? 1 : reasonIndex;
      final school = await _schoolRef(_client);
      final teacher = await _teacherId(_client);
      final payload = <Map<String, dynamic>>[];
      for (final row in rows.skip(1)) {
        if (row.length <= d) continue;
        final date = _parseDate(row[d]);
        if (date == null) continue;
        final reason = row.length > r ? row[r].trim() : '';
        payload.add(<String, dynamic>{
          'school_ref': school,
          'holiday_date': _dateIso(date),
          'reason': reason,
          'created_by_teacher': teacher,
        });
      }
      if (payload.isNotEmpty) {
        await _client
            .from('school_holidays')
            .upsert(payload, onConflict: 'school_ref,holiday_date');
      }
      final imported = payload.length;
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported/updated $imported holidays.')),
        );
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete holiday?'),
        content: Text('${row['holiday_date']}  |  ${row['reason'] ?? ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _client.from('school_holidays').delete().eq('id', '${row['id']}');
      await _load();
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Holidays are saved per school. Import Excel with Date and Reason columns; dates already present will be updated.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Holiday date: ${_dateIso(_date)}'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Holiday reason',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Holiday'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Saved holidays',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final row in _records)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.event_busy_outlined),
                  ),
                  title: Text('${row['holiday_date']}'),
                  subtitle: Text('${row['reason'] ?? ''}'),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _delete(row),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () {
                    final parsed = _parseDate('${row['holiday_date']}');
                    setState(() {
                      if (parsed != null) _date = parsed;
                      _reason.text = '${row['reason'] ?? ''}';
                    });
                  },
                ),
              ),
          ],
        );
}

class SupabaseLeaveApprovalsScreen extends StatefulWidget {
  const SupabaseLeaveApprovalsScreen({super.key});
  @override
  State<SupabaseLeaveApprovalsScreen> createState() =>
      _SupabaseLeaveApprovalsScreenState();
}

class _SupabaseLeaveApprovalsScreenState
    extends State<SupabaseLeaveApprovalsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _manualReason = TextEditingController();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teacherDirectory = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _savingManual = false;
  bool _exporting = false;
  bool _manualHalfDay = false;
  String _manualLeaveType = 'પ્રાસંગિક રજા (CL)';
  String? _manualTeacherId;
  String? _error;
  String? _school;
  String? _teacher;
  DateTime _manualStart = DateTime.now();
  DateTime _manualEnd = DateTime.now();

  static const List<String> _manualLeaveTypes = <String>[
    'પ્રાસંગિક રજા (CL)',
    'મરજિયાત રજા',
    'વળતર રજા',
    'તબીબી રજા (ML)',
    'અર્ધ પગારી રજા (HPL)',
    'પ્રસુતિ રજા',
    'અન્ય',
  ];

  String _text(dynamic value, [String fallback = '']) {
    final valueText = (value ?? '').toString().trim();
    return valueText.isEmpty || valueText.toLowerCase() == 'null'
        ? fallback
        : valueText;
  }

  bool get _manualIsCl =>
      _manualLeaveType.toLowerCase().contains('(cl)') ||
      _manualLeaveType.contains('પ્રાસંગિક');
  double get _manualDays =>
      (_manualEnd.difference(_manualStart).inDays + 1).toDouble() -
      (_manualIsCl && _manualHalfDay ? 0.5 : 0);
  String _dateLabel(DateTime date) => _dateIso(date);

  List<Map<String, dynamic>> _rowsFromRpc(dynamic value) {
    dynamic current = value;
    if (current is String) {
      try {
        current = jsonDecode(current);
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    }
    if (current is Map) {
      final map = current.map((key, value) => MapEntry(key.toString(), value));
      if (map.containsKey('id') &&
          (map.containsKey('teacher_name') ||
              map.containsKey('teacherName') ||
              map.containsKey('name'))) {
        return <Map<String, dynamic>>[Map<String, dynamic>.from(map)];
      }
      for (final key in const [
        'teachers',
        'classes',
        'data',
        'result',
        'payload',
        'rows',
        'records',
        'psm_leave_teacher_roster_v2',
      ]) {
        final candidate = map[key];
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty || candidate is List && candidate.isEmpty)
            return parsed;
        }
      }
      for (final candidate in map.values) {
        if (candidate is List || candidate is String) {
          final parsed = _rowsFromRpc(candidate);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    }
    if (current is! List) return <Map<String, dynamic>>[];
    return current
        .whereType<Map>()
        .map(
          (row) => row
              .map(
                (key, value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              )
              .cast<String, dynamic>(),
        )
        .toList();
  }

  Map<String, dynamic> _leaveData(Map<String, dynamic> row) {
    final data = row['leave_data'];
    if (data is Map)
      return data
          .map((key, value) => MapEntry<String, dynamic>(key.toString(), value))
          .cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _teacherRow(String id) {
    for (final row in _teachers) {
      if (_text(row['id']) == id) return row;
    }
    return null;
  }

  String _teacherName(String id, [Map<String, dynamic>? row]) {
    final direct = row ?? _teacherRow(id);
    final directName = _text(
      direct?['teacher_name'] ?? direct?['teacherName'] ?? direct?['name'],
    );
    if (directName.isNotEmpty) return directName;
    for (final teacher in _teacherDirectory) {
      if (_text(teacher['id']) != id) continue;
      final name = _text(
        teacher['teacher_name'] ?? teacher['teacherName'] ?? teacher['name'],
      );
      if (name.isNotEmpty) return name;
    }
    return 'શિક્ષક';
  }

  String _applicationCreatedLabel(dynamic value) {
    final parsed = DateTime.tryParse(_text(value));
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} • $hour:$minute $ampm';
  }

  String _teacherClass(String id) {
    final labels = _classes
        .where(
          (row) =>
              _text(row['class_teacher_id']) == id &&
              _text(row['is_active'], 'true').toLowerCase() != 'false',
        )
        .map((row) => _text(row['label'], _text(row['class_key'], 'ધોરણ')))
        .where((value) => value.isNotEmpty)
        .toList();
    if (labels.isNotEmpty) return labels.join(' / ');
    final allowed = _teacherRow(id)?['allowed_classes'];
    if (allowed is List) {
      for (final item in allowed) {
        final value = _text(item);
        if (value.isEmpty) continue;
        Map<String, dynamic>? matched;
        for (final row in _classes) {
          if (_text(row['is_active'], 'true').toLowerCase() == 'false')
            continue;
          final tokens = <String>{
            _text(row['label']).toLowerCase(),
            _text(row['class_key']).toLowerCase(),
            _text(row['sheet_name']).toLowerCase(),
          };
          if (tokens.contains(value.toLowerCase())) {
            matched = row;
            break;
          }
        }
        final label = matched == null
            ? value
            : _text(matched['label'], _text(matched['class_key'], value));
        if (!labels.contains(label)) labels.add(label);
      }
    }
    return labels.isEmpty ? '—' : labels.join(' / ');
  }

  String _sourceLabel(Map<String, dynamic> row) =>
      _text(row['record_source'], 'teacher_application') == 'admin_manual'
      ? 'હસ્તલિખિત નોંધ (Admin દ્વારા)'
      : 'શિક્ષકની અરજી';

  String _statusLabel(String status) => switch (status.toLowerCase()) {
    'approved' => 'મંજૂર',
    'rejected' => 'નામંજૂર',
    'cancelled' => 'રદ',
    _ => 'મંજૂરી બાકી',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manualReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final school = await _schoolRef(_client);
      final teacher = await _teacherId(_client);
      final values = await _client
          .from('teacher_leaves')
          .select(
            'id,school_ref,teacher_id,start_date,end_date,leave_type,reason,status,decision_note,leave_data,record_source,recorded_by,created_at,updated_at',
          )
          .eq('school_ref', school)
          .order('created_at', ascending: false);
      List<Map<String, dynamic>> roster = <Map<String, dynamic>>[];
      try {
        roster = _rowsFromRpc(await _client.rpc('psm_leave_teacher_roster_v2'));
      } catch (_) {}
      if (roster.isEmpty) {
        try {
          roster = _rowsFromRpc(
            await _client.rpc('current_school_teacher_roster'),
          );
        } catch (_) {}
      }
      final classes = _rowsFromRpc(
        await _client.rpc('current_school_class_roster'),
      );
      List<Map<String, dynamic>> directory = <Map<String, dynamic>>[];
      try {
        directory = _rowsFromRpc(
          await _client.rpc('psm_leave_applicant_directory_v1'),
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _school = school;
        _teacher = teacher;
        _rows = values.map((row) => Map<String, dynamic>.from(row)).toList();
        _teachers = roster;
        _teacherDirectory = directory;
        _classes = classes;
        if (_manualTeacherId == null ||
            !_teachers.any((row) => _text(row['id']) == _manualTeacherId)) {
          _manualTeacherId = _teachers.isEmpty
              ? null
              : _text(_teachers.first['id']);
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _pickManualDate({required bool start}) async {
    final current = start ? _manualStart : _manualEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'રજા શરૂ થયાની તારીખ' : 'રજા પૂરી થયાની તારીખ',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _manualStart = picked;
        if (_manualEnd.isBefore(picked)) _manualEnd = picked;
      } else {
        _manualEnd = picked;
        if (picked.isBefore(_manualStart)) _manualStart = picked;
      }
    });
  }

  Future<void> _recordManualLeave() async {
    final school = _school;
    final teacherId = _manualTeacherId;
    if (school == null || teacherId == null || teacherId.isEmpty) {
      setState(() => _error = 'કૃપા કરીને શિક્ષક પસંદ કરો.');
      return;
    }
    if (_manualEnd.isBefore(_manualStart) || _manualDays <= 0) {
      setState(() => _error = 'રજાની તારીખ અથવા દિવસોની સંખ્યા યોગ્ય નથી.');
      return;
    }
    final teacherRow = _teacherRow(teacherId);
    final name = _teacherName(teacherId, teacherRow);
    final assignedClass = _teacherClass(teacherId);
    setState(() {
      _savingManual = true;
      _error = null;
    });
    try {
      await _client.from('teacher_leaves').insert(<String, dynamic>{
        'school_ref': school,
        'teacher_id': teacherId,
        'start_date': _dateLabel(_manualStart),
        'end_date': _dateLabel(_manualEnd),
        'leave_type': _manualLeaveType,
        'reason': _manualReason.text.trim().isEmpty
            ? 'હસ્તલિખિત રજા નોંધ મુજબ'
            : _manualReason.text.trim(),
        'status': 'approved',
        'decision_note': 'હસ્તલિખિત રજા રેકોર્ડ મુજબ Admin દ્વારા દાખલ',
        'record_source': 'admin_manual',
        'recorded_by': _teacher,
        'decided_by_teacher': _teacher,
        'leave_data': <String, dynamic>{
          'teacher_name': name,
          'teacher_class': assignedClass,
          'charge_teacher_name': '',
          'charge_teacher_class': '',
          'total_days': _manualDays,
          'half_day': _manualIsCl && _manualHalfDay,
          'half_day_period': '',
          'days_calculation': 'admin_manual_record',
          'reason_preset': 'હસ્તલિખિત નોંધ',
          'submitted_from': 'admin_manual_record',
          'admin_manual_record': true,
          'recorded_by_name': 'શાળા Admin',
        },
      });
      _manualReason.clear();
      if (mounted)
        setState(() {
          _manualHalfDay = false;
          _manualStart = DateTime.now();
          _manualEnd = DateTime.now();
        });
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('હસ્તલિખિત રજા રેકોર્ડમાં ઉમેરાઈ અને મંજૂર ગણાઈ.'),
          ),
        );
    } catch (error) {
      if (mounted)
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingManual = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final workbook = ec.Excel.createExcel();
      final sheet = workbook['Sheet1'];
      const headers = <String>[
        'Teacher Name',
        'Assigned Class',
        'Leave Type',
        'From Date',
        'To Date',
        'Total Days',
        'Reason',
        'Status',
        'Record Source',
        'Recorded By',
        'Decision Note',
        'Created At',
      ];
      for (var column = 0; column < headers.length; column++) {
        _putText(sheet, 0, column, headers[column]);
      }
      for (var i = 0; i < _rows.length; i++) {
        final row = _rows[i];
        final data = _leaveData(row);
        final teacherId = _text(row['teacher_id']);
        final fields = <String>[
          _text(data['teacher_name'], _teacherName(teacherId)),
          _teacherClass(teacherId) == '—'
              ? _text(data['teacher_class'], '—')
              : _teacherClass(teacherId),
          _text(row['leave_type']),
          _text(row['start_date']),
          _text(row['end_date']),
          SupabaseLeavePdfService.totalDays(row).toString(),
          _text(row['reason']),
          _statusLabel(_text(row['status'], 'pending')),
          _sourceLabel(row),
          _text(data['recorded_by_name'], _text(row['recorded_by'])),
          _text(row['decision_note']),
          _text(row['created_at']),
        ];
        for (var column = 0; column < fields.length; column++) {
          _putText(sheet, i + 1, column, fields[column]);
        }
      }
      final bytes = workbook.encode(); // encode(): no extra auto-download on web
      if (bytes == null) throw StateError('Excel workbook બનાવી શકાયો નથી.');
      await _shareXlsx(
        bytes,
        'School_Leave_Register_${_dateIso(DateTime.now())}.xlsx',
        context,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_rows.length} રજા રેકોર્ડ Excel માં ઉમેર્યા.'),
          ),
        );
    } catch (error) {
      if (mounted)
        setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> row, String status) async {
    String note = '${row['decision_note'] ?? ''}';
    if (status == 'rejected') {
      final controller = TextEditingController(text: note);
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('રજા અરજી નામંજૂર કરો'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'કારણ / નોંધ (વૈકલ્પિક)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('રદ કરો'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('નામંજૂર કરો'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null) return;
      note = result;
    }
    try {
      await _client
          .from('teacher_leaves')
          .update(<String, dynamic>{
            'status': status,
            'decision_note': note,
            'decided_by_teacher': _teacher,
            'teacher_decision_notified': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('school_ref', _school ?? await _schoolRef(_client))
          .eq('id', '${row['id']}');
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved' ? 'રજા મંજૂર કરી.' : 'રજા નામંજૂર કરી.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      await _showError(context, error);
    }
  }

  Future<void> _deleteLeaveWithAdminPassword(Map<String, dynamic> row) async {
    final leaveId = _text(row['id']);
    if (leaveId.isEmpty) return;
    final data = _leaveData(row);
    final teacherName = _text(
      data['teacher_name'],
      _teacherName(_text(row['teacher_id'])),
    );
    final leaveType = _text(row['leave_type'], 'રજા');
    final startDate = _text(row['start_date']);
    final endDate = _text(row['end_date'], startDate);
    final days = SupabaseLeavePdfService.totalDays(row);
    final statusText = _statusLabel(_text(row['status'], 'pending'));

    final pwdCtrl = TextEditingController();
    var obscure = true;
    var submitting = false;
    String? dialogError;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> confirmDelete() async {
            final pwd = pwdCtrl.text.trim();
            if (pwd.isEmpty) {
              setDialogState(
                () => dialogError = 'કૃપા કરીને School Admin પાસવર્ડ દાખલ કરો.',
              );
              return;
            }
            setDialogState(() {
              submitting = true;
              dialogError = null;
            });
            try {
              await _client.rpc(
                'psm_admin_delete_leave_with_password',
                params: <String, dynamic>{
                  'p_leave_id': leaveId,
                  'p_admin_password': pwd,
                },
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            } catch (e) {
              setDialogState(() {
                submitting = false;
                dialogError = '$e'
                    .replaceFirst('Exception: ', '')
                    .replaceFirst('Bad state: ', '');
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('રજા રેકોર્ડ કાયમ માટે કાઢી નાખવો?'),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'શિક્ષક: $teacherName\n'
                      'રજા: $leaveType ($statusText)\n'
                      'તારીખ: $startDate થી $endDate ($days દિવસ)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        '⚠️ મહત્વપૂર્ણ ચેતવણી (Important Warning):\n'
                        '• આ રજા તમામ રેકોર્ડ અને રિપોર્ટમાંથી કાયમ માટે દૂર થશે.\n'
                        '• આ રજા શિક્ષકની વપરાયેલી રજા (Utilised Leave — C.L. / મરજિયાત / વળતર) માંથી પણ બાદ થઈ જશે (એટલે કે વપરાયેલી રજામાં ગણાશે નહીં).\n'
                        '• આ ક્રિયા પાછી ફેરવી શકાશે નહીં.',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: obscure,
                      autofocus: true,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'School Admin પાસવર્ડ દાખલ કરો',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: dialogError,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => confirmDelete(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('રદ કરો'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting ? null : confirmDelete,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: Text(
                  submitting ? 'કાઢી રહ્યું છે…' : 'પાસવર્ડથી રજા કાઢી નાખો',
                ),
              ),
            ],
          );
        },
      ),
    );
    pwdCtrl.dispose();
    if (deleted == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'રજાનો રેકોર્ડ તમામ રજીસ્ટર અને વપરાયેલી રજામાંથી કાયમ માટે કાઢી નાખવામાં આવ્યો છે.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
        appBar: AppBar(title: const Text('રજા મંજૂરી')),
        body: const Center(child: CircularProgressIndicator()),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('રજા મંજૂરી અને રેકોર્ડ / Leave Register'),
        actions: [
          IconButton(
            tooltip: 'Leave PDF Report',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SupabaseLeaveReportPdfScreen(),
              ),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'આ શાળાની રજા અરજીઓ અહીં મંજૂર અથવા નામંજૂર કરો. હસ્તલિખિત રજાનો રેકોર્ડ ઉમેરવાથી તે મંજૂર વપરાયેલી રજા તરીકે ગણાશે.',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _exporting ? null : _exportExcel,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(
                _exporting
                    ? 'Excel બનાવે છે…'
                    : 'તમામ રજા રેકોર્ડ Excel માં ડાઉનલોડ કરો',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('હસ્તલિખિત / અગાઉની રજા ઉમેરો'),
              subtitle: const Text(
                'આ નોંધ મંજૂર થયેલી અને વપરાયેલી રજા તરીકે ગણાશે.',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _manualTeacherId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'શિક્ષકનું નામ',
                          border: OutlineInputBorder(),
                        ),
                        items: _teachers
                            .map(
                              (row) => DropdownMenuItem<String>(
                                value: _text(row['id']),
                                child: Text(
                                  '${_teacherName(_text(row['id']), row)} • ${_teacherClass(_text(row['id']))}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _manualTeacherId = value),
                      ),
                      const SizedBox(height: 8),
                      if (_manualTeacherId != null)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'ફાળવેલ ધોરણ (ઓટોમેટિક)',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(_teacherClass(_manualTeacherId!)),
                        ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _manualLeaveType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'રજાનો પ્રકાર',
                          border: OutlineInputBorder(),
                        ),
                        items: _manualLeaveTypes
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null)
                            setState(() {
                              _manualLeaveType = value;
                              if (!_manualIsCl) _manualHalfDay = false;
                            });
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickManualDate(start: true),
                            icon: const Icon(Icons.calendar_month),
                            label: Text('થી: ${_dateLabel(_manualStart)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pickManualDate(start: false),
                            icon: const Icon(Icons.calendar_month),
                            label: Text('સુધી: ${_dateLabel(_manualEnd)}'),
                          ),
                        ],
                      ),
                      if (_manualIsCl)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('અડધી C.L. (0.5 દિવસ ઓછા)'),
                          value: _manualHalfDay,
                          onChanged: (value) =>
                              setState(() => _manualHalfDay = value),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(
                          'કુલ દિવસ: ${_manualDays > 0 ? _manualDays.toStringAsFixed(_manualDays % 1 == 0 ? 0 : 1) : '0'}',
                        ),
                        subtitle: const Text('મંજૂર થયેલી વપરાયેલી રજા ગણાશે.'),
                      ),
                      TextField(
                        controller: _manualReason,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'નોંધ / હસ્તલિખિત રજાનું કારણ',
                          hintText: 'રજાના રેકોર્ડ મુજબ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _savingManual ? null : _recordManualLeave,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _savingManual
                              ? 'રેકોર્ડ સાચવે છે…'
                              : 'હસ્તલિખિત રજા રેકોર્ડ સાચવો',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('હજુ કોઈ રજા રેકોર્ડ ઉપલબ્ધ નથી.'),
              ),
            ),
          for (final row in _rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_note_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_text(row['leave_type'], 'રજા')}  |  ${_statusLabel(_text(row['status'], 'pending'))}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'અરજદાર શિક્ષક: ${_text(_leaveData(row)['teacher_name'], _teacherName(_text(row['teacher_id'])))}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (_applicationCreatedLabel(row['created_at']).isNotEmpty)
                      Text(
                        'અરજી તારીખ અને સમય: ${_applicationCreatedLabel(row['created_at'])}',
                      ),
                    Text(
                      'ધોરણ: ${ClassLabel.bare(_teacherClass(_text(row['teacher_id'])) == '—' ? _text(_leaveData(row)['teacher_class'], '—') : _teacherClass(_text(row['teacher_id'])))}',
                    ),
                    Text(
                      'રજાની તારીખ: ${row['start_date']} થી ${row['end_date']} • ${SupabaseLeavePdfService.totalDays(row)} દિવસ',
                    ),
                    Text('કારણ: ${_text(row['reason'], '—')}'),
                    Text(
                      _sourceLabel(row),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                    if (_text(row['decision_note']).isNotEmpty)
                      Text('નોંધ: ${row['decision_note']}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_text(row['status'], 'pending') == 'pending') ...[
                          FilledButton.icon(
                            onPressed: () => _decide(row, 'approved'),
                            icon: const Icon(Icons.check),
                            label: const Text('મંજૂર કરો'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _decide(row, 'rejected'),
                            icon: const Icon(Icons.close),
                            label: const Text('નામંજૂર કરો'),
                          ),
                        ],
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                          onPressed: () => _deleteLeaveWithAdminPassword(row),
                          icon: const Icon(Icons.delete_forever_outlined, size: 18),
                          label: const Text('રજા કાઢી નાખો (Delete)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportField {
  const _ExportField(this.key, this.label, {this.private = false});
  final String key;
  final String label;
  final bool private;
}

const List<_ExportField> _baseExportFields = <_ExportField>[
  _ExportField('class_label', 'Class'),
  _ExportField('roll_number', 'Roll Number'),
  _ExportField('gr', 'GR Number'),
  _ExportField('name', 'Student Name (Gujarati)'),
  _ExportField('name_en', 'Student Name (English)'),
  _ExportField('father_name', 'Father Name'),
  _ExportField('mother_name', 'Mother Name'),
  _ExportField('category', 'Category'),
  _ExportField('category_en', 'Category (English)'),
  _ExportField('gender', 'Gender'),
  _ExportField('religion', 'ધર્મ / Religion (Gujarati)'),
  _ExportField('religion_en', 'RELIGION IN ENGLISH'),
  _ExportField('caste', 'Caste / Sub-caste'),
  _ExportField('caste_en', 'Caste (English)'),
  _ExportField('dd', 'DOB Day'),
  _ExportField('mm', 'DOB Month'),
  _ExportField('yyyy', 'DOB Year'),
  _ExportField('mobile', 'Mobile'),
  _ExportField('address', 'Address'),
  _ExportField('birth_place', 'Birth Place'),
  _ExportField('birth_place_en', 'Birth Place (English)'),
  _ExportField('native_place', 'Native Place (વતન)'),
  _ExportField('native_place_en', 'Native Place (English)'),
  _ExportField('dob_words', 'DOB in Words (Gujarati)'),
  _ExportField('dob_en', 'DOB in Words (English)'),
  _ExportField('enroll_school', 'Enrollment School'),
  _ExportField('enroll_class', 'Enrollment Class'),
  _ExportField('last_school', 'Last School'),
  _ExportField('last_school_en', 'Last School (English)'),
  _ExportField('enroll_sch_class', 'Admission Class'),
  _ExportField('enroll_sch_class_words', 'Admission Class in Words'),
  _ExportField('enroll_sch_class_en', 'Admission Class (English)'),
  _ExportField('enroll_sch_class_words_en', 'Admission Class Words (English)'),
  _ExportField('uid', 'UID'),
  _ExportField('pen', 'PEN'),
  _ExportField('apaar_id', 'APAAR ID'),
  _ExportField('present_days', 'Present Days'),
  _ExportField('has_aadhaar', 'Has Student Aadhaar (YES/NO)'),
  _ExportField('ration_card_kyc', 'Ration Card KYC (YES/NO)'),
  _ExportField('scholarship_done', 'Scholarship Done (YES/NO)'),
  _ExportField('scholarship_reason', 'Scholarship Reason (શિષ્યવૃત્તિ બાકી કારણ)'),
  _ExportField('scholarship_other', 'Other Scholarship'),
  _ExportField('bank_name', 'Bank Name', private: true),
  _ExportField('bank_branch', 'Bank Branch', private: true),
  _ExportField('name_as_passbook', 'Name as per Passbook', private: true),
  _ExportField('account_number', 'Bank Account Number', private: true),
  _ExportField('ifsc_code', 'IFSC Code', private: true),
  _ExportField('is_active', 'Active'),
  _ExportField('exit_date', 'Exit Date'),
  _ExportField('exit_reason', 'Exit Reason'),
];

class SupabaseSchoolDataExportScreen extends StatefulWidget {
  const SupabaseSchoolDataExportScreen({super.key});
  @override
  State<SupabaseSchoolDataExportScreen> createState() =>
      _SupabaseSchoolDataExportScreenState();
}

class _SupabaseSchoolDataExportScreenState
    extends State<SupabaseSchoolDataExportScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<String> _customHeaders = List<String>.filled(11, '');
  final Set<String> _selected = <String>{
    'class_label',
    'roll_number',
    'gr',
    'name',
    'father_name',
    'category',
    'gender',
    'mobile',
    'has_aadhaar',
    'ration_card_kyc',
    'scholarship_done',
    'scholarship_reason',
  };
  bool _all = false;
  bool _includeArchived = false;
  String _categoryFilter = 'ALL'; // 'ALL', 'CATEGORY_WISE_SHEETS', 'SC', 'ST', 'OBC', 'OTHER'
  String _scholarshipFilter = 'ALL'; // 'ALL', 'NO_WITH_REASON', 'YES_ONLY'
  int _activeCount = 0;
  int _archivedCount = 0;
  String _schoolRefId = '';
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  List<_ExportField> get _fields => <_ExportField>[
    ..._baseExportFields,
    for (var i = 0; i < 11; i++)
      _ExportField(
        'c${i + 1}',
        _customHeaders.length > i && _customHeaders[i].trim().isNotEmpty
            ? _customHeaders[i].trim()
            : 'Custom Field ${i + 1}',
      ),
  ];

  @override
  void initState() {
    super.initState();
    _loadHeaders();
  }

  Future<void> _loadHeaders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      _schoolRefId = school;
      final allSt = await _client
          .from('students')
          .select('id,is_active,leaving_date,exit_date')
          .eq('school_ref', school);
      var act = 0;
      var arch = 0;
      for (final s in allSt) {
        final isAct = s['is_active'] == true &&
            '${s['leaving_date'] ?? ''}'.trim().isEmpty &&
            '${s['exit_date'] ?? ''}'.trim().isEmpty;
        if (isAct) {
          act++;
        } else {
          arch++;
        }
      }
      _activeCount = act;
      _archivedCount = arch;
      final row = await _client
          .from('school_custom_headers')
          .select('headers')
          .eq('school_ref', school)
          .maybeSingle();
      final raw = row?['headers'];
      if (raw is List)
        _customHeaders = List<String>.generate(
          11,
          (i) => i < raw.length ? '${raw[i] ?? ''}' : '',
        );
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  /// Adds an attendance-derived Present Days value without trusting the
  /// manually populated students.present_days field. If the class has no
  /// attendance history, or even one saved day uses Direct Entry/incomplete
  /// individual marks, leave Present Days blank for students in that class.
  Future<void> _populatePresentDays(
    List<Map<String, dynamic>> students,
    String school,
  ) async {
    for (final student in students) {
      student['present_days'] = '';
    }
    final classIds = students
        .map((row) => '${row['class_id'] ?? ''}'.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (classIds.isEmpty) return;

    final allDays = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('attendance_days')
          .select(
            'id,class_id,attendance_mode,student_details_saved,attendance_date',
          )
          .eq('school_ref', school)
          .inFilter('class_id', classIds.toList())
          .order('attendance_date')
          .range(offset, offset + 999);
      allDays.addAll(page.map((row) => Map<String, dynamic>.from(row)));
      if (page.length < 1000) break;
      offset += 1000;
    }
    if (allDays.isEmpty) return;

    final hasDays = <String>{};
    final allDaysAreIndividual = <String, bool>{};
    for (final day in allDays) {
      final classId = '${day['class_id'] ?? ''}';
      if (classId.isEmpty) continue;
      hasDays.add(classId);
      final individual =
          '${day['attendance_mode'] ?? ''}'.toLowerCase() == 'student' &&
          day['student_details_saved'] == true;
      allDaysAreIndividual[classId] =
          (allDaysAreIndividual[classId] ?? true) && individual;
    }
    final completeClasses = classIds
        .where(
          (classId) =>
              hasDays.contains(classId) &&
              allDaysAreIndividual[classId] == true,
        )
        .toSet();
    if (completeClasses.isEmpty) return;

    final dayIds = allDays
        .where((day) => completeClasses.contains('${day['class_id'] ?? ''}'))
        .map((day) => '${day['id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList();
    final presentDaysByStudent = <String, int>{};
    // Keep each IN filter short; page each result so large schools are not
    // truncated at the normal PostgREST row limit.
    for (var start = 0; start < dayIds.length; start += 100) {
      final chunk = dayIds.sublist(
        start,
        start + 100 > dayIds.length ? dayIds.length : start + 100,
      );
      var markOffset = 0;
      while (true) {
        final page = await _client
            .from('student_attendance')
            .select('student_id,present')
            .eq('school_ref', school)
            .inFilter('attendance_day_id', chunk)
            .range(markOffset, markOffset + 999);
        for (final row in page) {
          if (row['present'] == true) {
            final id = '${row['student_id'] ?? ''}';
            if (id.isNotEmpty)
              presentDaysByStudent[id] = (presentDaysByStudent[id] ?? 0) + 1;
          }
        }
        if (page.length < 1000) break;
        markOffset += 1000;
      }
    }

    for (final student in students) {
      final classId = '${student['class_id'] ?? ''}';
      final studentId = '${student['id'] ?? ''}';
      if (completeClasses.contains(classId)) {
        student['present_days'] = presentDaysByStudent[studentId] ?? 0;
      }
    }
  }

  Future<void> _export() async {
    if (_selected.isEmpty && !_all) {
      setState(
        () => _error = 'Select at least one header, or choose All Headers.',
      );
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final studentsRaw = await _client
          .from('students')
          .select('*')
          .eq('school_ref', school)
          .order('class_id')
          .order('roll_number');
      var students = studentsRaw
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => _includeArchived || row['is_active'] == true)
          .toList();
      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order')
          .eq('school_ref', school)
          .order('sort_order');
      final classLabels = <String, String>{
        for (final row in classRows)
          '${row['id']}': '${row['label'] ?? row['class_key'] ?? ''}',
      };
      final classPositions = <String, int>{
        for (var i = 0; i < classRows.length; i++) '${classRows[i]['id']}': i,
      };
      students.sort((a, b) {
        final classCompare = (classPositions['${a['class_id']}'] ?? 999999)
            .compareTo(classPositions['${b['class_id']}'] ?? 999999);
        if (classCompare != 0) return classCompare;
        final rawA = '${a['roll_number'] ?? ''}'.trim();
        final rawB = '${b['roll_number'] ?? ''}'.trim();
        final rollA = int.tryParse(rawA);
        final rollB = int.tryParse(rawB);
        if (rollA != null && rollB != null) {
          final numericCompare = rollA.compareTo(rollB);
          if (numericCompare != 0) return numericCompare;
        } else if (rollA != null) {
          return -1;
        } else if (rollB != null) {
          return 1;
        }
        return rawA.toLowerCase().compareTo(rawB.toLowerCase());
      });
      for (final student in students) {
        final custom = student['custom_fields'];
        if (custom is Map)
          student.addAll(custom.map((k, v) => MapEntry('$k', v)));
        student['class_label'] = classLabels['${student['class_id']}'] ?? '';
      }
      await _populatePresentDays(students, school);
      final selectedFields = _fields
          .where((field) => _all || _selected.contains(field.key))
          .toList();
      final needPrivate = selectedFields.any((field) => field.private);
      if (needPrivate && students.isNotEmpty) {
        final ids = students
            .map((row) => '${row['id'] ?? ''}')
            .where((v) => v.isNotEmpty)
            .toList();
        final privateRows = await _client
            .from('student_private_details')
            .select('*')
            .eq('school_ref', school)
            .inFilter('student_id', ids);
        final privateById = <String, Map<String, dynamic>>{
          for (final row in privateRows)
            '${row['student_id']}': Map<String, dynamic>.from(row),
        };
        for (final student in students) {
          final private = privateById['${student['id']}'];
          if (private != null) student.addAll(private);
        }
      }
      bool isScholarshipYes(Map<String, dynamic> st) {
        final raw = '${st['scholarship_done'] ?? ''}'.trim().toUpperCase();
        return const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(raw) ||
            raw.startsWith('YES') ||
            raw.startsWith('હા');
      }

      String normCategory(Map<String, dynamic> st) {
        final raw = '${st['category'] ?? 'OTHER'}'.trim().toUpperCase();
        if (raw == 'SC' || raw.contains('અ.જા')) return 'SC';
        if (raw == 'ST' || raw.contains('અ.જ.જા')) return 'ST';
        if (raw == 'OBC' || raw.contains('બક્ષી')) return 'OBC';
        return 'OTHER';
      }

      for (final st in students) {
        final schYes = isScholarshipYes(st);
        st['scholarship_done'] = schYes ? 'YES' : 'NO';
        if (schYes) {
          st['scholarship_reason'] = '';
        }
        final aadhaarRaw = '${st['has_aadhaar'] ?? ''}'.trim().toUpperCase();
        st['has_aadhaar'] =
            (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(aadhaarRaw) ||
                    aadhaarRaw.startsWith('YES') ||
                    aadhaarRaw.startsWith('હા'))
                ? 'YES'
                : 'NO';
        final kycRaw = '${st['ration_card_kyc'] ?? ''}'.trim().toUpperCase();
        st['ration_card_kyc'] =
            (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(kycRaw) ||
                    kycRaw.startsWith('YES') ||
                    kycRaw.startsWith('હા'))
                ? 'YES'
                : 'NO';
        st['category'] = normCategory(st);
      }

      // Apply Scholarship filter
      if (_scholarshipFilter == 'NO_WITH_REASON') {
        students = students.where((st) => st['scholarship_done'] == 'NO').toList();
        for (final reqKey in const <String>[
          'category',
          'scholarship_done',
          'scholarship_reason',
        ]) {
          if (!selectedFields.any((f) => f.key == reqKey)) {
            final match = _fields.where((f) => f.key == reqKey);
            if (match.isNotEmpty) selectedFields.add(match.first);
          }
        }
      } else if (_scholarshipFilter == 'YES_ONLY') {
        students = students.where((st) => st['scholarship_done'] == 'YES').toList();
      }

      // Apply Category filter
      if (const <String>{'SC', 'ST', 'OBC', 'OTHER'}.contains(_categoryFilter)) {
        students = students
            .where((st) => normCategory(st) == _categoryFilter)
            .toList();
      } else if (_categoryFilter == 'CATEGORY_WISE_SHEETS' ||
          _scholarshipFilter == 'NO_WITH_REASON') {
        const catOrder = <String, int>{'SC': 0, 'ST': 1, 'OBC': 2, 'OTHER': 3};
        students.sort((a, b) {
          final ca = catOrder[normCategory(a)] ?? 9;
          final cb = catOrder[normCategory(b)] ?? 9;
          if (ca != cb) return ca.compareTo(cb);
          final classCompare = (classPositions['${a['class_id']}'] ?? 999999)
              .compareTo(classPositions['${b['class_id']}'] ?? 999999);
          if (classCompare != 0) return classCompare;
          final rollA = int.tryParse('${a['roll_number'] ?? ''}'.trim()) ?? 9999;
          final rollB = int.tryParse('${b['roll_number'] ?? ''}'.trim()) ?? 9999;
          return rollA.compareTo(rollB);
        });
      }

      void writeStudentSheet(ec.Sheet targetSheet, List<Map<String, dynamic>> rowsToWrite) {
        for (var col = 0; col < selectedFields.length; col++) {
          _putText(targetSheet, 0, col, selectedFields[col].label);
        }
        for (var row = 0; row < rowsToWrite.length; row++) {
          final student = rowsToWrite[row];
          for (var col = 0; col < selectedFields.length; col++) {
            final value = student[selectedFields[col].key];
            _putText(
              targetSheet,
              row + 1,
              col,
              value is bool ? (value ? 'YES' : 'NO') : '${value ?? ''}',
            );
          }
        }
      }

      final workbook = ec.Excel.createExcel();
      final mainSheetName = _scholarshipFilter == 'NO_WITH_REASON'
          ? 'Scholarship_Pending_All'
          : 'All_Students';
      workbook.rename('Sheet1', mainSheetName);
      writeStudentSheet(workbook[mainSheetName], students);

      if (_categoryFilter == 'CATEGORY_WISE_SHEETS' ||
          _scholarshipFilter == 'NO_WITH_REASON') {
        for (final cat in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
          final catRows = students.where((s) => normCategory(s) == cat).toList();
          if (catRows.isNotEmpty) {
            writeStudentSheet(workbook['Category_$cat'], catRows);
          }
        }
      }

      final bytes = workbook.encode(); // encode(): no extra auto-download on web
      if (bytes == null) throw StateError('Could not create student workbook.');
      final filePrefix = _scholarshipFilter == 'NO_WITH_REASON'
          ? 'Scholarship_Pending_With_Reason_${_categoryFilter}_'
          : (_categoryFilter != 'ALL'
              ? 'Whole_School_Students_${_categoryFilter}_'
              : 'Whole_School_Students_');
      if (!mounted) return;
      await _shareXlsx(
        bytes,
        '$filePrefix${_dateIso(DateTime.now())}.xlsx',
        context,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${students.length} student records with ${selectedFields.length} headers.',
            ),
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
        appBar: AppBar(title: Text('Whole-school Student Export')),
        body: Center(child: CircularProgressIndicator()),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whole-school Student Export / વિદ્યાર્થી ડેટા'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_archivedCount > 0)
            Card(
              color: Colors.amber.shade50,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'સક્રિય વિદ્યાર્થીઓ: $_activeCount  •  આર્કાઇવ / ગાયબ વિદ્યાર્થીઓ: $_archivedCount',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ArchivedStudentsScreen(
                                  schoolRef: _schoolRefId,
                                  classId: '',
                                  classLabel: 'સમગ્ર શાળા (All Classes)',
                                ),
                              ),
                            );
                            if (mounted) await _loadHeaders();
                          },
                          icon: const Icon(Icons.restore),
                          label: Text('આર્કાઇવ થયેલા $_archivedCount વિદ્યાર્થીઓ જુઓ / પાછા સક્રિય કરો'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Card(
            color: Colors.indigo.shade50,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'રિપોર્ટ ફિલ્ટર — કેટેગરી અને શિષ્યવૃત્તિ (Category-wise & Scholarship YES/NO with Reason)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _categoryFilter,
                          decoration: const InputDecoration(
                            labelText: 'કેટેગરી વિકલ્પ (Category Option)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'ALL',
                              child: Text('તમામ કેટેગરી (All Categories)'),
                            ),
                            DropdownMenuItem(
                              value: 'CATEGORY_WISE_SHEETS',
                              child: Text('કેટેગરી મુજબ અલગ Sheet (Category-wise SC/ST/OBC/OTHER)'),
                            ),
                            DropdownMenuItem(
                              value: 'SC',
                              child: Text('ફક્ત અ. જા. (SC Only)'),
                            ),
                            DropdownMenuItem(
                              value: 'ST',
                              child: Text('ફક્ત અ. જ. જા. (ST Only)'),
                            ),
                            DropdownMenuItem(
                              value: 'OBC',
                              child: Text('ફક્ત બક્ષીપંચ (OBC Only)'),
                            ),
                            DropdownMenuItem(
                              value: 'OTHER',
                              child: Text('ફક્ત અન્ય / General (OTHER Only)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _categoryFilter = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _scholarshipFilter,
                          decoration: const InputDecoration(
                            labelText: 'શિષ્યવૃત્તિ વિકલ્પ (Scholarship Option)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'ALL',
                              child: Text('તમામ વિદ્યાર્થીઓ (All Students)'),
                            ),
                            DropdownMenuItem(
                              value: 'NO_WITH_REASON',
                              child: Text('માત્ર શિષ્યવૃત્તિ બાકી (NO) — કારણ સાથે (Not Done with Reason)'),
                            ),
                            DropdownMenuItem(
                              value: 'YES_ONLY',
                              child: Text('માત્ર શિષ્યવૃત્તિ થયેલ (Only Scholarship YES)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _scholarshipFilter = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _exporting
                        ? null
                        : () {
                            setState(() {
                              _scholarshipFilter = 'NO_WITH_REASON';
                              if (_categoryFilter == 'ALL') {
                                _categoryFilter = 'CATEGORY_WISE_SHEETS';
                              }
                              _selected.addAll(const <String>[
                                'class_label',
                                'roll_number',
                                'gr',
                                'name',
                                'father_name',
                                'category',
                                'gender',
                                'mobile',
                                'has_aadhaar',
                                'ration_card_kyc',
                                'scholarship_done',
                                'scholarship_reason',
                              ]);
                            });
                            _export();
                          },
                    icon: const Icon(Icons.assignment_late_outlined),
                    label: const Text(
                      'શિષ્યવૃત્તિ બાકી (NO) વિદ્યાર્થીઓનો કેટેગરી મુજબ કારણ સાથે રિપોર્ટ ડાઉનલોડ કરો',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeArchived,
            onChanged: (v) => setState(() => _includeArchived = v),
            title: Text(
              'નિષ્ક્રિય (Deactive) થયેલા વિદ્યાર્થીઓ પણ Export માં સામેલ કરો (Include $_archivedCount Deactive Students)',
            ),
          ),
          const Text(
            'Choose the fields to include in the Excel file. Includes Has Student Aadhaar (YES/NO), Ration Card KYC (YES/NO), Scholarship Done (YES/NO), and Scholarship Reason.',
          ),
          CheckboxListTile(
            value: _all,
            onChanged: (value) => setState(() {
              _all = value ?? false;
              if (_all) {
                _selected.addAll(_fields.map((f) => f.key));
              } else {
                _selected.clear();
              }
            }),
            title: const Text('All Headers / બધા હેડર'),
            subtitle: const Text(
              'Select every available student column, including custom headers and private fields.',
            ),
          ),
          const Divider(),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _all = true;
                  _selected.addAll(_fields.map((f) => f.key));
                }),
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _all = false;
                  _selected.clear();
                }),
                child: const Text('Clear selection'),
              ),
              TextButton(
                onPressed: _loadHeaders,
                child: const Text('Reload headers'),
              ),
            ],
          ),
          for (final field in _fields)
            CheckboxListTile(
              dense: true,
              value: _all || _selected.contains(field.key),
              onChanged: _all
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selected.add(field.key);
                      } else {
                        _selected.remove(field.key);
                      }
                    }),
              title: Text(field.label),
              subtitle: field.private
                  ? const Text('Private identifier or bank data')
                  : null,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(
              _exporting ? 'Exporting...' : 'Export Whole School Excel',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _exporting
                ? null
                : () async {
                    final school = await _schoolRef(_client);
                    final sRow = await _client
                        .from('schools')
                        .select('school_type')
                        .eq('id', school)
                        .maybeSingle();
                    final sType = '${sRow?['school_type'] ?? 'mixed'}';
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StudentBulkImportScreen(
                          classId: '',
                          classLabel: 'સમગ્ર શાળા (All Classes / Whole School)',
                          schoolType: sType,
                        ),
                      ),
                    );
                    if (mounted) await _loadHeaders();
                  },
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text(
              'Import Whole-School / Partial-Column Excel (GR મુજબ અપલોડ)',
            ),
          ),
        ],
      ),
    );
  }
}

class SupabaseCustomHeadersScreen extends StatefulWidget {
  const SupabaseCustomHeadersScreen({super.key});
  @override
  State<SupabaseCustomHeadersScreen> createState() =>
      _SupabaseCustomHeadersScreenState();
}

class _SupabaseCustomHeadersScreenState
    extends State<SupabaseCustomHeadersScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(11, (_) => TextEditingController());
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final row = await _client
          .from('school_custom_headers')
          .select('headers')
          .eq('school_ref', school)
          .maybeSingle();
      final raw = row?['headers'];
      if (raw is List) {
        for (var i = 0; i < 11; i++)
          _controllers[i].text = i < raw.length ? '${raw[i] ?? ''}' : '';
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final headers = _controllers.map((c) => c.text.trim()).toList();
      if (headers.any((v) => v.length > 80))
        throw StateError('Each custom header must be 80 characters or fewer.');
      await _client.from('school_custom_headers').upsert(<String, dynamic>{
        'school_ref': school,
        'headers': headers,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Custom headers saved. Student forms and exports use these labels on next load.',
            ),
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Custom Headers / કસ્ટમ હેડર',
        style: const TextStyle(fontFamily: 'NotoSansGujaratiLocal'),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Set up to 11 additional student data fields. The label is stored separately from its stable field position, so renaming a label does not move existing data.',
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < 11; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[i],
                    maxLength: 80,
                    style: const TextStyle(fontFamily: 'NotoSansGujaratiLocal'),
                    decoration: InputDecoration(
                      labelText: 'Custom Header ${i + 1}',
                      labelStyle: const TextStyle(
                        fontFamily: 'NotoSansGujaratiLocal',
                      ),
                      hintText: 'Leave blank to show Custom Field ${i + 1}',
                      hintStyle: const TextStyle(
                        fontFamily: 'NotoSansGujaratiLocal',
                      ),
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save Custom Headers'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload saved headers'),
              ),
            ],
          ),
  );
}


class SupabaseAttendancePermissionScreen extends StatelessWidget {
  const SupabaseAttendancePermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Teacher Attendance Permission / હાજરી પૂરવાની પરવાનગી',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SupabaseAttendancePermissionControlCard(),
        ],
      ),
    );
  }
}

class SupabaseAttendancePermissionControlCard extends StatefulWidget {
  const SupabaseAttendancePermissionControlCard({super.key});

  @override
  State<SupabaseAttendancePermissionControlCard> createState() =>
      _SupabaseAttendancePermissionControlCardState();
}

class _SupabaseAttendancePermissionControlCardState
    extends State<SupabaseAttendancePermissionControlCard> {
  final SupabaseClient _client = Supabase.instance.client;
  String _permissionMode = 'subject_and_class_teachers';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const List<(String, String, String, bool)> _modes =
      <(String, String, String, bool)>[
    (
      'only_class_teacher',
      '1️⃣ માત્ર વર્ગ શિક્ષક જ હાજરી પૂરી શકે (Only Class Teacher)',
      'જે વર્ગના વર્ગ શિક્ષક (Class Teacher) તરીકે નિમણૂક થઈ હોય માત્ર તે જ શિક્ષક પોતાના વર્ગની હાજરી (PM POSHAN અને અલ્પાહાર સાથે) પૂરી શકશે. (રજા દરમિયાન ચાર્જ સંભાળનાર ઇન્ચાર્જ શિક્ષક માત્ર રજાના દિવસો પૂરતી હાજરી પૂરી શકશે).',
      true,
    ),
    (
      'section_wise_class_teachers',
      '2️⃣ ધોરણના બધા વિભાગના વર્ગ શિક્ષકો (Section-Wise Class Teachers: 6A, 6B, 6C...)',
      'એક જ ધોરણના કોઈપણ વિભાગના વર્ગ શિક્ષક તે ધોરણના તમામ વિભાગોની હાજરી પૂરી શકશે — દા.ત. ધોરણ 6A ના વર્ગ શિક્ષક ધોરણ 6A, 6B, 6C, 6D... ની હાજરી પૂરી શકશે અને ધોરણ 6B ના વર્ગ શિક્ષક પણ 6A, 6B, 6C, 6D... ની હાજરી પૂરી શકશે. (રજા દરમિયાન ચાર્જ શિક્ષક પર પણ આ નિયમ લાગુ પડશે).',
      true,
    ),
    (
      'subject_and_class_teachers',
      '3️⃣ વિષય શિક્ષક + વિભાગ વર્ગ શિક્ષક + વર્ગ શિક્ષક (Subject & Class Teachers — હાલની જેમ)',
      'વર્ગ શિક્ષક, તે ધોરણના અન્ય વિભાગના વર્ગ શિક્ષક તેમજ જે-તે વર્ગમાં વિષય ભણાવતા વિષય શિક્ષક (Subject Teacher) હાજરી પૂરી શકશે. (રજા દરમિયાન ચાર્જ સંભાળનાર ઇન્ચાર્જ શિક્ષક પણ રજાના દિવસો પૂરતી હાજરી પૂરી શકશે).',
      true,
    ),
    (
      'any_teacher_all_classes',
      '4️⃣ કોઈપણ શિક્ષક કોઈપણ વર્ગની હાજરી પૂરી શકે (Any Teacher Can Record Any Class Attendance)',
      'શાળાના કોઈપણ સક્રિય શિક્ષક શાળાના તમામ ધોરણ અને વિભાગોની હાજરી (PM POSHAN અને અલ્પાહાર સાથે) પૂરી શકશે.',
      false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schoolRef = await _schoolRef(_client);
      final row = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = row?['config'] is Map
          ? Map<String, dynamic>.from(row!['config'] as Map)
          : <String, dynamic>{};
      final raw = '${cfg['attendance_recording_permission_mode'] ?? ''}'
          .trim()
          .toLowerCase();
      final resolved = switch (raw) {
        'only_class_teacher' => 'only_class_teacher',
        'section_wise_class_teachers' => 'section_wise_class_teachers',
        'any_teacher_all_classes' => 'any_teacher_all_classes',
        _ => 'subject_and_class_teachers',
      };
      if (!mounted) return;
      setState(() {
        _permissionMode = resolved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveMode(String nextMode) async {
    if (_saving || nextMode == _permissionMode) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final schoolRef = await _schoolRef(_client);
      final existingRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = existingRow?['config'] is Map
          ? Map<String, dynamic>.from(existingRow!['config'] as Map)
          : <String, dynamic>{};
      cfg['attendance_recording_permission_mode'] = nextMode;
      await _client.from('school_settings').upsert(<String, dynamic>{
        'school_ref': schoolRef,
        'config': cfg,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref');
      FirestoreQueryBuilder.invalidateCache('school_settings');
      if (!mounted) return;
      setState(() {
        _permissionMode = nextMode;
        _saving = false;
      });
      final title = _modes
          .firstWhere((m) => m.$1 == nextMode, orElse: () => _modes[2])
          .$2;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ હાજરી પરવાનગી નિયમ સેવ થયો: $title'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF0F766E),
                  size: 28,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'શિક્ષક હાજરી પૂરવાની પરવાનગી (Teacher Attendance Recording Permission — Admin Control)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                    ),
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _loadMode,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF5EEAD4)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🛡️ School Admin હંમેશા શાળાના તમામ વર્ગોની હાજરી (PM POSHAN અને અલ્પાહાર સાથે) પૂરી શકે છે.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: Color(0xFF115E59),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '📅 રજા ચાર્જ નિયમ (Leave In-Charge Rule): વિકલ્પ 1, 2 અને 3 માં જ્યારે કોઈ શિક્ષક રજા પર હોય ત્યારે તેમણે રજા અરજીમાં પસંદ કરેલ "ચાર્જ શિક્ષક (In-Charge Teacher)" માત્ર રજાની શરૂઆતથી અંતિમ તારીખ (Leave Period) દરમિયાન જ તે શિક્ષકના વર્ગની હાજરી પૂરી શકશે.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final item in _modes)
                Builder(
                  builder: (context) {
                    final selected = _permissionMode == item.$1;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFECFDF5)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF059669)
                              : const Color(0xFFCBD5E1),
                          width: selected ? 1.8 : 1.1,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: item.$1,
                        groupValue: _permissionMode,
                        onChanged: _saving
                            ? null
                            : (val) {
                                if (val != null) _saveMode(val);
                              },
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              item.$2,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: selected
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: item.$4
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.$4
                                    ? '🟠 રજા ઇન્ચાર્જ નિયમ લાગુ'
                                    : '🌐 તમામ વર્ગ ખુલ્લા',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: item.$4
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF1E40AF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.$3,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _roleColorLegendChip(
                  bg: const Color(0xFFECFDF5),
                  border: const Color(0xFF6EE7B7),
                  text: const Color(0xFF065F46),
                  label: '🟢 વર્ગ શિક્ષક (Class Teacher)',
                ),
                _roleColorLegendChip(
                  bg: const Color(0xFFEFF6FF),
                  border: const Color(0xFF93C5FD),
                  text: const Color(0xFF1E40AF),
                  label: '🔵 વિભાગ / વિષય શિક્ષક (Section / Subject Teacher)',
                ),
                _roleColorLegendChip(
                  bg: const Color(0xFFFFFBEB),
                  border: const Color(0xFFFCD34D),
                  text: const Color(0xFF92400E),
                  label: '🟠 રજા ઇન્ચાર્જ શિક્ષક (Leave In-Charge Period)',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleColorLegendChip({
    required Color bg,
    required Color border,
    required Color text,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
}

class SupabaseAttendanceFreezeManageScreen extends StatefulWidget {
  const SupabaseAttendanceFreezeManageScreen({super.key});

  @override
  State<SupabaseAttendanceFreezeManageScreen> createState() =>
      _SupabaseAttendanceFreezeManageScreenState();
}

class _SupabaseAttendanceFreezeManageScreenState
    extends State<SupabaseAttendanceFreezeManageScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  DateTime _selectedDate = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  Map<String, Map<String, dynamic>> _daysByClassId =
      <String, Map<String, dynamic>>{};
  bool _threeStepSaveMode = false;
  bool _directEntryEnabled = true;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schoolRef = await _schoolRef(_client);
      final dateIso = _dateIso(_selectedDate);
      final settingsRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = settingsRow?['config'] is Map
          ? Map<String, dynamic>.from(settingsRow!['config'] as Map)
          : <String, dynamic>{};
      final threeStep = cfg['three_step_attendance_save_mode'] == true;
      final directEnabled = cfg['direct_attendance_entry_enabled'] != false;

      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order');
      final dayRows = await _client
          .from('attendance_days')
          .select(
            'id,class_id,attendance_date,attendance_mode,is_frozen,unfrozen_by_admin,present_saved,mdm_saved,breakfast_saved,present_frozen,mdm_frozen,breakfast_frozen,updated_at',
          )
          .eq('school_ref', schoolRef)
          .eq('attendance_date', dateIso);

      final byClass = <String, Map<String, dynamic>>{};
      for (final d in dayRows) {
        final cid = '${d['class_id'] ?? ''}'.trim();
        if (cid.isNotEmpty) {
          byClass[cid] = Map<String, dynamic>.from(d);
        }
      }
      if (!mounted) return;
      setState(() {
        _threeStepSaveMode = threeStep;
        _directEntryEnabled = directEnabled;
        _classes = classRows.map((c) => Map<String, dynamic>.from(c)).toList();
        _daysByClassId = byClass;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleThreeStepMode(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final schoolRef = await _schoolRef(_client);
      final existingRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = existingRow?['config'] is Map
          ? Map<String, dynamic>.from(existingRow!['config'] as Map)
          : <String, dynamic>{};
      cfg['three_step_attendance_save_mode'] = enabled;
      await _client.from('school_settings').upsert(<String, dynamic>{
        'school_ref': schoolRef,
        'config': cfg,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref');
      FirestoreQueryBuilder.invalidateCache('school_settings');
      if (!mounted) return;
      setState(() => _threeStepSaveMode = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '✅ ૩-તબક્કા હાજરી સેવ મોડ ચાલુ (Active): હવે શિક્ષકને ૩ અલગ સેવ બટન (1. Present/Absent, 2. PM POSHAN, 3. Breakfast) દેખાશે.'
                : '✅ સિંગલ સેવ બટન મોડ ચાલુ (Deactive): હવે શિક્ષકને ૧ જ સેવ બટન દેખાશે.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDirectEntryMode(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final schoolRef = await _schoolRef(_client);
      final existingRow = await _client
          .from('school_settings')
          .select('config')
          .eq('school_ref', schoolRef)
          .maybeSingle();
      final cfg = existingRow?['config'] is Map
          ? Map<String, dynamic>.from(existingRow!['config'] as Map)
          : <String, dynamic>{};
      cfg['direct_attendance_entry_enabled'] = enabled;
      await _client.from('school_settings').upsert(<String, dynamic>{
        'school_ref': schoolRef,
        'config': cfg,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'school_ref');
      FirestoreQueryBuilder.invalidateCache('school_settings');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('psm.attendance.$schoolRef.direct_enabled', enabled);
        await prefs.setString('psm.attendance.$schoolRef.mode', enabled ? 'direct' : 'student');
      } catch (_) {}
      if (!mounted) return;
      setState(() => _directEntryEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '✅ Direct Entry મોડ ચાલુ (Active): શિક્ષકની હાજરી સ્ક્રીન પર Student Selection અને Direct Entry બંને વિકલ્પ દેખાશે.'
                : '✅ Direct Entry મોડ બંધ (Deactive): હવે શિક્ષકની હાજરી સ્ક્રીન પર માત્ર વિદ્યાર્થીવાર હાજરી (Student Selection) જ દેખાશે.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setFreeze(
    Map<String, dynamic> dayRow,
    bool freeze, {
    String section = 'all',
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_set_attendance_freeze_status',
        params: <String, dynamic>{
          'p_day_id': '${dayRow['id'] ?? ''}',
          'p_class_id': '${dayRow['class_id'] ?? ''}',
          'p_attendance_date': _dateIso(_selectedDate),
          'p_is_frozen': freeze,
          'p_section': section,
        },
      );
      await _load();
      if (mounted) {
        final secLabel = switch (section) {
          'present' => 'હાજર-ગેરહાજર (Present/Absent)',
          'mdm' => 'PM POSHAN',
          'breakfast' => 'અલ્પાહાર (Breakfast)',
          _ => 'સંપૂર્ણ હાજરી (All Attendance)',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              freeze
                  ? '$secLabel ફ્રીઝ કરવામાં આવેલ છે (Frozen).'
                  : '$secLabel અનફ્રીઝ કરવામાં આવેલ છે — હવે શિક્ષક સુધારો કરીને સેવ કરી શકશે.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateIso = _dateIso(_selectedDate);
    return Scaffold(
      appBar: AppBar(
        title: const Text('3-Step Save Mode & Attendance Unfreeze / હાજરી સેવ મોડ અને અનફ્રીઝ'),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SupabaseAttendancePermissionControlCard(),
                const SizedBox(height: 12),
                Card(
                  color: _threeStepSaveMode
                      ? Colors.indigo.shade50
                      : Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _threeStepSaveMode
                          ? Colors.indigo.shade400
                          : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _threeStepSaveMode
                                  ? Icons.looks_3_rounded
                                  : Icons.looks_one_rounded,
                              color: _threeStepSaveMode
                                  ? Colors.indigo.shade800
                                  : Colors.blueGrey.shade800,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '૩ તબક્કામાં હાજરી સેવ મોડ (3-Step Separate Save Buttons Mode)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                ),
                              ),
                            ),
                            Switch(
                              value: _threeStepSaveMode,
                              onChanged: _busy ? null : _toggleThreeStepMode,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _threeStepSaveMode
                              ? '🟢 હાલમાં ચાલુ (ACTIVE): શિક્ષકની સ્ક્રીન પર ૩ અલગ સેવ બટન દેખાશે:\n'
                                '   1️⃣ પહેલા "હાજર-ગેરહાજર (Present/Absent)" સેવ કરવું ફરજિયાત છે (સેવ થતાં જ હાજર-ગેરહાજર ફ્રીઝ થશે).\n'
                                '   2️⃣ ત્યારબાદ કોઈપણ ક્રમમાં "અલ્પાહાર (Breakfast)" અથવા "PM POSHAN" અલગ-અલગ સમયે સેવ કરી શકાશે (જે સેવ થતાં તે ભાગ પણ ફ્રીઝ થશે).'
                              : '⚪ હાલમાં બંધ (DEACTIVE - Default): શિક્ષકની સ્ક્રીન પર ૧ જ "Save Attendance" બટન દેખાશે જેનાથી હાજરી, PM POSHAN અને અલ્પાહાર ત્રણેય એકસાથે સેવ અને ફ્રીઝ થશે.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: _directEntryEnabled
                      ? Colors.teal.shade50
                      : Colors.amber.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _directEntryEnabled
                          ? Colors.teal.shade400
                          : Colors.amber.shade700,
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _directEntryEnabled
                                  ? Icons.numbers_rounded
                                  : Icons.checklist_rtl_rounded,
                              color: _directEntryEnabled
                                  ? Colors.teal.shade900
                                  : Colors.amber.shade900,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'ડાયરેક્ટ હાજરી એન્ટ્રી મોડ (Direct Entry Mode — Active / Deactive)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                ),
                              ),
                            ),
                            Switch(
                              value: _directEntryEnabled,
                              onChanged: _busy ? null : _toggleDirectEntryMode,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _directEntryEnabled
                              ? '🟢 હાલમાં ચાલુ (ACTIVE - Default): શિક્ષકની હાજરી સ્ક્રીન પર હાલની જેમ જ "Student Selection (વિદ્યાર્થીવાર)" અને "Direct Entry (ડાયરેક્ટ સંખ્યા)" બંને વિકલ્પ દેખાશે.'
                              : '🔒 હાલમાં બંધ (DEACTIVE): શિક્ષકની હાજરી સ્ક્રીન પર "Direct Entry" વિકલ્પ બંધ રહેશે — માત્ર "વિદ્યાર્થીવાર હાજરી (Student Selection)" જ દેખાશે.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'શિક્ષક એકવાર હાજરી (અથવા ૩-તબક્કા મોડમાં જે-તે તબક્કો) સબમિટ કરે એટલે તે આપોઆપ ફ્રીઝ (Freeze) થઈ જાય છે. જો શિક્ષકને સુધારો કરવો હોય તો અહીંથી જે-તે વર્ગની સંપૂર્ણ હાજરી અથવા ચોક્કસ વિભાગ (Present / PM POSHAN / Breakfast) Unfreeze કરો.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickDate,
                          icon: const Icon(Icons.calendar_month),
                          label: Text('તારીખ પસંદ કરો / Date: $dateIso'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 12),
                for (final c in _classes)
                  Builder(
                    builder: (context) {
                      final cid = '${c['id']}';
                      final label = '${c['label'] ?? c['class_key'] ?? cid}';
                      final day = _daysByClassId[cid];
                      final hasStepFlags = day != null &&
                          (day['present_frozen'] != null ||
                              day['mdm_frozen'] != null ||
                              day['breakfast_frozen'] != null);
                      final legacyFrozen = day != null &&
                          (day['is_frozen'] == true ||
                              (day['is_frozen'] == null &&
                                  day['unfrozen_by_admin'] != true));
                      final pFrozen = day != null &&
                          (hasStepFlags
                              ? day['present_frozen'] == true
                              : legacyFrozen);
                      final mFrozen = day != null &&
                          (hasStepFlags
                              ? day['mdm_frozen'] == true
                              : legacyFrozen);
                      final bFrozen = day != null &&
                          (hasStepFlags
                              ? day['breakfast_frozen'] == true
                              : legacyFrozen);
                      final isAllFrozen =
                          day != null && pFrozen && mFrozen && bFrozen;
                      final isAnyFrozen =
                          day != null && (pFrozen || mFrozen || bFrozen);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    day == null
                                        ? Icons.pending_outlined
                                        : (isAllFrozen
                                            ? Icons.lock
                                            : (isAnyFrozen
                                                ? Icons.lock_clock
                                                : Icons.lock_open)),
                                    color: day == null
                                        ? Colors.grey
                                        : (isAllFrozen
                                            ? Colors.amber.shade900
                                            : (isAnyFrozen
                                                ? Colors.indigo
                                                : Colors.green)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15.5,
                                          ),
                                        ),
                                        Text(
                                          day == null
                                              ? 'હજુ સુધી હાજરી સબમિટ થઈ નથી (Not submitted yet)'
                                              : (isAllFrozen
                                                  ? 'ત્રણેય વિભાગ સબમિટ અને ફ્રીઝ (All Frozen)'
                                                  : (isAnyFrozen
                                                      ? 'આંશિક ફ્રીઝ (Partial Frozen — બાકીના તબક્કા ખુલ્લા છે)'
                                                      : 'અનફ્રીઝ (Unfrozen — શિક્ષક સુધારો કરી શકે છે)')),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (day != null)
                                    FilledButton.tonalIcon(
                                      onPressed: _busy
                                          ? null
                                          : () => _setFreeze(
                                                day,
                                                !isAnyFrozen,
                                                section: 'all',
                                              ),
                                      icon: Icon(
                                        isAnyFrozen
                                            ? Icons.lock_open
                                            : Icons.lock,
                                      ),
                                      label: Text(
                                        isAnyFrozen
                                            ? 'Unfreeze All (બધું અનફ્રીઝ)'
                                            : 'Freeze All (બધું ફ્રીઝ)',
                                      ),
                                    ),
                                ],
                              ),
                              if (day != null) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ActionChip(
                                      avatar: Icon(
                                        pFrozen ? Icons.lock : Icons.lock_open,
                                        size: 16,
                                        color: pFrozen
                                            ? Colors.amber.shade900
                                            : Colors.green.shade800,
                                      ),
                                      backgroundColor: pFrozen
                                          ? Colors.amber.shade50
                                          : Colors.green.shade50,
                                      label: Text(
                                        pFrozen
                                            ? '1. Present/Absent: Frozen (Unfreeze કરો)'
                                            : '1. Present/Absent: Unfrozen (Freeze કરો)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => _setFreeze(
                                                day,
                                                !pFrozen,
                                                section: 'present',
                                              ),
                                    ),
                                    ActionChip(
                                      avatar: Icon(
                                        mFrozen ? Icons.lock : Icons.lock_open,
                                        size: 16,
                                        color: mFrozen
                                            ? Colors.amber.shade900
                                            : Colors.green.shade800,
                                      ),
                                      backgroundColor: mFrozen
                                          ? Colors.amber.shade50
                                          : Colors.green.shade50,
                                      label: Text(
                                        mFrozen
                                            ? '2. PM POSHAN: Frozen (Unfreeze કરો)'
                                            : '2. PM POSHAN: Unfrozen (Freeze કરો)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => _setFreeze(
                                                day,
                                                !mFrozen,
                                                section: 'mdm',
                                              ),
                                    ),
                                    ActionChip(
                                      avatar: Icon(
                                        bFrozen ? Icons.lock : Icons.lock_open,
                                        size: 16,
                                        color: bFrozen
                                            ? Colors.amber.shade900
                                            : Colors.green.shade800,
                                      ),
                                      backgroundColor: bFrozen
                                          ? Colors.amber.shade50
                                          : Colors.green.shade50,
                                      label: Text(
                                        bFrozen
                                            ? '3. Breakfast: Frozen (Unfreeze કરો)'
                                            : '3. Breakfast: Unfrozen (Freeze કરો)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => _setFreeze(
                                                day,
                                                !bFrozen,
                                                section: 'breakfast',
                                              ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class SupabaseClassPromotionScreen extends StatefulWidget {
  const SupabaseClassPromotionScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<SupabaseClassPromotionScreen> createState() =>
      _SupabaseClassPromotionScreenState();
}

class _SupabaseClassPromotionScreenState
    extends State<SupabaseClassPromotionScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final Set<String> _retainedStudentIds = <String>{};
  final Map<String, String> _studentTargetClassMap = <String, String>{};
  final Map<String, String> _classTargetClassMap = <String, String>{};
  bool _keepSameClassTeacher = true;
  late final TextEditingController _newClassEnrollDateController =
      TextEditingController(
        text:
            '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
      );
  String _search = '';
  bool _loading = true;
  bool _promoting = false;
  bool _exportingPromoted = false;
  bool _changingSection = false;
  String? _error;
  Map<String, dynamic> _preview = <String, dynamic>{};

  // Section Change Anytime tab state
  String _secFromClassId = '';
  String _secToClassId = '';
  String _secSearch = '';
  late final TextEditingController _secEffectiveDateController =
      TextEditingController(
        text:
            '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
      );
  final Set<String> _secSelectedStudentIds = <String>{};
  List<Map<String, dynamic>> _schoolTeachers = <Map<String, dynamic>>[];
  final Map<String, String> _currentClassTeacherByClassId = <String, String>{};
  final Map<String, String> _newClassTeacherMap = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.rpc('psm_get_class_promotion_preview');
      if (!mounted) return;
      final previewMap =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final clsList = (previewMap['classes'] is List)
          ? (previewMap['classes'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      String fromId = _secFromClassId;
      if (fromId.isEmpty || !clsList.any((c) => '${c['class_id']}' == fromId)) {
        // Default to the first class that has multiple sections, or the first class
        final withSections = clsList.firstWhere(
          (c) =>
              (c['same_standard_classes'] is List) &&
              (c['same_standard_classes'] as List).length > 1,
          orElse: () => clsList.isNotEmpty ? clsList.first : <String, dynamic>{},
        );
        fromId = '${withSections['class_id'] ?? ''}';
      }
      String toId = _secToClassId;
      if (fromId.isNotEmpty) {
        final curClass = clsList.firstWhere(
          (c) => '${c['class_id']}' == fromId,
          orElse: () => <String, dynamic>{},
        );
        final sameStd = (curClass['same_standard_classes'] is List)
            ? (curClass['same_standard_classes'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .where((sc) => '${sc['id']}' != fromId)
                .toList()
            : <Map<String, dynamic>>[];
        if (toId.isEmpty ||
            toId == fromId ||
            !sameStd.any((sc) => '${sc['id']}' == toId)) {
          toId = sameStd.isNotEmpty ? '${sameStd.first['id']}' : '';
        }
      }

      // Load active school teachers & current class_teacher_id per class for New Class Teacher assignment
      List<Map<String, dynamic>> teacherRows = <Map<String, dynamic>>[];
      final currentCtMap = <String, String>{};
      try {
        final sRef = '${await _client.rpc('current_school_ref') ?? ''}'.trim();
        if (sRef.isNotEmpty) {
          final tRes = await _client
              .from('school_teachers')
              .select('id,teacher_name,role,is_active')
              .eq('school_ref', sRef)
              .eq('is_active', true);
          teacherRows = tRes
              .map((e) => Map<String, dynamic>.from(e))
              .where((t) {
                final r = '${t['role'] ?? 'teacher'}'.trim().toLowerCase();
                return r != 'developer' && '${t['teacher_name'] ?? ''}'.trim().isNotEmpty;
              })
              .toList()
            ..sort(
              (a, b) => '${a['teacher_name'] ?? ''}'.toLowerCase().compareTo(
                '${b['teacher_name'] ?? ''}'.toLowerCase(),
              ),
            );
          final cRes = await _client
              .from('school_classes')
              .select('id,class_teacher_id')
              .eq('school_ref', sRef)
              .eq('is_active', true);
          for (final cr in cRes) {
            final cid = '${cr['id'] ?? ''}'.trim();
            final ctid = '${cr['class_teacher_id'] ?? ''}'.trim();
            if (cid.isNotEmpty) currentCtMap[cid] = ctid;
          }
        }
      } catch (_) {}

      final validTeacherIds = <String>{
        for (final t in teacherRows) '${t['id'] ?? ''}'.trim(),
      };
      final nextCtMap = <String, String>{};
      for (final cl in clsList) {
        final cid = '${cl['class_id'] ?? ''}'.trim();
        if (cid.isEmpty) continue;
        final existingSel = _newClassTeacherMap[cid];
        final curCt = currentCtMap[cid] ?? '';
        final chosen = (existingSel != null &&
                (existingSel.isEmpty || validTeacherIds.contains(existingSel)))
            ? existingSel
            : (validTeacherIds.contains(curCt) ? curCt : '');
        nextCtMap[cid] = chosen;
      }

      if (!mounted) return;
      setState(() {
        _preview = previewMap;
        _secFromClassId = fromId;
        _secToClassId = toId;
        _schoolTeachers = teacherRows;
        _currentClassTeacherByClassId
          ..clear()
          ..addAll(currentCtMap);
        _newClassTeacherMap
          ..clear()
          ..addAll(nextCtMap);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickResultDate() async {
    final currentIso = '${_preview['result_date_iso'] ?? ''}'.trim();
    final initial = DateTime.tryParse(currentIso) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'બીજા સત્રના પરિણામની તારીખ (Second Semester Result Date)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.rpc(
        'psm_set_second_sem_result_date',
        params: <String, dynamic>{'p_result_date': _dateIso(picked)},
      );
      if (!mounted) return;
      setState(() {
        _preview =
            res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'બીજા સત્રના પરિણામની તારીખ ${_preview['result_date_dmy'] ?? _dateIso(picked)} સેવ થઈ ગઈ છે (Result પત્રક સાથે પણ સિંક થયેલ છે).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _classes {
    final raw = _preview['classes'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, String> get _classLabelsById => <String, String>{
        for (final c in _classes)
          '${c['class_id'] ?? ''}': '${c['label'] ?? ''}',
      };

  List<Map<String, dynamic>> get _graduatedStd8Students {
    final raw = _preview['graduated_std8_students'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> get _promotedStudentsHistory {
    final raw = _preview['promoted_students_history'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _exportPromotedStudentsFullExcel({
    bool onlyStd8Graduated = false,
  }) async {
    if (_exportingPromoted) return;
    setState(() {
      _exportingPromoted = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final customRow = await _client
          .from('school_custom_headers')
          .select('headers')
          .eq('school_ref', school)
          .maybeSingle();
      final customHeaders = <String>[];
      final rawCustom = customRow?['headers'];
      if (rawCustom is List) {
        for (var i = 0; i < 11; i++) {
          customHeaders.add(
            i < rawCustom.length && '${rawCustom[i] ?? ''}'.trim().isNotEmpty
                ? '${rawCustom[i]}'.trim()
                : 'Custom Field ${i + 1}',
          );
        }
      } else {
        for (var i = 0; i < 11; i++) {
          customHeaders.add('Custom Field ${i + 1}');
        }
      }

      final allDbRows = await _client
          .from('students')
          .select('*')
          .eq('school_ref', school);
      final allStudents =
          allDbRows.map((r) => Map<String, dynamic>.from(r)).toList();

      // Load private bank details for admin full-data export
      final privateRows = await _client
          .from('student_private_details')
          .select('*')
          .eq('school_ref', school);
      final privateById = <String, Map<String, dynamic>>{
        for (final r in privateRows)
          '${r['student_id']}': Map<String, dynamic>.from(r),
      };

      final classLabels = _classLabelsById;
      final nextLabelByClassId = <String, String>{
        for (final c in _classes)
          '${c['class_id']}': '${c['next_class_label'] ?? ''}',
      };
      final stdByClassId = <String, int>{
        for (final c in _classes)
          '${c['class_id']}': int.tryParse('${c['standard'] ?? 0}') ?? 0,
      };

      final promotedRows = <Map<String, dynamic>>[];
      final std8GraduatedRows = <Map<String, dynamic>>[];
      final retainedRows = <Map<String, dynamic>>[];

      // Determine whether promotion has already been executed or if we are exporting the promotion preview
      final hasExecutedPromotion = allStudents.any(
        (s) =>
            '${s['last_promotion_status'] ?? ''}'.isNotEmpty ||
            '${s['exit_reason'] ?? ''}' == 'promoted_graduated',
      );

      for (final raw in allStudents) {
        final s = Map<String, dynamic>.from(raw);
        final sid = '${s['id'] ?? ''}';
        final priv = privateById[sid];
        if (priv != null) s.addAll(priv);
        final custom = s['custom_fields'];
        if (custom is Map) {
          s.addAll(custom.map((k, v) => MapEntry('$k', v)));
        }
        final cid = '${s['class_id'] ?? ''}';
        s['class_label'] = classLabels[cid] ?? '${s['promoted_from_class_label'] ?? ''}';

        if (hasExecutedPromotion) {
          final status = '${s['last_promotion_status'] ?? ''}';
          if (status == 'graduated_std_9' ||
              '${s['exit_reason'] ?? ''}' == 'promoted_graduated') {
            s['_from_class'] = '${s['promoted_from_class_label'] ?? s['class_label'] ?? 'ધોરણ - 8'}';
            s['_to_class'] = '${s['promoted_to_class_label'] ?? 'ધોરણ - 9 (Class 9)'}';
            s['_promo_status'] = 'ધોરણ 8 પૂર્ણ -> ધોરણ 9 માં બઢતી / કમી (Graduated to Class 9)';
            s['_old_roll'] = '${s['previous_roll_number'] ?? s['roll_number'] ?? ''}';
            s['_new_roll'] = '—';
            std8GraduatedRows.add(s);
            promotedRows.add(s);
          } else if (status == 'promoted' && s['is_active'] == true) {
            s['_from_class'] = '${s['promoted_from_class_label'] ?? ''}';
            s['_to_class'] = '${s['promoted_to_class_label'] ?? s['class_label'] ?? ''}';
            s['_promo_status'] = 'આગળના વર્ગમાં બઢતી (Promoted +1)';
            s['_old_roll'] = '${s['previous_roll_number'] ?? ''}';
            s['_new_roll'] = '${s['roll_number'] ?? ''}';
            promotedRows.add(s);
          } else if (status == 'retained' && s['is_active'] == true) {
            s['_from_class'] = '${s['class_label'] ?? ''}';
            s['_to_class'] = '${s['class_label'] ?? ''}';
            s['_promo_status'] = 'તે જ વર્ગમાં રાખેલ (Retained)';
            s['_old_roll'] = '${s['roll_number'] ?? ''}';
            s['_new_roll'] = '${s['roll_number'] ?? ''}';
            retainedRows.add(s);
          }
        } else if (s['is_active'] == true) {
          // Pre-promotion preview export
          final isRetained = _retainedStudentIds.contains(sid);
          final overrideCid = '${_studentTargetClassMap[sid] ?? ''}'.trim();
          final std = stdByClassId[cid] ?? 0;
          if (isRetained) {
            s['_from_class'] = '${s['class_label'] ?? ''}';
            s['_to_class'] = '${s['class_label'] ?? ''}';
            s['_promo_status'] = 'તે જ વર્ગમાં રાખેલ (Retained)';
            s['_old_roll'] = '${s['roll_number'] ?? ''}';
            s['_new_roll'] = '${s['roll_number'] ?? ''}';
            retainedRows.add(s);
          } else if (std >= 8) {
            s['_from_class'] = '${s['class_label'] ?? 'ધોરણ - 8'}';
            s['_to_class'] = 'ધોરણ - 9 (Class 9)';
            s['_promo_status'] = 'ધોરણ 8 પૂર્ણ -> ધોરણ 9 માં બઢતી / કમી (Graduated to Class 9)';
            s['_old_roll'] = '${s['roll_number'] ?? ''}';
            s['_new_roll'] = '—';
            std8GraduatedRows.add(s);
            promotedRows.add(s);
          } else {
            final nextLbl = overrideCid.isNotEmpty
                ? (classLabels[overrideCid] ?? nextLabelByClassId[cid] ?? '')
                : (nextLabelByClassId[cid] ?? '');
            s['_from_class'] = '${s['class_label'] ?? ''}';
            s['_to_class'] = nextLbl;
            s['_promo_status'] = 'આગળના વર્ગમાં બઢતી (Promoted +1)';
            s['_old_roll'] = '${s['roll_number'] ?? ''}';
            s['_new_roll'] = '${s['roll_number'] ?? ''}';
            promotedRows.add(s);
          }
        }
      }

      final exportCols = <_ExportField>[
        const _ExportField('_from_class', 'અગાઉનું ધોરણ (Promoted From Class)'),
        const _ExportField('_to_class', 'નવું ધોરણ / વિભાગ (Promoted To Class)'),
        const _ExportField('_promo_status', 'બઢતી સ્થિતિ (Promotion Status)'),
        const _ExportField('_old_roll', 'જૂનો રોલ નંબર (Old Roll Number)'),
        const _ExportField('_new_roll', 'નવો રોલ નંબર (New Roll Number)'),
        const _ExportField('promoted_at', 'બઢતી તારીખ (Promotion Date)'),
        ..._baseExportFields,
        for (var i = 0; i < 11; i++)
          _ExportField('c${i + 1}', customHeaders[i]),
      ];

      void populateSheet(ec.Sheet sheet, List<Map<String, dynamic>> list) {
        for (var col = 0; col < exportCols.length; col++) {
          _putText(sheet, 0, col, exportCols[col].label);
        }
        for (var r = 0; r < list.length; r++) {
          final st = list[r];
          for (var col = 0; col < exportCols.length; col++) {
            final key = exportCols[col].key;
            final val = st[key];
            _putText(
              sheet,
              r + 1,
              col,
              val is bool ? (val ? 'Yes' : 'No') : '${val ?? ''}',
            );
          }
        }
      }

      final workbook = ec.Excel.createExcel();
      if (onlyStd8Graduated) {
        workbook.rename('Sheet1', 'Std8_To_Class9_FullData');
        populateSheet(workbook['Std8_To_Class9_FullData'], std8GraduatedRows);
      } else {
        workbook.rename('Sheet1', 'All_Promoted_Students');
        populateSheet(workbook['All_Promoted_Students'], promotedRows);
        populateSheet(workbook['Std8_To_Class9_Graduated'], std8GraduatedRows);
        if (retainedRows.isNotEmpty) {
          populateSheet(workbook['Retained_Students'], retainedRows);
        }
      }

      final bytes = workbook.encode(); // encode(): no extra auto-download on web
      if (bytes == null) {
        throw StateError('Could not create Promoted Students Excel workbook.');
      }
      final fileName = onlyStd8Graduated
          ? 'Std8_Graduated_To_Class9_FullData_${_dateIso(DateTime.now())}.xlsx'
          : 'Promoted_And_Std8_Students_FullData_${_dateIso(DateTime.now())}.xlsx';
      if (!mounted) return;
      await _shareXlsx(bytes, fileName, context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _exportingPromoted = false);
    }
  }

  Future<void> _executeSectionChangeAnytime({
    required List<String> studentIds,
    required String toClassId,
  }) async {
    if (_changingSection || studentIds.isEmpty || toClassId.isEmpty) return;
    setState(() {
      _changingSection = true;
      _error = null;
    });
    try {
      final res = await _client.rpc(
        'psm_change_student_section_only',
        params: <String, dynamic>{
          'p_student_ids': studentIds,
          'p_to_class_id': toClassId,
          'p_effective_date': _secEffectiveDateController.text.trim(),
        },
      );
      final map =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final changed = map['changed_count'] ?? studentIds.length;
      final toLabel = '${map['to_class_label'] ?? _classLabelsById[toClassId] ?? ''}';
      _secSelectedStudentIds.removeAll(studentIds);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$changed વિદ્યાર્થીઓનો વિભાગ બદલીને "$toLabel" કરવામાં આવ્યો છે (હાજર દિવસો, જન્મ તારીખ કે અન્ય કોઈ ડેટા બદલાયો નથી).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _changingSection = false);
    }
  }

  Future<void> _createNewClassFromPromotionDialog() async {
    final stdCtrl = TextEditingController();
    final secCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('નવો વર્ગ / વિભાગ ઉમેરો (Create New Class for Promotion)'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ધોરણ (Standard 1–8, અથવા બાલવાટિકા માટે 0)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  final s = v.trim();
                  final sec = secCtrl.text.trim().toUpperCase();
                  if (s == '0') {
                    labelCtrl.text = sec.isEmpty ? 'બાલવાટિકા' : 'બાલવાટિકા - $sec';
                  } else if (s.isNotEmpty) {
                    labelCtrl.text = sec.isEmpty ? 'ધોરણ - $s' : 'ધોરણ - $s - $sec';
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secCtrl,
                decoration: const InputDecoration(
                  labelText: 'વિભાગ (Section A, B, C — વૈકલ્પિક)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  final s = stdCtrl.text.trim();
                  final sec = v.trim().toUpperCase();
                  if (s == '0') {
                    labelCtrl.text = sec.isEmpty ? 'બાલવાટિકા' : 'બાલવાટિકા - $sec';
                  } else if (s.isNotEmpty) {
                    labelCtrl.text = sec.isEmpty ? 'ધોરણ - $s' : 'ધોરણ - $s - $sec';
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'વર્ગનું નામ (Class Label, દા.ત. ધોરણ - 5 અથવા ધોરણ - 1 - B) *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.add),
            label: const Text('વર્ગ બનાવો (Create Class)'),
          ),
        ],
      ),
    );
    final lbl = labelCtrl.text.trim();
    final stdText = stdCtrl.text.trim();
    final secText = secCtrl.text.trim().toUpperCase();
    stdCtrl.dispose();
    secCtrl.dispose();
    labelCtrl.dispose();
    if (created != true || lbl.isEmpty || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await _schoolRef(_client);
      final stdNum = int.tryParse(stdText) ?? 1;
      final group = stdNum == 0
          ? 'BALVATIKA'
          : (stdNum <= 5 ? 'STD_1_TO_5' : 'STD_6_TO_8');
      await _client.from('school_classes').insert(<String, dynamic>{
        'school_ref': school,
        'class_key': lbl,
        'label': lbl,
        'sheet_name': lbl,
        'standard': stdNum == 0 ? 'બાલવાટિકા' : '$stdNum',
        'section': secText,
        'report_group': group,
        'sort_order': stdNum * 10 + (secText.isEmpty ? 0 : secText.codeUnitAt(0) - 64),
        'is_active': true,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('નવો વર્ગ "$lbl" સફળતાપૂર્વક બની ગયો છે અને બઢતી યાદીમાં ઉમેરાઈ ગયો છે.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndPromote() async {
    final canPromote = _preview['can_promote'] == true;
    if (!canPromote || _promoting) return;

    final classLabels = _classLabelsById;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final allStudents = <Map<String, dynamic>>[];
            int std8Count = 0;
            for (final c in _classes) {
              final cLabel = '${c['label'] ?? ''}';
              final std = int.tryParse('${c['standard'] ?? 0}') ?? 0;
              final defaultNextId = '${c['next_class_id'] ?? ''}';
              final defaultNextLabel = '${c['next_class_label'] ?? ''}';
              final stList = (c['students'] is List)
                  ? (c['students'] as List)
                  : const <dynamic>[];
              for (final s in stList.whereType<Map>()) {
                final sid = '${s['id']}';
                final overrideId = _studentTargetClassMap[sid] ?? defaultNextId;
                final effNextLabel = std >= 8
                    ? 'ધોરણ - 9 (શાળા પૂર્ણ / કમી)'
                    : (classLabels[overrideId] ?? defaultNextLabel);
                if (std >= 8 && !_retainedStudentIds.contains(sid)) {
                  std8Count++;
                }
                allStudents.add(<String, dynamic>{
                  ...Map<String, dynamic>.from(s),
                  'class_label': cLabel,
                  'standard': std,
                  'next_class_label': effNextLabel,
                });
              }
            }
            final retainedList = allStudents
                .where((s) => _retainedStudentIds.contains('${s['id']}'))
                .toList();
            final promotedCount =
                allStudents.length - retainedList.length - std8Count;

            return AlertDialog(
              title: const Text(
                'વર્ગ બઢતી (Class Promotion) કન્ફર્મ કરો',
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• આગળના વર્ગમાં બઢતી પામનાર (બાલવાટિકા → 1 અને +1): $promotedCount\n'
                        '• ધોરણ 8 પૂર્ણ કરી ધોરણ 9 માં જનાર (સક્રિય વર્ગમાંથી કમી): $std8Count\n'
                        '• નાપાસ / આ જ વર્ગમાં રહેનાર (Retained): ${retainedList.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newClassEnrollDateController,
                        decoration: InputDecoration(
                          labelText:
                              'નવા વર્ગમાં દાખલ તારીખ (New Class Enroll Date — ફક્ત બઢતી પામનાર માટે જ)',
                          helperText:
                              'બઢતી પામનાર વિદ્યાર્થીઓના નવા વર્ગના હાજરીપત્રકમાં આ તારીખ આવશે. બઢતી ન પામનાર (Retained) વિદ્યાર્થીઓની જૂની તારીખ જ રહેશે.',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'તારીખ પસંદ કરો',
                            icon: const Icon(Icons.calendar_month),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: now,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                helpText: 'નવા વર્ગમાં દાખલ તારીખ (New Class Enroll Date)',
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  _newClassEnrollDateController.text =
                                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                });
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _keepSameClassTeacher,
                        onChanged: (v) {
                          setDialogState(() => _keepSameClassTeacher = v ?? true);
                          setState(() {});
                        },
                        title: const Text(
                          'નવા વર્ગમાં પણ હાલના જ વર્ગ શિક્ષક રાખો (Keep same Class Teacher for promoted class — Admin can edit later)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'જે વિદ્યાર્થીને તે જ વર્ગમાં રાખવાનો હોય તેની સામે ટીક કરો. બઢતી પૂર્ણ થયા પછી તમે બઢતી પામેલ અને ધોરણ-8 કમી વિદ્યાર્થીઓની સંપૂર્ણ ડેટા Excel ડાઉનલોડ કરી શકશો:',
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: allStudents.length,
                            itemBuilder: (_, idx) {
                              final st = allStudents[idx];
                              final sid = '${st['id']}';
                              final isRetained =
                                  _retainedStudentIds.contains(sid);
                              return CheckboxListTile(
                                dense: true,
                                value: isRetained,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      _retainedStudentIds.add(sid);
                                    } else {
                                      _retainedStudentIds.remove(sid);
                                    }
                                  });
                                  setState(() {});
                                },
                                title: Text(
                                  '${st['class_label']} • Roll ${st['roll_number']} — ${st['name']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  isRetained
                                      ? 'બઢતી નહીં — ${st['class_label']} માં જ રહેશે (Not Promoted)'
                                      : 'બઢતી -> ${st['next_class_label']}',
                                  style: TextStyle(
                                    color: isRetained
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.trending_up),
                  label: const Text('વર્ગ બઢતી કરો (Promote Now)'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _promoting = true;
      _error = null;
    });
    try {
      // Mandatory Pre-Promote Backup: automatically download full student data Excel
      // (especially Class 8 students moving to Class 9) BEFORE promotion removes them from active classes.
      await _exportPromotedStudentsFullExcel(onlyStd8Graduated: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final res = await _client.rpc(
        'psm_promote_school_classes',
        params: <String, dynamic>{
          'p_retained_student_ids': _retainedStudentIds.toList(),
          'p_student_target_class_map': _studentTargetClassMap,
          'p_class_target_class_map': _classTargetClassMap,
          'p_new_class_enroll_date': _newClassEnrollDateController.text.trim(),
          'p_keep_same_class_teacher': _keepSameClassTeacher,
          'p_new_class_teacher_map': _newClassTeacherMap,
        },
      );
      final map =
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      _retainedStudentIds.clear();
      _studentTargetClassMap.clear();
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('વર્ગ બઢતી પૂર્ણ (Class Promotion Complete)'),
          content: Text(
            '• આગળના વર્ગમાં બઢતી પામેલ વિદ્યાર્થીઓ (બાલવાટિકા → 1 અને +1): ${map['promoted_count'] ?? 0}\n'
            '• ધોરણ 8 પૂર્ણ કરી ધોરણ 9 માં જનાર (સક્રિય વર્ગમાંથી કમી): ${map['graduated_count'] ?? 0}\n'
            '• તે જ વર્ગમાં રાખેલ (Not Promoted) વિદ્યાર્થીઓ: ${map['retained_count'] ?? 0}\n\n'
            '• અગાઉના વર્ષના તમામ હાજરી અને પરિણામ રેકોર્ડ સુરક્ષિત (Archived) રાખવામાં આવ્યા છે.\n'
            '• નવા શૈક્ષણિક વર્ષ માટે પસંદ કરેલ વર્ગ શિક્ષકો અપડેટ થઈ ગયા છે.\n'
            '• આ બઢતીના મહિનામાં હાજરીપત્રક (Hajari Patrak) માં જૂના વર્ગ (જૂની દાખલ તારીખ) અને નવા વર્ગ (નવી દાખલ તારીખ) બંને પ્રિન્ટ કરી શકાશે.\n\n'
            'તમામ વર્ગોમાં રોલ નંબર 1 થી સળંગ ગોઠવાઈ ગયા છે. નીચેના બટનથી બઢતી પામેલ અને ધોરણ-8 ના વિદ્યાર્થીઓની સંપૂર્ણ વિગતવાર Excel ડાઉનલોડ કરી શકો છો.',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _exportPromotedStudentsFullExcel(onlyStd8Graduated: false);
              },
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('બઢતી પામેલ સંપૂર્ણ Excel ડાઉનલોડ કરો'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  String _extractClassSectionToken(Map<String, dynamic> c) {
    final sec = '${c['section'] ?? ''}'.trim().toUpperCase();
    if (sec.isNotEmpty) return sec;
    final lbl = '${c['label'] ?? c['class_key'] ?? ''}'.trim().toUpperCase();
    final m = RegExp(r'\d+\s*[-–]?\s*([A-Z])\b').firstMatch(lbl);
    return m?.group(1) ?? '';
  }

  void _applyKeepSameClassTeachersPreset() {
    setState(() {
      _keepSameClassTeacher = true;
      for (final c in _classes) {
        final cid = '${c['class_id'] ?? ''}'.trim();
        if (cid.isEmpty) continue;
        _newClassTeacherMap[cid] = _currentClassTeacherByClassId[cid] ?? '';
      }
    });
  }

  /// Gujarat primary/upper-primary teacher rotation preset:
  /// - Balvatika (0) -> Std 1 -> ... -> Std 5 (teachers move up +1 with students; Std 5 teacher moves to Balvatika/Std 1)
  /// - Std 6 -> Std 7 -> Std 8 -> Std 6 (previous Std 8 teacher becomes new Std 6 Class Teacher!)
  void _applyGujaratTeacherRotationPreset() {
    final byStd = <int, List<Map<String, dynamic>>>{};
    for (final c in _classes) {
      final std = int.tryParse('${c['standard'] ?? -1}') ?? -1;
      if (std < 0) continue;
      byStd.putIfAbsent(std, () => <Map<String, dynamic>>[]).add(c);
    }

    String findPrevTeacherFor(int srcStd, String targetSec) {
      final list = byStd[srcStd];
      if (list == null || list.isEmpty) return '';
      if (targetSec.isNotEmpty) {
        for (final c in list) {
          if (_extractClassSectionToken(c) == targetSec) {
            return _currentClassTeacherByClassId['${c['class_id'] ?? ''}'.trim()] ?? '';
          }
        }
      }
      return _currentClassTeacherByClassId['${list.first['class_id'] ?? ''}'.trim()] ?? '';
    }

    final hasBalvatika = byStd.containsKey(0);
    setState(() {
      _keepSameClassTeacher = false;
      for (final c in _classes) {
        final cid = '${c['class_id'] ?? ''}'.trim();
        final std = int.tryParse('${c['standard'] ?? -1}') ?? -1;
        final sec = _extractClassSectionToken(c);
        if (cid.isEmpty || std < 0) continue;

        String nextTid = _currentClassTeacherByClassId[cid] ?? '';
        if (std == 0) {
          // Balvatika gets previous Std 5 teacher (if exists)
          final t = findPrevTeacherFor(5, sec);
          if (t.isNotEmpty) nextTid = t;
        } else if (std >= 1 && std <= 5) {
          // Std 1..5 gets previous (std - 1) teacher (or Std 5 if std==1 and no Balvatika)
          final srcStd = (std == 1 && !hasBalvatika) ? 5 : (std - 1);
          final t = findPrevTeacherFor(srcStd, sec);
          if (t.isNotEmpty) nextTid = t;
        } else if (std == 6) {
          // Std 6 gets previous Std 8 teacher!
          final t = findPrevTeacherFor(8, sec);
          if (t.isNotEmpty) nextTid = t;
        } else if (std == 7 || std == 8) {
          // Std 7 gets previous Std 6 teacher; Std 8 gets previous Std 7 teacher
          final t = findPrevTeacherFor(std - 1, sec);
          if (t.isNotEmpty) nextTid = t;
        }
        _newClassTeacherMap[cid] = nextTid;
      }
    });
  }

  Widget _buildPromotionTab() {
    final canPromote = _preview['can_promote'] == true;
    final resultDateDmy = '${_preview['result_date_dmy'] ?? '30/04/2027'}';
    final todayIso = '${_preview['today_iso'] ?? ''}';
    final classLabels = _classLabelsById;

    // Build a globally deduplicated list of all active classes in the school
    final uniqueSchoolClasses = <Map<String, String>>[];
    final seenGlobalClassIds = <String>{};
    for (final cl in _classes) {
      final cid = '${cl['class_id'] ?? ''}'.trim();
      final lbl = '${cl['label'] ?? cl['class_key'] ?? ''}'.trim();
      if (cid.isNotEmpty && seenGlobalClassIds.add(cid)) {
        uniqueSchoolClasses.add(<String, String>{
          'id': cid,
          'label': lbl.isEmpty ? cid : lbl,
        });
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: canPromote ? Colors.green.shade50 : Colors.amber.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: canPromote ? Colors.green.shade600 : Colors.amber.shade800,
              width: 1.4,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitleWithActions(
                  leading: Icon(
                      canPromote
                          ? Icons.verified_outlined
                          : Icons.lock_clock_outlined,
                      color: canPromote
                          ? Colors.green.shade800
                          : Colors.deepOrange.shade800,
                      size: 26,
                    ),
                  title: Text(
                        'બીજા સત્રના પરિણામની તારીખ (Second Sem Result Date): $resultDateDmy',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _promoting ? null : _pickResultDate,
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('પરિણામ તારીખ બદલો'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _promoting ? null : _createNewClassFromPromotionDialog,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('+ નવો વર્ગ ઉમેરો (New Class)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '• બઢતીનો નિયમ: બાલવાટિકા → ધોરણ 1, અને ધોરણ 1 થી 7 → +1 ધોરણ (અથવા આપે પસંદ કરેલ નવો વર્ગ).\n'
                  '• ધોરણ 8 ના વિદ્યાર્થીઓ ધોરણ 9 માં જતા હોવાથી સક્રિય વર્ગમાંથી આપમેળે કમી (Remove) થશે.\n'
                  '• પહેલા આખા વર્ગ માટે નવો વર્ગ પસંદ કરો — જો કોઈ અમુક વિદ્યાર્થીઓનો જ વર્ગ બદલવો હોય તો નીચે તે વિદ્યાર્થી સામેથી અલગ વર્ગ પસંદ કરી શકાશે.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: canPromote ? Colors.green.shade100 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: canPromote ? Colors.green.shade600 : Colors.red.shade400,
                    ),
                  ),
                  child: Text(
                    canPromote
                        ? '✅ આજની તારીખ ($todayIso) બીજા સત્રના પરિણામની તારીખ ($resultDateDmy) અથવા ત્યારબાદની હોવાથી વર્ગ બઢતી સક્રિય છે.'
                        : '🔒 હાલ બીજા સત્રના પરિણામની તારીખ ($resultDateDmy) ભવિષ્યમાં છે (આજની તારીખ: $todayIso). નિયમ મુજબ બીજા સત્રના પરિણામની તારીખ ($resultDateDmy) ના રોજ અથવા ત્યારબાદ જ વર્ગ બઢતી (Class Promote) કરી શકાશે.',
                    style: TextStyle(
                      color: canPromote
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          canPromote && !_promoting ? _confirmAndPromote : null,
                      icon: _promoting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(canPromote ? Icons.trending_up : Icons.lock_outline),
                      label: Text(
                        _promoting
                            ? 'વર્ગ બઢતી થઈ રહી છે...'
                            : (canPromote
                                ? 'વર્ગ બઢતી કરો (Promote All Classes)'
                                : 'પરિણામ તારીખ ($resultDateDmy) ના રોજ અથવા પછી જ બઢતી થશે'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportingPromoted
                          ? null
                          : () => _exportPromotedStudentsFullExcel(
                                onlyStd8Graduated: false,
                              ),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text(
                        'બઢતી પામેલ અને ધોરણ-8 કમી વિદ્યાર્થીઓની સંપૂર્ણ Excel (Full Data)',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exportingPromoted
                          ? null
                          : () => _exportPromotedStudentsFullExcel(
                                onlyStd8Graduated: true,
                              ),
                      icon: const Icon(Icons.school_outlined),
                      label: const Text(
                        'ફક્ત ધોરણ-8 (Class 9 માં જનાર) સંપૂર્ણ Excel',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'બઢતી સેટિંગ્સ: નવા વર્ગમાં દાખલ તારીખ, વર્ગ શિક્ષક અને વર્ગવાર / વિદ્યાર્થીવાર નવો વર્ગ પસંદગી',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _newClassEnrollDateController,
                        enabled: canPromote && !_promoting,
                        decoration: InputDecoration(
                          labelText:
                              'નવા વર્ગમાં દાખલ તારીખ (New Class Enroll Date — ફક્ત બઢતી પામનાર માટે)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'તારીખ પસંદ કરો',
                            icon: const Icon(Icons.calendar_month),
                            onPressed: (!canPromote || _promoting)
                                ? null
                                : () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: now,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      helpText:
                                          'નવા વર્ગમાં દાખલ તારીખ (New Class Enroll Date)',
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _newClassEnrollDateController.text =
                                            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                      });
                                    }
                                  },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _keepSameClassTeacher,
                        onChanged: (!canPromote || _promoting)
                            ? null
                            : (v) => setState(
                                  () => _keepSameClassTeacher = v ?? true,
                                ),
                        title: const Text(
                          'નવા વર્ગમાં પણ તે જ વર્ગ શિક્ષક રાખો (Keep same Class Teacher for promoted class)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'જરૂર હોય તો Admin પછીથી Class & Teacher સેટિંગમાં બદલી શકશે.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '• દરેક વર્ગમાં ઉપર "આ આખા વર્ગને કયા વર્ગમાં બઢતી આપવી છે?" ડ્રોપડાઉનથી આખા વર્ગનો નવો વર્ગ પસંદ થશે.\n'
                  '• જો તેમાંથી અમુક જ વિદ્યાર્થીઓનો નવો વર્ગ બદલવો હોય, તો નીચે તે વિદ્યાર્થીની સામેના ડ્રોપડાઉનથી માત્ર તે જ વિદ્યાર્થીનો નવો વર્ગ બદલી શકાશે.\n'
                  '• જે વિદ્યાર્થીને બઢતી આપવાની નથી (નાપાસ / Retained) તેની સામે ટીક કરો — તેમની વર્ગ દાખલ તારીખ જૂની જ રહેશે.',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: const Text(
                    '✅ અગાઉના વર્ષના તમામ હાજરી અને પરિણામ રેકોર્ડ સુરક્ષિત (Archived) રહેશે.\n'
                    '📅 બઢતીના મહિનામાં હાજરીપત્રક (Hajari Patrak) માં બંને પત્રક — (૧) જૂના વર્ગ અને જૂની દાખલ તારીખ મુજબ અને (૨) નવા વર્ગ અને નવી દાખલ તારીખ મુજબ — પ્રિન્ટ કરી શકાશે.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                      height: 1.4,
                    ),
                  ),
                ),
                if (_schoolTeachers.isNotEmpty && _classes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_pin_rounded, color: Color(0xFF0F766E)),
                    title: const Text(
                      'નવા વર્ગ માટે વર્ગ શિક્ષક પસંદગી (New Class Teacher Dropdown)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    subtitle: const Text(
                      'ડિફોલ્ટ રૂપે તે જ વર્ગ શિક્ષક રહેશે. જરૂર મુજબ બાલવાટિકા–૫ સાથે જાય અને ધોરણ ૮→૬ રોટેશન અથવા કોઈપણ વર્ગના શિક્ષક બદલી શકો છો.',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: (!canPromote || _promoting)
                                ? null
                                : _applyKeepSameClassTeachersPreset,
                            icon: const Icon(Icons.lock_reset_rounded, size: 17),
                            label: const Text('તે જ વર્ગ શિક્ષક રાખો (Default)'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: (!canPromote || _promoting)
                                ? null
                                : _applyGujaratTeacherRotationPreset,
                            icon: const Icon(Icons.sync_rounded, size: 17),
                            label: const Text(
                              'બાલવાટિકા → ધોરણ 5 સાથે જાય + ધોરણ 8 → 6 રોટેશન',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final cl in _classes) ...[
                        Builder(
                          builder: (ctx) {
                            final cid = '${cl['class_id'] ?? ''}'.trim();
                            final cLabel = '${cl['label'] ?? cl['class_key'] ?? cid}'.trim();
                            final selTid = _newClassTeacherMap[cid] ?? '';
                            final validIds = _schoolTeachers
                                .map((t) => '${t['id'] ?? ''}'.trim())
                                .toSet();
                            final safeVal =
                                (selTid.isEmpty || validIds.contains(selTid))
                                    ? selTid
                                    : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      cLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: safeVal,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'નવો વર્ગ શિક્ષક',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: <DropdownMenuItem<String>>[
                                        const DropdownMenuItem<String>(
                                          value: '',
                                          child: Text('— પસંદ નથી (Unassigned) —'),
                                        ),
                                        for (final t in _schoolTeachers)
                                          DropdownMenuItem<String>(
                                            value: '${t['id'] ?? ''}'.trim(),
                                            child: Text(
                                              '${t['teacher_name'] ?? ''}'.trim(),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (!canPromote || _promoting)
                                          ? null
                                          : (v) {
                                              if (v != null) {
                                                setState(() {
                                                  _newClassTeacherMap[cid] = v;
                                                });
                                              }
                                            },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'વિદ્યાર્થી શોધો (Search student name or GR)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final c in _classes)
          Builder(
            builder: (context) {
              final curClassId = '${c['class_id'] ?? ''}'.trim();
              final label = '${c['label'] ?? ''}';
              final std = int.tryParse('${c['standard'] ?? 0}') ?? 0;
              final defaultNextId = '${c['next_class_id'] ?? ''}'.trim();
              final nextLabel = '${c['next_class_label'] ?? ''}';
              final candidateNextList = (c['candidate_next_classes'] is List)
                  ? (c['candidate_next_classes'] as List)
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList()
                  : <Map<String, dynamic>>[];
              final rawStudents = (c['students'] is List)
                  ? (c['students'] as List)
                  : const <dynamic>[];
              final students = rawStudents
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .where((s) {
                    if (_search.isEmpty) return true;
                    final q = _search.toLowerCase();
                    return '${s['name'] ?? ''}'.toLowerCase().contains(q) ||
                        '${s['gr'] ?? ''}'.toLowerCase().contains(q) ||
                        '${s['roll_number'] ?? ''}'.toLowerCase().contains(q);
                  })
                  .toList();

              // Build a strictly deduplicated target option list for this class
              // shared by both the Whole-Class dropdown and every Per-Student dropdown!
              final seenIds = <String>{};
              final allTargetOptions = <Map<String, String>>[];
              for (final cl in uniqueSchoolClasses) {
                final cid = cl['id']!;
                if (cid == curClassId || !seenIds.add(cid)) continue;
                final isDef = cid == defaultNextId;
                allTargetOptions.add(<String, String>{
                  'id': cid,
                  'label': isDef ? '★ ${cl['label']} (Default +1)' : cl['label']!,
                });
              }
              if (seenIds.add('__GRADUATE_9__')) {
                allTargetOptions.add(<String, String>{
                  'id': '__GRADUATE_9__',
                  'label': 'ધોરણ - 9 (શાળા પૂર્ણ / સક્રિય વર્ગમાંથી કમી)',
                });
              }

              final fallbackTargetId = std >= 8
                  ? '__GRADUATE_9__'
                  : (seenIds.contains(defaultNextId)
                      ? defaultNextId
                      : (allTargetOptions.isNotEmpty
                          ? allTargetOptions.first['id']!
                          : '__GRADUATE_9__'));

              final rawWholeChoice =
                  _classTargetClassMap[curClassId] ?? fallbackTargetId;
              final safeWholeChoice = seenIds.contains(rawWholeChoice)
                  ? rawWholeChoice
                  : fallbackTargetId;
              final wholeTargetLabel = safeWholeChoice == '__GRADUATE_9__'
                  ? 'ધોરણ - 9 (શાળા પૂર્ણ / કમી)'
                  : (classLabels[safeWholeChoice] ?? nextLabel);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(
                    '$label  ->  $wholeTargetLabel',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    std >= 8
                        ? 'કુલ વિદ્યાર્થીઓ: ${rawStudents.length} (ધોરણ 9 માં જતા હોવાથી બઢતી વખતે કમી થશે અને Excel માં નિકાસ થશે)'
                        : 'કુલ વિદ્યાર્થીઓ: ${rawStudents.length}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'આ આખા વર્ગને કયા વર્ગમાં બઢતી આપવી છે? (Whole Class Target):',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey('whole_${curClassId}_$safeWholeChoice'),
                              initialValue: seenIds.contains(safeWholeChoice)
                                  ? safeWholeChoice
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'આખા વર્ગ માટે નવો વર્ગ (Promote Whole Class To)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: allTargetOptions
                                  .map(
                                    (opt) => DropdownMenuItem<String>(
                                      value: opt['id'],
                                      child: Text(
                                        opt['label']!,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (!canPromote || _promoting)
                                  ? null
                                  : (val) {
                                      if (val == null) return;
                                      setState(() {
                                        _classTargetClassMap[curClassId] = val;
                                        for (final st
                                            in rawStudents.whereType<Map>()) {
                                          _studentTargetClassMap['${st['id']}'] =
                                              val;
                                        }
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (std < 8 && candidateNextList.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'ઝડપી વિભાગ પસંદગી (Quick Section): ',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: candidateNextList.map((cand) {
                                final candId = '${cand['id']}';
                                final candLbl = '${cand['label']}';
                                return ActionChip(
                                  label: Text('બધા -> $candLbl'),
                                  onPressed: (!canPromote || _promoting)
                                      ? null
                                      : () {
                                          setState(() {
                                            _classTargetClassMap[curClassId] =
                                                candId;
                                            for (final st in rawStudents
                                                .whereType<Map>()) {
                                              _studentTargetClassMap[
                                                  '${st['id']}'] = candId;
                                            }
                                          });
                                        },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    if (students.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('આ વર્ગમાં કોઈ વિદ્યાર્થી નથી.'),
                      ),
                    for (final st in students)
                      Builder(
                        builder: (context) {
                          final sid = '${st['id']}';
                          final retained = _retainedStudentIds.contains(sid);
                          final rawStuChoice =
                              _studentTargetClassMap[sid] ?? safeWholeChoice;
                          final safeStuChoice = seenIds.contains(rawStuChoice)
                              ? rawStuChoice
                              : safeWholeChoice;
                          final effNextLabel =
                              safeStuChoice == '__GRADUATE_9__'
                                  ? 'ધોરણ - 9 (શાળા પૂર્ણ / કમી)'
                                  : (classLabels[safeStuChoice] ??
                                      wholeTargetLabel);
                          return ListTile(
                            leading: Checkbox(
                              value: retained,
                              onChanged: (!canPromote || _promoting)
                                  ? null
                                  : (val) {
                                      setState(() {
                                        if (val == true) {
                                          _retainedStudentIds.add(sid);
                                        } else {
                                          _retainedStudentIds.remove(sid);
                                        }
                                      });
                                    },
                            ),
                            title: Text(
                              'Roll ${st['roll_number']} — ${st['name']} (GR: ${st['gr'] ?? '—'})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              retained
                                  ? 'બઢતી નહીં — આ જ વર્ગમાં રહેશે (Not Promoted • વર્ગ દાખલ તારીખ જૂની જ રહેશે)'
                                  : (safeStuChoice == '__GRADUATE_9__'
                                      ? 'ધોરણ 8 પૂર્ણ -> ધોરણ 9 માં જશે (સક્રિય વર્ગમાંથી કમી)'
                                      : 'બઢતી પામશે -> $effNextLabel (નવા વર્ગમાં દાખલ તારીખ: ${_newClassEnrollDateController.text})'),
                              style: TextStyle(
                                color: retained
                                    ? Colors.red.shade700
                                    : (safeStuChoice == '__GRADUATE_9__'
                                        ? Colors.deepPurple.shade700
                                        : Colors.green.shade700),
                              ),
                            ),
                            trailing: (!retained && allTargetOptions.isNotEmpty)
                                ? SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      key: ValueKey('stu_${sid}_$safeStuChoice'),
                                      initialValue:
                                          seenIds.contains(safeStuChoice)
                                              ? safeStuChoice
                                              : null,
                                      decoration: const InputDecoration(
                                        labelText: 'નવો વર્ગ / વિભાગ (New Class)',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                      ),
                                      items: allTargetOptions
                                          .map(
                                            (opt) => DropdownMenuItem<String>(
                                              value: opt['id'],
                                              child: Text(
                                                opt['label']!,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (!canPromote || _promoting)
                                          ? null
                                          : (val) {
                                              if (val == null) return;
                                              setState(() {
                                                _studentTargetClassMap[sid] =
                                                    val;
                                              });
                                            },
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSectionChangeAnytimeTab() {
    final currentClass = _classes.firstWhere(
      (c) => '${c['class_id']}' == _secFromClassId,
      orElse: () => _classes.isNotEmpty ? _classes.first : <String, dynamic>{},
    );
    final rawStudents = (currentClass['students'] is List)
        ? (currentClass['students'] as List)
        : const <dynamic>[];
    final students = rawStudents
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) {
          if (_secSearch.isEmpty) return true;
          final q = _secSearch.toLowerCase();
          return '${s['name'] ?? ''}'.toLowerCase().contains(q) ||
              '${s['gr'] ?? ''}'.toLowerCase().contains(q) ||
              '${s['roll_number'] ?? ''}'.toLowerCase().contains(q);
        })
        .toList();

    final seenSameStdIds = <String>{};
    final sameStdClasses = (currentClass['same_standard_classes'] is List)
        ? (currentClass['same_standard_classes'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((sc) {
              final id = '${sc['id'] ?? ''}'.trim();
              return id.isNotEmpty &&
                  id != _secFromClassId &&
                  seenSameStdIds.add(id);
            })
            .toList()
        : <Map<String, dynamic>>[];

    // Strictly restrict targetOptions to sections of the SAME standard only (e.g. Class 6-A -> Class 6-B / 6-C)
    final sameStdIdSet = sameStdClasses.map((sc) => '${sc['id']}').toSet();
    final seenTargetIds = <String>{};
    final targetOptions = _classes
        .where((c) {
          final cid = '${c['class_id'] ?? ''}'.trim();
          if (cid.isEmpty || cid == _secFromClassId) return false;
          if (!sameStdIdSet.contains(cid)) return false;
          return seenTargetIds.add(cid);
        })
        .toList();

    final safeSecToClassId =
        targetOptions.any((c) => '${c['class_id']}' == _secToClassId)
            ? _secToClassId
            : (targetOptions.isNotEmpty
                ? '${targetOptions.first['class_id']}'
                : '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitleWithActions(
                  leading: Icon(Icons.swap_horiz_rounded, color: Colors.teal.shade900),
                  title: Text(
                        'વર્ગ વિભાગ બદલો — કોઈપણ સમયે માત્ર તે જ ધોરણના વિભાગમાં (Same Class Section Change: A ↔ B ↔ C)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade900,
                        ),
                      ),
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _changingSection
                          ? null
                          : _createNewClassFromPromotionDialog,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('+ નવો વિભાગ ઉમેરો (New Section)'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '• વર્ષ દરમિયાન કોઈપણ સમયે વિદ્યાર્થીનો માત્ર તે જ ધોરણના અન્ય વિભાગમાં (દા.ત. ધોરણ 6-A માંથી 6-B કે 6-C માં) વિભાગ બદલી શકાશે (અન્ય ધોરણમાં નહીં).\n'
                  '• વિદ્યાર્થીનો તમામ પ્રોફાઈલ ડેટા (GR, જન્મ તારીખ, શાળા પ્રવેશ, જ્ઞાતિ/કેટેગરી, આધાર/KYC, શિષ્યવૃત્તિ, પરિણામ) નવા વિભાગમાં જશે, પરંતુ અગાઉની હાજરી (Attendance Record) વિભાગ બદલ્યા તારીખ સુધી જૂના વિભાગ (Section A) માં જ રહેશે અને ત્યારબાદની હાજરી નવા વિભાગ (Section B/C) માં નોંધાશે.\n'
                  '• હાજરીપત્રક (Hajari Patrak) Reprint નિયમ: જો માર્ચ દરમિયાન વિભાગ બદલાય તો માર્ચ સુધીના હાજરીપત્રકમાં વિદ્યાર્થી જૂના વિભાગ (Section A) માં પ્રિન્ટ થશે અને એપ્રિલથી નવા વિભાગ (Section B/C) માં પ્રિન્ટ થશે.',
                ),
                const SizedBox(height: 14),
                ResponsiveFields(breakpoint: 720, children: [
                  DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('sec_from_$_secFromClassId'),
                        initialValue: _classes
                                .any((c) => '${c['class_id']}' == _secFromClassId)
                            ? _secFromClassId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'હાલનો વર્ગ / વિભાગ (Current Section)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _classes
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: '${c['class_id']}',
                                child: Text('${c['label']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _secFromClassId = val;
                            _secSelectedStudentIds.clear();
                            final nextCls = _classes.firstWhere(
                              (c) => '${c['class_id']}' == val,
                              orElse: () => <String, dynamic>{},
                            );
                            final nextSameStd =
                                (nextCls['same_standard_classes'] is List)
                                    ? (nextCls['same_standard_classes'] as List)
                                        .whereType<Map>()
                                        .map((e) => Map<String, dynamic>.from(e))
                                        .where((sc) => '${sc['id']}' != val)
                                        .toList()
                                    : <Map<String, dynamic>>[];
                            _secToClassId = nextSameStd.isNotEmpty
                                ? '${nextSameStd.first['id']}'
                                : '';
                          });
                        },
                      ),
                  DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('sec_to_${_secFromClassId}_$safeSecToClassId'),
                        initialValue: safeSecToClassId.isNotEmpty
                            ? safeSecToClassId
                            : null,
                        decoration: InputDecoration(
                          labelText: targetOptions.isEmpty
                              ? 'આ ધોરણમાં અન્ય કોઈ વિભાગ (B/C) નથી'
                              : 'આ જ ધોરણનો નવો વિભાગ (Target Section A/B/C)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: targetOptions.map((c) {
                          final cid = '${c['class_id']}';
                          return DropdownMenuItem<String>(
                            value: cid,
                            child: Text(
                              '★ ${c['label']} (આ જ ધોરણનો વિભાગ)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: targetOptions.isEmpty
                            ? null
                            : (val) {
                                if (val == null) return;
                                setState(() => _secToClassId = val);
                              },
                      ),
                  TextField(
                        controller: _secEffectiveDateController,
                        decoration: InputDecoration(
                          labelText: 'વિભાગ બદલ્યા તારીખ (Effective Date)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'તારીખ પસંદ કરો',
                            icon: const Icon(Icons.calendar_month),
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                helpText: 'વિભાગ બદલ્યા તારીખ (Section Change Date)',
                              );
                              if (picked != null) {
                                setState(() {
                                  _secEffectiveDateController.text =
                                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                });
                              }
                            },
                          ),
                        ),
                      ),
                ]),
                if (targetOptions.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ℹ️ "${currentClass['label'] ?? ''}" ધોરણમાં હાલ બીજો કોઈ વિભાગ (Section B / C) બનાવેલ નથી. ઉપર "+ નવો વિભાગ ઉમેરો" બટનથી આ જ ધોરણનો નવો વિભાગ ઉમેરી શકો છો.',
                    style: TextStyle(
                      color: Colors.deepOrange.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: (_changingSection ||
                              _secSelectedStudentIds.isEmpty ||
                              safeSecToClassId.isEmpty)
                          ? null
                          : () => _executeSectionChangeAnytime(
                                studentIds: _secSelectedStudentIds.toList(),
                                toClassId: safeSecToClassId,
                              ),
                      icon: _changingSection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz),
                      label: Text(
                        'પસંદ કરેલા ${_secSelectedStudentIds.length} વિદ્યાર્થીઓનો વિભાગ બદલો',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          for (final s in students) {
                            _secSelectedStudentIds.add('${s['id']}');
                          }
                        });
                      },
                      child: const Text('બધા પસંદ કરો (Select All)'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _secSelectedStudentIds.clear()),
                      child: const Text('પસંદગી દૂર કરો (Clear)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            labelText: 'વિદ્યાર્થી શોધો (Search by name, roll, or GR)',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _secSearch = v.trim()),
        ),
        const SizedBox(height: 10),
        if (students.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('આ વર્ગ/વિભાગમાં કોઈ વિદ્યાર્થી નથી.')),
            ),
          )
        else
          for (final st in students)
            Builder(
              builder: (context) {
                final sid = '${st['id']}';
                final checked = _secSelectedStudentIds.contains(sid);
                final quickTargets = sameStdClasses;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: Checkbox(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _secSelectedStudentIds.add(sid);
                          } else {
                            _secSelectedStudentIds.remove(sid);
                          }
                        });
                      },
                    ),
                    title: Text(
                      'Roll ${st['roll_number']} — ${st['name']} (GR: ${st['gr'] ?? '—'})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'DOB: ${st['dd'] ?? ''}/${st['mm'] ?? ''}/${st['yyyy'] ?? ''} • શાળા પ્રવેશ: ${st['enroll_school'] ?? '—'} • હાજર દિવસો: ${st['present_days'] ?? 0}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        for (final qt in quickTargets)
                          ActionChip(
                            avatar: const Icon(Icons.swap_horiz, size: 16),
                            label: Text('-> ${qt['label']}'),
                            onPressed: _changingSection
                                ? null
                                : () => _executeSectionChangeAnytime(
                                      studentIds: <String>[sid],
                                      toClassId: '${qt['id']}',
                                    ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }

  Widget _buildPromotedAndStd8ExportTab() {
    final gradStd8 = _graduatedStd8Students;
    final promotedHist = _promotedStudentsHistory;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'બઢતી પામેલ અને ધોરણ-8 (Class 9 માં જનાર) વિદ્યાર્થીઓની સંપૂર્ણ ડેટા Excel Export',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• અગાઉના વર્ગમાંથી બઢતી પામેલ સક્રિય વિદ્યાર્થીઓ: ${promotedHist.length}\n'
                  '• ધોરણ 8 પૂર્ણ કરી ધોરણ 9 માં જનાર (કમી થયેલ) વિદ્યાર્થીઓ: ${gradStd8.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'આ Excel ફાઇલમાં દરેક વિદ્યાર્થીનો સંપૂર્ણ ડેટા (અગાઉનું ધોરણ, નવું ધોરણ/વિભાગ, જૂનો/નવો રોલ નંબર, GR, નામ, ધર્મ ગુજરાતી/અંગ્રેજી, જ્ઞાતિ, કેટેગરી, જન્મ તારીખ, શાળા પ્રવેશ, UID, PEN, APAAR, બેંક વિગતો અને કસ્ટમ હેડર) સામેલ થાય છે.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _exportingPromoted
                          ? null
                          : () => _exportPromotedStudentsFullExcel(
                                onlyStd8Graduated: false,
                              ),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text(
                        'તમામ બઢતી પામેલ + ધોરણ-8 વિદ્યાર્થીઓની સંપૂર્ણ Excel ડાઉનલોડ કરો',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _exportingPromoted
                          ? null
                          : () => _exportPromotedStudentsFullExcel(
                                onlyStd8Graduated: true,
                              ),
                      icon: const Icon(Icons.school_outlined),
                      label: Text(
                        'ફક્ત ધોરણ-8 થી ધોરણ-9 (${gradStd8.length}) સંપૂર્ણ Excel ડાઉનલોડ કરો',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ધોરણ 8 પૂર્ણ કરી ધોરણ 9 માં ગયેલ વિદ્યાર્થીઓ (${gradStd8.length})',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (gradStd8.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'હાલમાં ધોરણ 8 પૂર્ણ કરેલ કોઈ વિદ્યાર્થી નોંધાયેલ નથી (તમે ઉપરના બટનથી વર્તમાન ધોરણ 8 ના વિદ્યાર્થીઓની Preview Excel પણ ડાઉનલોડ કરી શકો છો).',
              ),
            ),
          )
        else
          for (final st in gradStd8)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    '${st['previous_roll_number'] ?? st['roll_number'] ?? '8'}',
                  ),
                ),
                title: Text(
                  '${st['name'] ?? ''} (GR: ${st['gr'] ?? '—'})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${st['promoted_from_class_label'] ?? 'ધોરણ - 8'} -> ${st['promoted_to_class_label'] ?? 'ધોરણ - 9'} • તારીખ: ${st['promoted_at'] ?? st['leaving_date'] ?? ''}',
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Class Promote & Section Change / વર્ગ બઢતી અને વિભાગ બદલો',
          ),
          actions: [
            IconButton(
              tooltip: 'Export Promoted Students Full Excel',
              onPressed: _loading || _exportingPromoted
                  ? null
                  : () => _exportPromotedStudentsFullExcel(
                        onlyStd8Graduated: false,
                      ),
              icon: const Icon(Icons.file_download_outlined),
            ),
            IconButton(
              onPressed: _loading || _promoting ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                icon: Icon(Icons.trending_up),
                text: '૧. વર્ગ બઢતી (Class Promote +1 & Std 8)',
              ),
              Tab(
                icon: Icon(Icons.swap_horiz),
                text: '૨. વિભાગ બદલો (Section Change A ↔ B ↔ C Anytime)',
              ),
              Tab(
                icon: Icon(Icons.table_view_outlined),
                text: '૩. બઢતી અને ધોરણ-8 Excel Export (Full Data)',
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildPromotionTab(),
                  _buildSectionChangeAnytimeTab(),
                  _buildPromotedAndStd8ExportTab(),
                ],
              ),
      ),
    );
  }
}

class SupabaseDeveloperSharedFilesAdminScreen extends StatefulWidget {
  const SupabaseDeveloperSharedFilesAdminScreen({super.key});

  @override
  State<SupabaseDeveloperSharedFilesAdminScreen> createState() =>
      _SupabaseDeveloperSharedFilesAdminScreenState();
}

class _SupabaseDeveloperSharedFilesAdminScreenState
    extends State<SupabaseDeveloperSharedFilesAdminScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _files = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _downloadingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.rpc('psm_get_developer_shared_files');
      if (!mounted) return;
      final list = res is List
          ? res
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _files = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _formatBytes(dynamic raw) {
    final n = int.tryParse('${raw ?? 0}') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final id = '${file['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    setState(() {
      _downloadingId = id;
      _error = null;
    });
    try {
      final res = await _client.rpc(
        'psm_download_developer_shared_file',
        params: <String, dynamic>{'p_file_id': id},
      );
      final map = res is Map
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{};
      final b64 = '${map['base64'] ?? ''}'.trim();
      if (b64.isEmpty) {
        throw StateError('File content could not be found in Cloud Storage.');
      }
      final bytes = base64Decode(b64);
      final fileName =
          '${map['file_name'] ?? file['file_name'] ?? 'developer_file'}'.trim();
      final mime =
          '${map['mime_type'] ?? file['mime_type'] ?? 'application/octet-stream'}'
              .trim();
      await PsmFileExportHelper.saveOrShare(
        bytes: Uint8List.fromList(bytes),
        filename: fileName,
        title: '${file['title'] ?? fileName}',
        mimeType: mime,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Files / ડેવલપર તરફથી ફાઈલ ડાઉનલોડ'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'હાલમાં ડેવલપર તરફથી કોઈ ફાઈલ ઉપલબ્ધ નથી.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    for (final f in _files)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.cloud_download_outlined),
                          ),
                          title: Text(
                            '${f['title'] ?? f['file_name'] ?? 'File'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${f['file_name'] ?? ''} • ${_formatBytes(f['size_bytes'])}${'${f['description'] ?? ''}'.trim().isNotEmpty ? '\n${f['description']}' : ''}',
                          ),
                          isThreeLine:
                              '${f['description'] ?? ''}'.trim().isNotEmpty,
                          trailing: FilledButton.icon(
                            onPressed: _downloadingId != null
                                ? null
                                : () => _downloadFile(f),
                            icon: _downloadingId == '${f['id']}'
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download),
                            label: const Text('Download'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}


class SupabaseAdminGlobalStudentSearchScreen extends StatefulWidget {
  const SupabaseAdminGlobalStudentSearchScreen({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<SupabaseAdminGlobalStudentSearchScreen> createState() =>
      _SupabaseAdminGlobalStudentSearchScreenState();
}

class _SupabaseAdminGlobalStudentSearchScreenState
    extends State<SupabaseAdminGlobalStudentSearchScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allStudents = <Map<String, dynamic>>[];
  Map<String, String> _classLabels = <String, String>{};
  String _statusFilter = 'ALL'; // ALL, ACTIVE, PROMOTED_STD8, DEACTIVE
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ref = await _schoolRef(_client);
      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order')
          .eq('school_ref', ref);
      final labels = <String, String>{};
      for (final c in classRows) {
        if (c is Map) {
          labels['${c['id']}'] = '${c['label'] ?? c['class_key'] ?? ''}';
        }
      }
      final stuRows = await _client
          .from('students')
          .select('*')
          .eq('school_ref', ref);
      final list = <Map<String, dynamic>>[];
      for (final r in stuRows) {
        if (r is Map) {
          list.add(Map<String, dynamic>.from(r));
        }
      }
      if (!mounted) return;
      setState(() {
        _classLabels = labels;
        _allStudents = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  bool _isStd8Graduated(Map<String, dynamic> s) {
    return '${s['promoted_to_standard'] ?? ''}'.trim() == '9' ||
        s['graduated_from_std_8'] == true ||
        '${s['leaving_reason_gu'] ?? ''}'.contains('ધોરણ 8') ||
        '${s['leaving_reason_en'] ?? ''}'.toLowerCase().contains('promoted to std 9');
  }

  bool _isActiveStudent(Map<String, dynamic> s) {
    return s['is_active'] == true &&
        '${s['leaving_date'] ?? ''}'.trim().isEmpty &&
        '${s['exit_date'] ?? ''}'.trim().isEmpty;
  }

  String _studentStatusLabel(Map<String, dynamic> s) {
    if (_isStd8Graduated(s)) {
      return 'Promoted Std 8 -> 9 (ધોરણ-8 પૂર્ણ)';
    }
    if (_isActiveStudent(s)) {
      final fromLbl = '${s['promoted_from_class_label'] ?? ''}'.trim();
      return fromLbl.isNotEmpty
          ? 'Active • બઢતી પામેલ ($fromLbl માંથી)'
          : 'Active (સક્રિય)';
    }
    return 'Deactive / કમી (${s['leaving_date'] ?? s['exit_date'] ?? ''})';
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final tokens = q
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return _allStudents.where((s) {
      if (_statusFilter == 'ACTIVE' && !_isActiveStudent(s)) return false;
      if (_statusFilter == 'PROMOTED_STD8' &&
          !_isStd8Graduated(s) &&
          '${s['promoted_from_class_label'] ?? ''}'.trim().isEmpty) {
        return false;
      }
      if (_statusFilter == 'DEACTIVE' && _isActiveStudent(s)) return false;

      if (tokens.isEmpty) return true;
      final searchable = <String>[
        '${s['gr'] ?? ''}',
        '${s['roll_number'] ?? ''}',
        '${s['previous_roll_number'] ?? ''}',
        '${s['name'] ?? ''}',
        '${s['name_en'] ?? ''}',
        '${s['father_name'] ?? ''}',
        '${s['mother_name'] ?? ''}',
        '${s['mother_en'] ?? ''}',
        '${s['mobile'] ?? ''}',
        '${s['uid'] ?? ''}',
        '${s['pen'] ?? ''}',
        '${s['apaar_id'] ?? ''}',
        '${s['caste'] ?? ''}',
        '${s['religion'] ?? ''}',
        _classLabels['${s['class_id']}'] ?? '',
        '${s['promoted_from_class_label'] ?? ''}',
        '${s['promoted_to_class_label'] ?? ''}',
      ].join(' ').toLowerCase();
      return tokens.every((t) => searchable.contains(t));
    }).toList();
  }

  Future<void> _exportStudentsWholeDataExcel(
    List<Map<String, dynamic>> rows, {
    String filePrefix = 'ADMIN_STUDENT_WHOLE_DATA',
  }) async {
    if (rows.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final wb = ec.Excel.createExcel();
      final def = wb.getDefaultSheet() ?? 'Sheet1';
      const sName = 'Students Whole Data';
      if (def != sName) wb.rename(def, sName);
      final sheet = wb[sName];

      const headers = <String>[
        'Status / સ્થિતિ',
        'Current Class / હાલનું ધોરણ',
        'Promoted From / અગાઉનું ધોરણ',
        'Promoted To / બઢતી ધોરણ',
        'Roll Number / રોલ નંબર',
        'Previous Roll / જૂનો રોલ નંબર',
        'GR Number / જનરલ રજીસ્ટર નંબર',
        'Student Name (Surname Name Father) / વિદ્યાર્થીનું નામ',
        'Name in English',
        'Father Name / પિતાનું નામ',
        'Mother Name / માતાનું નામ',
        'Mother Name (EN)',
        'Gender / જાતિ',
        'Category / કેટેગરી',
        'Caste / જ્ઞાતિ',
        'Caste (EN)',
        'Religion / ધર્મ',
        'Religion (EN)',
        'DOB (DD/MM/YYYY) / જન્મ તારીખ',
        'DOB in Words / જન્મ તારીખ શબ્દોમાં',
        'Birth Place / જન્મ સ્થળ',
        'School Enroll Date / શાળા પ્રવેશ તારીખ',
        'Class Enroll Date / વર્ગ પ્રવેશ તારીખ',
        'Enroll Std / દાખલ ધોરણ',
        'Last School / છેલ્લી શાળા',
        'Mobile / મોબાઇલ નંબર',
        'Address / સરનામું',
        'Native Place / વતન',
        'UID / Aadhaar',
        'Has Aadhaar',
        'PEN Number',
        'APAAR ID',
        'Ration Card KYC',
        'Scholarship Done',
        'Scholarship Reason',
        'Bank Name',
        'Bank Branch',
        'Account Number',
        'IFSC Code',
        'Name as Passbook',
        'Present Days / હાજર દિવસો',
        'Leaving Date / શાળા છોડ્યા તારીખ',
      ];
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(ec.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = ec.TextCellValue(headers[c]);
      }
      for (var r = 0; r < rows.length; r++) {
        final s = rows[r];
        final cls = _classLabels['${s['class_id']}'] ??
            '${s['class_label'] ?? s['promoted_from_class_label'] ?? ''}';
        final vals = <String>[
          _studentStatusLabel(s),
          cls,
          '${s['promoted_from_class_label'] ?? ''}',
          '${s['promoted_to_class_label'] ?? ''}',
          '${s['roll_number'] ?? ''}',
          '${s['previous_roll_number'] ?? ''}',
          '${s['gr'] ?? ''}',
          '${s['name'] ?? ''}',
          '${s['name_en'] ?? ''}',
          '${s['father_name'] ?? ''}',
          '${s['mother_name'] ?? ''}',
          '${s['mother_en'] ?? ''}',
          '${s['gender'] ?? ''}',
          '${s['category'] ?? ''}',
          '${s['caste'] ?? ''}',
          '${s['caste_en'] ?? ''}',
          '${s['religion'] ?? ''}',
          '${s['religion_en'] ?? ''}',
          '${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''}',
          '${s['dob_words'] ?? ''}',
          '${s['birth_place'] ?? ''}',
          '${s['enroll_school'] ?? ''}',
          '${s['enroll_class'] ?? ''}',
          '${s['enroll_sch_class'] ?? ''}',
          '${s['last_school'] ?? ''}',
          '${s['mobile'] ?? ''}',
          '${s['address'] ?? ''}',
          '${s['native_place'] ?? ''}',
          '${s['uid'] ?? ''}',
          '${s['has_aadhaar'] ?? ''}',
          '${s['pen'] ?? ''}',
          '${s['apaar_id'] ?? ''}',
          '${s['ration_card_kyc'] ?? ''}',
          '${s['scholarship_done'] ?? ''}',
          '${s['scholarship_reason'] ?? ''}',
          '${s['bank_name'] ?? ''}',
          '${s['bank_branch'] ?? ''}',
          '${s['account_number'] ?? ''}',
          '${s['ifsc_code'] ?? ''}',
          '${s['name_as_passbook'] ?? ''}',
          '${s['present_days'] ?? ''}',
          '${s['leaving_date'] ?? s['exit_date'] ?? ''}',
        ];
        for (var c = 0; c < vals.length; c++) {
          sheet
              .cell(
                ec.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
              )
              .value = ec.TextCellValue(vals[c]);
        }
      }
      final bytes = wb.encode();
      if (bytes != null && bytes.isNotEmpty) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(bytes),
          filename: '${filePrefix}_$today.xlsx',
          title: 'Admin Student Whole Data Excel',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showWholeDataModal(Map<String, dynamic> s) {
    final cls = _classLabels['${s['class_id']}'] ??
        '${s['class_label'] ?? s['promoted_from_class_label'] ?? '-'}';
    final items = <MapEntry<String, String>>[
      MapEntry('સ્થિતિ (Status)', _studentStatusLabel(s)),
      MapEntry('વર્ગ (Current / Last Class)', cls),
      MapEntry('અગાઉનું ધોરણ (Promoted From)', '${s['promoted_from_class_label'] ?? '-'} (Old Roll: ${s['previous_roll_number'] ?? '-'})'),
      MapEntry('બઢતી ધોરણ (Promoted To)', '${s['promoted_to_class_label'] ?? '-'} (${s['promoted_at'] ?? '-'})'),
      MapEntry('રોલ નંબર (Roll Number)', '${s['roll_number'] ?? '-'}'),
      MapEntry('GR નંબર (GR Number)', '${s['gr'] ?? '-'}'),
      MapEntry('વિદ્યાર્થીનું પૂરું નામ (Surname Name Father)', '${s['name'] ?? '-'}'),
      MapEntry('Name in English', '${s['name_en'] ?? '-'}'),
      MapEntry('પિતાનું નામ (Father Name)', '${s['father_name'] ?? '-'}'),
      MapEntry('માતાનું નામ (Mother Name)', '${s['mother_name'] ?? '-'} (${s['mother_en'] ?? ''})'),
      MapEntry('જન્મ તારીખ (DOB)', '${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''} (${s['dob_words'] ?? ''})'),
      MapEntry('જાતિ / કેટેગરી (Gender / Category)', '${s['gender'] ?? '-'} / ${s['category'] ?? '-'}'),
      MapEntry('જ્ઞાતિ / ધર્મ (Caste / Religion)', '${s['caste'] ?? '-'} / ${s['religion'] ?? '-'} (${s['religion_en'] ?? ''})'),
      MapEntry('શાળા પ્રવેશ તારીખ (School Enroll Date)', '${s['enroll_school'] ?? '-'}'),
      MapEntry('વર્ગ પ્રવેશ તારીખ (Class Enroll Date)', '${s['enroll_class'] ?? '-'}'),
      MapEntry('મોબાઇલ નંબર (Mobile)', '${s['mobile'] ?? '-'}'),
      MapEntry('સરનામું / વતન (Address / Native)', '${s['address'] ?? ''} ${s['native_place'] ?? ''}'),
      MapEntry('UID / PEN / APAAR ID', 'UID: ${s['uid'] ?? '-'} | PEN: ${s['pen'] ?? '-'} | APAAR: ${s['apaar_id'] ?? '-'}'),
      MapEntry('બેંક વિગત (Bank / Account / IFSC)', '${s['bank_name'] ?? '-'} (${s['bank_branch'] ?? '-'}) • A/C: ${s['account_number'] ?? '-'} • IFSC: ${s['ifsc_code'] ?? '-'}'),
      MapEntry('હાજર દિવસો (Present Days)', '${s['present_days'] ?? '-'}'),
      MapEntry('શાળા છોડ્યા તારીખ (Leaving Date)', '${s['leaving_date'] ?? s['exit_date'] ?? '-'}'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('વિદ્યાર્થીનો સંપૂર્ણ ડેટા (Whole Data) — ${s['name'] ?? ''}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 230,
                          child: Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(child: SelectableText(e.value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _exportStudentsWholeDataExcel(
                <Map<String, dynamic>>[s],
                filePrefix: 'STUDENT_DATA_GR_${s['gr'] ?? s['roll_number'] ?? '1'}',
              );
            },
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('આ વિદ્યાર્થીની Excel ડાઉનલોડ કરો'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('બંધ કરો (Close)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Student Search (GR / Roll / Name — Whole Data)',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.person_search),
                          labelText:
                              'GR નંબર, રોલ નંબર, અથવા નામના કોઈપણ ભાગથી શોધો (અટક / નામ / પિતાનું નામ / માતાનું નામ)',
                          hintText:
                              'દા.ત. GR નંબર, રોલ નંબર, અટક, વિદ્યાર્થીનું નામ કે પિતાનું નામ લખો...',
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                            label: Text('બધા (All: ${_allStudents.length})'),
                            selected: _statusFilter == 'ALL',
                            onSelected: (_) =>
                                setState(() => _statusFilter = 'ALL'),
                          ),
                          ChoiceChip(
                            label: const Text('સક્રિય (Active)'),
                            selected: _statusFilter == 'ACTIVE',
                            onSelected: (_) =>
                                setState(() => _statusFilter = 'ACTIVE'),
                          ),
                          ChoiceChip(
                            label: const Text(
                              'બઢતી પામેલ અને ધોરણ 8 -> 9 (Promoted & Std 8)',
                            ),
                            selected: _statusFilter == 'PROMOTED_STD8',
                            onSelected: (_) =>
                                setState(() => _statusFilter = 'PROMOTED_STD8'),
                          ),
                          ChoiceChip(
                            label: const Text('નિષ્ક્રિય / કમી (Deactive)'),
                            selected: _statusFilter == 'DEACTIVE',
                            onSelected: (_) =>
                                setState(() => _statusFilter = 'DEACTIVE'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _exporting || results.isEmpty
                                ? null
                                : () => _exportStudentsWholeDataExcel(results),
                            icon: const Icon(Icons.file_download_outlined),
                            label: Text(
                              'શોધેલા (${results.length}) વિદ્યાર્થીઓની Whole Data Excel ડાઉનલોડ કરો',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: results.isEmpty
                      ? const Center(
                          child: Text('કોઈ વિદ્યાર્થી મળ્યો નથી.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: results.length,
                          itemBuilder: (context, idx) {
                            final s = results[idx];
                            final cls = _classLabels['${s['class_id']}'] ??
                                '${s['class_label'] ?? s['promoted_from_class_label'] ?? '-'}';
                            final isGrad8 = _isStd8Graduated(s);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isGrad8
                                      ? Colors.deepPurple.shade100
                                      : null,
                                  child: Text(
                                    '${s['roll_number'] ?? idx + 1}',
                                  ),
                                ),
                                title: Text(
                                  '${s['name'] ?? ''} (GR: ${s['gr'] ?? '-'} • Roll: ${s['roll_number'] ?? '-'})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'વર્ગ: $cls • ${_studentStatusLabel(s)} • પિતા: ${s['father_name'] ?? '-'} • માતા: ${s['mother_name'] ?? '-'} • DOB: ${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''} • Mobile: ${s['mobile'] ?? '-'}',
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showWholeDataModal(s),
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Whole Data'),
                                    ),
                                    IconButton(
                                      tooltip: 'Download Student Excel',
                                      onPressed: () =>
                                          _exportStudentsWholeDataExcel(
                                        <Map<String, dynamic>>[s],
                                        filePrefix:
                                            'STUDENT_GR_${s['gr'] ?? s['roll_number'] ?? '1'}',
                                      ),
                                      icon: const Icon(
                                        Icons.file_download_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class SupabaseAdminBackupAndResetScreen extends StatefulWidget {
  const SupabaseAdminBackupAndResetScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<SupabaseAdminBackupAndResetScreen> createState() =>
      _SupabaseAdminBackupAndResetScreenState();
}

class _SupabaseAdminBackupAndResetScreenState
    extends State<SupabaseAdminBackupAndResetScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _downloadingBackups = false;
  bool _deleting = false;
  bool _backupCompleted = false;
  String _selectedScope = 'all'; // attendance, students, library, all
  String _attendanceDeleteMode = 'whole'; // whole, date_range
  DateTime _attFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _attToDate = DateTime.now();
  List<String> _downloadedFiles = <String>[];
  String? _statusMessage;
  String? _error;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickAttDate({required bool isFrom}) async {
    final initial = isFrom ? _attFromDate : _attToDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: isFrom
          ? 'શરૂઆતની તારીખ પસંદ કરો (From Date)'
          : 'અંતિમ તારીખ પસંદ કરો (To Date)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _attFromDate = DateTime(picked.year, picked.month, picked.day);
        if (_attFromDate.isAfter(_attToDate)) _attToDate = _attFromDate;
      } else {
        _attToDate = DateTime(picked.year, picked.month, picked.day);
        if (_attToDate.isBefore(_attFromDate)) _attFromDate = _attToDate;
      }
    });
  }

  void _setCell(ec.Sheet sheet, int row, int col, String value) {
    sheet
        .cell(ec.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value = ec.TextCellValue(value);
  }

  Future<void> _downloadAttendanceOnlyExcel({
    required String ref,
    required String schoolId,
    required String schoolName,
    required String schoolType,
    required bool dateRangeOnly,
  }) async {
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final clsRaw = await _client
        .from('school_classes')
        .select('*')
        .eq('school_ref', ref);
    final classRows = SchoolClassOrder.sorted(
      clsRaw.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        m['school_type'] ??= schoolType;
        return m;
      }),
    );
    final classById = <String, Map<String, dynamic>>{
      for (final c in classRows) '${c['id']}': c,
    };
    final attRaw = await _client
        .from('attendance_days')
        .select('*')
        .eq('school_ref', ref);
    final fromFilter = _iso(_attFromDate);
    final toFilter = _iso(_attToDate);
    final attendanceRows = <Map<String, dynamic>>[];
    for (final r in attRaw) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final dt = '${m['attendance_date'] ?? ''}'.trim();
      final dShort = dt.length >= 10 ? dt.substring(0, 10) : dt;
      if (dateRangeOnly && dShort.isNotEmpty) {
        if (dShort.compareTo(fromFilter) < 0 || dShort.compareTo(toFilter) > 0) {
          continue;
        }
      }
      final cid = '${m['class_id'] ?? ''}';
      final cRow = classById[cid] ?? const <String, dynamic>{};
      m['class_key'] ??= cRow['class_key'] ?? '';
      m['class_label'] ??= cRow['label'] ?? cRow['class_key'] ?? '';
      m['label'] ??= cRow['label'] ?? cRow['class_key'] ?? '';
      m['sheet_name'] ??= cRow['sheet_name'] ?? cRow['label'] ?? '';
      m['standard'] ??= cRow['standard'] ?? '';
      m['section'] ??= cRow['section'] ?? '';
      m['report_group'] ??= cRow['report_group'] ?? '';
      m['sort_order'] ??= cRow['sort_order'] ?? 0;
      m['school_type'] ??= schoolType;
      attendanceRows.add(m);
    }
    final dates = attendanceRows
        .map((r) => '${r['attendance_date'] ?? ''}'.trim())
        .where((d) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d))
        .toList()
      ..sort();
    final fromDate = dateRangeOnly
        ? fromFilter
        : (dates.isNotEmpty ? dates.first : todayIso);
    final toDate = dateRangeOnly
        ? toFilter
        : (dates.isNotEmpty ? dates.last : todayIso);
    final visibleKeys = DateWiseReportColumn.keysForSchoolType(schoolType);
    final attBytes =
        await SupabaseReportExportService().exportClasswiseAllDataXlsx(
      schoolName: schoolName,
      fromDate: fromDate,
      toDate: toDate,
      classRows: classRows,
      attendanceRows: attendanceRows,
      visibleColumnKeys: visibleKeys,
    );
    final f1 = dateRangeOnly
        ? '1_EKANDAR_CLASSWISE_ATTENDANCE_${schoolId}_${fromDate}_TO_$toDate.xlsx'
        : '1_EKANDAR_CLASSWISE_ATTENDANCE_${schoolId}_$todayIso.xlsx';
    await PsmFileExportHelper.saveOrShare(
      bytes: attBytes,
      filename: f1,
      title: '1. Ekandar & Class-wise Attendance ($schoolName)',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    _downloadedFiles.add(f1);
  }

  Future<void> _downloadAllSchoolBackupsOneByOne() async {
    if (_downloadingBackups || _deleting) return;
    setState(() {
      _downloadingBackups = true;
      _error = null;
      _downloadedFiles = <String>[];
      _statusMessage = 'શાળાના તમામ રિપોર્ટ એક પછી એક Excel માં બની રહ્યા છે...';
    });
    try {
      final ref = await _schoolRef(_client);
      final schoolRow = await _client
          .from('schools')
          .select('school_type,school_id,school_name,school_name_gu,school_name_en')
          .eq('id', ref)
          .maybeSingle();
      final schoolType = DateWiseReportColumn.normalizeSchoolType(
        schoolRow?['school_type'] ??
            widget.profile['school_type'] ??
            widget.profile['schoolType'],
      );
      final schoolId =
          '${schoolRow?['school_id'] ?? widget.profile['school_id'] ?? widget.profile['schoolDiseCode'] ?? 'SCHOOL'}'
              .trim();
      final schoolName =
          '${schoolRow?['school_name_gu'] ?? schoolRow?['school_name_en'] ?? schoolRow?['school_name'] ?? widget.profile['school_name_gu'] ?? widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? 'School'}'
              .trim();
      final todayIso = DateTime.now().toIso8601String().substring(0, 10);

      // 1. Ekandar & Class-wise Attendance Report Excel
      setState(() {
        _statusMessage =
            '1/5: Ekandar & Class-wise Attendance Report Excel ડાઉનલોડ થઈ રહી છે...';
      });
      await _downloadAttendanceOnlyExcel(
        ref: ref,
        schoolId: schoolId,
        schoolName: schoolName,
        schoolType: schoolType,
        dateRangeOnly: _attendanceDeleteMode == 'date_range',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final clsRaw = await _client
          .from('school_classes')
          .select('*')
          .eq('school_ref', ref);
      final classRows = SchoolClassOrder.sorted(
        clsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      final classById = <String, Map<String, dynamic>>{
        for (final c in classRows) '${c['id']}': c,
      };

      // 2. Whole School Students Data (Active + Deactive + Promoted Class 8->9)
      if (!mounted) return;
      setState(() {
        _statusMessage =
            '2/5: Students Whole Data (Promoted સહિત) Excel ડાઉનલોડ થઈ રહી છે...';
      });
      final stuRaw = await _client
          .from('students')
          .select('*')
          .eq('school_ref', ref);
      final wbStu = ec.Excel.createExcel();
      final defStu = wbStu.getDefaultSheet() ?? 'Sheet1';
      if (defStu != 'Students Whole Data') {
        wbStu.rename(defStu, 'Students Whole Data');
      }
      final sStu = wbStu['Students Whole Data'];
      const stuHeaders = <String>[
        'Status',
        'Class / ધોરણ',
        'Promoted From',
        'Promoted To',
        'Roll No',
        'Old Roll No',
        'GR No',
        'Student Name / વિદ્યાર્થીનું નામ',
        'Name (EN)',
        'Father Name / પિતાનું નામ',
        'Mother Name / માતાનું નામ',
        'Gender',
        'Category',
        'Caste / જ્ઞાતિ',
        'Religion / ધર્મ',
        'DOB (DD/MM/YYYY)',
        'Enroll School Date',
        'Enroll Class Date',
        'Mobile',
        'UID / Aadhaar',
        'PEN',
        'APAAR ID',
        'Bank Name',
        'Account Number',
        'IFSC Code',
        'Present Days',
        'Leaving Date',
      ];
      for (var c = 0; c < stuHeaders.length; c++) {
        _setCell(sStu, 0, c, stuHeaders[c]);
      }
      var sIdx = 0;
      for (final r in stuRaw) {
        if (r is! Map) continue;
        final s = Map<String, dynamic>.from(r);
        final isGrad8 = '${s['promoted_to_standard'] ?? ''}' == '9' ||
            s['graduated_from_std_8'] == true;
        final status = isGrad8
            ? 'Promoted Std 8->9'
            : (s['is_active'] == false ? 'Deactive' : 'Active');
        final clsLabel =
            '${classById['${s['class_id']}']?['label'] ?? s['class_label'] ?? s['promoted_from_class_label'] ?? ''}';
        final genderVal = schoolType == 'boys'
            ? 'BOYS'
            : schoolType == 'girls'
                ? 'GIRLS'
                : '${s['gender'] ?? ''}';
        final rowVals = <String>[
          status,
          clsLabel,
          '${s['promoted_from_class_label'] ?? ''}',
          '${s['promoted_to_class_label'] ?? ''}',
          '${s['roll_number'] ?? ''}',
          '${s['previous_roll_number'] ?? ''}',
          '${s['gr'] ?? ''}',
          '${s['name'] ?? ''}',
          '${s['name_en'] ?? ''}',
          '${s['father_name'] ?? ''}',
          '${s['mother_name'] ?? ''}',
          genderVal,
          '${s['category'] ?? ''}',
          '${s['caste'] ?? ''}',
          '${s['religion'] ?? ''}',
          '${s['dd'] ?? ''}/${s['mm'] ?? ''}/${s['yyyy'] ?? ''}',
          '${s['enroll_school'] ?? ''}',
          '${s['enroll_class'] ?? ''}',
          '${s['mobile'] ?? ''}',
          '${s['uid'] ?? ''}',
          '${s['pen'] ?? ''}',
          '${s['apaar_id'] ?? ''}',
          '${s['bank_name'] ?? ''}',
          '${s['account_number'] ?? ''}',
          '${s['ifsc_code'] ?? ''}',
          '${s['present_days'] ?? ''}',
          '${s['leaving_date'] ?? s['exit_date'] ?? ''}',
        ];
        for (var c = 0; c < rowVals.length; c++) {
          _setCell(sStu, sIdx + 1, c, rowVals[c]);
        }
        sIdx++;
      }
      final stuBytes = wbStu.encode();
      final f2 = '2_STUDENTS_WHOLE_DATA_${schoolId}_$todayIso.xlsx';
      if (stuBytes != null && stuBytes.isNotEmpty) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(stuBytes),
          filename: f2,
          title: '2. Whole School Students Data ($schoolName)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        _downloadedFiles.add(f2);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // 3. Library Book List Excel
      if (!mounted) return;
      setState(() {
        _statusMessage = '3/5: Library Book List Excel ડાઉનલોડ થઈ રહી છે...';
      });
      final booksRaw = await _client
          .from('library_books')
          .select('*')
          .eq('school_ref', ref);
      final wbBooks = ec.Excel.createExcel();
      final defBooks = wbBooks.getDefaultSheet() ?? 'Sheet1';
      if (defBooks != 'Library Book List') {
        wbBooks.rename(defBooks, 'Library Book List');
      }
      final sBooks = wbBooks['Library Book List'];
      const bookHeaders = <String>[
        'Book Number / પુસ્તક નંબર',
        'Book Name / પુસ્તકનું નામ',
        'Author / લેખક',
        'Publication / પ્રકાશક',
        'Price ₹ / કિંમત',
        'ISBN',
        'Status',
      ];
      for (var c = 0; c < bookHeaders.length; c++) {
        _setCell(sBooks, 0, c, bookHeaders[c]);
      }
      var bIdx = 0;
      for (final r in booksRaw) {
        if (r is! Map) continue;
        final b = Map<String, dynamic>.from(r);
        final vals = <String>[
          '${b['book_number'] ?? bIdx + 1}',
          '${b['title'] ?? b['book_name'] ?? ''}',
          '${b['author'] ?? ''}',
          '${b['publisher'] ?? b['publication'] ?? ''}',
          '${b['price'] ?? ''}',
          '${b['isbn'] ?? ''}',
          b['is_active'] == false ? 'Removed' : 'Active',
        ];
        for (var c = 0; c < vals.length; c++) {
          _setCell(sBooks, bIdx + 1, c, vals[c]);
        }
        bIdx++;
      }
      final bookBytes = wbBooks.encode();
      final f3 = '3_LIBRARY_BOOK_LIST_${schoolId}_$todayIso.xlsx';
      if (bookBytes != null && bookBytes.isNotEmpty) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(bookBytes),
          filename: f3,
          title: '3. Library Book List ($schoolName)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        _downloadedFiles.add(f3);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // 4. Library Issue/Return Register Excel
      if (!mounted) return;
      setState(() {
        _statusMessage = '4/5: Library Register Excel ડાઉનલોડ થઈ રહી છે...';
      });
      final txRaw = await _client
          .from('library_transactions')
          .select('*')
          .eq('school_ref', ref);
      final wbReg = ec.Excel.createExcel();
      final defReg = wbReg.getDefaultSheet() ?? 'Sheet1';
      if (defReg != 'Library Register') {
        wbReg.rename(defReg, 'Library Register');
      }
      final sReg = wbReg['Library Register'];
      const regHeaders = <String>[
        'Book Number / પુસ્તક નંબર',
        'Book Name / પુસ્તકનું નામ',
        'Borrower Type',
        'Borrower Name / વાંચનારનું નામ',
        'Class / ધોરણ',
        'Roll / GR',
        'Issue Date / આપ્યા તારીખ',
        'Return Date / પરત તારીખ',
        'Status',
      ];
      for (var c = 0; c < regHeaders.length; c++) {
        _setCell(sReg, 0, c, regHeaders[c]);
      }
      var tIdx = 0;
      for (final r in txRaw) {
        if (r is! Map) continue;
        final tx = Map<String, dynamic>.from(r);
        final vals = <String>[
          '${tx['book_number'] ?? ''}',
          '${tx['book_title'] ?? tx['title'] ?? ''}',
          '${tx['borrower_type'] ?? 'student'}',
          '${tx['borrower_name'] ?? tx['student_name'] ?? tx['teacher_name'] ?? ''}',
          '${tx['class_label'] ?? ''}',
          '${tx['roll_number'] ?? tx['gr'] ?? ''}',
          '${tx['issue_date'] ?? tx['issued_at'] ?? ''}',
          '${tx['return_date'] ?? tx['returned_at'] ?? ''}',
          '${tx['status'] ?? (tx['returned_at'] != null ? 'Returned' : 'Issued')}',
        ];
        for (var c = 0; c < vals.length; c++) {
          _setCell(sReg, tIdx + 1, c, vals[c]);
        }
        tIdx++;
      }
      final regBytes = wbReg.encode();
      final f4 = '4_LIBRARY_REGISTER_${schoolId}_$todayIso.xlsx';
      if (regBytes != null && regBytes.isNotEmpty) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(regBytes),
          filename: f4,
          title: '4. Library Register ($schoolName)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        _downloadedFiles.add(f4);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // 5. Classes & Teachers Master Excel
      if (!mounted) return;
      setState(() {
        _statusMessage =
            '5/5: Classes & Teachers Master Excel ડાઉનલોડ થઈ રહી છે...';
      });
      final tchRaw = await _client
          .from('school_teachers')
          .select('*')
          .eq('school_ref', ref);
      final wbMaster = ec.Excel.createExcel();
      final defMaster = wbMaster.getDefaultSheet() ?? 'Sheet1';
      if (defMaster != 'Classes') {
        wbMaster.rename(defMaster, 'Classes');
      }
      final sCls = wbMaster['Classes'];
      final sTch = wbMaster['Teachers'];
      const clsHeaders = <String>['Class Key', 'Label / ધોરણ', 'Standard', 'Section', 'Report Group'];
      for (var c = 0; c < clsHeaders.length; c++) {
        _setCell(sCls, 0, c, clsHeaders[c]);
      }
      for (var i = 0; i < classRows.length; i++) {
        final cl = classRows[i];
        _setCell(sCls, i + 1, 0, '${cl['class_key'] ?? ''}');
        _setCell(sCls, i + 1, 1, '${cl['label'] ?? ''}');
        _setCell(sCls, i + 1, 2, '${cl['standard'] ?? ''}');
        _setCell(sCls, i + 1, 3, '${cl['section'] ?? ''}');
        _setCell(sCls, i + 1, 4, '${cl['report_group'] ?? ''}');
      }
      const tchHeaders = <String>['Teacher Name', 'Role', 'Login Email / ID', 'Mobile'];
      for (var c = 0; c < tchHeaders.length; c++) {
        _setCell(sTch, 0, c, tchHeaders[c]);
      }
      var tchIdx = 0;
      for (final r in tchRaw) {
        if (r is! Map) continue;
        _setCell(sTch, tchIdx + 1, 0, '${r['teacher_name'] ?? ''}');
        _setCell(sTch, tchIdx + 1, 1, '${r['role'] ?? ''}');
        _setCell(sTch, tchIdx + 1, 2, '${r['email'] ?? r['teacher_code'] ?? ''}');
        _setCell(sTch, tchIdx + 1, 3, '${r['mobile'] ?? ''}');
        tchIdx++;
      }
      final masterBytes = wbMaster.encode();
      final f5 = '5_CLASSES_AND_TEACHERS_${schoolId}_$todayIso.xlsx';
      if (masterBytes != null && masterBytes.isNotEmpty) {
        await PsmFileExportHelper.saveOrShare(
          bytes: Uint8List.fromList(masterBytes),
          filename: f5,
          title: '5. Classes & Teachers Master ($schoolName)',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        _downloadedFiles.add(f5);
      }

      if (!mounted) return;
      setState(() {
        _backupCompleted = true;
        _statusMessage =
            '✅ તમામ 5 બેકઅપ Excel રિપોર્ટ એક પછી એક સફળતાપૂર્વક ડાઉનલોડ થઈ ગયા છે. હવે તમે નીચેથી ડેટા ડિલીટ કરી શકો છો.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _downloadingBackups = false);
    }
  }

  Future<void> _executeDeleteAfterBackup() async {
    if (_confirmCtrl.text.trim().toUpperCase() != 'DELETE') return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      // If Date Range Attendance delete is selected or backup hasn't been run yet,
      // automatically download the matching Excel backup first!
      if (!_backupCompleted ||
          (_selectedScope == 'attendance' &&
              _attendanceDeleteMode == 'date_range')) {
        final ref = await _schoolRef(_client);
        final schoolRow = await _client
            .from('schools')
            .select('school_type,school_id,school_name,school_name_gu,school_name_en')
            .eq('id', ref)
            .maybeSingle();
        final schoolType = DateWiseReportColumn.normalizeSchoolType(
          schoolRow?['school_type'] ??
              widget.profile['school_type'] ??
              widget.profile['schoolType'],
        );
        final schoolId =
            '${schoolRow?['school_id'] ?? widget.profile['school_id'] ?? widget.profile['schoolDiseCode'] ?? 'SCHOOL'}'
                .trim();
        final schoolName =
            '${schoolRow?['school_name_gu'] ?? schoolRow?['school_name_en'] ?? schoolRow?['school_name'] ?? widget.profile['school_name_gu'] ?? widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? 'School'}'
                .trim();
        if (_selectedScope == 'attendance' &&
            _attendanceDeleteMode == 'date_range') {
          await _downloadAttendanceOnlyExcel(
            ref: ref,
            schoolId: schoolId,
            schoolName: schoolName,
            schoolType: schoolType,
            dateRangeOnly: true,
          );
          _backupCompleted = true;
          await Future<void>.delayed(const Duration(milliseconds: 350));
        } else {
          await _downloadAllSchoolBackupsOneByOne();
        }
      }

      final res = await _client.rpc(
        'psm_admin_delete_school_data',
        params: <String, dynamic>{
          'p_scope': _selectedScope,
          'p_backup_downloaded': true,
          'p_attendance_mode': _attendanceDeleteMode,
          'p_from_date': _iso(_attFromDate),
          'p_to_date': _iso(_attToDate),
        },
      );
      final map = res is Map
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{};
      if (!mounted) return;
      _confirmCtrl.clear();
      final rangeNote = (_selectedScope == 'attendance' &&
              _attendanceDeleteMode == 'date_range')
          ? ' (${_dmy(_attFromDate)} થી ${_dmy(_attToDate)})'
          : '';
      setState(() {
        _statusMessage =
            '✅ Excel બેકઅપ બાદ ડેટા સફળતાપૂર્વક ડિલીટ થયો$rangeNote: Attendance (${map['deleted_attendance'] ?? 0}), Students (${map['deleted_students'] ?? 0}), Books (${map['deleted_books'] ?? 0}), Library Transactions (${map['deleted_transactions'] ?? 0}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDateRangeAttendance =
        _selectedScope == 'attendance' && _attendanceDeleteMode == 'date_range';
    final canTriggerDelete = !_deleting &&
        !_downloadingBackups &&
        _confirmCtrl.text.trim().toUpperCase() == 'DELETE' &&
        (_backupCompleted || isDateRangeAttendance);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'One-by-One Excel Backup & Delete Data / બેકઅપ અને ડેટા ડિલીટ',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'પગલું ૧ (ફરજિયાત): ડેટા ડિલીટ કરતા પહેલાં શાળાના તમામ Excel રિપોર્ટ એક પછી એક (One-by-One) ડાઉનલોડ કરો',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'જ્યારે તમે નીચેનું બટન દબાવશો ત્યારે સિસ્ટમ આપમેળે એક પછી એક નીચેની 5 Excel ફાઈલો ડાઉનલોડ કરશે જેથી ભવિષ્યમાં કોઈપણ સમયે ડેટા પાછો અપલોડ (Recover) કરી શકાય:\n'
                    '1. Ekandar & Class-wise Attendance Report (.xlsx — શાળા રજીસ્ટ્રેશન મુજબ Boys / Girls / Mixed)\n'
                    '2. Whole School Students Data — Active, Deactive & Promoted Class 8->9 (.xlsx)\n'
                    '3. Library Book List (.xlsx)\n'
                    '4. Library Issue/Return Register (.xlsx)\n'
                    '5. Classes & Teachers Master (.xlsx)',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _downloadingBackups || _deleting
                        ? null
                        : _downloadAllSchoolBackupsOneByOne,
                    icon: _downloadingBackups
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      _downloadingBackups
                          ? 'એક પછી એક Excel ડાઉનલોડ થઈ રહી છે...'
                          : '1. Download All 5 School Backup Excel Reports One-by-One',
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _statusMessage!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                  if (_downloadedFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final f in _downloadedFiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                f,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: (_backupCompleted || isDateRangeAttendance)
                ? Colors.red.shade50
                : Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'પગલું ૨: ડેટા ડિલીટ કરો — સંપૂર્ણ ડેટા અથવા તારીખ ગાળા (Date Range) મુજબ હાજરી ડિલીટ (Auto Excel Download સાથે)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: (_backupCompleted || isDateRangeAttendance)
                          ? Colors.red.shade900
                          : Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedScope,
                    decoration: const InputDecoration(
                      labelText: 'કયો ડેટા ડિલીટ કરવો છે? (Select Data Scope)',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'All Uploaded/Inserted Data (હાજરી + વિદ્યાર્થીઓ + પુસ્તકાલય તમામ ડેટા)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'attendance',
                        child: Text(
                          'Only Attendance Data (ફક્ત હાજરી — સંપૂર્ણ અથવા તારીખ ગાળા મુજબ)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'students',
                        child: Text(
                          'Only Student Data (ફક્ત વિદ્યાર્થીઓનો ડેટા)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'library',
                        child: Text(
                          'Only Library Data (ફક્ત પુસ્તકાલય પુસ્તક યાદી અને રજીસ્ટર)',
                        ),
                      ),
                    ],
                    onChanged: _deleting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _selectedScope = v);
                          },
                  ),
                  if (_selectedScope == 'attendance') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'હાજરી ડિલીટ કરવાનો પ્રકાર પસંદ કરો (Attendance Delete Option):',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text(
                            'સંપૂર્ણ હાજરી ડેટા (Delete Whole Attendance Data)',
                          ),
                          selected: _attendanceDeleteMode == 'whole',
                          onSelected: _deleting
                              ? null
                              : (_) => setState(
                                    () => _attendanceDeleteMode = 'whole',
                                  ),
                        ),
                        ChoiceChip(
                          label: const Text(
                            'તારીખ ગાળા મુજબ હાજરી (Delete Date Range: From – To Date)',
                          ),
                          selected: _attendanceDeleteMode == 'date_range',
                          onSelected: _deleting
                              ? null
                              : (_) => setState(
                                    () => _attendanceDeleteMode = 'date_range',
                                  ),
                        ),
                      ],
                    ),
                    if (_attendanceDeleteMode == 'date_range') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _deleting
                                ? null
                                : () => _pickAttDate(isFrom: true),
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text('From Date (થી): ${_dmy(_attFromDate)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _deleting
                                ? null
                                : () => _pickAttDate(isFrom: false),
                            icon: const Icon(Icons.event_outlined),
                            label: Text('To Date (સુધી): ${_dmy(_attToDate)}'),
                          ),
                          Text(
                            '(${_dmy(_attFromDate)} થી ${_dmy(_attToDate)} ની Excel આપમેળે ડાઉનલોડ થઈને તે તારીખોની હાજરી ડિલીટ થશે)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmCtrl,
                    enabled: (_backupCompleted || isDateRangeAttendance) && !_deleting,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'કન્ફર્મ કરવા માટે કેપિટલમાં DELETE લખો',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                    ),
                    onPressed: canTriggerDelete ? _executeDeleteAfterBackup : null,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(
                      isDateRangeAttendance
                          ? 'Auto-Download Excel (${_dmy(_attFromDate)} – ${_dmy(_attToDate)}) & Delete Date Range Attendance'
                          : (_backupCompleted
                              ? '2. Delete Selected School Data (બેકઅપ લેવાઈ ગયો છે)'
                              : 'પહેલા ઉપરથી 5 Excel બેકઅપ ડાઉનલોડ કરો (અથવા Date Range Attendance પસંદ કરો)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
