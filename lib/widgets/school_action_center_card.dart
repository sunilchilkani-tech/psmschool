import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../screens/supabase_attendance_entry_screen.dart';
import '../screens/supabase_library_screen.dart';
import '../screens/supabase_low_attendance_alerts_screen.dart';
import '../services/school_class_order.dart';

class _ActionCardItem {
  const _ActionCardItem({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onResolve,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onResolve;
}

/// Actionable "Today's Action Center / આજની જરૂરી કાર્યવાહી" cards with direct
/// "Resolve Now" buttons:
/// 1. Pending class attendance today -> opens that exact class & date.
/// 2. Class with > 20% students absent today -> opens that exact class & date.
/// 3. Students below 65% monthly attendance -> opens `<65%` filtered list.
/// 4. Library books overdue by due date (Class Teacher, Allotted Teacher & Admin)
///    -> opens Library Register directly.
class SchoolActionCenterCard extends StatefulWidget {
  const SchoolActionCenterCard({
    super.key,
    required this.profile,
    this.readOnly = false,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;

  @override
  State<SchoolActionCenterCard> createState() => _SchoolActionCenterCardState();
}

class _SchoolActionCenterCardState extends State<SchoolActionCenterCard> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  bool _expanded = true;
  List<_ActionCardItem> _items = <_ActionCardItem>[];

  bool get _isAdmin {
    final r = '${widget.profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    return r == 'admin' || r == 'developer';
  }

  DateTime _indiaNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _text(dynamic v) => (v ?? '').toString().trim();

  int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_text(v)) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openExactAttendance(String classId, String dateIso) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupabaseAttendanceEntryScreen(
          profile: widget.profile,
          readOnly: widget.readOnly,
          showAppBar: true,
          initialClassId: classId,
          initialDate: dateIso,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (_client.auth.currentUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final schoolRef = _text(await _client.rpc('current_school_ref'));
      if (schoolRef.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final now = _indiaNow();
      final todayIso = _iso(now);
      final isSunday = now.weekday == DateTime.sunday;

      final results = await Future.wait<dynamic>([
        _client.rpc(
          'psm_get_attendance_entry_access',
          params: <String, dynamic>{'p_attendance_date': todayIso},
        ),
        _client
            .from('school_holidays')
            .select('holiday_date')
            .eq('school_ref', schoolRef)
            .eq('holiday_date', todayIso),
        _client
            .from('attendance_days')
            .select('id,class_id,attendance_date,present_saved,registered_counts,present_counts,gender_breakdown')
            .eq('school_ref', schoolRef)
            .eq('attendance_date', todayIso),
        _client
            .from('students')
            .select('id,class_id,is_active,leaving_date,exit_date')
            .eq('school_ref', schoolRef)
            .eq('is_active', true),
        _client
            .from('library_transactions')
            .select('id,class_id,student_name,book_title,due_date,status')
            .eq('school_ref', schoolRef)
            .eq('status', 'issued'),
        _client.rpc(
          'psm_compute_absence_streaks_and_alerts',
          params: const <String, dynamic>{},
        ),
      ]);

      final accessMap =
          results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : <String, dynamic>{};
      final rawClasses = (accessMap['classes'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();
      final classes = SchoolClassOrder.sorted(rawClasses);
      final classIdsInScope = <String>{
        for (final c in classes) _text(c['id']),
      };
      final classLabelById = <String, String>{
        for (final c in classes)
          _text(c['id']): _text(c['label']).isNotEmpty
              ? _text(c['label'])
              : _text(c['class_key']),
      };

      final isHoliday = (results[1] as List).isNotEmpty;
      final todayDays = (results[2] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();
      final dayByClassId = <String, Map<String, dynamic>>{
        for (final d in todayDays) _text(d['class_id']): d,
      };

      final activeStudents = (results[3] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .where(
            (s) =>
                s['is_active'] == true &&
                _text(s['leaving_date']).isEmpty &&
                _text(s['exit_date']).isEmpty,
          )
          .toList();
      final regCountByClassId = <String, int>{};
      for (final s in activeStudents) {
        final cid = _text(s['class_id']);
        regCountByClassId[cid] = (regCountByClassId[cid] ?? 0) + 1;
      }

      final issuedBooks = (results[4] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();

      final absMap =
          results[5] is Map ? Map<String, dynamic>.from(results[5] as Map) : <String, dynamic>{};
      final absAlerts = (absMap['alerts'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();

      final cards = <_ActionCardItem>[];

      // 1 & 2: Pending attendance today & >20% absent in one day (skip Sunday & Holidays)
      if (!isSunday && !isHoliday) {
        for (final c in classes) {
          final cid = _text(c['id']);
          final lbl = classLabelById[cid] ?? 'Class';
          final regCount = regCountByClassId[cid] ?? 0;
          if (regCount == 0) continue;
          final day = dayByClassId[cid];
          final presentSaved = day != null && day['present_saved'] != false;

          if (!presentSaved) {
            cards.add(
              _ActionCardItem(
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFB91C1C),
                bgColor: const Color(0xFFFEF2F2),
                title: '$lbl — આજની હાજરી બાકી છે (Attendance Pending)',
                subtitle: 'તારીખ $todayIso • કુલ વિદ્યાર્થીઓ: $regCount',
                buttonLabel: 'Resolve Now / હાજરી પૂરો',
                onResolve: () => _openExactAttendance(cid, todayIso),
              ),
            );
          } else {
            // Check > 20% absent on this single day
            final gb = day['gender_breakdown'] is Map
                ? Map<String, dynamic>.from(day['gender_breakdown'] as Map)
                : <String, dynamic>{};
            final pCounts = day['present_counts'] is Map
                ? Map<String, dynamic>.from(day['present_counts'] as Map)
                : <String, dynamic>{};
            var pres = _int(gb['present_total']);
            if (pres == 0 && pCounts.isNotEmpty) {
              pres = _int(pCounts['TOTAL'] ?? pCounts['total']);
              if (pres == 0) {
                for (final v in pCounts.values) {
                  pres += _int(v);
                }
              }
            }
            if (pres == 0) {
              pres = _int(gb['present_boys']) + _int(gb['present_girls']);
            }
            final absent = (regCount - pres).clamp(0, regCount);
            final absentPct = regCount > 0 ? (absent * 100.0 / regCount) : 0.0;
            if (absentPct > 20.0) {
              cards.add(
                _ActionCardItem(
                  icon: Icons.groups_2_rounded,
                  color: const Color(0xFFC2410C),
                  bgColor: const Color(0xFFFFF7ED),
                  title:
                      '$lbl — આજે ${absentPct.toStringAsFixed(0)}% વિદ્યાર્થી ગેરહાજર (>20%)',
                  subtitle:
                      'તારીખ $todayIso • ગેરહાજર: $absent / $regCount (હાજર: $pres)',
                  buttonLabel: 'Resolve Now / વર્ગ જુઓ',
                  onResolve: () => _openExactAttendance(cid, todayIso),
                ),
              );
            }
          }
        }
      }

      // 3: Low-attendance students below 65% for current month
      final below65 = absAlerts.where((a) {
        final w = _int(a['month_working_days']);
        final pct = (a['month_percentage'] as num?)?.toDouble() ?? 100.0;
        return w >= 3 && pct < 65.0;
      }).toList();
      if (below65.isNotEmpty) {
        final previewNames = below65
            .take(3)
            .map(
              (a) =>
                  '${_text(a['student_name'])} (${_text(a['class_label'])} • ${a['month_percentage']}%)',
            )
            .join(', ');
        cards.add(
          _ActionCardItem(
            icon: Icons.trending_down_rounded,
            color: const Color(0xFF991B1B),
            bgColor: const Color(0xFFFFF1F2),
            title:
                'માસિક હાજરી 65% થી ઓછી: ${below65.length} વિદ્યાર્થીઓ (Low Attendance <65%)',
            subtitle:
                '$previewNames${below65.length > 3 ? ' + ${below65.length - 3} અન્ય' : ''}',
            buttonLabel: 'Resolve Now / યાદી જુઓ',
            onResolve: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SupabaseLowAttendanceAlertsScreen(
                    profile: widget.profile,
                    initialFilterMode: 'below_65',
                  ),
                ),
              );
              if (mounted) _load();
            },
          ),
        );
      }

      // 4: Overdue Library Books by due_date (for Class Teacher, Allotted Teacher & Admin)
      final overdueBooks = issuedBooks.where((tx) {
        final due = _text(tx['due_date']);
        if (due.length < 10) return false;
        final dueIso = due.substring(0, 10);
        if (dueIso.compareTo(todayIso) >= 0) return false;
        if (_isAdmin) return true;
        final cid = _text(tx['class_id']);
        return cid.isEmpty || classIdsInScope.contains(cid);
      }).toList();

      if (overdueBooks.isNotEmpty) {
        final sample = overdueBooks
            .take(2)
            .map(
              (tx) =>
                  '${_text(tx['student_name']).isEmpty ? 'વિદ્યાર્થી' : _text(tx['student_name'])} — ${_text(tx['book_title'])} (મુદત: ${_text(tx['due_date']).substring(0, 10)})',
            )
            .join(' • ');
        cards.add(
          _ActionCardItem(
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF7C2D12),
            bgColor: const Color(0xFFFFFBEB),
            title:
                'પુસ્તકાલય પુસ્તક મુદત પૂર્ણ (Overdue): ${overdueBooks.length} પુસ્તકો',
            subtitle:
                '$sample${overdueBooks.length > 2 ? ' + ${overdueBooks.length - 2} અન્ય' : ''}',
            buttonLabel: 'Resolve Now / પરત લો',
            onResolve: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SupabaseLibraryScreen(
                    profile: widget.profile,
                    readOnly: widget.readOnly,
                  ),
                ),
              );
              if (mounted) _load();
            },
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _items = cards;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.red.shade200, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'આજની જરૂરી કાર્યવાહી / Action Required (${_items.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.red.shade700,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              for (final item in _items)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: item.bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.color.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(item.icon, color: item.color, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: item.color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: item.color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: item.onResolve,
                        child: Text(
                          item.buttonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
