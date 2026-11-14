import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/school_class_order.dart';
import '../services/school_name_language_service.dart';
import '../widgets/school_name_language_selector.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Calculates individual attendance from saved student-level attendance rows.
/// Direct Entry dates count as recorded school days, but are excluded from an
/// individual student's percentage because they cannot be attributed by student.
class SupabaseParentAttendanceMessageScreen extends StatefulWidget {
  const SupabaseParentAttendanceMessageScreen({
    super.key,
    required this.profile,
    this.readOnly = false,
  });

  final Map<String, dynamic> profile;
  final bool readOnly;

  @override
  State<SupabaseParentAttendanceMessageScreen> createState() =>
      _SupabaseParentAttendanceMessageScreenState();
}

class _SupabaseParentAttendanceMessageScreenState
    extends State<SupabaseParentAttendanceMessageScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final DateFormat _displayDate = DateFormat('dd-MM-yyyy');

  bool _loading = true;
  bool _calculating = false;
  String? _error;
  String? _schoolRef;
  String _schoolNameLanguage = SchoolNameLanguageService.gujarati;
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  String? _classId;
  String _fromDate = _monthStart();
  String _toDate = _today();
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<_AttendanceMessageRecipient> _recipients = <_AttendanceMessageRecipient>[];
  int _recordedWorkingDays = 0;
  int _studentLevelDays = 0;
  int _nextQueueIndex = 0;

  DateTime _indiaNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _today() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _monthStart() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
  }

  String _dateLabel(String iso) {
    try {
      return _displayDate.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  int _numericRoll(dynamic value) {
    final raw = _text(value);
    return int.tryParse(raw) ?? 1 << 30;
  }

  String _normalizePhone(dynamic raw) {
    var digits = _text(raw).replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 10) digits = '91$digits';
    if (digits.length < 11 || digits.length > 15) return '';
    return digits;
  }

  String get _schoolName => SchoolNameLanguageService.resolveSchoolName(
        language: _schoolNameLanguage,
        profile: widget.profile,
        schoolContext: _schoolContext,
        fallbackEnglish: _text(widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? widget.profile['schoolName']),
      );

  Map<String, dynamic>? get _selectedClass {
    for (final row in _classes) {
      if ('${row['id']}' == _classId) return row;
    }
    return null;
  }

  String get _classLabel {
    final row = _selectedClass;
    return row == null ? '' : '${row['label'] ?? row['class_key'] ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_client.auth.currentUser == null) throw StateError('તમારું Supabase login સમાપ્ત થયું છે. ફરી login કરો.');
      final schoolRef = _text(await _client.rpc('current_school_ref'));
      if (schoolRef.isEmpty) throw StateError('આ login સાથે સક્રિય શાળા જોડાયેલી નથી.');
      final schoolNameLanguage = await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      final schoolContext = await SchoolNameLanguageService.loadCurrentSchoolContext(_client);
      final rows = await _client
          .from('school_classes')
          .select('id,school_ref,class_key,label,standard,section,report_group,sort_order,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      final classes = SchoolClassOrder.sorted(
        rows.map((row) => Map<String, dynamic>.from(row)),
      );
      if (!mounted) return;
      setState(() {
        _schoolRef = schoolRef;
        _schoolNameLanguage = schoolNameLanguage;
        _schoolContext = schoolContext;
        _classes = classes;
        _classId = classes.isEmpty ? null : '${classes.first['id']}';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = _cleanError(error); _loading = false; });
    }
  }

  String _cleanError(Object error) => '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');

  Future<void> _pickDate({required bool isFrom}) async {
    final now = _indiaNow();
    final current = DateTime.tryParse(isFrom ? _fromDate : _toDate) ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(DateTime(now.year, now.month, now.day)) ? DateTime(now.year, now.month, now.day) : current,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: isFrom ? 'શરૂઆતની તારીખ પસંદ કરો' : 'અંતિમ તારીખ પસંદ કરો',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = _iso(picked);
        if (_fromDate.compareTo(_toDate) > 0) _toDate = _fromDate;
      } else {
        _toDate = _iso(picked);
        if (_toDate.compareTo(_fromDate) < 0) _fromDate = _toDate;
      }
      _recipients = <_AttendanceMessageRecipient>[];
      _recordedWorkingDays = 0;
      _studentLevelDays = 0;
      _nextQueueIndex = 0;
      _error = null;
    });
  }

  Future<void> _prepareMessages() async {
    final schoolRef = _schoolRef;
    final classId = _classId;
    if (schoolRef == null || classId == null) return;
    if (_fromDate.compareTo(_toDate) > 0) {
      setState(() => _error = 'શરૂઆતની તારીખ અંતિમ તારીખ કરતાં મોટી ન હોઈ શકે.');
      return;
    }

    setState(() {
      _calculating = true;
      _error = null;
      _recipients = <_AttendanceMessageRecipient>[];
      _nextQueueIndex = 0;
    });

    try {
      final dayRowsRaw = await _client
          .from('attendance_days')
          .select('id,attendance_date,attendance_mode,student_details_saved')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .gte('attendance_date', _fromDate)
          .lte('attendance_date', _toDate)
          .order('attendance_date');
      final dayRows = dayRowsRaw.map((row) => Map<String, dynamic>.from(row)).toList();
      final individualDays = dayRows.where((row) {
        final mode = _text(row['attendance_mode']).toLowerCase();
        return mode != 'direct' && row['student_details_saved'] == true;
      }).toList();
      _recordedWorkingDays = dayRows.length;
      _studentLevelDays = individualDays.length;

      if (dayRows.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'પસંદ કરેલા સમયગાળામાં આ વર્ગની કોઈ હાજરી નોંધાઈ નથી.');
        return;
      }
      if (individualDays.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'આ સમયગાળામાં હાજરી Direct Entry થી નોંધાઈ છે. Direct Entry કુલ આંકડામાંથી દરેક વિદ્યાર્થીની વ્યક્તિગત હાજરી/ટકાવારી કાઢી શકાતી નથી. વ્યક્તિગત હાજરી નોંધણીવાળા દિવસો પસંદ કરો.');
        return;
      }

      final studentsRaw = await _client
          .from('students')
          .select('id,roll_number,name,mobile')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('is_active', true);
      final students = studentsRaw.map((row) => Map<String, dynamic>.from(row)).toList();
      if (students.isEmpty) {
        if (!mounted) return;
        setState(() => _error = 'આ વર્ગમાં સક્રિય વિદ્યાર્થીઓ મળ્યા નથી.');
        return;
      }

      final studentMap = <String, Map<String, dynamic>>{
        for (final student in students) _text(student['id']): student,
      };
      final presentByStudent = <String, int>{};
      final trackedByStudent = <String, int>{};
      final dayIds = individualDays.map((row) => _text(row['id'])).where((id) => id.isNotEmpty).toList();
      const chunkSize = 150;
      for (var offset = 0; offset < dayIds.length; offset += chunkSize) {
        final chunk = dayIds.skip(offset).take(chunkSize).toList();
        final markRows = await _client
            .from('student_attendance')
            .select('student_id,present,attendance_day_id')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .inFilter('attendance_day_id', chunk);
        for (final raw in markRows) {
          final row = Map<String, dynamic>.from(raw);
          final id = _text(row['student_id']);
          if (!studentMap.containsKey(id)) continue;
          trackedByStudent[id] = (trackedByStudent[id] ?? 0) + 1;
          if (row['present'] == true) presentByStudent[id] = (presentByStudent[id] ?? 0) + 1;
        }
      }

      final recipients = <_AttendanceMessageRecipient>[];
      for (final student in students) {
        final id = _text(student['id']);
        final tracked = trackedByStudent[id] ?? 0;
        if (tracked == 0) continue;
        final present = presentByStudent[id] ?? 0;
        final percent = tracked == 0 ? 0.0 : present * 100 / tracked;
        recipients.add(_AttendanceMessageRecipient(
          id: id,
          name: _text(student['name']),
          roll: _text(student['roll_number']),
          phone: _normalizePhone(student['mobile']),
          presentDays: present,
          trackedDays: tracked,
          percentage: percent,
        ));
      }
      recipients.sort((a, b) {
        final pct = b.percentage.compareTo(a.percentage);
        if (pct != 0) return pct;
        final present = b.presentDays.compareTo(a.presentDays);
        if (present != 0) return present;
        return _numericRoll(a.roll).compareTo(_numericRoll(b.roll));
      });
      for (var index = 0; index < recipients.length; index++) {
        final recipient = recipients[index];
        recipient.rank = index + 1;
        recipient.message = _buildMessage(recipient, index, recipients.length);
      }
      if (!mounted) return;
      setState(() {
        _recipients = recipients;
        _nextQueueIndex = 0;
        if (recipients.isEmpty) {
          _error = 'પસંદ કરેલા દિવસો માટે કોઈ વિદ્યાર્થીની વ્યક્તિગત હાજરી નોંધ મળી નથી.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  String _buildMessage(_AttendanceMessageRecipient student, int sortedIndex, int totalStudents) {
    final start = _dateLabel(_fromDate);
    final end = _dateLabel(_toDate);
    final isTopThree = sortedIndex < 3 && student.percentage > 0;
    String suggestion;
    if (isTopThree) {
      suggestion = '🏆 અભિનંદન! આ સમયગાળામાં તમારા સંતાનની હાજરી વર્ગના ટોચના 3 વિદ્યાર્થીઓમાં છે. આ ઉત્તમ નિયમિતતા જાળવી રાખવા બદલ ખૂબ ખૂબ અભિનંદન. નિયમિત હાજરીથી પાઠ સમજવામાં, પુનરાવર્તન અને અભ્યાસમાં સતત પ્રગતિ કરવામાં મદદ મળે છે.';
    } else if (student.percentage >= 95) {
      suggestion = 'તમારા સંતાનની હાજરી ખૂબ સારી છે. આ નિયમિતતા ચાલુ રાખશો. રોજ શાળામાં હાજર રહેવાથી નવો પાઠ, પ્રવૃત્તિઓ અને પુનરાવર્તનનો સંપૂર્ણ લાભ મળે છે.';
    } else if (student.percentage >= 85) {
      suggestion = 'હાજરી સારી છે; તેને વધુ સુધારી 95% કે તેથી વધુ રાખવાનો પ્રયત્ન કરશો. શક્ય હોય ત્યાં સુધી કારણ વગરની રજા ટાળો, કારણ કે દરરોજના પાઠ એકબીજા સાથે જોડાયેલા હોય છે.';
    } else if (student.percentage >= 75) {
      suggestion = 'હાજરીમાં થોડો સુધારો જરૂરી છે. કૃપા કરીને તમારા સંતાનને નિયમિત શાળાએ મોકલશો. વારંવાર ગેરહાજરીથી પાઠ, વર્ગકાર્ય અને પુનરાવર્તન ચૂકી શકે છે.';
    } else {
      suggestion = 'આ સમયગાળામાં હાજરી ઓછી નોંધાઈ છે. તમારા સંતાનના અભ્યાસમાં સતત પ્રગતિ માટે નિયમિત શાળાએ મોકલવા આપશ્રીને ખાસ વિનંતી છે. સ્વાસ્થ્ય અથવા અન્ય કોઈ મુશ્કેલીને કારણે ગેરહાજરી થતી હોય તો વર્ગશિક્ષક સાથે સંપર્ક કરશો, જેથી યોગ્ય સહાય કરી શકાય.';
    }
    final notes = student.trackedDays < _recordedWorkingDays
        ? '\nનોંધ: પસંદ કરેલા સમયગાળામાં શાળામાં કુલ $_recordedWorkingDays દિવસની હાજરી નોંધાઈ છે. વ્યક્તિગત ટકાવારી દરેક વિદ્યાર્થી માટે ઉપલબ્ધ વ્યક્તિગત હાજરી નોંધાયેલા દિવસો પરથી ગણાઈ છે. Direct Entry અથવા વિદ્યાર્થી માટે વ્યક્તિગત નોંધ ઉપલબ્ધ ન હોય તે દિવસો ટકાવારીમાં સામેલ નથી.'
        : '';
    final rankLine = isTopThree ? '\nવર્ગમાં હાજરી રેન્ક: ${student.rank} / $totalStudents' : '';
    return 'આપના બાળકનો હાજરી અહેવાલ\n\n'
        'શાળા: $_schoolName\n'
        'ધોરણ: ${ClassLabel.bare(_classLabel)}\n'
        'સમયગાળો: $start થી $end\n'
        'વિદ્યાર્થી: ${student.name}\n'
        'કુલ નોંધાયેલા કાર્યદિવસ: $_recordedWorkingDays\n'
        'વિદ્યાર્થીની હાજરી ગણતરીમાં લેવાયેલા દિવસો: ${student.trackedDays}\n'
        'હાજર દિવસો: ${student.presentDays}\n'
        'હાજરીની ટકાવારી: ${student.percentage.toStringAsFixed(1)}%$rankLine\n\n'
        '$suggestion\n\n'
        'વિદ્યાર્થીની નિયમિત હાજરી તેના જ્ઞાન, આત્મવિશ્વાસ અને શૈક્ષણિક વિકાસ માટે ખૂબ મહત્વપૂર્ણ છે. આપના સહકાર બદલ આભાર.$notes';
  }

  List<_AttendanceMessageRecipient> get _withMobile =>
      _recipients.where((student) => student.phone.isNotEmpty).toList();

  Future<void> _openNextWhatsAppDraft() async {
    if (widget.readOnly) return;
    final queue = _withMobile;
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('માન્ય મોબાઇલ નંબરવાળા વિદ્યાર્થી મળ્યા નથી.')));
      return;
    }
    if (_nextQueueIndex >= queue.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('બધા WhatsApp ડ્રાફ્ટ ખોલી દીધા છે. દરેક ચેટમાં Send દબાવવાનું યાદ રાખો.')));
      return;
    }
    final recipient = queue[_nextQueueIndex];
    final uri = Uri.https('wa.me', '/${recipient.phone}', <String, String>{'text': recipient.message});
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('WhatsApp ખોલી શકાયું નથી. ફોનમાં WhatsApp અથવા compatible browser તપાસો.');
      if (!mounted) return;
      setState(() => _nextQueueIndex++);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${recipient.name} માટે WhatsApp ડ્રાફ્ટ ખુલ્યો. WhatsApp માં Send દબાવીને પાછા આવી આગળનો ડ્રાફ્ટ ખોલો.'),
        duration: const Duration(seconds: 5),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  Future<void> _editMessage(_AttendanceMessageRecipient recipient) async {
    final controller = TextEditingController(text: recipient.message);
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('સંદેશ સંપાદિત કરો • ${recipient.name}'),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'WhatsApp સંદેશ'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('રદ કરો')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('સંદેશ સાચવો')),
        ],
      ),
    );
    controller.dispose();
    if (edited != null && mounted) {
      setState(() => recipient.message = edited);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_classes.isEmpty) {
      return Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.school_outlined, size: 44),
          const SizedBox(height: 10),
          const Text('આ login માટે કોઈ સક્રિય/ફાળવેલ વર્ગ ઉપલબ્ધ નથી.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _loadInitial, icon: const Icon(Icons.refresh), label: const Text('ફરી પ્રયાસ કરો')),
        ]),
      ));
    }

    final queue = _withMobile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('વાલીઓને સમયગાળાવાર હાજરી સંદેશ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('પસંદ કરેલા સમયગાળામાં શિક્ષકે નોંધેલી હાજરીમાંથી દરેક વિદ્યાર્થીની હાજરી અને ટકાવારી કાઢીને ગુજરાતી WhatsApp સંદેશ તૈયાર કરો.'),
        const SizedBox(height: 10),
        SchoolNameLanguageSelector(
          schoolRef: _schoolRef,
          label: 'School name in WhatsApp messages / સંદેશમાં શાળાનું નામ',
          onChanged: (language) {
            setState(() {
              _schoolNameLanguage = language;
              for (var i = 0; i < _recipients.length; i++) {
                _recipients[i].message = _buildMessage(_recipients[i], i, _recipients.length);
              }
            });
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _classId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'વર્ગ પસંદ કરો', border: OutlineInputBorder()),
          items: _classes.map((row) => DropdownMenuItem<String>(
            value: '${row['id']}',
            child: Text('${row['label'] ?? row['class_key'] ?? ''} • ${SchoolClassOrder.labelFor(SchoolClassOrder.groupOf(row))}', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: _calculating ? null : (value) => setState(() {
            _classId = value;
            _recipients = <_AttendanceMessageRecipient>[];
            _nextQueueIndex = 0;
            _error = null;
          }),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DateSelector(label: 'તારીખથી', value: _dateLabel(_fromDate), onTap: _calculating ? null : () => _pickDate(isFrom: true)),
            _DateSelector(label: 'તારીખ સુધી', value: _dateLabel(_toDate), onTap: _calculating ? null : () => _pickDate(isFrom: false)),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _calculating ? null : _prepareMessages,
          icon: _calculating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.calculate_outlined),
          label: Text(_calculating ? 'હાજરીની ગણતરી થાય છે…' : 'હાજરી ગણો અને સંદેશ તૈયાર કરો'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Material(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10), child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
          )),
        ],
        if (_recipients.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('શાળા: $_schoolName • ધોરણ: ${ClassLabel.bare(_classLabel)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _StatChip(label: 'નોંધાયેલા કાર્યદિવસ', value: '$_recordedWorkingDays'),
                _StatChip(label: 'વિદ્યાર્થીવાર દિવસો', value: '$_studentLevelDays'),
                _StatChip(label: 'સંદેશ તૈયાર', value: '${_recipients.length}'),
                _StatChip(label: 'મોબાઇલ ઉપલબ્ધ', value: '${queue.length}'),
              ]),
              if (_studentLevelDays < _recordedWorkingDays) ...[
                const SizedBox(height: 10),
                const Text('નોંધ: Direct Entry દિવસો શાળાના નોંધાયેલા કાર્યદિવસમાં ગણાય છે, પરંતુ વ્યક્તિગત વિદ્યાર્થીની ટકાવારીમાં નહીં, કારણ કે તે દિવસ માટે બાળકવાર હાજરી નથી.', style: TextStyle(fontSize: 12)),
              ],
            ]),
          )),
          const SizedBox(height: 8),
          if (!widget.readOnly)
            FilledButton.icon(
              onPressed: queue.isEmpty ? null : _openNextWhatsAppDraft,
              icon: const Icon(Icons.forum_outlined),
              label: Text(_nextQueueIndex >= queue.length
                  ? 'બધા ડ્રાફ્ટ ખોલાઈ ગયા (${queue.length})'
                  : 'WhatsApp આગળનો સંદેશ ખોલો (${_nextQueueIndex + 1}/${queue.length})'),
            ),
          if (widget.readOnly)
            const Text('શાળા read-only/blocked હોવાથી અહીંથી WhatsApp સંદેશ મોકલવાના ડ્રાફ્ટ ખોલવા બંધ છે.'),
          const SizedBox(height: 8),
          const Text('દરેક વિદ્યાર્થી માટેનો સંદેશ નીચે જોઈ/સંપાદિત કરી શકાય છે. WhatsApp સામાન્ય રીતે દરેક વાલીનો ડ્રાફ્ટ અલગ ખોલે છે; દરેક ચેટમાં Send દબાવ્યા પછી એપમાં પાછા આવી આગળનો ડ્રાફ્ટ ખોલો.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          for (var i = 0; i < _recipients.length; i++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(child: Text('${_recipients[i].rank ?? i + 1}')),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_recipients[i].name} • રોલ ${_recipients[i].roll.isEmpty ? '-' : _recipients[i].roll}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('હાજર ${_recipients[i].presentDays}/${_recipients[i].trackedDays} • ${_recipients[i].percentage.toStringAsFixed(1)}% • ${_recipients[i].phone.isEmpty ? 'મોબાઇલ નંબર ઉપલબ્ધ નથી' : _recipients[i].phone}'),
                    ])),
                  ]),
                  const SizedBox(height: 8),
                  Text(_recipients[i].message, maxLines: 5, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: [
                    OutlinedButton.icon(onPressed: widget.readOnly ? null : () => _editMessage(_recipients[i]), icon: const Icon(Icons.edit_outlined), label: const Text('સંદેશ સંપાદિત કરો')),
                    if (_recipients[i].phone.isNotEmpty && !widget.readOnly)
                      TextButton.icon(onPressed: () async {
                        // Keep queue order predictable: individual opens use the
                        // same next-draft routine only for the next queue item.
                        final next = _withMobile.indexWhere((item) => item.id == _recipients[i].id);
                        if (next >= 0) {
                          final recipient = _withMobile[next];
                          final uri = Uri.https('wa.me', '/${recipient.phone}', <String, String>{'text': recipient.message});
                          final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
                          if (opened && mounted) {
                            setState(() {
                              if (next == _nextQueueIndex) _nextQueueIndex++;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${recipient.name} નો WhatsApp ડ્રાફ્ટ ખોલાયો. Send દબાવવું જરૂરી છે.')));
                          }
                        }
                      }, icon: const Icon(Icons.open_in_new), label: const Text('ખોલો')),
                  ])),
                ]),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _AttendanceMessageRecipient {
  _AttendanceMessageRecipient({
    required this.id,
    required this.name,
    required this.roll,
    required this.phone,
    required this.presentDays,
    required this.trackedDays,
    required this.percentage,
  });

  final String id;
  final String name;
  final String roll;
  final String phone;
  final int presentDays;
  final int trackedDays;
  final double percentage;
  int? rank;
  String message = '';
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );
}
