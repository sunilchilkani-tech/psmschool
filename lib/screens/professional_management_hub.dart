import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/device_preferences_service.dart';
import '../services/supabase_class_service.dart';
import '../widgets/school_export_button.dart';
import '../widgets/global_student_search_card.dart';
import 'admin_workflow_panel.dart';
import 'archived_students_screen.dart';
import 'student_bulk_import_screen.dart';
import 'student_management_screen.dart';
import '../services/school_type.dart';

/// Self-contained entry point for Supabase professional student & school tools.
class ProfessionalManagementHub extends StatefulWidget {
  const ProfessionalManagementHub({super.key});
  @override
  State<ProfessionalManagementHub> createState() =>
      _ProfessionalManagementHubState();
}

class _ProfessionalManagementHubState extends State<ProfessionalManagementHub> {
  final _classesService = SupabaseClassService();
  final _devicePreferences = DevicePreferencesService();
  List<Map<String, dynamic>> _classes = [];
  String? _classId;
  String? _schoolRef;
  String _schoolType = 'coed';
  bool _isAdmin = false;
  int _archivedCount = 0;
  bool _loading = true;
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
      final results = await Future.wait([
        _classesService.listAccessibleClasses(),
        _classesService.getCurrentSchool(),
        _classesService.getCurrentUserIsAdmin(),
        _devicePreferences.loadLastClass(),
      ]);
      final classes = results[0] as List<Map<String, dynamic>>;
      final school = results[1] as Map<String, dynamic>;
      final admin = results[2] as bool;
      final last = results[3] as String?;
      final schoolRef = '${school['id'] ?? ''}'.trim();

      var archivedCount = 0;
      if (schoolRef.isNotEmpty) {
        final studentRows = await Supabase.instance.client
            .from('students')
            .select('id,is_active,leaving_date,exit_date')
            .eq('school_ref', schoolRef);
        for (final r in studentRows) {
          final isAct = r['is_active'] == true &&
              '${r['leaving_date'] ?? ''}'.trim().isEmpty &&
              '${r['exit_date'] ?? ''}'.trim().isEmpty;
          if (!isAct) archivedCount++;
        }
      }

      final current = classes.cast<Map<String, dynamic>?>().firstWhere(
            (c) =>
                c != null &&
                ('${c['id']}' == last || '${c['class_key']}' == last),
            orElse: () => null,
          );
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _schoolRef = schoolRef;
        _classId = admin
            ? '__ALL__'
            : (last == '__ALL__'
                ? '__ALL__'
                : (current?['id']?.toString() ??
                    (classes.isEmpty ? '__ALL__' : '${classes.first['id']}')));
        _schoolType = SchoolType.coedCompat(school['school_type']);
        _isAdmin = admin;
        _archivedCount = archivedCount;
        _loading = false;
      });
      if (_classId != null) await _devicePreferences.saveLastClass(_classId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedClass {
    if (_classId == '__ALL__') {
      return <String, dynamic>{
        'id': '',
        'label': 'સમગ્ર શાળા (All Classes / Whole School)',
      };
    }
    for (final row in _classes) {
      if ('${row['id']}' == _classId) return row;
    }
    return null;
  }

  Future<void> _openStudents({required bool bulk}) async {
    final row = _selectedClass;
    final cid = row == null ? '' : '${row['id'] ?? ''}';
    final lbl = row == null
        ? 'સમગ્ર શાળા (All Classes / Whole School)'
        : '${row['label'] ?? row['class_key'] ?? 'સમગ્ર શાળા'}';
    final route = MaterialPageRoute<void>(
      builder: (_) => bulk
          ? StudentBulkImportScreen(
              classId: cid,
              classLabel: lbl,
              schoolType: _schoolType,
            )
          : StudentManagementScreen(
              classId: cid,
              classLabel: lbl,
              schoolType: _schoolType,
              isAdmin: _isAdmin,
            ),
    );
    await Navigator.push(context, route);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedClass;
    return Scaffold(
      appBar: AppBar(title: const Text('Professional management')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  GlobalStudentSearchCard(
                    onDataChanged: _load,
                  ),
                  if (_isAdmin && _archivedCount > 0 && _schoolRef != null)
                    Card(
                      color: Colors.amber.shade50,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          child: const Icon(Icons.settings_backup_restore),
                        ),
                        title: Text(
                          '$_archivedCount વિદ્યાર્થીઓ Deactive (નિષ્ક્રિય) સ્થિતિમાં છે (Active / Deactive)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'Admin Only: અહીં ક્લિક કરીને નિષ્ક્રિય (Deactive) વિદ્યાર્થીઓને વર્ગ પસંદ કરી પાછા સક્રિય (Active) કરો.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ArchivedStudentsScreen(
                                schoolRef: _schoolRef!,
                                classId: '',
                                classLabel:
                                    'સમગ્ર શાળા (All Classes / Whole School)',
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAdmin
                                ? 'School administrator tools'
                                : 'Teacher tools',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'School type: $_schoolType  •  ${_classes.length} accessible class(es)',
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _classId == '__ALL__' ||
                                    _classes.any((c) => '${c['id']}' == _classId)
                                ? _classId
                                : '__ALL__',
                            decoration: const InputDecoration(
                              labelText:
                                  'Select class or Whole School (વર્ગ / સમગ્ર શાળા પસંદ કરો)',
                              border: OutlineInputBorder(),
                            ),
                            items: <DropdownMenuItem<String>>[
                              const DropdownMenuItem<String>(
                                value: '__ALL__',
                                child: Text(
                                  'સમગ્ર શાળા (All Classes / Whole School)',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              ..._classes.map(
                                (c) => DropdownMenuItem(
                                  value: '${c['id']}',
                                  child: Text('${c['label'] ?? c['class_key']}'),
                                ),
                              ),
                            ],
                            onChanged: (v) async {
                              setState(() => _classId = v);
                              if (v != null) {
                                await _devicePreferences.saveLastClass(v);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _actionCard(
                    icon: Icons.people_alt_outlined,
                    title: 'Students (વિદ્યાર્થી યાદી અને સુધારા)',
                    subtitle:
                        'Add, edit, archive or restore students across the whole school or per class.',
                    onTap: selected == null
                        ? null
                        : () => _openStudents(bulk: false),
                  ),
                  _actionCard(
                    icon: Icons.upload_file_outlined,
                    title:
                        'Whole-School / Class Bulk Student Upload (સમગ્ર શાળા બલ્ક અપલોડ)',
                    subtitle:
                        'Upload full-school Excel or single-class Excel. Includes ધર્મ & RELIGION IN ENGLISH headers.',
                    onTap: selected == null
                        ? null
                        : () => _openStudents(bulk: true),
                  ),
                  if (_isAdmin && _schoolRef != null)
                    _actionCard(
                      icon: Icons.restore_from_trash_outlined,
                      title:
                          'Active / Deactive Students (${_archivedCount} Deactive વિદ્યાર્થીઓ)',
                      subtitle:
                          'Admin Only: Activate / Deactivate students (asks which class to restore into) or move students between classes.',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ArchivedStudentsScreen(
                              schoolRef: _schoolRef!,
                              classId:
                                  _classId == '__ALL__' ? '' : (_classId ?? ''),
                              classLabel:
                                  '${selected?['label'] ?? 'સમગ્ર શાળા (All Classes)'}',
                            ),
                          ),
                        );
                        if (mounted) await _load();
                      },
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Data export',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Admin exports the school workbook; a teacher exports only assigned-class data.',
                          ),
                          SizedBox(height: 12),
                          SchoolExportButton(),
                        ],
                      ),
                    ),
                  ),
                  if (_isAdmin)
                    _actionCard(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'School administration',
                      subtitle:
                          'Add classes/teachers, assign classes and change teacher passwords.',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminWorkflowPanel(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 90),
                ]),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) =>
      Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
