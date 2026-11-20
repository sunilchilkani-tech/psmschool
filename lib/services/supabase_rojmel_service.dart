import 'dart:convert';

import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// School-scoped cloud persistence for the Rojmel ledger.
/// No service-role credentials are ever shipped to Flutter.
class SupabaseRojmelService {
  SupabaseRojmelService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _text(dynamic value) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty || result.toLowerCase() == 'null' ? '' : result;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.map((key, value) => MapEntry(key.toString(), value));
      } catch (_) {
        // Let the caller show the consistent schema/data error.
      }
    }
    return <String, dynamic>{};
  }

  Future<String> currentSchoolRef() async {
    if (_client.auth.currentUser == null) {
      throw StateError('કૃપા કરીને School Admin તરીકે ફરી લૉગિન કરો.');
    }
    final value = _text(await _client.rpc('current_school_ref'));
    if (value.isEmpty) throw StateError('આ લૉગિન સાથે સક્રિય શાળા જોડાયેલ નથી.');
    return value;
  }

  Future<bool> isSchoolAdmin() async {
    final value = await _client.rpc('is_school_admin');
    if (value is bool) return value;
    return const <String>{'true', 't', '1'}.contains(_text(value).toLowerCase());
  }

  Future<Map<String, dynamic>> loadSchoolContext() async =>
      _map(await _client.rpc('psm_library_school_context'));

  Future<Map<String, dynamic>?> loadState(String schoolRef) async {
    final row = await _client
        .from('school_rojmel_state')
        .select('state,updated_at')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (row == null) return null;
    final state = _map(row['state']);
    if (state.isEmpty) throw StateError('Saved Rojmel cloud data is empty or invalid.');
    return state;
  }

  Future<void> saveState({
    required String schoolRef,
    required Map<String, dynamic> state,
  }) async {
    if (state.isEmpty) throw ArgumentError('Rojmel state payload cannot be empty.');
    // Database RLS and a write trigger independently validate the school and Admin role.
    await _client.from('school_rojmel_state').upsert(<String, dynamic>{
      'school_ref': schoolRef,
      'state': state,
    }, onConflict: 'school_ref');
  }

  String _archiveSlug(String value) {
    final cleaned = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'acc_${value.hashCode.abs()}' : trimmed;
  }

  /// Stores one immutable read-only FY archive document per (school, FY, account).
  /// Never read during daily work; keeps active school_rojmel_state small.
  Future<String> saveFrozenFyArchive({
    required String schoolRef,
    required String financialYear,
    required String accountName,
    required Map<String, dynamic> archivePayload,
  }) async {
    final cleanFy = financialYear.trim();
    final cleanAcc = accountName.trim();
    final docId = '${schoolRef}__${_archiveSlug(cleanFy)}__${_archiveSlug(cleanAcc)}';
    final existing = await _client
        .from('school_rojmel_fy_archives')
        .select('id')
        .eq('id', docId)
        .maybeSingle();
    if (existing != null) {
      throw StateError('FY $cleanFy for "$cleanAcc" is already frozen in archive ($docId).');
    }
    await _client.from('school_rojmel_fy_archives').insert(<String, dynamic>{
      'id': docId,
      'school_ref': schoolRef,
      'financial_year': cleanFy,
      'account_name': cleanAcc,
      'account_type': _text(archivePayload['accountType']),
      'entry_count': archivePayload['entryCount'] ?? 0,
      'totals': archivePayload['totals'] ?? const <String, dynamic>{},
      'frozen_at': DateTime.now().toUtc().toIso8601String(),
      'snapshot': archivePayload,
    });
    return docId;
  }

  /// On-demand list of frozen FY archives for this school (0 reads until clicked).
  Future<List<Map<String, dynamic>>> listFrozenFyArchives(String schoolRef) async {
    final rows = await _client
        .from('school_rojmel_fy_archives')
        .select('id,school_ref,financial_year,account_name,account_type,entry_count,totals,frozen_at')
        .eq('school_ref', schoolRef)
        .order('frozen_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// On-demand fetch of one immutable FY archive snapshot.
  Future<Map<String, dynamic>?> loadFrozenFyArchive(String archiveId) async {
    final row = await _client
        .from('school_rojmel_fy_archives')
        .select('*')
        .eq('id', archiveId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }
}
