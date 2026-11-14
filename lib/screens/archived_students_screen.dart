import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/school_class_order.dart';
import '../services/supabase_class_service.dart';

/// Whole-school and per-class Active / Deactive student management & recovery tool.
/// Admin-only restore: always asks Admin which class to restore/activate the student into.
class ArchivedStudentsScreen extends StatefulWidget {
  const ArchivedStudentsScreen({
    super.key,
    required this.schoolRef,
    required this.classId,
    required this.classLabel,
    this.readOnly = false,
  });

  final String schoolRef;
  final String classId;
  final String classLabel;
  final bool readOnly;

  @override
  State<ArchivedStudentsScreen> createState() => _ArchivedStudentsScreenState();
}

class _ArchivedStudentsScreenState extends State<ArchivedStudentsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _deactiveRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _activeRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  Map<String, String> _classLabelsById = <String, String>{};
  late String _selectedClassId;
  String _statusMode = 'deactive'; // 'deactive' or 'active'
  String _search = '';
  bool _loading = true;
  bool _isAdmin = false;
  String? _error;

  String _text(dynamic value) => (value ?? '').toString().trim();

  bool get _canAdminEdit => _isAdmin && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    _selectedClassId =
        widget.classId.trim().isEmpty ? '__ALL__' : widget.classId.trim();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final isAdmin = await SupabaseClassService().getCurrentUserIsAdmin();
      final classRows = await _client
          .from('school_classes')
          .select('id,label,class_key,sort_order,is_active')
          .eq('school_ref', widget.schoolRef)
          .eq('is_active', true)
          .order('sort_order');
      final sortedClasses = SchoolClassOrder.sorted(
        classRows.map((r) => Map<String, dynamic>.from(r)),
      );
      final labels = <String, String>{
        for (final c in sortedClasses)
          '${c['id']}': '${c['label'] ?? c['class_key'] ?? ''}',
      };

      final allRows = await _client
          .from('students')
          .select('*')
          .eq('school_ref', widget.schoolRef);

      final deactive = <Map<String, dynamic>>[];
      final active = <Map<String, dynamic>>[];
      for (final raw in allRows) {
        final row = Map<String, dynamic>.from(raw);
        final cid = _text(row['class_id']);
        if (_selectedClassId != '__ALL__' &&
            _selectedClassId.isNotEmpty &&
            cid != _selectedClassId) {
          continue;
        }
        final isInactive = row['is_active'] != true ||
            _text(row['leaving_date']).isNotEmpty ||
            _text(row['exit_date']).isNotEmpty;
        if (isInactive) {
          deactive.add(row);
        } else {
          active.add(row);
        }
      }

      int compareStudents(Map<String, dynamic> a, Map<String, dynamic> b) {
        final ca = _text(a['class_id']).compareTo(_text(b['class_id']));
        if (ca != 0) return ca;
        final ar = int.tryParse(
          _text(a['previous_roll_number']).isNotEmpty
              ? _text(a['previous_roll_number'])
              : _text(a['roll_number']),
        );
        final br = int.tryParse(
          _text(b['previous_roll_number']).isNotEmpty
              ? _text(b['previous_roll_number'])
              : _text(b['roll_number']),
        );
        if (ar != null && br != null && ar != br) return ar.compareTo(br);
        return _text(a['name']).compareTo(_text(b['name']));
      }

      deactive.sort(compareStudents);
      active.sort(compareStudents);

      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
        _classes = sortedClasses;
        _classLabelsById = labels;
        _deactiveRows = deactive;
        _activeRows = active;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _dateLabel(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _reasonLabel(dynamic value) {
    final r = _text(value).toLowerCase();
    if (r == 'promoted_graduated') return 'Promoted / Graduated (વર્ગ બઢતી)';
    if (r == 'lc') return 'LC / શાળા છોડી';
    if (r.isEmpty) return 'Deactive (નિષ્ક્રિય)';
    return r;
  }

  Future<void> _restoreSingleInSameClass(Map<String, dynamic> row) async {
    if (!_canAdminEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('માત્ર School Admin જ નિષ્ક્રિય વિદ્યાર્થીને પાછા Active કરી શકે છે.'),
        ),
      );
      return;
    }
    final targetCid = _text(row['class_id']);
    final targetLbl = _classLabelsById[targetCid] ?? widget.classLabel;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_school_ref': widget.schoolRef,
          'p_student_ids': <String>[_text(row['id'])],
          if (targetCid.isNotEmpty) 'p_target_class_id': targetCid,
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_text(row['name'])} ને તેમના મૂળ વર્ગ "$targetLbl" માં સફળતાપૂર્વક Active કરવામાં આવ્યા છે.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _restoreAllInSameClass(List<Map<String, dynamic>> visibleRows) async {
    if (!_canAdminEdit || visibleRows.isEmpty) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'બધા ${visibleRows.length} વિદ્યાર્થીઓ તેમના મૂળ વર્ગમાં જ Active કરો',
        ),
        content: Text(
          'શું તમે દર્શાવેલા બધા ${visibleRows.length} નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓને તેમના પોતાના મૂળ વર્ગ (Same Class) માં જ ફરીથી Active (સક્રિય) કરવા માંગો છો?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('રદ કરો (Cancel)'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore),
            label: Text('હા, બધા ${visibleRows.length} મૂળ વર્ગમાં Active કરો'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = visibleRows
          .map((r) => _text(r['id']))
          .where((s) => s.isNotEmpty)
          .toList();
      final res = await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_school_ref': widget.schoolRef,
          'p_student_ids': ids,
        },
      );
      final count =
          (res is Map ? res['restored_count'] : ids.length) ?? ids.length;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'સફળતાપૂર્વક $count વિદ્યાર્થીઓને તેમના મૂળ વર્ગમાં જ પાછા સક્રિય (Active) કરવામાં આવ્યા છે!',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _restoreSingle(Map<String, dynamic> row) async {
    if (!_canAdminEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('માત્ર School Admin જ નિષ્ક્રિય વિદ્યાર્થીને પાછા Active કરી શકે છે.'),
        ),
      );
      return;
    }
    if (_classes.isEmpty) return;
    String targetCid = _text(row['class_id']);
    if (!_classes.any((c) => '${c['id']}' == targetCid)) {
      targetCid = '${_classes.first['id']}';
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('વિદ્યાર્થીને સક્રિય કરો (Make Student Active)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_text(row['name'])} (GR: ${_text(row['gr']).isEmpty ? '—' : _text(row['gr'])}) ને કયા વર્ગમાં પાછા સક્રિય (Active) કરવા છે?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: targetCid,
                decoration: const InputDecoration(
                  labelText: 'વર્ગ પસંદ કરો (Select Class to Restore Into)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _classes
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: '${c['id']}',
                        child: Text('${c['label'] ?? c['class_key']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => targetCid = v);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રદ કરો (Cancel)'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('સક્રિય કરો (Make Active)'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_school_ref': widget.schoolRef,
          'p_student_ids': <String>[_text(row['id'])],
          'p_target_class_id': targetCid,
        },
      );
      await _load();
      if (mounted) {
        final targetLbl = _classLabelsById[targetCid] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_text(row['name'])} ને વર્ગ "$targetLbl" માં સફળતાપૂર્વક સક્રિય (Active) કરવામાં આવ્યા છે.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _deactivateSingle(Map<String, dynamic> row) async {
    if (!_canAdminEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('માત્ર School Admin જ વિદ્યાર્થીને Deactive કરી શકે છે.'),
        ),
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('વિદ્યાર્થીને નિષ્ક્રિય કરો (Make Student Deactive)'),
        content: Text(
          'શું તમે "${_text(row['name'])}" (GR: ${_text(row['gr']).isEmpty ? '—' : _text(row['gr'])}) ને નિષ્ક્રિય (Deactive) કરવા માંગો છો? (તેમનો ડેટા ડિલીટ નહીં થાય અને Admin ગમે ત્યારે પાછા Active કરી શકશે.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('રદ કરો (Cancel)'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.person_off_outlined),
            label: const Text('નિષ્ક્રિય કરો (Make Deactive)'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final targetId = _text(row['id']);
      if (targetId.isEmpty) {
        throw StateError('Student ID is missing.');
      }
      await _client.rpc(
        'psm_archive_student_and_shift_rolls',
        params: <String, dynamic>{
          'p_student_id': targetId,
          'p_exit_reason': 'deactive',
        },
      );
      FirestoreQueryBuilder.invalidateCache('students');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_text(row['name'])} ને નિષ્ક્રિય (Deactive) કરવામાં આવ્યા છે.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _restoreAllVisible(List<Map<String, dynamic>> visibleRows) async {
    if (!_canAdminEdit || visibleRows.isEmpty || _classes.isEmpty) return;
    String targetCid = (_selectedClassId != '__ALL__' &&
            _classes.any((c) => '${c['id']}' == _selectedClassId))
        ? _selectedClassId
        : '${_classes.first['id']}';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'બધા ${visibleRows.length} વિદ્યાર્થીઓ સક્રિય કરો (Make All Active)',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'દર્શાવેલા બધા ${visibleRows.length} નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓને કયા વર્ગમાં પાછા સક્રિય (Active) કરવા છે?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: targetCid,
                decoration: const InputDecoration(
                  labelText: 'વર્ગ પસંદ કરો (Select Target Class)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<String>>[
                  ..._classes.map(
                    (c) => DropdownMenuItem<String>(
                      value: '${c['id']}',
                      child: Text('${c['label'] ?? c['class_key']}'),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: '__ORIGINAL__',
                    child: Text('તેમના અગાઉના મૂળ વર્ગમાં જ (Original Class)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => targetCid = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_circle_outline),
              label: Text('બધા ${visibleRows.length} સક્રિય કરો (Active)'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = visibleRows
          .map((r) => _text(r['id']))
          .where((s) => s.isNotEmpty)
          .toList();
      final res = await _client.rpc(
        'psm_restore_disappeared_or_archived_students',
        params: <String, dynamic>{
          'p_school_ref': widget.schoolRef,
          'p_student_ids': ids,
          if (targetCid != '__ORIGINAL__') 'p_target_class_id': targetCid,
        },
      );
      final count =
          (res is Map ? res['restored_count'] : ids.length) ?? ids.length;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'સફળતાપૂર્વક $count વિદ્યાર્થીઓને પાછા સક્રિય (Active) કરવામાં આવ્યા છે!',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _openMoveMisroutedStudentsDialog() async {
    if (!_canAdminEdit || _classes.length < 2) return;
    String fromClassId = '${_classes.first['id']}';
    String toClassId = '${_classes.first['id']}';
    for (final c in _classes) {
      final lbl = '${c['label'] ?? c['class_key'] ?? ''}'.toLowerCase();
      if (lbl.contains('1') || lbl.contains('૧')) {
        fromClassId = '${c['id']}';
      }
      if (lbl.contains('બાલ') || lbl.contains('bal')) {
        toClassId = '${c['id']}';
      }
    }
    bool onlyOtherCategory = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('એક વર્ગમાંથી બીજા વર્ગમાં વિદ્યાર્થીઓ ખસેડો (Move Class)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'જો અપલોડ વખતે Sheet1 ના કારણે બાલવાટિકાના વિદ્યાર્થીઓ ધોરણ - 1 માં જતા રહ્યા હોય, તો અહીંથી તેમને સીધા બાલવાટિકામાં ખસેડી શકો છો:',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: fromClassId,
                decoration: const InputDecoration(
                  labelText: 'કયા વર્ગમાંથી ખસેડવા છે? (From Class)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _classes
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: '${c['id']}',
                        child: Text('${c['label'] ?? c['class_key']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => fromClassId = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: toClassId,
                decoration: const InputDecoration(
                  labelText: 'કયા વર્ગમાં લઈ જવા છે? (To Class)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _classes
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: '${c['id']}',
                        child: Text('${c['label'] ?? c['class_key']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => toClassId = v);
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: onlyOtherCategory,
                onChanged: (v) =>
                    setDialogState(() => onlyOtherCategory = v == true),
                title: const Text('ફક્ત OTHER કેટેગરીના જ વિદ્યાર્થીઓ ખસેડો'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('રદ કરો'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.drive_file_move_outlined),
              label: const Text('વિદ્યાર્થીઓ ખસેડો'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || fromClassId == toClassId) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<String> targetIds = <String>[];
      if (onlyOtherCategory) {
        final rows = await _client
            .from('students')
            .select('id,category')
            .eq('school_ref', widget.schoolRef)
            .eq('class_id', fromClassId);
        targetIds = rows
            .where((r) => '${r['category'] ?? 'OTHER'}'.toUpperCase() == 'OTHER')
            .map((r) => '${r['id']}')
            .toList();
      }
      final res = await _client.rpc(
        'psm_move_students_to_class',
        params: <String, dynamic>{
          'p_school_ref': widget.schoolRef,
          'p_from_class_id': fromClassId,
          'p_to_class_id': toClassId,
          if (onlyOtherCategory) 'p_student_ids': targetIds,
        },
      );
      final moved = (res is Map ? res['moved_count'] : 0) ?? 0;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$moved વિદ્યાર્થીઓનો વર્ગ સફળતાપૂર્વક બદલાઈ ગયો છે!')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceRows = _statusMode == 'deactive' ? _deactiveRows : _activeRows;
    final visible = sourceRows.where((row) {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return <String>[
        _text(row['name']),
        _text(row['gr']),
        _text(row['roll_number']),
        _text(row['previous_roll_number']),
        _classLabelsById[_text(row['class_id'])] ?? '',
      ].any((s) => s.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Active / Deactive Students (${visible.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (_canAdminEdit && _classes.length >= 2)
            TextButton.icon(
              onPressed: _loading ? null : _openMoveMisroutedStudentsDialog,
              icon: const Icon(Icons.drive_file_move_outlined),
              label: const Text('વર્ગ બદલો (Move Class)'),
            ),
          if (_canAdminEdit && _statusMode == 'deactive' && visible.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: _loading ? null : () => _restoreAllInSameClass(visible),
              icon: const Icon(Icons.restore),
              label: Text('બધા ${visible.length} મૂળ વર્ગમાં Active કરો (Same Class)'),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              onPressed: _loading ? null : () => _restoreAllVisible(visible),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('વર્ગ પસંદ કરી બધા Active કરો'),
            ),
          ],
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loading && !_isAdmin)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: const Text(
                '🔒 માત્ર School Admin જ નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓને વર્ગ પસંદ કરીને પાછા Active કરી શકે છે.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'deactive',
                  icon: const Icon(Icons.person_off_outlined),
                  label: Text('Deactive / નિષ્ક્રિય (${_deactiveRows.length})'),
                ),
                ButtonSegment<String>(
                  value: 'active',
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('Active / સક્રિય (${_activeRows.length})'),
                ),
              ],
              selected: <String>{_statusMode},
              onSelectionChanged: (s) {
                setState(() => _statusMode = s.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedClassId == '__ALL__' ||
                            _classes.any((c) => '${c['id']}' == _selectedClassId)
                        ? _selectedClassId
                        : '__ALL__',
                    decoration: const InputDecoration(
                      labelText: 'વર્ગ ફિલ્ટર (Class Filter)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '__ALL__',
                        child: Text('સમગ્ર શાળા (All Classes)'),
                      ),
                      ..._classes.map(
                        (c) => DropdownMenuItem<String>(
                          value: '${c['id']}',
                          child: Text('${c['label'] ?? c['class_key']}'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedClassId = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'નામ, GR કે રોલ નંબર શોધો...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!),
                        ),
                      )
                    : visible.isEmpty
                        ? Center(
                            child: Text(
                              _statusMode == 'deactive'
                                  ? 'આ પસંદગીમાં કોઈ નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓ નથી.'
                                  : 'આ પસંદગીમાં કોઈ સક્રિય (Active) વિદ્યાર્થીઓ નથી.',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final row = visible[index];
                              final dobParts = <String>[
                                _text(row['dd']),
                                _text(row['mm']),
                                _text(row['yyyy']),
                              ].where((part) => part.isNotEmpty).toList();
                              final dob =
                                  dobParts.isEmpty ? '—' : dobParts.join('/');
                              final classLbl =
                                  _classLabelsById[_text(row['class_id'])] ??
                                      widget.classLabel;
                              final prevRoll =
                                  _text(row['previous_roll_number']).isNotEmpty
                                      ? _text(row['previous_roll_number'])
                                      : (_text(row['roll_number']).isNotEmpty
                                          ? _text(row['roll_number'])
                                          : '—');
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(prevRoll),
                                  ),
                                  title: Text(
                                    '${_text(row['name'])}  •  [$classLbl]',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'GR: ${_text(row['gr']).isEmpty ? '—' : _text(row['gr'])} • Category: ${_text(row['category']).isEmpty ? 'OTHER' : _text(row['category'])} • DOB: $dob\n'
                                    '${_statusMode == 'deactive' ? 'Status: Deactive • Leaving: ${_dateLabel(row['leaving_date'] ?? row['exit_date'])} • Reason: ${_reasonLabel(row['exit_reason'])}' : 'Status: Active (સક્રિય)'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: !_canAdminEdit
                                      ? const Chip(
                                          label: Text(
                                            'View Only (Teacher)',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        )
                                      : _statusMode == 'deactive'
                                          ? Wrap(
                                              spacing: 6,
                                              children: [
                                                FilledButton.icon(
                                                  onPressed: _loading
                                                      ? null
                                                      : () => _restoreSingleInSameClass(row),
                                                  icon: const Icon(
                                                    Icons.restore,
                                                    size: 17,
                                                  ),
                                                  label: const Text(
                                                    'તે જ વર્ગમાં Active',
                                                  ),
                                                ),
                                                FilledButton.tonalIcon(
                                                  onPressed: _loading
                                                      ? null
                                                      : () => _restoreSingle(row),
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 17,
                                                  ),
                                                  label: const Text(
                                                    'વર્ગ પસંદ કરો',
                                                  ),
                                                ),
                                              ],
                                            )
                                          : OutlinedButton.icon(
                                              onPressed: _loading
                                                  ? null
                                                  : () => _deactivateSingle(row),
                                              icon: const Icon(
                                                Icons.person_off_outlined,
                                              ),
                                              label: const Text('Deactive કરો'),
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
