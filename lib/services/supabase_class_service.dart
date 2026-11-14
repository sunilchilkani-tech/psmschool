import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Reads only classes permitted by the logged-in teacher's RLS policy / allotted classes.
class SupabaseClassService {
  SupabaseClassService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listAccessibleClasses() async {
    final rows = await _client
        .from('school_classes')
        .select(
          'id,school_ref,class_key,label,sheet_name,standard,section,report_group,sort_order,is_active',
        )
        .eq('is_active', true)
        .order('sort_order');
    var list =
        rows.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
    try {
      final allowedIds = await _client.rpc('psm_attendance_class_ids');
      if (allowedIds is List) {
        final set = allowedIds.map((e) => '${e ?? ''}'.trim()).toSet();
        list = list.where((c) => set.contains('${c['id'] ?? ''}'.trim())).toList();
      }
    } catch (_) {}
    return list;
  }

  Future<String> resolveClassId(String classNameOrKey) async {
    final target = _clean(classNameOrKey);
    final rows = await listAccessibleClasses();
    for (final row in rows) {
      if ([row['class_key'], row['label'], row['sheet_name']]
          .whereType<String>()
          .any((candidate) => _clean(candidate) == target)) {
        return '${row['id']}';
      }
    }
    throw StateError('Class "$classNameOrKey" is not available to this teacher.');
  }

  Future<Map<String, dynamic>> getCurrentSchool() async {
    final schoolRef = await _client.rpc('current_school_ref');
    if (schoolRef == null) {
      throw StateError('No active school is linked to this login.');
    }
    final row =
        await _client.from('schools').select().eq('id', '$schoolRef').single();
    return Map<String, dynamic>.from(row);
  }

  Future<bool> getCurrentUserIsAdmin() async {
    final value = await _client.rpc('is_school_admin');
    return value == true;
  }

  String _clean(String value) => value
      .replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '');
}
