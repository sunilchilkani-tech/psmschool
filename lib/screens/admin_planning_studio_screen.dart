import 'package:flutter/material.dart';
import '../services/school_name_language_service.dart';
import '../services/supabase_school_planning_service.dart';
import 'exam_planning_screen.dart';
import 'smart_school_timetable_studio.dart';
import 'supabase_file_share_screen.dart';

/// Unified Studio for Smart Timetable, Exam Planning (18 Patraks), and
/// `<School Name> File Sharing`.
class AdminPlanningStudioScreen extends StatefulWidget {
  const AdminPlanningStudioScreen({
    super.key,
    required this.profile,
    this.initialTab = 0,
    this.singleTool = true,
  });

  final Map<String, dynamic> profile;

  /// 0 = Timetable, 1 = Exam planning.
  final int initialTab;

  /// When true (default) the screen shows only [initialTab] as its own tool,
  /// without switching tabs. File sharing has its own Home tile.
  final bool singleTool;

  @override
  State<AdminPlanningStudioScreen> createState() =>
      _AdminPlanningStudioScreenState();
}

class _AdminPlanningStudioScreenState extends State<AdminPlanningStudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final SupabaseSchoolPlanningService _service =
      SupabaseSchoolPlanningService();
  bool _loading = true;
  int _revision = 0;
  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  Map<String, dynamic> _data = <String, dynamic>{};

  bool get _isBlocked =>
      widget.profile['is_blocked'] == true ||
      widget.profile['can_edit'] == false;

  String get _schoolRef =>
      '${_data['schoolRef'] ?? widget.profile['school_ref'] ?? widget.profile['school_id'] ?? ''}'
          .trim();

  String get _schoolName {
    final gu =
        '${_data['schoolNameGu'] ?? widget.profile['school_name_gu'] ?? _data['schoolName'] ?? ''}'
            .trim();
    final en =
        '${_data['schoolNameEn'] ?? widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? _data['schoolName'] ?? ''}'
            .trim();
    if (_schoolNameLanguage == SchoolNameLanguageService.english) {
      return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : 'School');
    }
    return gu.isNotEmpty ? gu : (en.isNotEmpty ? en : 'School');
  }

  String get _schoolAddress {
    final gu =
        '${_data['schoolAddressGu'] ?? widget.profile['school_address_gu'] ?? _data['schoolAddress'] ?? ''}'
            .trim();
    final en =
        '${_data['schoolAddressEn'] ?? widget.profile['school_address_en'] ?? widget.profile['school_address'] ?? _data['schoolAddress'] ?? ''}'
            .trim();
    if (_schoolNameLanguage == SchoolNameLanguageService.english) {
      return en.isNotEmpty ? en : gu;
    }
    return gu.isNotEmpty ? gu : en;
  }

  Future<void> _setSchoolNameLanguage(String lang) async {
    if (lang != SchoolNameLanguageService.gujarati &&
        lang != SchoolNameLanguageService.english) {
      return;
    }
    setState(() {
      _schoolNameLanguage = lang;
      _revision++;
    });
    try {
      await SchoolNameLanguageService.saveLanguage(
        schoolRef: _schoolRef,
        language: lang,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) {
        setState(() {});
      }
    });
    _load(forceRefresh: false);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = true}) async {
    setState(() {
      _loading = true;
    });
    try {
      final loaded = await _service.loadPlanningData(
        profile: widget.profile,
        forceRefresh: forceRefresh,
      );
      final lang = await SchoolNameLanguageService.loadLanguage(
        schoolRef:
            '${loaded['schoolRef'] ?? widget.profile['school_ref'] ?? ''}',
      );
      if (!mounted) return;
      setState(() {
        _data = loaded;
        _schoolNameLanguage = lang;
        _loading = false;
        _revision++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = <String, dynamic>{
          'schoolName': widget.profile['school_name_gu'] ??
              widget.profile['school_name'] ??
              'PM SHRI School',
          'academicYear': widget.profile['academic_year'] ?? '૨૦૨૬-૨૭',
        };
        _loading = false;
        _revision++;
      });
    }
  }

  Future<void> _save(String key, Map<String, dynamic> value) async {
    if (_isBlocked) {
      throw StateError('This account is currently in read-only mode.');
    }
    await _service.savePlanningData(key: key, value: value);
  }

  Widget _buildActiveStudioTab(Map<String, dynamic> dbData) {
    switch (_tabs.index) {
      case 0:
        return RepaintBoundary(
          key: ValueKey('tt-tab-$_revision'),
          child: TimetableStudioHome(
            key: ValueKey(
              'timetable-$_revision-${(_data['teachers'] as List? ?? const []).length}-${(_data['assignments'] as List? ?? const []).length}',
            ),
            useDatabaseData: true,
            databaseData: dbData,
            savedData: _planningMap(_data['savedTimetable']),
            onSaveData: _isBlocked
                ? null
                : (value) => _save('planning_timetable_studio', value),
          ),
        );
      case 1:
      default:
        return RepaintBoundary(
          key: ValueKey('exam-tab-$_revision'),
          child: ExamPlanningScreen(
            key: ValueKey(
              'exam-$_revision-${(_data['teachers'] as List? ?? const []).length}-${(_data['examRows'] as List? ?? const []).length}',
            ),
            useDatabaseData: true,
            databaseData: dbData,
            savedData: _planningMap(_data['savedExam']),
            onSaveData: _isBlocked
                ? null
                : (value) => _save('planning_exam_planning', value),
          ),
        );
    }
  }

  Widget _buildLanguageToggleChip() {
    final isGu = _schoolNameLanguage != SchoolNameLanguageService.english;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.amber),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                _setSchoolNameLanguage(SchoolNameLanguageService.gujarati),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isGu ? const Color(0xFF00E5FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ગુજરાતી',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isGu ? const Color(0xFF0F172A) : Colors.white70,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                _setSchoolNameLanguage(SchoolNameLanguageService.english),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: !isGu ? const Color(0xFF00E5FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'English',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: !isGu ? const Color(0xFF0F172A) : Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_toolTitle),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final dbData = <String, dynamic>{
      ..._data,
      'schoolName': _schoolName,
      'schoolAddress': _schoolAddress,
      'schoolNameLanguage': _schoolNameLanguage,
      'academicYear': _data['academicYear'],
    };
    final isNarrow = MediaQuery.of(context).size.width < 680;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(
          '$_schoolName — $_toolTitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
        ),
        actions: [
          _buildLanguageToggleChip(),
          IconButton(
            tooltip: 'શાળાના ડેટાબેઝમાંથી શિક્ષકો, વર્ગો અને વિષયો રીફ્રેશ કરો',
            onPressed: () => _load(forceRefresh: true),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
        bottom: widget.singleTool
            ? null
            : TabBar(
          controller: _tabs,
          isScrollable: isNarrow,
          onTap: (_) => setState(() {}),
          indicatorColor: const Color(0xFF00E5FF),
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            const Tab(
              icon: Icon(Icons.calendar_month_rounded, size: 19),
              text: '1. 🗓️ સમયપત્રક (Timetable)',
            ),
            const Tab(
              icon: Icon(Icons.assignment_turned_in_rounded, size: 19),
              text: '2. 📝 પરીક્ષા આયોજન (Exam Plan)',
            ),
          ],
        ),
      ),
      body: _buildActiveStudioTab(dbData),
    );
  }

  String get _toolTitle => _tabs.index == 0
      ? 'સમયપત્રક / Timetable'
      : 'પરીક્ષા આયોજન / Exam Planner';

  Map<String, dynamic> _planningMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }
}
