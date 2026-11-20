import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_state.dart';
import 'result_shell.dart';

import '../services/school_name_language_service.dart';
import '../services/supabase_school_access_service.dart';

import 'admin_workflow_panel.dart';
import 'admin_planning_studio_screen.dart';
import 'professional_management_hub.dart';
import 'supabase_attendance_workspace_screen.dart';
import 'supabase_certificate_screen.dart';
import 'supabase_file_share_screen.dart';
import 'supabase_teacher_leave_screen.dart';
import 'supabase_admin_center_screen.dart';
import 'supabase_hajari_patrak_screen.dart';
import 'supabase_library_screen.dart';
import 'supabase_id_card_studio_screen.dart';
import 'fln_workbook_screen.dart';
import 'print_merge_studio_screen.dart';
import 'supabase_rojmel_screen.dart';
import 'supabase_academic_calendar_screen.dart';
import 'supabase_low_attendance_alerts_screen.dart';
import 'supabase_textbook_issue_register_screen.dart';
import 'supabase_weekly_meal_menu_screen.dart';
import 'supabase_whole_school_result_summary_screen.dart';
import '../widgets/supabase_birthday_reminder_on_login.dart';
import '../widgets/global_student_search_card.dart';
import '../widgets/admin_daily_attendance_dashboard.dart';
import '../widgets/school_action_center_card.dart';
import '../widgets/school_name_language_selector.dart';
import '../theme/display_scale.dart';
import '../services/school_type.dart';

/// Home for school login. Modules are routed through Firestore-aware
/// screens with fast navigation and modern visual polish.
class SupabaseSignedInHome extends StatefulWidget {
  const SupabaseSignedInHome({
    super.key,
    required this.profile,
    required this.onLogout,
  });

  final Map<String, dynamic> profile;
  final Future<void> Function() onLogout;

  @override
  State<SupabaseSignedInHome> createState() => _SupabaseSignedInHomeState();
}

class _SupabaseSignedInHomeState extends State<SupabaseSignedInHome> {
  Map<String, dynamic> get profile => widget.profile;
  Future<void> Function() get onLogout => widget.onLogout;

  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  String _schoolRef = '';
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  List<Map<String, dynamic>> _devSharedFiles = <Map<String, dynamic>>[];

  /// Selected main tab on the home screen ('all' shows every section).
  String _homeGroup = 'all';
  String _homeSearch = '';
  bool _devPreviewOnlyAllowedModules = false;
  final TextEditingController _homeSearchCtrl = TextEditingController();

  bool get _isDeveloperSession =>
      profile['is_developer_session'] == true ||
      Supabase.instance.client.isDeveloperImpersonatingSchool;

  bool _isModuleEnabled(String moduleKey) {
    return SchoolModuleRegistry.isModuleEnabled(
      moduleKey,
      schoolContext: _schoolContext,
      profile: profile,
      developerShowAll: _isDeveloperSession && !_devPreviewOnlyAllowedModules,
    );
  }

  @override
  void dispose() {
    _homeSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSchoolNameLanguage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowDuePopups();
    });
  }

  Future<void> _checkAndShowDuePopups() async {
    if (!mounted) return;
    try {
      final service = SupabaseSchoolAccessService();
      final popups = await service.loadDuePopups();
      for (var i = 0; i < popups.length; i++) {
        if (!mounted) return;
        final popup = popups[i];
        final kind = '${popup['kind'] ?? ''}';
        final isValidity = kind == 'validity_reminder';
        final isAdminPendingLeave = kind == 'admin_pending_leaves';
        final isTeacherLeaveDecision = kind == 'teacher_leave_decision';
        final decisionStatus = '${popup['status'] ?? ''}'.toLowerCase();
        var openAdminLeaveApproval = false;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isValidity
                      ? Icons.warning_amber_rounded
                      : isAdminPendingLeave
                          ? Icons.notification_important_rounded
                          : isTeacherLeaveDecision
                              ? (decisionStatus == 'approved'
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded)
                              : Icons.campaign_outlined,
                  color: isValidity
                      ? Colors.orange.shade800
                      : isAdminPendingLeave
                          ? Colors.deepOrange.shade700
                          : isTeacherLeaveDecision
                              ? (decisionStatus == 'approved'
                                  ? Colors.green.shade700
                                  : Colors.red.shade700)
                              : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${popup['title'] ?? (isValidity ? 'School Validity Reminder' : 'Notification')}',
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: SelectableText(
                  '${popup['message'] ?? ''}',
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ),
            ),
            actions: [
              if (isAdminPendingLeave)
                OutlinedButton.icon(
                  onPressed: () {
                    openAdminLeaveApproval = true;
                    Navigator.of(dialogContext).pop();
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('રજા મંજૂર / નામંજૂર કરો'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  i + 1 < popups.length ? 'Next (${i + 2}/${popups.length})' : 'OK',
                ),
              ),
            ],
          ),
        );
        if (!mounted) return;
        try {
          await service.dismissDuePopup(popup);
        } catch (_) {}
        if (openAdminLeaveApproval && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SupabaseAdminCenterScreen(profile: profile),
            ),
          );
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSchoolNameLanguage() async {
    final client = Supabase.instance.client;
    final schoolRef = await SchoolNameLanguageService.currentSchoolRef(client);
    final language =
        await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
    final schoolContext =
        await SchoolNameLanguageService.loadCurrentSchoolContext(client);
    if (!mounted) return;
    final role = '${profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    List<Map<String, dynamic>> sharedFiles = <Map<String, dynamic>>[];
    if (role == 'admin') {
      try {
        final res = await client.rpc('psm_get_developer_shared_files');
        if (res is List) {
          sharedFiles = res
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _schoolRef = schoolRef;
      _schoolNameLanguage = language;
      _schoolContext = schoolContext;
      _devSharedFiles = sharedFiles;
    });
    if (role == 'admin' && sharedFiles.isNotEmpty) {
      await _checkAndShowDeveloperSharedFilesPopup(
        schoolRef: schoolRef,
        files: sharedFiles,
      );
    }
  }

  bool _devFilesPopupShowing = false;

  Future<void> _checkAndShowDeveloperSharedFilesPopup({
    required String schoolRef,
    required List<Map<String, dynamic>> files,
  }) async {
    if (!mounted || _devFilesPopupShowing || files.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey =
          'psm_admin_seen_dev_files_v2_${schoolRef.isEmpty ? "default" : schoolRef}';
      final seenList = prefs.getStringList(prefKey) ?? const <String>[];
      final seenSet = seenList.toSet();
      final unseenFiles = files.where((f) {
        final id = '${f['id'] ?? ''}'.trim();
        final stamp = '${f['updated_at'] ?? f['created_at'] ?? ''}'.trim();
        final token = stamp.isEmpty ? id : '${id}_$stamp';
        return id.isNotEmpty && !seenSet.contains(token);
      }).toList();

      if (unseenFiles.isEmpty || !mounted) return;
      _devFilesPopupShowing = true;

      final openDownloadScreen = await showDialog<bool>(
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
                child: Text(
                  'ડેવલપર તરફથી નવી ફાઈલ (Developer Shared File)',
                ),
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
                  const SizedBox(height: 4),
                  const Text(
                    'તમે અહીંથી સીધી ફાઈલ જોઈ અને ડાઉનલોડ કરી શકો છો.',
                    style: TextStyle(fontSize: 12.5),
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

      if (openDownloadScreen == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SupabaseDeveloperSharedFilesAdminScreen(),
          ),
        );
      }
    } catch (_) {
    } finally {
      _devFilesPopupShowing = false;
    }
  }

  Future<void> _openResultModule() async {
    final role = '${profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    final isBlocked =
        profile['is_blocked'] == true || profile['can_edit'] == false;
    if (isBlocked || role == 'developer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Result is unavailable for this account.')),
      );
      return;
    }

    final state = Provider.of<AppState>(context, listen: false);
    try {
      await state.prepareResultModuleForSupabaseProfile(profile);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Result could not initialize: $error')),
      );
      return;
    }

    if (!mounted) return;
    if (!state.isLoggedIn || state.resultApi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Result could not connect to the authenticated session. Please sign in again.')),
      );
      return;
    }
    if (state.allowedClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'આ ખાતા માટે કોઈ સક્રિય/ફાળવેલો વર્ગ મળ્યો નથી. School Admin પાસે વર્ગ બનાવો અથવા શિક્ષકને વર્ગ ફાળવો.')),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/psm-result'),
        builder: (_) => const ResultShell(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = '${profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    final isAdmin = role == 'admin';
    final schoolName = SchoolNameLanguageService.resolveSchoolName(
      language: _schoolNameLanguage,
      profile: profile,
      schoolContext: _schoolContext,
      fallbackEnglish:
          '${profile['school_name_en'] ?? profile['school_name'] ?? profile['schoolName'] ?? 'School'}'
              .trim(),
    );
    final teacherName = '${profile['teacher_name'] ?? 'User'}'.trim();
    final schoolId = '${profile['school_id'] ?? ''}'.trim();
    final isBlocked =
        profile['is_blocked'] == true || profile['can_edit'] == false;

    void openAttendanceTab(int index) {
      final effectiveProfile = <String, dynamic>{
        ...profile,
        if (_schoolContext.containsKey('disabled_modules'))
          'disabled_modules': _schoolContext['disabled_modules'],
        'developer_show_all_modules':
            _isDeveloperSession && !_devPreviewOnlyAllowedModules,
      };
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SupabaseAttendanceWorkspaceScreen(
          profile: effectiveProfile,
          readOnly: isBlocked,
          initialIndex: index,
        ),
      ));
    }

    void openCertificatePlaceholder(String title, String description) {
      final normalizedTitle = title.toLowerCase();
      final isLc = normalizedTitle.contains('leaving certificate') ||
          normalizedTitle.contains('(lc)') ||
          normalizedTitle == 'lc' ||
          normalizedTitle.startsWith('lc ') ||
          normalizedTitle.startsWith('lc/') ||
          normalizedTitle.startsWith('lc -');
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SupabaseCertificateScreen(
          profile: profile,
          isLc: isLc,
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(schoolName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          DisplayScale.menuButton(color: Colors.white),
          if (_isModuleEnabled('student_search'))
            IconButton(
                tooltip: 'Global Student Search / વિદ્યાર્થી સર્ચ',
                onPressed: () => showGlobalStudentSearchDialog(
                      context,
                      readOnly: isBlocked,
                    ),
                icon: const Icon(Icons.person_search_rounded)),
          if (_isModuleEnabled('file_beam'))
            IconButton(
                tooltip: 'FileBeam Pro — Direct File & Text Share',
                onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SupabaseFileShareScreen(profile: profile),
                      ),
                    ),
                icon: const Icon(Icons.bolt_rounded)),
          IconButton(
              tooltip: _isDeveloperSession ? 'Exit to Developer Panel' : 'Log out',
              onPressed: onLogout,
              icon: Icon(_isDeveloperSession ? Icons.exit_to_app_rounded : Icons.logout)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isDeveloperSession) ...[
            Card(
              color: const Color(0xFFFEF3C7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFD97706), width: 1.4),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.developer_mode_rounded, color: Color(0xFFB45309)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Developer Operating School Admin: $schoolName (UDISE: $schoolId)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF78350F),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SupabaseAdminCenterScreen(profile: profile),
                            ),
                          ),
                          icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                          label: const Text('Open Admin Centre (શાળા સંચાલન)'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AdminWorkflowPanel(),
                            ),
                          ),
                          icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                          label: const Text('Classes & Teachers (વર્ગ અને શિક્ષક)'),
                        ),
                        FilterChip(
                          selected: _devPreviewOnlyAllowedModules,
                          label: Text(
                            _devPreviewOnlyAllowedModules
                                ? 'Previewing School Allowed Modules Only'
                                : 'Showing All Modules (Developer Mode)',
                          ),
                          onSelected: (v) => setState(() => _devPreviewOnlyAllowedModules = v),
                        ),
                        OutlinedButton.icon(
                          onPressed: onLogout,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back to Developer Panel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A2744), Color(0xFF243560), Color(0xFF2F4580)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A2744).withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        isAdmin
                            ? Icons.admin_panel_settings_rounded
                            : Icons.person_rounded,
                        size: 32,
                        color: const Color(0xFFFFD166),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'નમસ્તે, $teacherName',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            schoolName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroPill(
                      icon: isAdmin ? Icons.verified_user_rounded : Icons.school_rounded,
                      text: isAdmin ? 'School Admin' : 'Teacher',
                    ),
                    if (schoolId.isNotEmpty)
                      _HeroPill(icon: Icons.tag_rounded, text: 'UDISE $schoolId'),
                    _HeroPill(
                      icon: Icons.wc_rounded,
                      text: _schoolTypeLabel('${profile['school_type'] ?? ''}'),
                    ),
                    if (profile['validity_date'] != null)
                      _HeroPill(
                        icon: Icons.event_rounded,
                        text: 'Valid till ${profile['validity_date']}',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SchoolNameLanguageSelector(
                    schoolRef: _schoolRef.isEmpty ? null : _schoolRef,
                    label: 'School name language / શાળાના નામની ભાષા',
                    onChanged: (language) =>
                        setState(() => _schoolNameLanguage = language),
                  ),
                ),
                if (isBlocked) ...[
                  const SizedBox(height: 12),
                  const _ReadOnlyNotice(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _TodaySchoolMessageBanner(),
          if (_isModuleEnabled('academic_calendar'))
            UpcomingAcademicEventsBanner(profile: profile),
          if (role != 'developer')
            SchoolActionCenterCard(
              profile: profile,
              readOnly: isBlocked,
            ),
          if (role == 'teacher') const SupabaseBirthdayReminderOnLogin(),
          ..._buildModuleSections(
            context,
            role: role,
            isAdmin: isAdmin,
            isBlocked: isBlocked,
            openAttendanceTab: openAttendanceTab,
            openCertificate: openCertificatePlaceholder,
          ),
          if (isAdmin &&
              !isBlocked &&
              _isModuleEnabled('daily_dashboard') &&
              _isModuleEnabled('attendance')) ...[
            const SizedBox(height: 18),
            AdminDailyAttendanceDashboard(
              profile: profile,
              initiallyExpanded: true,
            ),
          ],
          if (isBlocked)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'This school is blocked. Attendance and reports remain available in read-only mode; editing, leave requests, and sending new parent-message drafts are disabled.'),
            ),
        ],
      ),
    );
  }

  static const List<(String, String, IconData)> _homeGroups =
      <(String, String, IconData)>[
    ('all', 'બધું / All', Icons.apps_rounded),
    ('daily', 'દૈનિક કામ / Daily', Icons.today_rounded),
    ('students', 'વિદ્યાર્થી અને પરિણામ / Students', Icons.school_rounded),
    ('admin', 'શાળા સંચાલન / Admin', Icons.admin_panel_settings_rounded),
    ('tools', 'સાધનો / Tools', Icons.handyman_rounded),
  ];

  List<Widget> _buildModuleSections(
    BuildContext context, {
    required String role,
    required bool isAdmin,
    required bool isBlocked,
    required void Function(int) openAttendanceTab,
    required void Function(String, String) openCertificate,
  }) {
    void push(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));

    final allCandidateModules = <_HomeModule>[
      // ---------------- Daily work ----------------
      _HomeModule(
        moduleKey: 'attendance',
        group: 'daily',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF0F766E),
        title: 'Attendance / હાજરી નોંધણી',
        subtitle: isBlocked
            ? 'View attendance and history (read-only).'
            : 'Daily attendance, PM POSHAN and breakfast entry.',
        onTap: () => openAttendanceTab(0),
      ),
      _HomeModule(
        moduleKey: 'reports',
        group: 'daily',
        icon: Icons.insert_chart_rounded,
        color: const Color(0xFF1D4ED8),
        title: 'Reports / અહેવાલ',
        subtitle:
            'Datewise, class-wise, TARIJ, MDM EKANDAR and combined reports.',
        onTap: () => openAttendanceTab(2),
      ),
      // Moved out of Reports into its own tab: blank register for every
      // teacher, recorded register (admin only) inside the screen.
      _HomeModule(
        moduleKey: 'hajari_patrak',
        group: 'daily',
        icon: Icons.grid_on_rounded,
        color: const Color(0xFF7C3AED),
        title: 'Hajari Patrak / હાજરીપત્રક',
        subtitle: isAdmin
            ? 'Blank and recorded registers from the same template with daily totals.'
            : 'Monthly front page and blank attendance register.',
        onTap: () => push(
            SupabaseHajariPatrakScreen(profile: profile, readOnly: isBlocked)),
      ),
      _HomeModule(
        moduleKey: 'parent_message',
        group: 'daily',
        icon: Icons.mark_email_read_rounded,
        color: const Color(0xFF0891B2),
        title: 'Parent Message / વાલી સંદેશ',
        subtitle: 'Attendance % per student with Gujarati WhatsApp drafts.',
        onTap: () => openAttendanceTab(5),
      ),
      _HomeModule(
        moduleKey: 'most_present',
        group: 'daily',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFFD97706),
        title: 'Most Present / સૌથી વધુ હાજર',
        subtitle: 'Week, month, quarter, year or custom range.',
        onTap: () => openAttendanceTab(3),
      ),
      _HomeModule(
        moduleKey: 'leave',
        group: 'daily',
        icon: Icons.event_available_rounded,
        color: const Color(0xFFDB2777),
        title: 'Leave / રજા અરજી',
        subtitle: isBlocked
            ? 'View leave requests (read-only).'
            : 'Apply for leave and track its status.',
        onTap: () => push(
            SupabaseTeacherLeaveScreen(profile: profile, readOnly: isBlocked)),
      ),
      _HomeModule(
        moduleKey: 'low_attendance_alerts',
        group: 'daily',
        icon: Icons.notification_important_rounded,
        color: const Color(0xFFDC2626),
        title: 'સતત ગેરહાજર / ઓછી હાજરી યાદી',
        subtitle:
            '૩+ સતત ગેરહાજર, ૭૫% થી ઓછી હાજરી, ૧-ક્લિક વાલી WhatsApp અને Admin Excel ડાઉનલોડ.',
        onTap: () => push(SupabaseLowAttendanceAlertsScreen(profile: profile)),
      ),
      _HomeModule(
        moduleKey: 'pm_poshan_menu',
        group: 'daily',
        icon: Icons.restaurant_menu_rounded,
        color: const Color(0xFF059669),
        title: 'PM POSHAN અને અલ્પાહાર મેનુ',
        subtitle:
            'આજનું અને આખા અઠવાડિયાનું વાનગી તથા સામગ્રી-જથ્થા સાથેનું મેનુ જુઓ/સેટ કરો.',
        onTap: () => push(SupabaseWeeklyMealMenuScreen(profile: profile)),
      ),
      // ---------------- Students & results ----------------
      if (role != 'developer')
        _HomeModule(
          moduleKey: 'student_search',
          group: 'students',
          icon: Icons.person_search_rounded,
          color: const Color(0xFF1D4ED8),
          title: 'Global Student Search / વિદ્યાર્થી સર્ચ',
          subtitle: isAdmin
              ? 'Search whole school by Name, GR, Mobile, Father or Mother name, edit & deactivate.'
              : 'Search allotted class by Name, GR, Mobile, Father or Mother name & edit.',
          onTap: () => showGlobalStudentSearchDialog(
            context,
            readOnly: isBlocked,
          ),
        ),
      if (!isBlocked)
        _HomeModule(
          moduleKey: 'student_management',
          group: 'students',
          icon: Icons.groups_rounded,
          color: const Color(0xFF059669),
          title: 'Student Management / વિદ્યાર્થી વ્યવસ્થાપન',
          subtitle: 'Student records, classes and data tools.',
          onTap: () => push(const ProfessionalManagementHub()),
        ),
      if (!isBlocked && role != 'developer')
        _HomeModule(
          moduleKey: 'result',
          group: 'students',
          icon: Icons.assessment_rounded,
          color: const Color(0xFF4F46E5),
          title: 'Result / પરિણામ પત્રક',
          subtitle: 'Semester registers, marks entry, result and front pages.',
          onTap: _openResultModule,
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'result_summary',
          group: 'admin',
          icon: Icons.analytics_rounded,
          color: const Color(0xFF0B2D5B),
          title: 'સમગ્ર શાળાનું પરિણામ સારાંશ (All 3 Formats)',
          subtitle: 'Admin-only semester-wise result summary (Class-Section, Category-Grade & Whole School) in 1 click with logo.',
          onTap: () => push(SupabaseWholeSchoolResultSummaryScreen(profile: profile)),
        ),
      _HomeModule(
        moduleKey: 'bonafide',
        group: 'students',
        icon: Icons.verified_rounded,
        color: const Color(0xFF0D9488),
        title: 'Bonafide / બોનાફાઈડ',
        subtitle: 'Bonafide certificate from the student database.',
        onTap: () => openCertificate(
          'Bonafide Certificate / બોનાફાઈડ',
          'Generate Bonafide certificates from school database.',
        ),
      ),
      _HomeModule(
        moduleKey: 'leaving_certificate',
        group: 'students',
        icon: Icons.history_edu_rounded,
        color: const Color(0xFFB45309),
        title: 'Leaving Certificate (LC)',
        subtitle: 'LC copies with editable leaving details.',
        onTap: () => openCertificate(
          'Leaving Certificate (LC) / શાળા છોડ્યાનું પ્રમાણપત્ર',
          'Generate Leaving Certificates from school database.',
        ),
      ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'id_card',
          group: 'students',
          icon: Icons.badge_rounded,
          color: const Color(0xFF2563EB),
          title: 'ID Card Studio / ઓળખપત્ર',
          subtitle: 'Design ID cards from the database or any Excel file.',
          onTap: () => push(const SupabaseIdCardStudioScreen()),
        ),
      if (role != 'developer')
        _HomeModule(
          moduleKey: 'fln_workbook',
          group: 'students',
          icon: Icons.calculate_rounded,
          color: const Color(0xFF0E7490),
          title: 'FLN 130 પ્રશ્નપત્ર / Workbook',
          subtitle: 'Class-wise FLN maths papers (PDF) with answer keys and A4 page setup.',
          onTap: () => push(FlnWorkbookScreen(profile: profile)),
        ),
      if (role != 'developer')
        _HomeModule(
          moduleKey: 'textbook_issue_register',
          group: 'students',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF0F766E),
          title: 'પાઠ્યપુસ્તક વિતરણ રજીસ્ટર / Textbook Issue',
          subtitle: 'વિદ્યાર્થી Snapshot તારીખ અને વધારાની ખાલી હરોળ સાથે વાલી/વિદ્યાર્થી સહી પહોંચ પ્રિન્ટ.',
          onTap: () => push(SupabaseTextbookIssueRegisterScreen(profile: profile)),
        ),
      // ---------------- Administration ----------------
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'daily_dashboard',
          group: 'admin',
          icon: Icons.notifications_active_rounded,
          color: const Color(0xFF15803D),
          title: 'દૈનિક હાજરી ડેશબોર્ડ અને WhatsApp રીમાઈન્ડર',
          subtitle: 'રિપોર્ટ વગર લાઈવ દૈનિક અહેવાલ, બાકી વર્ગો અને ૧-ક્લિક WhatsApp રીમાઈન્ડર.',
          onTap: () => push(SupabaseAdminDailyDashboardScreen(profile: profile)),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'rojmel',
          group: 'admin',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF123A6B),
          title: 'Rojmel / રોજમેળ અને ઓડિટ',
          subtitle: 'Cashbook, grant heads and all government audit reports.',
          onTap: () => push(SupabaseRojmelScreen(profile: profile)),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'attendance_permission',
          group: 'admin',
          icon: Icons.verified_user_rounded,
          color: const Color(0xFF0F766E),
          title: 'Teacher Attendance Permission / હાજરી પૂરવાની પરવાનગી (4 Modes)',
          subtitle:
              'નક્કી કરો કે કયા શિક્ષક હાજરી પૂરી શકે: (1) માત્ર વર્ગ શિક્ષક, (2) વિભાગવાર વર્ગ શિક્ષક (6A, 6B, 6C...), (3) વિષય શિક્ષક, કે (4) કોઈપણ શિક્ષક (+ રજા ચાર્જ).',
          onTap: () => push(const SupabaseAttendancePermissionScreen()),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'admin_panel',
          group: 'admin',
          icon: Icons.dashboard_customize_rounded,
          color: const Color(0xFF0F172A),
          title: 'Admin Centre / શાળા સંચાલન',
          subtitle: 'Logo, messages, holidays, leave approval, data and backup.',
          onTap: () => push(SupabaseAdminCenterScreen(profile: profile)),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'classes_teachers',
          group: 'admin',
          icon: Icons.manage_accounts_rounded,
          color: const Color(0xFF475569),
          title: 'Classes & Teachers / વર્ગ અને શિક્ષક',
          subtitle: 'Create classes and teacher accounts, assign access.',
          onTap: () => push(const AdminWorkflowPanel()),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'timetable',
          group: 'admin',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF9333EA),
          title: 'Timetable / સમયપત્રક',
          subtitle: 'Zero-clash automatic and editable school timetable.',
          onTap: () => push(
              AdminPlanningStudioScreen(profile: profile, initialTab: 0)),
        ),
      if (isAdmin && !isBlocked)
        _HomeModule(
          moduleKey: 'exam_planner',
          group: 'admin',
          icon: Icons.assignment_turned_in_rounded,
          color: const Color(0xFFBE185D),
          title: 'Exam Planner / પરીક્ષા આયોજન',
          subtitle: 'Complete exam file: timetable, seating, supervision, registers.',
          onTap: () => push(
              AdminPlanningStudioScreen(profile: profile, initialTab: 1)),
        ),
      _HomeModule(
        moduleKey: 'academic_calendar',
        group: 'admin',
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF3730A3),
        title: 'શૈક્ષણિક કેલેન્ડર / Academic Calendar',
        subtitle:
            'પરીક્ષા તારીખ, PTM, SMC સભા અને સરકારી ડેડલાઈન રીમાઈન્ડર.',
        onTap: () => push(SupabaseAcademicCalendarScreen(profile: profile)),
      ),

      // ---------------- Tools ----------------
      _HomeModule(
        moduleKey: 'library',
        group: 'daily',
        icon: Icons.local_library_rounded,
        color: const Color(0xFF65A30D),
        title: 'Library Register / પુસ્તકાલય રજીસ્ટર',
        subtitle: 'Book issue / return, registration and Excel reports.',
        onTap: () => push(
            SupabaseLibraryScreen(profile: profile, readOnly: isBlocked)),
      ),
      if (role != 'developer')
        _HomeModule(
          moduleKey: 'print_merge',
          group: 'tools',
          icon: Icons.auto_awesome_mosaic_rounded,
          color: const Color(0xFF4338CA),
          title: 'Print Merge Studio / પ્રિન્ટ મર્જ',
          subtitle: 'Certificates, cards and profiles from any Excel / CSV list, as PDF.',
          onTap: () => push(const PrintMergeStudioScreen()),
        ),
      _HomeModule(
        moduleKey: 'file_beam',
        group: 'tools',
        icon: Icons.bolt_rounded,
        color: const Color(0xFFEA580C),
        title: 'FileBeam Pro',
        subtitle: 'Send files and Gujarati text between phone and PC.',
        onTap: () => push(SupabaseFileShareScreen(profile: profile)),
      ),
      if (isAdmin && _devSharedFiles.isNotEmpty)
        _HomeModule(
          moduleKey: 'developer_files',
          group: 'tools',
          icon: Icons.cloud_download_rounded,
          color: const Color(0xFF0369A1),
          title: 'Developer Files (${_devSharedFiles.length})',
          subtitle: 'Important files shared by the developer.',
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SupabaseDeveloperSharedFilesAdminScreen(),
            ));
            if (mounted) _loadSchoolNameLanguage();
          },
        ),
    ];
    final modules = allCandidateModules
        .where((m) => _isModuleEnabled(m.moduleKey))
        .toList();

    final q = _homeSearch.trim().toLowerCase();
    final visible = modules.where((m) {
      if (q.isNotEmpty) {
        return '${m.title} ${m.subtitle}'.toLowerCase().contains(q);
      }
      return _homeGroup == 'all' || m.group == _homeGroup;
    }).toList();
    final usedGroups = modules.map((m) => m.group).toSet();

    final header = <Widget>[
      const SizedBox(height: 8),
      TextField(
        controller: _homeSearchCtrl,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'Search modules / મોડ્યુલ શોધો',
          isDense: true,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (v) => setState(() => _homeSearch = v),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final g in _homeGroups)
              if (g.$1 == 'all' || usedGroups.contains(g.$1))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(g.$3, size: 18),
                    label: Text(g.$2),
                    selected: _homeGroup == g.$1 && q.isEmpty,
                    onSelected: (_) => setState(() {
                      _homeGroup = g.$1;
                      _homeSearch = '';
                      _homeSearchCtrl.clear();
                    }),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 6),
    ];

    Widget grid(List<_HomeModule> items) => LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1100
                ? 4
                : c.maxWidth >= 760
                    ? 3
                    : c.maxWidth >= 460
                        ? 2
                        : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 104,
              ),
              itemBuilder: (_, i) => _HomeModuleTile(module: items[i]),
            );
          },
        );

    if (visible.isEmpty) {
      return [
        ...header,
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No module matches your search.')),
        ),
      ];
    }
    if (_homeGroup != 'all' || q.isNotEmpty) {
      return [...header, grid(visible)];
    }
    final sections = <Widget>[...header];
    for (final g in _homeGroups.skip(1)) {
      final items = visible.where((m) => m.group == g.$1).toList();
      if (items.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(
          children: [
            Icon(g.$3, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(
              g.$2,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            )),
          ],
        ),
      ));
      sections.add(grid(items));
    }
    return sections;
  }

  String _schoolTypeLabel(String value) => SchoolType.labelGu(value);
}

class _HomeModule {
  const _HomeModule({
    this.moduleKey = '',
    required this.group,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String moduleKey;
  final String group;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _HomeModuleTile extends StatelessWidget {
  const _HomeModuleTile({required this.module});

  final _HomeModule module;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: module.color.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: module.onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                module.color.withValues(alpha: 0.10),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: module.color,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: module.color.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(module.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        module.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: module.color.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFFFD166)),
            const SizedBox(width: 6),
            Flexible(child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )),
          ],
        ),
      );
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
            'School blocked: this account is read-only. Changes and uploads must be rejected by the backend as well.'),
      );
}

/// Shows the message published by Admin for today's school date on the teacher home.
class _TodaySchoolMessageBanner extends StatefulWidget {
  const _TodaySchoolMessageBanner();
  @override
  State<_TodaySchoolMessageBanner> createState() =>
      _TodaySchoolMessageBannerState();
}

class _TodaySchoolMessageBannerState extends State<_TodaySchoolMessageBanner> {
  String? _message;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      final school = await client.rpc('current_school_ref');
      if (school == null || '$school'.trim().isEmpty) return;
      final now =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final row = await client
          .from('school_admin_messages')
          .select('message')
          .eq('school_ref', '$school')
          .eq('message_date', date)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        final value = '${row?['message'] ?? ''}'.trim();
        _message = value.isEmpty ? null : value;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _message = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (!_loaded || message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.campaign_outlined,
              color: Theme.of(context).colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('આજનો શાળા સંદેશ / School Message',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(message),
              ])),
        ]),
      ),
    );
  }
}
