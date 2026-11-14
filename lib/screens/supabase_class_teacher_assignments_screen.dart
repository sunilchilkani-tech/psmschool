import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Admin-managed class-to-teacher assignment. Teacher records and class lists
/// are returned by school-scoped SECURITY DEFINER RPCs; writes stay protected
/// by the existing school_classes admin RLS policy and migration trigger.
class SupabaseClassTeacherAssignmentsScreen extends StatefulWidget {
  const SupabaseClassTeacherAssignmentsScreen({super.key});

  @override
  State<SupabaseClassTeacherAssignmentsScreen> createState() =>
      _SupabaseClassTeacherAssignmentsScreenState();
}

class _SupabaseClassTeacherAssignmentsScreenState
    extends State<SupabaseClassTeacherAssignmentsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String? _schoolRef;
  bool _savingAll = false;
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  final Map<String, String> _assignments = <String, String>{};

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    dynamic current = value;
    if (current is Map) {
      for (final key in const ['classes', 'teachers', 'data', 'result', 'payload']) {
        if (current[key] is List) {
          current = current[key];
          break;
        }
      }
    }
    if (current is! List) return <Map<String, dynamic>>[];
    return current
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  String _classLabel(Map<String, dynamic> row) =>
      _text(row['label'], _text(row['class_key'], 'ધોરણ'));

  String _teacherName(Map<String, dynamic> row) =>
      _text(row['teacher_name'] ?? row['teacherName'], 'શિક્ષક');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final school = _text(await _client.rpc('current_school_ref'));
      if (school.isEmpty) throw StateError('સક્રિય શાળા મળી નથી. ફરી login કરો.');
      final classRows = _rows(await _client.rpc('current_school_class_roster'));
      final teacherRows = _rows(await _client.rpc('current_school_teacher_roster'));
      final activeClasses = classRows.where((row) =>
          _text(row['is_active'], 'true').toLowerCase() != 'false').toList();
      final teacherIds = teacherRows.map((row) => _text(row['id'])).toSet();
      if (!mounted) return;
      setState(() {
        _schoolRef = school;
        _classes = activeClasses;
        _teachers = teacherRows.where((row) => _text(row['id']).isNotEmpty).toList();
        _assignments
          ..clear()
          ..addEntries(activeClasses.map((row) {
            final id = _text(row['id']);
            final current = _text(row['class_teacher_id']);
            return MapEntry(id, current.isNotEmpty && teacherIds.contains(current) ? current : '');
          }));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', ''); _loading = false; });
    }
  }

  Future<void> _saveAll() async {
    final school = _schoolRef;
    if (school == null || _classes.isEmpty || _savingAll) return;
    setState(() { _savingAll = true; _error = null; });
    var savedCount = 0;
    try {
      // One user action saves every displayed active class assignment. The
      // existing school RLS and class-teacher trigger validate every row.
      for (final row in _classes) {
        final classId = _text(row['id']);
        if (classId.isEmpty) continue;
        final teacherId = _assignments[classId] ?? '';
        final updatedRows = await _client.from('school_classes').update(<String, dynamic>{
          'class_teacher_id': teacherId.isEmpty ? null : teacherId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('school_ref', school).eq('id', classId).select('id');
        if (updatedRows.isEmpty) {
          throw StateError('No class row was updated for ${_text(row['label'], classId)}. Check Admin permissions and try again.');
        }
        savedCount++;
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('બધી વર્ગ શિક્ષક ફાળવણી સાચવાઈ. ($savedCount વર્ગો)'),
        ));
      }
    } catch (error) {
      final message = savedCount == 0
          ? 'ફાળવણી સાચવી શકાઈ નથી: $error'
          : '$savedCount વર્ગોની ફાળવણી સાચવાઈ; પછીની ફાળવણી નિષ્ફળ ગઈ. ફરી તપાસો અને ફરી સાચવો. વિગતો: $error';
      if (mounted) {
        setState(() => _error = message.replaceFirst('Exception: ', ''));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_error!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  Widget _withGujaratiFont(Widget child) {
    final baseTheme = Theme.of(context);
    const family = 'NotoSansGujaratiLocal';
    return Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: family),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(fontFamily: family),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          labelStyle: baseTheme.inputDecorationTheme.labelStyle?.copyWith(fontFamily: family),
          hintStyle: baseTheme.inputDecorationTheme.hintStyle?.copyWith(fontFamily: family),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _withGujaratiFont(Scaffold(appBar: AppBar(title: const Text('વર્ગ શિક્ષક ફાળવણી')), body: const Center(child: CircularProgressIndicator())));
    return _withGujaratiFont(Scaffold(
      appBar: AppBar(
        title: const Text('વર્ગ શિક્ષક ફાળવણી'),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _savingAll || _classes.isEmpty ? null : _saveAll,
            icon: _savingAll
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_savingAll ? 'બધી ફાળવણી સાચવી રહ્યા છીએ...' : 'બધી વર્ગ શિક્ષક ફાળવણી એક સાથે સાચવો'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('શાળામાં બનાવેલા દરેક ધોરણ માટે શિક્ષકનું ખાતું પસંદ કરો. આ ફાળવણી રજા અરજીમાં ચાર્જ શિક્ષકનું ધોરણ આપમેળે બતાવવા માટે વપરાશે.'),
          const SizedBox(height: 12),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          if (_classes.isEmpty) const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('કોઈ સક્રિય ધોરણ મળ્યું નથી. પહેલાં Admin Centre માં ધોરણ બનાવો.'),
          )),
          for (final row in _classes)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_classLabel(row), style: Theme.of(context).textTheme.titleMedium),
                    if (_text(row['class_key']).isNotEmpty) Text('Class key: ${row['class_key']}'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: (_assignments[_text(row['id'])] ?? '').isEmpty ? null : _assignments[_text(row['id'])],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'વર્ગ શિક્ષકનું નામ', border: OutlineInputBorder()),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(value: '', child: Text('— વર્ગ શિક્ષક પસંદ કરો —')),
                        ..._teachers.map((teacher) => DropdownMenuItem<String>(
                          value: _text(teacher['id']),
                          child: Text(_teacherName(teacher), overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: _savingAll ? null : (value) {
                        setState(() => _assignments[_text(row['id'])] = value ?? '');
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ));
  }
}
