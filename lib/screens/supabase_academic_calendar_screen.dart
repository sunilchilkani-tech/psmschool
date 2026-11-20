import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Academic Calendar & Circular Reminders (`શૈક્ષણિક કેલેન્ડર અને પરિપત્ર રીમાઈન્ડર`).
/// Admin marks exam dates, PTM dates, SMC meetings, and government deadlines;
/// Teachers & Admin see upcoming events right on their Home screen and here.
class SupabaseAcademicCalendarScreen extends StatefulWidget {
  const SupabaseAcademicCalendarScreen({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<SupabaseAcademicCalendarScreen> createState() =>
      _SupabaseAcademicCalendarScreenState();
}

class _SupabaseAcademicCalendarScreenState
    extends State<SupabaseAcademicCalendarScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final DateFormat _dmy = DateFormat('dd/MM/yyyy');

  static const List<String> _categories = <String>[
    'પરીક્ષા / Exam',
    'PTM / વાલી મીટિંગ',
    'SMC સભા',
    'સરકારી ડેડલાઈન / Govt Deadline',
    'ઉજવણી / પ્રવૃત્તિ',
    'અન્ય',
  ];

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = <Map<String, dynamic>>[];

  bool get _isAdmin {
    final r = '${widget.profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    return r == 'admin' || r == 'developer';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _todayIso() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return _iso(now);
  }

  String _displayDate(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    final dt = DateTime.tryParse(s);
    return dt == null ? s : _dmy.format(dt);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.rpc('psm_get_academic_calendar');
      final list = res is List
          ? res
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry('$k', v)))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _events = list;
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

  Future<void> _addOrEditEvent([Map<String, dynamic>? existing]) async {
    final titleCtrl = TextEditingController(
      text: '${existing?['title'] ?? ''}',
    );
    final notesCtrl = TextEditingController(
      text: '${existing?['notes'] ?? ''}',
    );
    var category = _categories.contains('${existing?['category'] ?? ''}')
        ? '${existing!['category']}'
        : _categories.first;
    var eventDate =
        DateTime.tryParse('${existing?['event_date'] ?? ''}') ?? DateTime.now();
    var endDate =
        DateTime.tryParse('${existing?['end_date'] ?? ''}') ?? eventDate;
    var saving = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'નવો શૈક્ષણિક કાર્યક્રમ / રીમાઈન્ડર ઉમેરો'
                : 'કાર્યક્રમ સુધારો',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'પ્રકાર (Category)',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'કાર્યક્રમ / પરિપત્રનું શીર્ષક',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: eventDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (p != null) {
                            setDialogState(() {
                              eventDate = p;
                              if (endDate.isBefore(eventDate)) {
                                endDate = eventDate;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text('તારીખ થી: ${_dmy.format(eventDate)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: endDate,
                            firstDate: eventDate,
                            lastDate: DateTime(2100),
                          );
                          if (p != null) {
                            setDialogState(() => endDate = p);
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: Text('સુધી: ${_dmy.format(endDate)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'વિગત / સૂચના (વૈકલ્પિક)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(false),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        setDialogState(
                          () => dialogError = 'કૃપા કરીને શીર્ષક દાખલ કરો.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });
                      try {
                        await _client.rpc(
                          'psm_save_academic_calendar_event',
                          params: <String, dynamic>{
                            if (existing != null) 'p_id': existing['id'],
                            'p_event_date': _iso(eventDate),
                            'p_end_date': _iso(endDate),
                            'p_title': titleCtrl.text.trim(),
                            'p_category': category,
                            'p_notes': notesCtrl.text.trim(),
                          },
                        );
                        if (dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(true);
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          dialogError = '$e'.replaceFirst('Exception: ', '');
                        });
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'સાચવે છે…' : 'સાચવો'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    notesCtrl.dispose();
    if (saved == true) await _load();
  }

  Future<void> _deleteEvent(Map<String, dynamic> ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('કાર્યક્રમ કાઢી નાખવો?'),
        content: Text('"${ev['title'] ?? ''}" ને કેલેન્ડરમાંથી દૂર કરવામાં આવશે.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('રદ કરો'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('કાઢી નાખો'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _client.rpc(
      'psm_delete_academic_calendar_event',
      params: <String, dynamic>{'p_id': '${ev['id'] ?? ''}'},
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayIso();
    final upcoming = _events
        .where((e) => '${e['end_date'] ?? e['event_date'] ?? ''}'.compareTo(today) >= 0)
        .toList();
    final past = _events
        .where((e) => '${e['end_date'] ?? e['event_date'] ?? ''}'.compareTo(today) < 0)
        .toList()
        .reversed
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('શૈક્ષણિક કેલેન્ડર અને રીમાઈન્ડર'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _addOrEditEvent(),
              icon: const Icon(Icons.add),
              label: const Text('નવો કાર્યક્રમ'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Text(
                  '📅 આગામી કાર્યક્રમો અને ડેડલાઈન (${upcoming.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                if (upcoming.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('હાલમાં કોઈ આગામી કાર્યક્રમ નોંધાયેલ નથી.'),
                    ),
                  )
                else
                  for (final ev in upcoming) _eventCard(ev, isUpcoming: true),
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '🗂️ પૂર્ણ થયેલા કાર્યક્રમો (${past.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final ev in past) _eventCard(ev, isUpcoming: false),
                ],
                const SizedBox(height: 70),
              ],
            ),
    );
  }

  Widget _eventCard(Map<String, dynamic> ev, {required bool isUpcoming}) {
    final sDate = _displayDate(ev['event_date']);
    final eDate = _displayDate(ev['end_date']);
    final dateText = sDate == eDate || eDate.isEmpty ? sDate : '$sDate થી $eDate';
    final notes = '${ev['notes'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isUpcoming ? Colors.indigo.shade100 : Colors.grey.shade200,
          child: Icon(
            Icons.event_note_rounded,
            color: isUpcoming ? Colors.indigo.shade800 : Colors.grey.shade700,
          ),
        ),
        title: Text(
          '${ev['title'] ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${ev['category'] ?? ''}  •  $dateText${notes.isEmpty ? '' : '\n$notes'}',
        ),
        isThreeLine: notes.isNotEmpty,
        trailing: _isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'સુધારો',
                    onPressed: () => _addOrEditEvent(ev),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'કાઢી નાખો',
                    onPressed: () => _deleteEvent(ev),
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

/// Compact Home Screen banner showing upcoming academic calendar events (next 14 days).
class UpcomingAcademicEventsBanner extends StatefulWidget {
  const UpcomingAcademicEventsBanner({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<UpcomingAcademicEventsBanner> createState() =>
      _UpcomingAcademicEventsBannerState();
}

class _UpcomingAcademicEventsBannerState
    extends State<UpcomingAcademicEventsBanner> {
  List<Map<String, dynamic>> _upcoming = <Map<String, dynamic>>[];
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
      final res = await client.rpc('psm_get_academic_calendar');
      if (res is! List) return;
      final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final todayIso =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final upcoming = res
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .where(
            (e) =>
                '${e['end_date'] ?? e['event_date'] ?? ''}'.compareTo(todayIso) >=
                0,
          )
          .take(3)
          .toList();
      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _upcoming.isEmpty) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFEEF2FF),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SupabaseAcademicCalendarScreen(profile: widget.profile),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.event_available_rounded,
                      color: Color(0xFF3730A3), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'આગામી શાળા કાર્યક્રમો / Upcoming School Events',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF312E81),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Color(0xFF3730A3)),
                ],
              ),
              const SizedBox(height: 6),
              for (final ev in _upcoming)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '• ${ev['event_date']} — ${ev['title']} (${ev['category']})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E1B4B),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
