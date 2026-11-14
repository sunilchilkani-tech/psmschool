import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/admin_school_management_service.dart';

/// School-scoped administrator tools. Teacher creation/password changes run server-side.
class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});
  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final _service = AdminSchoolManagementService();
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final schoolRef = await client.rpc('current_school_ref');
      if (schoolRef == null)
        throw StateError('No active school is linked to this session.');
      final classRows = await client
          .from('school_classes')
          .select()
          .eq('school_ref', '$schoolRef')
          .order('sort_order');
      final teacherRows = await client
          .from('school_teachers')
          .select('id,teacher_name,role,allowed_classes,is_active,auth_user_id')
          .eq('school_ref', '$schoolRef')
          .order('teacher_name');
      if (!mounted) return;
      setState(() {
        _classes = classRows
            .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
            .toList();
        _teachers = teacherRows
            .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
            .toList();
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

  Future<void> _createClass() async {
    final key = TextEditingController();
    final label = TextEditingController();
    final standard = TextEditingController();
    final section = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add class'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: key,
                  decoration: const InputDecoration(
                    labelText: 'Class key (unique)',
                  ),
                ),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Display label'),
                ),
                TextField(
                  controller: standard,
                  decoration: const InputDecoration(
                    labelText: 'Standard (optional)',
                  ),
                ),
                TextField(
                  controller: section,
                  decoration: const InputDecoration(
                    labelText: 'Section (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (key.text.trim().isEmpty || label.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Class key and label are required.'),
                  ),
                );
                return;
              }
              try {
                await _service.createClass(
                  classKey: key.text,
                  label: label.text,
                  standard: standard.text,
                  section: section.text,
                  sortOrder: _classes.length + 1,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted)
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    key.dispose();
    label.dispose();
    standard.dispose();
    section.dispose();
    if (saved == true && mounted) await _reload();
  }

  Future<void> _createTeacher() async {
    final name = TextEditingController();
    final password = TextEditingController();
    final selected = <String>{};
    var role = 'teacher';
    var working = false;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add teacher account'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Teacher name *',
                    ),
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'Temporary password (4 to 15 characters) *',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: 'teacher',
                        child: Text('Teacher'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('School administrator'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => role = v ?? 'teacher'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Assigned classes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final schoolClass in _classes)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${schoolClass['label'] ?? schoolClass['class_key']}',
                      ),
                      value: selected.contains('${schoolClass['id']}'),
                      onChanged: (v) => setDialogState(() {
                        if (v == true) {
                          selected.add('${schoolClass['id']}');
                        } else {
                          selected.remove('${schoolClass['id']}');
                        }
                      }),
                    ),
                  const Text(
                    'The password is sent directly to Supabase Auth; it is not stored as plain text in app data.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      if (name.text.trim().length < 2 ||
                          (password.text.length < 4 ||
                              password.text.length > 15)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a teacher name and a password of 4 to 15 characters.',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => working = true);
                      try {
                        await _service.createTeacher(
                          teacherName: name.text,
                          temporaryPassword: password.text,
                          allowedClasses: selected.toList(),
                          role: role,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() => working = false);
                        if (ctx.mounted)
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
              child: Text(working ? 'Creating…' : 'Create account'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    password.dispose();
    if (created == true && mounted) await _reload();
  }

  Future<void> _changePassword(Map<String, dynamic> teacher) async {
    final password = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change password — ${teacher['teacher_name']}'),
        content: TextField(
          controller: password,
          obscureText: true,
          maxLength: 15,
          decoration: const InputDecoration(
            labelText: 'New password (4 to 15 characters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if ((password.text.length < 4 || password.text.length > 15)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Password must be 4 to 15 characters.'),
                  ),
                );
                return;
              }
              try {
                await _service.changeTeacherPassword(
                  teacherId: '${teacher['id']}',
                  newPassword: password.text,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted)
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Update password'),
          ),
        ],
      ),
    );
    password.dispose();
    if (saved == true && mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teacher password updated.')),
      );
  }

  Future<void> _toggleActive(Map<String, dynamic> teacher) async {
    final active = teacher['is_active'] == true;
    try {
      await _service.setTeacherActive(
        teacherId: '${teacher['id']}',
        isActive: !active,
      );
      await _reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('School administration'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          )
        : RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Classes (${_classes.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createClass,
                      icon: const Icon(Icons.add),
                      label: const Text('Add class'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._classes.map(
                  (c) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.class_rounded),
                      title: Text('${c['label'] ?? ''}'),
                      subtitle: Text(
                        'Key: ${c['class_key'] ?? ''}  •  ${c['is_active'] == true ? 'Active' : 'Inactive'}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Teachers (${_teachers.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createTeacher,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add teacher'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._teachers.map(
                  (teacher) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          '${teacher['teacher_name'] ?? '?'}'.isEmpty
                              ? '?'
                              : '${teacher['teacher_name']}'
                                    .substring(0, 1)
                                    .toUpperCase(),
                        ),
                      ),
                      title: Text('${teacher['teacher_name'] ?? ''}'),
                      subtitle: Text(
                        '${teacher['role']} • ${teacher['is_active'] == true ? 'Active' : 'Inactive'}\nAssigned: ${(teacher['allowed_classes'] as List? ?? const []).length} class(es)',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'password') _changePassword(teacher);
                          if (v == 'active') _toggleActive(teacher);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'password',
                            child: Text('Change password'),
                          ),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                              teacher['is_active'] == true
                                  ? 'Deactivate'
                                  : 'Activate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
  );
}
