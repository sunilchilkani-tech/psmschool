// Native Firebase Auth + Cloud Firestore + Cloud Functions backend engine
// replacing package:supabase_flutter/supabase_flutter.dart across the app.
library firebase_backend_client;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart' as fn;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart' as fb_core;

import '../firebase_options.dart';
import 'school_type.dart';

class PostgrestException implements Exception {
  final String message;
  final String? code;
  final dynamic details;
  final String? hint;

  const PostgrestException({
    required this.message,
    this.code,
    this.details,
    this.hint,
  });

  @override
  String toString() => message;
}

class AuthException implements Exception {
  final String message;
  final String? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class FunctionException implements Exception {
  final int status;
  final dynamic details;
  final String? reasonPhrase;

  const FunctionException({
    required this.status,
    this.details,
    this.reasonPhrase,
  });

  @override
  String toString() {
    if (details is Map) {
      final msg = details['error'] ?? details['message'];
      if (msg != null && '$msg'.trim().isNotEmpty) return '$msg';
    }
    return reasonPhrase ?? 'Function error ($status)';
  }
}

class FileOptions {
  final String contentType;
  final bool upsert;

  const FileOptions({
    this.contentType = 'application/octet-stream',
    this.upsert = false,
  });
}

class User {
  final String id;
  final String? email;
  final Map<String, dynamic> appMetadata;
  final Map<String, dynamic> userMetadata;

  const User({
    required this.id,
    this.email,
    this.appMetadata = const <String, dynamic>{},
    this.userMetadata = const <String, dynamic>{},
  });
}

class Session {
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String tokenType;
  final User user;

  const Session({
    required this.accessToken,
    required this.user,
    this.refreshToken,
    this.expiresIn = 3600,
    this.tokenType = 'bearer',
  });
}

class AuthResponse {
  final Session? session;
  final User? user;

  const AuthResponse({this.session, this.user});
}

class FunctionResponse {
  final int status;
  final dynamic data;

  const FunctionResponse({required this.status, this.data});
}

class Supabase {
  Supabase._();

  static final Supabase instance = Supabase._();
  static bool _initialized = false;

  final SupabaseClient client = SupabaseClient._();

  static Future<Supabase> initialize({
    String url = '',
    String? anonKey,
    String? publishableKey,
  }) async {
    if (!_initialized) {
      try {
        if (fb_core.Firebase.apps.isEmpty) {
          await fb_core.Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
      } catch (_) {
        // Ignore if already initialized.
      }
      await instance.client.auth._init();
      _initialized = true;
    }
    return instance;
  }
}

class FirestoreAuthClient {
  FirestoreAuthClient(this._parent);

  final SupabaseClient _parent;
  String _cachedAccessToken = '';
  DateTime? _lastPasswordAuthAt;
  Map<String, dynamic> _cachedAppMetadata = <String, dynamic>{};
  Map<String, dynamic> _cachedUserMetadata = <String, dynamic>{};

  fb_auth.FirebaseAuth get _fbAuth => fb_auth.FirebaseAuth.instance;

  Future<void> _init() async {
    try {
      final fbUser = await _fbAuth.authStateChanges().first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => _fbAuth.currentUser,
      );
      if (fbUser != null) {
        await _syncFromFirebaseUser(fbUser);
      }
      _fbAuth.idTokenChanges().listen((fb_auth.User? u) async {
        if (u == null) {
          _cachedAccessToken = '';
          _cachedAppMetadata = <String, dynamic>{};
          _cachedUserMetadata = <String, dynamic>{};
          _parent._clearIdentityCache();
        } else {
          try {
            _cachedAccessToken = (await u.getIdToken()) ?? '';
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _syncFromFirebaseUser(fb_auth.User fbUser) async {
    try {
      final tokenResult = await fbUser.getIdTokenResult();
      _cachedAccessToken = tokenResult.token ?? '';
      final claims = tokenResult.claims ?? const <String, dynamic>{};
      _cachedAppMetadata = <String, dynamic>{
        ...claims,
        if (claims['psm_school_id'] != null)
          'psm_school_id': claims['psm_school_id'],
        if (claims['psm_teacher_id'] != null)
          'psm_teacher_id': claims['psm_teacher_id'],
        if (claims['psm_school_ref'] != null)
          'psm_school_ref': claims['psm_school_ref'],
        if (claims['psm_role'] != null) 'psm_role': claims['psm_role'],
      };
      _cachedUserMetadata = <String, dynamic>{
        'display_name': fbUser.displayName ?? '',
        'email': fbUser.email ?? '',
      };
      if (tokenResult.authTime != null) {
        _lastPasswordAuthAt ??= tokenResult.authTime;
      }
    } catch (_) {
      try {
        _cachedAccessToken = (await fbUser.getIdToken()) ?? '';
      } catch (_) {}
    }
  }

  User? get currentUser {
    final imp = _parent._developerImpersonatedContext;
    if (imp != null) {
      return User(
        id: imp.authUserId,
        email: 'developer@${imp.schoolRef}.psmschool.local',
        appMetadata: <String, dynamic>{
          'psm_school_id': '${imp.schoolRow['school_id'] ?? ''}',
          'psm_teacher_id': imp.teacherId,
          'psm_school_ref': imp.schoolRef,
          'psm_role': imp.role,
          'psm_developer_impersonation': true,
        },
        userMetadata: <String, dynamic>{
          'display_name': imp.teacherName,
          'email': 'developer@${imp.schoolRef}.psmschool.local',
        },
      );
    }
    final fbUser = _fbAuth.currentUser;
    if (fbUser == null) return null;
    return User(
      id: fbUser.uid,
      email: fbUser.email,
      appMetadata: _cachedAppMetadata,
      userMetadata: _cachedUserMetadata,
    );
  }

  Session? get currentSession {
    final user = currentUser;
    if (user == null) return null;
    return Session(
      accessToken: _cachedAccessToken.isNotEmpty
          ? _cachedAccessToken
          : 'firebase_${user.id}',
      refreshToken: user.id,
      user: user,
    );
  }

  bool get hasRecentPasswordAuth {
    if (_parent._developerImpersonatedContext != null) return true;
    final last = _lastPasswordAuthAt;
    if (last == null) {
      final authTime = _fbAuth.currentUser?.metadata.lastSignInTime;
      if (authTime == null) return false;
      return DateTime.now().difference(authTime).inMinutes <= 10;
    }
    return DateTime.now().difference(last).inMinutes <= 10;
  }

  void markPasswordVerifiedNow() {
    _lastPasswordAuthAt = DateTime.now();
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      fb_auth.UserCredential cred;
      final normalizedPwd = SupabaseClient._toFirebasePassword(password);
      try {
        cred = await _fbAuth.signInWithEmailAndPassword(
          email: email.trim(),
          password: normalizedPwd,
        );
      } on fb_auth.FirebaseAuthException {
        if (normalizedPwd != password) {
          cred = await _fbAuth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
        } else {
          rethrow;
        }
      }
      final fbUser = cred.user;
      if (fbUser == null) {
        throw const AuthException('Invalid login credentials.');
      }
      _lastPasswordAuthAt = DateTime.now();
      _parent._clearIdentityCache();
      await _syncFromFirebaseUser(fbUser);
      await _parent._resolveCurrentTeacherContext(forceRefresh: true);
      return AuthResponse(user: currentUser, session: currentSession);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(
        e.message ?? 'Invalid login credentials.',
        statusCode: e.code,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('$e');
    }
  }

  Future<AuthResponse> setSession(String refreshToken) async {
    try {
      if (refreshToken.startsWith('CUSTOM_TOKEN:')) {
        final customToken = refreshToken.substring('CUSTOM_TOKEN:'.length);
        final cred = await _fbAuth.signInWithCustomToken(customToken);
        if (cred.user != null) {
          await _syncFromFirebaseUser(cred.user!);
        }
      } else if (_fbAuth.currentUser != null) {
        _cachedAccessToken =
            (await _fbAuth.currentUser!.getIdToken(true)) ?? refreshToken;
        await _syncFromFirebaseUser(_fbAuth.currentUser!);
      } else {
        _cachedAccessToken = refreshToken;
      }
      _lastPasswordAuthAt = DateTime.now();
      _parent._clearIdentityCache();
      await _parent._resolveCurrentTeacherContext(forceRefresh: true);
      return AuthResponse(user: currentUser, session: currentSession);
    } catch (e) {
      throw AuthException('Could not restore Firebase session: $e');
    }
  }

  Future<void> signOut() async {
    _cachedAccessToken = '';
    _lastPasswordAuthAt = null;
    _cachedAppMetadata = <String, dynamic>{};
    _cachedUserMetadata = <String, dynamic>{};
    _parent._clearIdentityCache();
    // Never let the next school/user on this device reuse cached rows.
    FirestoreQueryBuilder.clearAllForSessionChange();
    await _fbAuth.signOut();
  }
}

class FirestoreStorageClient {
  FirestoreStorageClient(this._parent);
  final SupabaseClient _parent;

  FirestoreStorageBucket from(String bucket) =>
      FirestoreStorageBucket(_parent, bucket);
}

class FirestoreStorageBucket {
  FirestoreStorageBucket(this._parent, this.bucket);
  final SupabaseClient _parent;
  final String bucket;

  static final Map<String, String> _dataUriCache = <String, String>{};

  String _docIdForPath(String path) =>
      Uri.encodeComponent(path.trim().replaceFirst(RegExp(r'^/+'), ''));

  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions? fileOptions,
  }) async {
    if (data.length > 5 * 1024 * 1024) {
      throw const PostgrestException(message: 'File size exceeds 5 MB limit.');
    }
    final schoolRef = await _parent._requireSchoolWriteAccess();
    final isAdmin = await _parent._isCurrentUserAdmin();
    if (!isAdmin) {
      throw const PostgrestException(
        message: 'Only the School Admin can upload school assets.',
      );
    }
    final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
    final mime = fileOptions?.contentType ?? 'image/png';
    final b64 = base64Encode(data);
    final dataUri = 'data:$mime;base64,$b64';
    _dataUriCache[cleanPath] = dataUri;

    final docId = _docIdForPath(cleanPath);
    await _parent._db.collection('school_assets').doc(docId).set(
      <String, dynamic>{
        'id': docId,
        'bucket': bucket,
        'path': cleanPath,
        'school_ref': schoolRef,
        'content_type': mime,
        'base64_data': b64,
        'data_uri': dataUri,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      fs.SetOptions(merge: true),
    );

    // Also store data_uri in school_settings.logo_url for instant access
    await _parent._db.collection('school_settings').doc(schoolRef).set(
      <String, dynamic>{
        'school_ref': schoolRef,
        'logo_path': cleanPath,
        'logo_data_uri': dataUri,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      fs.SetOptions(merge: true),
    );
    FirestoreQueryBuilder.invalidateCache('school_settings');

    return cleanPath;
  }

  String getPublicUrl(String path) {
    final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
    if (cleanPath.isEmpty) return '';
    if (cleanPath.startsWith('data:') ||
        cleanPath.startsWith('http://') ||
        cleanPath.startsWith('https://')) {
      return cleanPath;
    }
    return _dataUriCache[cleanPath] ?? cleanPath;
  }

  Future<Uint8List> download(String path) async {
    final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
    if (cleanPath.startsWith('data:')) {
      final comma = cleanPath.indexOf(',');
      if (comma >= 0) {
        return base64Decode(cleanPath.substring(comma + 1));
      }
    }
    final cached = _dataUriCache[cleanPath];
    if (cached != null && cached.startsWith('data:')) {
      final comma = cached.indexOf(',');
      if (comma >= 0) {
        return base64Decode(cached.substring(comma + 1));
      }
    }
    final docId = _docIdForPath(cleanPath);
    final snap = await _parent._db.collection('school_assets').doc(docId).get();
    if (snap.exists && snap.data() != null) {
      final data = snap.data()!;
      final b64 = (data['base64_data'] ?? '').toString();
      final mime = (data['content_type'] ?? 'image/png').toString();
      if (b64.isNotEmpty) {
        _dataUriCache[cleanPath] = 'data:$mime;base64,$b64';
        return base64Decode(b64);
      }
    }
    throw const PostgrestException(message: 'Asset not found in Firestore.');
  }

  Future<void> remove(List<String> paths) async {
    for (final p in paths) {
      final cleanPath = p.trim().replaceFirst(RegExp(r'^/+'), '');
      _dataUriCache.remove(cleanPath);
      final docId = _docIdForPath(cleanPath);
      await _parent._db.collection('school_assets').doc(docId).delete();
    }
  }
}

enum _QueryOp { select, insert, update, upsert, delete }

class _OrderSpec {
  final String column;
  final bool ascending;
  const _OrderSpec(this.column, {this.ascending = true});
}

class FirestoreQueryBuilder implements Future<List<Map<String, dynamic>>> {
  FirestoreQueryBuilder(this._client, this._table);

  final SupabaseClient _client;
  final String _table;

  _QueryOp _op = _QueryOp.select;
  String _selectColumns = '*';
  bool _returningSelect = false;
  List<Map<String, dynamic>> _payloadRows = <Map<String, dynamic>>[];
  String? _onConflict;
  bool _ignoreDuplicates = false;

  final Map<String, Object?> _eqFilters = <String, Object?>{};
  final Map<String, List<Object?>> _inFilters = <String, List<Object?>>{};
  final Map<String, Object> _gteFilters = <String, Object>{};
  final Map<String, Object> _lteFilters = <String, Object>{};
  final List<_OrderSpec> _orders = <_OrderSpec>[];
  int? _rangeFrom;
  int? _rangeTo;
  int? _limitCount;

  FirestoreQueryBuilder select([String columns = '*']) {
    _selectColumns = columns;
    if (_op != _QueryOp.select) {
      _returningSelect = true;
    }
    return this;
  }

  FirestoreQueryBuilder insert(Object values) {
    _op = _QueryOp.insert;
    _payloadRows = _normalizeRows(values);
    return this;
  }

  FirestoreQueryBuilder update(Map<String, dynamic> values) {
    _op = _QueryOp.update;
    _payloadRows = <Map<String, dynamic>>[Map<String, dynamic>.from(values)];
    return this;
  }

  FirestoreQueryBuilder upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) {
    _op = _QueryOp.upsert;
    _payloadRows = _normalizeRows(values);
    _onConflict = onConflict;
    _ignoreDuplicates = ignoreDuplicates;
    return this;
  }

  FirestoreQueryBuilder delete() {
    _op = _QueryOp.delete;
    return this;
  }

  FirestoreQueryBuilder eq(String column, Object? value) {
    _eqFilters[column] = value;
    return this;
  }

  FirestoreQueryBuilder inFilter(String column, List<Object?> values) {
    _inFilters[column] = List<Object?>.from(values);
    return this;
  }

  FirestoreQueryBuilder gte(String column, Object value) {
    _gteFilters[column] = value;
    return this;
  }

  FirestoreQueryBuilder lte(String column, Object value) {
    _lteFilters[column] = value;
    return this;
  }

  FirestoreQueryBuilder order(String column, {bool ascending = true}) {
    _orders.add(_OrderSpec(column, ascending: ascending));
    return this;
  }

  FirestoreQueryBuilder range(int from, int to) {
    _rangeFrom = from;
    _rangeTo = to;
    return this;
  }

  FirestoreQueryBuilder limit(int count) {
    _limitCount = count;
    return this;
  }

  Future<Map<String, dynamic>> single() async {
    final rows = await _execute();
    if (rows.isEmpty) {
      throw const PostgrestException(
        message: 'Requested single row was not found.',
        code: 'PGRST116',
      );
    }
    return rows.first;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await _execute();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  List<Map<String, dynamic>> _normalizeRows(Object values) {
    if (values is List) {
      return values
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();
    }
    if (values is Map) {
      return <Map<String, dynamic>>[values.map((k, v) => MapEntry('$k', v))];
    }
    throw ArgumentError('Unsupported payload type for $_table');
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    switch (_op) {
      case _QueryOp.select:
        return _executeSelect();
      case _QueryOp.insert:
        return _executeInsertOrUpsert(isUpsert: false);
      case _QueryOp.upsert:
        return _executeInsertOrUpsert(isUpsert: true);
      case _QueryOp.update:
        return _executeUpdate();
      case _QueryOp.delete:
        return _executeDelete();
    }
  }

  static const Set<String> _schoolScopedTables = <String>{
    'school_classes',
    'students',
    'student_private_details',
    'attendance_days',
    'student_attendance',
    'attendance_admin_overrides',
    'school_settings',
    'school_holidays',
    'school_admin_messages',
    'school_custom_headers',
    'school_report_settings',
    'school_hajari_patrak_settings',
    'hajari_student_present_day_overrides',
    'class_subjects',
    'school_subject_catalog',
    'school_subject_master',
    'school_result_grade_settings',
    'teacher_subject_assignments',
    'class_result_settings',
    'student_result_profiles',
    'student_subject_marks',
    'student_result_roster_snapshots',
    'student_result_roster_members',
    'teacher_leaves',
    'school_leave_settings',
    'school_teacher_valtar_rules',
    'library_books',
    'library_book_number_history',
    'library_settings',
    'library_transactions',
    'school_rojmel_state',
  };

  Future<List<Map<String, dynamic>>> _executeSelect() async {
    final ctx = await _client._resolveCurrentTeacherContext();
    final eqMap = Map<String, Object?>.from(_eqFilters);
    if (_schoolScopedTables.contains(_table) &&
        !eqMap.containsKey('school_ref') &&
        ctx != null &&
        ctx.schoolRef.isNotEmpty) {
      eqMap['school_ref'] = ctx.schoolRef;
    }

    if (_table == 'student_private_details' && ctx != null && !ctx.isAdmin) {
      throw const PostgrestException(
        message: 'Only the School Admin can access private student details.',
        code: '42501',
      );
    }

    final col = _client._db.collection(_table);
    List<Map<String, dynamic>> docs = <Map<String, dynamic>>[];

    // Optimization #1: Resolve student_attendance from embedded student_marks on attendance_days
    if (_table == 'student_attendance') {
      docs = await _resolveStudentAttendanceFromDaysOrLegacy(col, eqMap);
    } else {
      // Check if we can fetch directly by document ID (with in-memory cache!)
      final directDocId = _tryResolveDirectDocId(eqMap);
      if (directDocId != null) {
        final docCacheKey = '$_table|__doc__=$directDocId';
        final now = DateTime.now();
        final cachedDoc = _queryCache[docCacheKey];
        final ttlSec = _cacheTtlSecondsForTable(_table);
        final schoolRefFilter = '${eqMap['school_ref'] ?? ''}'.trim();
        final schoolWideCached = schoolRefFilter.isNotEmpty
            ? _queryCache['$_table|school_ref=$schoolRefFilter|in=']
            : null;
        if (cachedDoc != null &&
            now.difference(cachedDoc.ts).inSeconds < ttlSec) {
          docs = cachedDoc.rows
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
        } else if (schoolWideCached != null &&
            now.difference(schoolWideCached.ts).inSeconds < ttlSec) {
          docs = schoolWideCached.rows
              .where((r) => '${r['id'] ?? ''}' == directDocId)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
        } else {
          final gen = _generationOf(_table);
          var pending = _inFlightReads[docCacheKey];
          if (pending == null) {
            pending = col.doc(directDocId).get().then((snap) {
              if (!snap.exists || snap.data() == null) {
                return <Map<String, dynamic>>[];
              }
              final row = Map<String, dynamic>.from(snap.data()!);
              row['id'] ??= snap.id;
              _applyTableSqlDefaults(_table, row);
              return <Map<String, dynamic>>[row];
            });
            _inFlightReads[docCacheKey] = pending;
            pending.whenComplete(() {
              if (identical(_inFlightReads[docCacheKey], pending)) {
                _inFlightReads.remove(docCacheKey);
              }
            }).ignore();
          }
          final fetched = await pending;
          if (fetched.isNotEmpty) {
            docs = fetched.map((r) => Map<String, dynamic>.from(r)).toList();
            if (gen == _generationOf(_table)) {
              _queryCache[docCacheKey] = (
                ts: now,
                rows: <Map<String, dynamic>>[
                  Map<String, dynamic>.from(fetched.first),
                ],
              );
            }
          } else {
            docs = await _runCollectionQuery(col, eqMap);
          }
        }
      } else {
        docs = await _runCollectionQuery(col, eqMap);
      }
    }

    // Special reassembly for chunked Rojmel state and pre-caching of school logo
    if (_table == 'school_rojmel_state' && docs.isNotEmpty) {
      for (final d in docs) {
        if (d['is_chunked'] == true) {
          final schoolRef = '${d['school_ref'] ?? d['id'] ?? ''}';
          final stamp = '${d['updated_at'] ?? ''}';
          final cc = int.tryParse('${d['chunk_count'] ?? ''}');
          if (cc != null) _rojmelChunkCounts[schoolRef] = cc;
          final cachedState = _rojmelStateCache[schoolRef];
          if (cachedState != null &&
              stamp.isNotEmpty &&
              cachedState.updatedAt == stamp) {
            d['state'] = cachedState.state;
            continue;
          }
          final chunkSnap = await col
              .doc(schoolRef)
              .collection('chunks')
              .orderBy('index')
              .get();
          final buffer = StringBuffer();
          for (final ch in chunkSnap.docs) {
            final idx = int.tryParse('${ch.data()['index'] ?? ch.id}');
            // Ignore surplus chunks left from an older, longer save.
            if (cc != null && idx != null && idx >= cc) continue;
            buffer.write('${ch.data()['data'] ?? ''}');
          }
          final rawJson = buffer.toString();
          if (rawJson.isNotEmpty) {
            try {
              d['state'] = jsonDecode(rawJson);
              if (stamp.isNotEmpty) {
                _rojmelStateCache[schoolRef] =
                    (updatedAt: stamp, state: d['state']);
              }
            } catch (_) {}
          }
        }
      }
    } else if (_table == 'school_settings' && docs.isNotEmpty) {
      for (final d in docs) {
        final logoPath = '${d['logo_path'] ?? ''}'.trim();
        final logoDataUri = '${d['logo_data_uri'] ?? ''}'.trim();
        if (logoPath.isNotEmpty && logoDataUri.isNotEmpty) {
          FirestoreStorageBucket._dataUriCache[logoPath] = logoDataUri;
        } else if (logoPath.isNotEmpty &&
            !FirestoreStorageBucket._dataUriCache.containsKey(logoPath)) {
          try {
            final assetDocId = Uri.encodeComponent(
              logoPath.replaceFirst(RegExp(r'^/+'), ''),
            );
            final assetSnap = await _client._db
                .collection('school_assets')
                .doc(assetDocId)
                .get();
            if (assetSnap.exists && assetSnap.data() != null) {
              final uri = '${assetSnap.data()!['data_uri'] ?? ''}'.trim();
              if (uri.isNotEmpty) {
                FirestoreStorageBucket._dataUriCache[logoPath] = uri;
              }
            }
          } catch (_) {}
        }
      }
    }

    if (_table == 'school_admin_messages' && docs.isNotEmpty) {
      final todayIso = SupabaseClient._indiaTodayIso();
      final keepDocs = <Map<String, dynamic>>[];
      for (final d in docs) {
        final rawDate = '${d['message_date'] ?? ''}'.trim();
        final normDate = SupabaseClient._parseAnyDateToIso(rawDate) ?? rawDate;
        if (normDate.length >= 10 &&
            normDate.substring(0, 10).compareTo(todayIso) < 0) {
          final docId = '${d['id'] ?? ''}'.trim();
          if (docId.isNotEmpty) {
            _client._db
                .collection('school_admin_messages')
                .doc(docId)
                .delete()
                .ignore();
          }
          continue;
        }
        keepDocs.add(d);
      }
      docs = keepDocs;
    }

    // Apply all equality, inFilter, gte, lte, and RLS filters in memory
    final filtered = <Map<String, dynamic>>[];
    for (final row in docs) {
      if (!_matchesFilters(row, eqMap)) continue;
      if (!_matchesRlsSelect(row, ctx)) continue;
      filtered.add(row);
    }

    // Apply ordering
    if (_orders.isNotEmpty) {
      filtered.sort((a, b) {
        for (final spec in _orders) {
          final cmp = _compareValues(a[spec.column], b[spec.column]);
          if (cmp != 0) return spec.ascending ? cmp : -cmp;
        }
        return 0;
      });
    }

    // Apply range / limit
    var result = filtered;
    if (_rangeFrom != null && _rangeTo != null) {
      final start = _rangeFrom!.clamp(0, result.length);
      final end = (_rangeTo! + 1).clamp(start, result.length);
      result = result.sublist(start, end);
    } else if (_limitCount != null) {
      final end = _limitCount!.clamp(0, result.length);
      result = result.sublist(0, end);
    }

    return result;
  }

  String? _tryResolveDirectDocId(Map<String, Object?> eqMap) {
    if (eqMap.containsKey('id') && eqMap['id'] != null) {
      final id = '${eqMap['id']}'.trim();
      if (id.isNotEmpty) return id;
    }
    if (const <String>{
          'school_settings',
          'school_custom_headers',
          'school_leave_settings',
          'library_settings',
          'school_rojmel_state',
        }.contains(_table) &&
        eqMap.containsKey('school_ref')) {
      final ref = '${eqMap['school_ref'] ?? ''}'.trim();
      if (ref.isNotEmpty) return ref;
    }
    if (_table == 'student_private_details' &&
        eqMap.containsKey('student_id')) {
      final sid = '${eqMap['student_id'] ?? ''}'.trim();
      if (sid.isNotEmpty) return sid;
    }
    if (_table == 'class_result_settings' && eqMap.containsKey('class_id')) {
      final cid = '${eqMap['class_id'] ?? ''}'.trim();
      if (cid.isNotEmpty) return cid;
    }
    return null;
  }

  static final Map<String, ({DateTime ts, List<Map<String, dynamic>> rows})>
  _queryCache = <String, ({DateTime ts, List<Map<String, dynamic>> rows})>{};

  /// Identical queries issued at the same time (several widgets / services
  /// loading on one screen) share a single Firestore read.
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlightReads =
      <String, Future<List<Map<String, dynamic>>>>{};

  /// Bumped on every invalidation so a read that started before a write never
  /// stores stale rows in the cache.
  static final Map<String, int> _tableGeneration = <String, int>{};
  static int _globalGeneration = 0;
  static int _generationOf(String table) =>
      _globalGeneration * 1000003 + (_tableGeneration[table] ?? 0);

  /// Re-assembled chunked Rojmel state keyed by school, valid while the
  /// parent document's updated_at is unchanged (saves N chunk reads per open).
  static final Map<String, ({String updatedAt, dynamic state})>
  _rojmelStateCache = <String, ({String updatedAt, dynamic state})>{};
  static final Map<String, int> _rojmelChunkCounts = <String, int>{};
  static final Map<String, String> _lastWrittenPayloadHash = <String, String>{};

  static const Set<String> _longTtlMasterTables = <String>{
    'schools',
    'school_settings',
    'school_classes',
    'school_teachers',
    'school_subject_master',
    'school_subject_catalog',
    'class_subjects',
    'school_result_grade_settings',
    'teacher_subject_assignments',
    'school_custom_headers',
    'school_report_settings',
    'school_hajari_patrak_settings',
    'school_leave_settings',
    'school_teacher_valtar_rules',
    'library_settings',
    'class_result_settings',
    'school_holidays',
    'students',
    'attendance_days',
    'student_attendance',
    'student_subject_marks',
    'student_result_profiles',
    'student_result_roster_snapshots',
    'student_result_roster_members',
    'teacher_leaves',
    'library_books',
    'library_book_number_history',
    'library_transactions',
    'student_private_details',
  };

  /// Synthesizes `student_attendance` rows from `attendance_days.student_marks`
  /// in memory (0 extra Firestore reads), falling back to legacy
  /// `student_attendance` documents only for older days that do not yet have
  /// embedded `student_marks`.
  Future<List<Map<String, dynamic>>> _resolveStudentAttendanceFromDaysOrLegacy(
    fs.CollectionReference<Map<String, dynamic>> col,
    Map<String, Object?> eqMap,
  ) async {
    final schoolRef = '${eqMap['school_ref'] ?? ''}'.trim();
    if (schoolRef.isEmpty) {
      return _runCollectionQuery(col, eqMap);
    }

    final allDays = await _client._cachedSchoolTableRows(
      'attendance_days',
      schoolRef,
    );
    final eqDayId = '${eqMap['attendance_day_id'] ?? ''}'.trim();
    final eqClassId = '${eqMap['class_id'] ?? ''}'.trim();
    final inDayIds = _inFilters['attendance_day_id']
        ?.where((v) => v != null)
        .map((v) => '$v'.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    final candidateDays = <Map<String, dynamic>>[];
    for (final d in allDays) {
      final did = '${d['id'] ?? ''}'.trim();
      if (did.isEmpty) continue;
      if (eqDayId.isNotEmpty && did != eqDayId) continue;
      if (inDayIds != null && !inDayIds.contains(did)) continue;
      if (eqClassId.isNotEmpty && '${d['class_id'] ?? ''}'.trim() != eqClassId) {
        continue;
      }
      candidateDays.add(d);
    }

    final synthesized = <Map<String, dynamic>>[];
    final embeddedDayIds = <String>{};
    final legacyDayIds = <String>{};

    for (final d in candidateDays) {
      final did = '${d['id'] ?? ''}'.trim();
      final rawMarks = d['student_marks'];
      if (rawMarks is Map) {
        embeddedDayIds.add(did);
        rawMarks.forEach((k, v) {
          final sid = '$k'.trim();
          if (sid.isEmpty) return;
          final m = v is Map ? v : const <String, dynamic>{};
          synthesized.add(<String, dynamic>{
            'id': '${did}__$sid',
            'school_ref': '${d['school_ref'] ?? schoolRef}',
            'class_id': '${d['class_id'] ?? ''}',
            'attendance_day_id': did,
            'attendance_date': '${d['attendance_date'] ?? ''}',
            'student_id': sid,
            'present': m['present'] == true || m['p'] == true || m['p'] == 1,
            'mdm': m['mdm'] == true || m['m'] == true || m['m'] == 1,
            'breakfast':
                m['breakfast'] == true || m['b'] == true || m['b'] == 1,
            'updated_by_teacher':
                m['updated_by_teacher'] ?? d['updated_by_teacher'],
            'updated_at': '${d['updated_at'] ?? ''}',
          });
        });
      } else if (d['has_embedded_marks'] == true) {
        embeddedDayIds.add(did);
      } else if ('${d['attendance_mode'] ?? 'student'}' != 'direct' &&
          d['student_details_saved'] != false) {
        legacyDayIds.add(did);
      }
    }

    if (legacyDayIds.isEmpty) {
      return synthesized;
    }

    // Fetch legacy student_attendance rows (cached per school or per single day)
    List<Map<String, dynamic>> legacyRows;
    if (legacyDayIds.length == 1 && eqDayId.isNotEmpty) {
      legacyRows = await _runCollectionQuery(col, eqMap);
    } else {
      legacyRows = await _client._cachedSchoolTableRows(
        'student_attendance',
        schoolRef,
      );
    }

    final legacyByDay = <String, Map<String, Map<String, dynamic>>>{};
    for (final r in legacyRows) {
      final did = '${r['attendance_day_id'] ?? ''}'.trim();
      if (did.isEmpty || embeddedDayIds.contains(did)) continue;
      final sid = '${r['student_id'] ?? ''}'.trim();
      if (sid.isNotEmpty) {
        legacyByDay.putIfAbsent(did, () => <String, Map<String, dynamic>>{})[sid] =
            <String, dynamic>{
              'present': r['present'] == true,
              'mdm': r['mdm'] == true,
              'breakfast': r['breakfast'] == true,
              if (r['updated_by_teacher'] != null)
                'updated_by_teacher': r['updated_by_teacher'],
            };
      }
      if (legacyDayIds.contains(did)) {
        synthesized.add(Map<String, dynamic>.from(r));
      }
    }

    // Backfill in-memory attendance_days cache with legacy marks so subsequent
    // report downloads in this session require 0 legacy queries!
    final daysCacheKey = 'attendance_days|school_ref=$schoolRef|in=';
    final cachedDaysEntry = _queryCache[daysCacheKey];
    if (cachedDaysEntry != null) {
      for (final d in cachedDaysEntry.rows) {
        final did = '${d['id'] ?? ''}'.trim();
        if (d['student_marks'] == null && legacyDayIds.contains(did)) {
          d['student_marks'] =
              legacyByDay[did] ?? const <String, Map<String, dynamic>>{};
          d['has_embedded_marks'] = true;
        }
      }
    }

    return synthesized;
  }

  static int _cacheTtlSecondsForTable(String table) =>
      _longTtlMasterTables.contains(table) ? 900 : 300;

  static String _canonicalRowSignature(Map<String, dynamic> row) {
    final keys = row.keys
        .where((k) => k != 'updated_at' && k != 'created_at')
        .toList()
      ..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      sb.write('$k=${row[k]};');
    }
    return sb.toString();
  }

  /// Clears every cached row, in-flight read and write signature. Called on
  /// logout and when a different user signs in on the same device.
  static void clearAllForSessionChange() {
    invalidateCache();
    _lastWrittenPayloadHash.clear();
    _rojmelStateCache.clear();
    _rojmelChunkCounts.clear();
  }

  /// Drops expired entries once the cache grows large (long sessions).
  static void _pruneCacheIfLarge() {
    if (_queryCache.length < 600) return;
    final now = DateTime.now();
    _queryCache.removeWhere((k, v) {
      final table = k.split('|').first;
      return now.difference(v.ts).inSeconds >= _cacheTtlSecondsForTable(table);
    });
    if (_queryCache.length >= 600) {
      final keys = _queryCache.entries.toList()
        ..sort((a, b) => a.value.ts.compareTo(b.value.ts));
      for (final e in keys.take(_queryCache.length - 400)) {
        _queryCache.remove(e.key);
      }
    }
  }

  static void invalidateCache([String? table]) {
    if (table == null) {
      _globalGeneration++;
      _queryCache.clear();
      _inFlightReads.clear();
      return;
    }
    _tableGeneration[table] = (_tableGeneration[table] ?? 0) + 1;
    _queryCache.removeWhere((k, _) => k.startsWith('$table|'));
    _inFlightReads.removeWhere((k, _) => k.startsWith('$table|'));
  }

  /// Patches already-cached rows in memory after a local write so callers do
  /// not re-download an entire school collection (e.g. 1,800+ attendance_days)
  /// right after saving 1 document.
  static void patchCacheRows(
    String table,
    List<Map<String, dynamic>> savedRows,
  ) {
    if (savedRows.isEmpty) return;
    _tableGeneration[table] = (_tableGeneration[table] ?? 0) + 1;
    _inFlightReads.removeWhere((k, _) => k.startsWith('$table|'));
    final byId = <String, Map<String, dynamic>>{
      for (final r in savedRows)
        if ('${r['id'] ?? ''}'.trim().isNotEmpty)
          '${r['id']}'.trim(): Map<String, dynamic>.from(r),
    };
    if (byId.isEmpty) {
      invalidateCache(table);
      return;
    }
    final now = DateTime.now();
    for (final entry in byId.entries) {
      _queryCache['$table|__doc__=${entry.key}'] = (
        ts: now,
        rows: <Map<String, dynamic>>[Map<String, dynamic>.from(entry.value)],
      );
    }
    final existingKeys = _queryCache.keys
        .where((k) => k.startsWith('$table|') && !k.startsWith('$table|__doc__='))
        .toList();
    for (final k in existingKeys) {
      if (k.startsWith('$table|school_ref=') && k.endsWith('|in=')) {
        final ref = k.substring(
          '$table|school_ref='.length,
          k.length - '|in='.length,
        );
        final cached = _queryCache[k];
        if (cached == null) continue;
        final list =
            cached.rows.map((r) => Map<String, dynamic>.from(r)).toList();
        var changed = false;
        for (final row in byId.values) {
          final rowRef = '${row['school_ref'] ?? ''}'.trim();
          if (rowRef.isNotEmpty && rowRef != ref) continue;
          final id = '${row['id']}'.trim();
          final idx = list.indexWhere((e) => '${e['id'] ?? ''}'.trim() == id);
          if (idx >= 0) {
            list[idx] = <String, dynamic>{...list[idx], ...row};
          } else {
            list.add(Map<String, dynamic>.from(row));
          }
          changed = true;
        }
        if (changed) {
          _queryCache[k] = (ts: cached.ts, rows: list);
        }
      } else {
        _queryCache.remove(k);
      }
    }
  }

  /// Merges embedded `student_marks` patches into cached `attendance_days`
  /// documents in memory without triggering a full-school reload.
  static void patchEmbeddedAttendanceMarks(
    Map<String, Map<String, Map<String, dynamic>>> byDayId,
    String nowIso,
  ) {
    if (byDayId.isEmpty) return;
    _tableGeneration['attendance_days'] =
        (_tableGeneration['attendance_days'] ?? 0) + 1;
    _inFlightReads.removeWhere((k, _) => k.startsWith('attendance_days|'));
    final existingKeys = _queryCache.keys
        .where((k) => k.startsWith('attendance_days|'))
        .toList();
    for (final k in existingKeys) {
      final cached = _queryCache[k];
      if (cached == null) continue;
      final list =
          cached.rows.map((r) => Map<String, dynamic>.from(r)).toList();
      var changed = false;
      for (final d in list) {
        final did = '${d['id'] ?? ''}'.trim();
        final patch = byDayId[did];
        if (patch == null) continue;
        final existingMarks = d['student_marks'] is Map
            ? Map<String, dynamic>.from(d['student_marks'] as Map)
            : <String, dynamic>{};
        existingMarks.addAll(patch);
        d['student_marks'] = existingMarks;
        d['has_embedded_marks'] = true;
        d['updated_at'] = nowIso;
        changed = true;
      }
      if (changed) {
        _queryCache[k] = (ts: cached.ts, rows: list);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _runCollectionQuery(
    fs.CollectionReference<Map<String, dynamic>> col,
    Map<String, Object?> eqMap,
  ) async {
    fs.Query<Map<String, dynamic>> query = col;
    // Choose a single primary indexed filter to push down to Firestore so we
    // never trigger composite-index errors on multi-field queries.
    const priorityKeys = <String>[
      'id',
      'auth_user_id',
      'school_id',
      'attendance_day_id',
      'snapshot_id',
      'student_id',
      'class_id',
      'school_ref',
    ];
    String? pushedKey;
    for (final key in priorityKeys) {
      if (eqMap.containsKey(key) && eqMap[key] != null) {
        query = query.where(key, isEqualTo: eqMap[key]);
        pushedKey = key;
        break;
      }
    }
    if (pushedKey == null && _inFilters.isNotEmpty) {
      final firstIn = _inFilters.entries.first;
      final nonNulls = firstIn.value.where((v) => v != null).toList();
      if (nonNulls.isNotEmpty && nonNulls.length <= 30) {
        query = query.where(firstIn.key, whereIn: nonNulls);
      }
    }

    final now = DateTime.now();
    final ttlSec = _cacheTtlSecondsForTable(_table);
    final schoolRefFilter = '${eqMap['school_ref'] ?? ''}'.trim();
    if (schoolRefFilter.isNotEmpty) {
      final schoolWideKey = '$_table|school_ref=$schoolRefFilter|in=';
      final schoolWideCached = _queryCache[schoolWideKey];
      if (schoolWideCached != null &&
          now.difference(schoolWideCached.ts).inSeconds < ttlSec) {
        return schoolWideCached.rows
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      }
    }

    // When pushedKey != null, _inFilters was NOT pushed to Firestore; cache
    // under the pushedKey alone so subsequent inFilter slices reuse 0 reads.
    final cacheKey =
        '$_table|$pushedKey=${pushedKey != null ? eqMap[pushedKey] : ""}|in=${pushedKey == null && _inFilters.isNotEmpty ? _inFilters.toString() : ""}';
    final cached = _queryCache[cacheKey];
    if (cached != null && now.difference(cached.ts).inSeconds < ttlSec) {
      return cached.rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    final gen = _generationOf(_table);
    var pending = _inFlightReads[cacheKey];
    if (pending == null) {
      final table = _table;
      pending = query.get().then((snap) => snap.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] ??= doc.id;
            _applyTableSqlDefaults(table, data);
            _lastWrittenPayloadHash['$table/${doc.id}'] =
                _canonicalRowSignature(data);
            return data;
          }).toList());
      _inFlightReads[cacheKey] = pending;
      pending.whenComplete(() {
        if (identical(_inFlightReads[cacheKey], pending)) {
          _inFlightReads.remove(cacheKey);
        }
      }).ignore();
    }
    final rows = await pending;
    if (gen == _generationOf(_table)) {
      _pruneCacheIfLarge();
      _queryCache[cacheKey] = (ts: now, rows: rows);
    }
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static const Set<String> _defaultActiveTrueTables = <String>{
    'students',
    'school_classes',
    'school_teachers',
    'schools',
    'class_subjects',
    'school_subject_master',
    'school_subject_catalog',
    'school_result_grade_settings',
    'library_books',
    'developer_messages',
  };

  static void _applyTableSqlDefaults(String table, Map<String, dynamic> row) {
    if (_defaultActiveTrueTables.contains(table)) {
      row['is_active'] ??= true;
    }
    if (table == 'school_teachers') {
      final rawMob = '${row['mobile'] ?? ''}'.trim();
      final digits = rawMob.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 12 && digits.startsWith('91')) {
        row['mobile'] = digits.substring(2);
      } else if (digits.length == 10) {
        row['mobile'] = digits;
      }
    }
    if (table == 'students') {
      row['is_divyang'] ??= false;
      row['category'] ??= 'OTHER';
    } else if (table == 'schools') {
      row['is_blocked'] ??= false;
      row['report_gender_split_enabled'] ??= true;
    } else if (table == 'library_books') {
      row['is_archived'] ??= false;
    }
  }

  bool _matchesFilters(Map<String, dynamic> row, Map<String, Object?> eqMap) {
    for (final entry in eqMap.entries) {
      final col = entry.key;
      final expected = entry.value;
      final actual = row[col];
      if (!_valuesEqual(actual, expected)) return false;
    }
    for (final entry in _inFilters.entries) {
      final col = entry.key;
      final allowed = entry.value;
      final actual = row[col];
      if (!allowed.any((item) => _valuesEqual(actual, item))) return false;
    }
    for (final entry in _gteFilters.entries) {
      final actual = row[entry.key];
      if (actual == null || _compareValues(actual, entry.value) < 0) {
        return false;
      }
    }
    for (final entry in _lteFilters.entries) {
      final actual = row[entry.key];
      if (actual == null || _compareValues(actual, entry.value) > 0) {
        return false;
      }
    }
    return true;
  }

  bool _matchesRlsSelect(
    Map<String, dynamic> row,
    _TeacherSessionContext? ctx,
  ) {
    if (ctx == null) return true;
    if (ctx.isAdmin) return true;

    if (_table == 'school_classes') {
      return ctx.canAccessClassRow(row);
    }
    if (_table == 'teacher_leaves' || _table == 'teacher_subject_assignments') {
      return '${row['teacher_id'] ?? ''}' == ctx.teacherId;
    }
    if (_table == 'library_transactions') {
      if ('${row['status'] ?? ''}' == 'issued') return true;
      if ('${row['recorded_by_teacher_id'] ?? ''}' == ctx.teacherId)
        return true;
      if ('${row['borrower_type'] ?? ''}' == 'teacher' &&
          '${row['teacher_borrower_id'] ?? ''}' == ctx.teacherId) {
        return true;
      }
      final cid = '${row['class_id'] ?? ''}';
      if (cid.isNotEmpty && ctx.canAccessClassIdOrKey(cid)) return true;
      return false;
    }
    return true;
  }

  static bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is bool || b is bool) {
      return _toBool(a) == _toBool(b);
    }
    if (a is num && b is num) {
      return a.toDouble() == b.toDouble();
    }
    return '$a'.trim() == '$b'.trim();
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = '${v ?? ''}'.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't' || s == 'yes';
  }

  static int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    final na = num.tryParse('$a');
    final nb = num.tryParse('$b');
    if (na != null && nb != null) return na.compareTo(nb);
    return '$a'.compareTo('$b');
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() =>
      Stream<List<Map<String, dynamic>>>.fromFuture(_execute());

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _execute().catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => _execute().then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => _execute().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => _execute().whenComplete(action);

  static String _slug(dynamic value) {
    final s = '${value ?? ''}'.trim().toLowerCase();
    if (s.isEmpty) return 'empty';
    return Uri.encodeComponent(s).replaceAll('%', '_');
  }

  String _deterministicDocId(Map<String, dynamic> row) {
    final explicitId = '${row['id'] ?? ''}'.trim();
    switch (_table) {
      case 'school_settings':
      case 'school_custom_headers':
      case 'school_leave_settings':
      case 'library_settings':
      case 'school_rojmel_state':
        return '${row['school_ref'] ?? explicitId}'.trim();
      case 'student_private_details':
        return '${row['student_id'] ?? explicitId}'.trim();
      case 'class_result_settings':
        return '${row['class_id'] ?? explicitId}'.trim();
      case 'attendance_days':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id']}__${row['attendance_date']}';
      case 'student_attendance':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['attendance_day_id']}__${row['student_id']}';
      case 'attendance_admin_overrides':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['authorized_by']}__${row['attendance_date']}';
      case 'school_holidays':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['holiday_date']}';
      case 'school_admin_messages':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['message_date']}';
      case 'school_report_settings':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id'] ?? 'GLOBAL'}__${row['report_key']}';
      case 'school_hajari_patrak_settings':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id']}';
      case 'hajari_student_present_day_overrides':
        return '${row['school_ref']}__${row['class_id']}__${row['student_id']}__${row['academic_year_start']}__${row['through_date']}';
      case 'class_subjects':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id']}__${_slug(row['subject_name'])}';
      case 'school_subject_catalog':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${_slug(row['standard'])}__${_slug(row['subject_name'])}';
      case 'school_subject_master':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${_slug(row['subject_name'])}';
      case 'school_result_grade_settings':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${_slug(row['grade_label'])}';
      case 'teacher_subject_assignments':
        return '${row['school_ref']}__${row['teacher_id']}__${row['class_id']}__${_slug(row['subject_name'])}';
      case 'student_result_profiles':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id']}__${row['student_id']}__${_slug(row['academic_year'])}';
      case 'student_subject_marks':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['school_ref']}__${row['class_id']}__${row['student_id']}__${_slug(row['academic_year'])}__${row['semester']}__${_slug(row['subject_name'])}';
      case 'student_result_roster_members':
        if (explicitId.isNotEmpty) return explicitId;
        return '${row['snapshot_id']}__${row['student_id']}';
      case 'school_teacher_valtar_rules':
        return '${row['school_ref']}__${row['teacher_id']}';
      default:
        return explicitId.isNotEmpty
            ? explicitId
            : SupabaseClient._generateUuid();
    }
  }

  Future<List<Map<String, dynamic>>> _executeInsertOrUpsert({
    required bool isUpsert,
  }) async {
    if (_payloadRows.isEmpty) return <Map<String, dynamic>>[];

    final ctx = await _client._resolveCurrentTeacherContext();
    final schoolRef = await _client._requireSchoolWriteAccess(
      explicitSchoolRef: '${_payloadRows.first['school_ref'] ?? ''}',
    );

    final col = _client._db.collection(_table);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final savedRows = <Map<String, dynamic>>[];

    // Pre-validate table-specific guards (attendance lock, Sunday/holiday, leave caps, etc.)
    if (_table == 'attendance_days' || _table == 'student_attendance') {
      await _client._enforceAttendanceWriteGuard(
        table: _table,
        rows: _payloadRows,
        schoolRef: schoolRef,
        ctx: ctx,
      );
    } else if (_table == 'teacher_leaves') {
      for (final row in _payloadRows) {
        await _client._enforceLeaveWriteGuard(row, isInsert: !isUpsert);
      }
    } else if (_table == 'student_subject_marks' ||
        _table == 'student_result_profiles') {
      await _client._enforceResultWriteGuard(
        table: _table,
        rows: _payloadRows,
        ctx: ctx,
      );
    }

    // Optimization #1: Pack student_attendance upserts into a single embedded
    // `student_marks` map on the parent `attendance_days` document (1 write
    // instead of 40-50 separate document writes per class).
    if (_table == 'student_attendance') {
      final byDayId = <String, Map<String, Map<String, dynamic>>>{};
      for (final raw in _payloadRows) {
        final row = Map<String, dynamic>.from(raw);
        final dayId = '${row['attendance_day_id'] ?? ''}'.trim();
        final studentId = '${row['student_id'] ?? ''}'.trim();
        if (dayId.isEmpty || studentId.isEmpty) continue;
        row['school_ref'] = '${row['school_ref'] ?? schoolRef}'.trim();
        row['id'] = '${dayId}__$studentId';
        row['updated_at'] ??= nowIso;
        savedRows.add(row);
        final dayMap = byDayId.putIfAbsent(
          dayId,
          () => <String, Map<String, dynamic>>{},
        );
        dayMap[studentId] = <String, dynamic>{
          'present': row['present'] == true,
          'mdm': row['mdm'] == true,
          'breakfast': row['breakfast'] == true,
          if (row['updated_by_teacher'] != null)
            'updated_by_teacher': row['updated_by_teacher'],
        };
      }
      for (final entry in byDayId.entries) {
        final dayId = entry.key;
        final marksPatch = entry.value;
        final embedHashKey = 'student_attendance_embed/$dayId';
        final sig = jsonEncode(marksPatch);
        if (_lastWrittenPayloadHash[embedHashKey] != sig) {
          await _client._db.collection('attendance_days').doc(dayId).set(
            <String, dynamic>{
              'student_marks': marksPatch,
              'has_embedded_marks': true,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          _lastWrittenPayloadHash[embedHashKey] = sig;
        }
      }
      patchEmbeddedAttendanceMarks(byDayId, nowIso);
      invalidateCache('student_attendance');
      return savedRows;
    }

    // Special handling for school_rojmel_state (chunking states > 700 KB)
    if (_table == 'school_rojmel_state') {
      if (ctx != null && !ctx.isAdmin) {
        throw const PostgrestException(
          message: 'Only the School Admin can edit Rojmel records.',
          code: '42501',
        );
      }
      for (final raw in _payloadRows) {
        final row = Map<String, dynamic>.from(raw);
        final ref = '${row['school_ref'] ?? schoolRef}'.trim();
        row['school_ref'] = ref;
        row['id'] = ref;
        row['updated_at'] = nowIso;
        row['updated_by_teacher_id'] = ctx?.teacherId;
        final stateObj = row['state'];
        final encoded = jsonEncode(stateObj ?? const <String, dynamic>{});
        final rojmelHashKey = 'school_rojmel_state/$ref';
        if (_lastWrittenPayloadHash[rojmelHashKey] == encoded) {
          savedRows.add(row);
          continue;
        }
        _lastWrittenPayloadHash[rojmelHashKey] = encoded;
        invalidateCache('school_rojmel_state');
        if (encoded.length > 700000) {
          const chunkSize = 700000;
          final chunkCount = (encoded.length / chunkSize).ceil();
          final chunksCol = col.doc(ref).collection('chunks');
          var batch = _client._db.batch();
          var ops = 0;
          final knownOld = _rojmelChunkCounts[ref];
          if (knownOld != null) {
            // Chunks 0..chunkCount-1 are overwritten below; delete only the
            // surplus ones without reading the sub-collection.
            for (var i = chunkCount; i < knownOld; i++) {
              batch.delete(chunksCol.doc('$i'));
              ops++;
            }
          } else {
            final existingChunks = await chunksCol.get();
            for (final d in existingChunks.docs) {
              final idx = int.tryParse(d.id);
              if (idx != null && idx < chunkCount) continue;
              batch.delete(d.reference);
              ops++;
              if (ops >= 400) {
                await batch.commit();
                batch = _client._db.batch();
                ops = 0;
              }
            }
          }
          for (var i = 0; i < chunkCount; i++) {
            final start = i * chunkSize;
            final end = math.min(start + chunkSize, encoded.length);
            batch.set(chunksCol.doc('$i'), <String, dynamic>{
              'index': i,
              'data': encoded.substring(start, end),
            });
            ops++;
            if (ops >= 400) {
              await batch.commit();
              batch = _client._db.batch();
              ops = 0;
            }
          }
          batch.set(col.doc(ref), <String, dynamic>{
            'id': ref,
            'school_ref': ref,
            'is_chunked': true,
            'chunk_count': chunkCount,
            'updated_at': nowIso,
            'updated_by_teacher_id': ctx?.teacherId,
          });
          await batch.commit();
          _rojmelChunkCounts[ref] = chunkCount;
          _rojmelStateCache[ref] = (updatedAt: nowIso, state: stateObj);
        } else {
          await col.doc(ref).set(<String, dynamic>{
            ...row,
            'is_chunked': false,
          }, fs.SetOptions(merge: true));
        }
        savedRows.add(row);
      }
      return savedRows;
    }

    // Standard insert/upsert with batching (up to 400 docs per WriteBatch)
    var batch = _client._db.batch();
    var batchOps = 0;

    for (final raw in _payloadRows) {
      final row = Map<String, dynamic>.from(raw);
      if (_schoolScopedTables.contains(_table) &&
          '${row['school_ref'] ?? ''}'.trim().isEmpty &&
          schoolRef.isNotEmpty) {
        row['school_ref'] = schoolRef;
      }

      _applyTableSqlDefaults(_table, row);
      if (_table == 'students') {
        await _client._normalizeStudentRowOnWrite(row, schoolRef);
      }

      String docId = _deterministicDocId(row);

      // For attendance_days upsert on (school_ref, class_id, attendance_date),
      // check if an older row with a UUID docId already exists so we preserve its ID!
      if (_table == 'attendance_days' &&
          '${row['id'] ?? ''}'.trim().isEmpty &&
          row['class_id'] != null &&
          row['attendance_date'] != null) {
        final existing = await _client
            .from('attendance_days')
            .select(
              'id,registered_counts,present_counts,mdm_counts,breakfast_total,gender_breakdown,attendance_mode,student_details_saved,is_frozen,unfrozen_by_admin,present_saved,mdm_saved,breakfast_saved,present_frozen,mdm_frozen,breakfast_frozen,student_marks,has_embedded_marks',
            )
            .eq('school_ref', '${row['school_ref']}')
            .eq('class_id', '${row['class_id']}')
            .eq('attendance_date', '${row['attendance_date']}')
            .maybeSingle();
        if (existing != null && '${existing['id'] ?? ''}'.trim().isNotEmpty) {
          docId = '${existing['id']}'.trim();
          for (final entry in existing.entries) {
            row.putIfAbsent(entry.key, () => entry.value);
          }
        }
      }

      if (_table == 'attendance_days') {
        if ('${row['attendance_mode'] ?? ''}' == 'count_only' ||
            '${row['attendance_mode'] ?? ''}' == 'direct') {
          row['is_frozen'] = row['is_frozen'] ?? true;
        }
        if (row['is_frozen'] == true) {
          row['unfrozen_by_admin'] = false;
          row['frozen_at'] = nowIso;
        }
      }
      row['id'] = docId;
      row.putIfAbsent('created_at', () => nowIso);
      row['updated_at'] ??= nowIso;

      final rowHashKey = '$_table/$docId';
      final newSig = _canonicalRowSignature(row);
      if (!isUpsert || _lastWrittenPayloadHash[rowHashKey] != newSig) {
        batch.set(col.doc(docId), row, fs.SetOptions(merge: isUpsert));
        _lastWrittenPayloadHash[rowHashKey] = newSig;
        batchOps++;
      }
      savedRows.add(row);

      // Sync school_subject_master when class_subjects are inserted/upserted
      if (_table == 'class_subjects' &&
          row['is_active'] == true &&
          '${row['subject_name'] ?? ''}'.trim().isNotEmpty &&
          '${row['subject_name'] ?? ''}'.trim() != 'વ્યક્તિત્વ વિકાસ') {
        final sName = '${row['subject_name']}'.trim();
        final masterId = '${row['school_ref']}__${_slug(sName)}';
        batch.set(
          _client._db.collection('school_subject_master').doc(masterId),
          <String, dynamic>{
            'id': masterId,
            'school_ref': row['school_ref'],
            'subject_name': sName,
            'sort_order': row['sort_order'] ?? 100,
            'is_active': true,
            'updated_at': nowIso,
          },
          fs.SetOptions(merge: true),
        );
        batchOps++;
      }

      if (batchOps >= 400) {
        await batch.commit();
        batch = _client._db.batch();
        batchOps = 0;
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }
    if (_table == 'attendance_days' ||
        _table == 'school_settings' ||
        _table == 'student_subject_marks' ||
        _table == 'student_result_profiles' ||
        _table == 'student_private_details') {
      patchCacheRows(_table, savedRows);
    } else {
      invalidateCache(_table);
    }
    if (_table == 'class_subjects' ||
        _table == 'school_subject_master' ||
        _table == 'school_classes') {
      invalidateCache('school_subject_master');
      invalidateCache('class_subjects');
      invalidateCache('school_subject_catalog');
    }
    if (_table == 'school_classes') {
      for (final r in savedRows) {
        if (r['is_active'] == true) {
          await _client._seedSubjectsForClassRow(r);
        }
      }
    } else if (_table == 'school_subject_master') {
      for (final r in savedRows) {
        await _client._syncMasterSubjectRowToClasses(r);
      }
    }

    return savedRows;
  }

  Future<List<Map<String, dynamic>>> _executeUpdate() async {
    if (_payloadRows.isEmpty) return <Map<String, dynamic>>[];
    final patch = Map<String, dynamic>.from(_payloadRows.first);
    final ctx = await _client._resolveCurrentTeacherContext();
    await _client._requireSchoolWriteAccess(
      explicitSchoolRef:
          '${_eqFilters['school_ref'] ?? patch['school_ref'] ?? ''}',
    );

    if (_table == 'students' && patch['is_active'] == false) {
      final targetStudentId = '${_eqFilters['id'] ?? ''}'.trim();
      if (targetStudentId.isEmpty) {
        throw const PostgrestException(
          message: 'A specific student ID is required to deactivate a student.',
        );
      }
      final singleSnap =
          await _client._db.collection('students').doc(targetStudentId).get();
      if (!singleSnap.exists || singleSnap.data() == null) {
        return <Map<String, dynamic>>[];
      }
      final old = <String, dynamic>{
        ...singleSnap.data()!,
        'id': singleSnap.data()!['id'] ?? singleSnap.id,
      };
      final todayIso = SupabaseClient._indiaTodayIso();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final next = <String, dynamic>{
        ...old,
        ...patch,
        'id': targetStudentId,
        'is_active': false,
        'exit_date': old['exit_date'] ?? patch['exit_date'] ?? todayIso,
        'leaving_date': old['leaving_date'] ?? patch['leaving_date'] ?? todayIso,
        'exit_reason': '${patch['exit_reason'] ?? old['exit_reason'] ?? 'other'}',
        if ('${old['roll_number'] ?? ''}'.trim().isNotEmpty)
          'previous_roll_number': '${old['roll_number']}'.trim(),
        'roll_number': '',
        'updated_at': nowIso,
      };
      await _client._db
          .collection('students')
          .doc(targetStudentId)
          .set(next, fs.SetOptions(merge: true));
      invalidateCache('students');
      final sRef = '${old['school_ref'] ?? ''}'.trim();
      final cId = '${old['class_id'] ?? ''}'.trim();
      if (sRef.isNotEmpty && cId.isNotEmpty) {
        await _client._renumberActiveClassStudentsContinually(
          schoolRef: sRef,
          classId: cId,
        );
      }
      return <Map<String, dynamic>>[next];
    }

    final matching = await _executeSelect();
    if (matching.isEmpty) return <Map<String, dynamic>>[];

    if (_table == 'attendance_days' || _table == 'student_attendance') {
      final mergedRows = matching
          .map((old) => <String, dynamic>{...old, ...patch})
          .toList();
      await _client._enforceAttendanceWriteGuard(
        table: _table,
        rows: mergedRows,
        schoolRef: '${matching.first['school_ref'] ?? ctx?.schoolRef ?? ''}',
        ctx: ctx,
      );
    }

    final col = _client._db.collection(_table);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final updatedRows = <Map<String, dynamic>>[];
    var batch = _client._db.batch();
    var ops = 0;

    for (final old in matching) {
      final docId = '${old['id']}';
      final next = <String, dynamic>{...old, ...patch, 'id': docId};
      next['updated_at'] ??= nowIso;

      // Capture exit_date and clear roll_number when a student leaves / becomes inactive,
      // and cleanly clear stale leaving_date / exit_date when a student is reactivated or updated as active!
      if (_table == 'students') {
        final wasActive = old['is_active'] == true;
        final patchExplicitlyActivating = patch['is_active'] == true &&
            (!patch.containsKey('leaving_date') ||
                patch['leaving_date'] == null ||
                '${patch['leaving_date']}'.trim().isEmpty);
        if (patchExplicitlyActivating) {
          next['is_active'] = true;
          next['leaving_date'] = null;
          next['exit_date'] = null;
          next['exit_reason'] = '';
          if ('${next['roll_number'] ?? ''}'.trim().isEmpty &&
              '${old['previous_roll_number'] ?? ''}'.trim().isNotEmpty) {
            next['roll_number'] = '${old['previous_roll_number']}'.trim();
          }
        } else {
          final leavingRaw = '${next['leaving_date'] ?? ''}'.trim();
          final todayIso = SupabaseClient._indiaTodayIso();
          final leftByDate = leavingRaw.length >= 10 &&
              leavingRaw.substring(0, 10).compareTo(todayIso) <= 0;
          final nowActive = (next['is_active'] == true) && !leftByDate;
          if (!nowActive) {
            next['is_active'] = false;
            next['exit_date'] ??=
                (leavingRaw.isNotEmpty ? leavingRaw : todayIso);
            next['leaving_date'] ??= next['exit_date'];
            if ('${next['exit_reason'] ?? ''}'.trim().isEmpty) {
              next['exit_reason'] = 'other';
            }
            if ('${old['roll_number'] ?? ''}'.trim().isNotEmpty) {
              next['previous_roll_number'] = '${old['roll_number']}'.trim();
            }
            next['roll_number'] = '';
          } else if (!wasActive && nowActive) {
            next['exit_date'] = null;
            next['leaving_date'] = null;
            next['exit_reason'] = '';
          }
        }
      }

      final rowHashKey = '$_table/$docId';
      final newSig = _canonicalRowSignature(next);
      if (_lastWrittenPayloadHash[rowHashKey] != newSig) {
        batch.set(col.doc(docId), next, fs.SetOptions(merge: true));
        _lastWrittenPayloadHash[rowHashKey] = newSig;
        ops++;
      }
      updatedRows.add(next);
      if (ops >= 400) {
        await batch.commit();
        batch = _client._db.batch();
        ops = 0;
      }
    }

    if (ops > 0) {
      await batch.commit();
    }
    if (_table == 'attendance_days' ||
        _table == 'school_settings' ||
        _table == 'student_subject_marks' ||
        _table == 'student_result_profiles' ||
        _table == 'student_private_details') {
      patchCacheRows(_table, updatedRows);
    } else {
      invalidateCache(_table);
    }
    final studentRollAffectingChange = _table == 'students' &&
        (patch.containsKey('roll_number') ||
            patch.containsKey('class_id') ||
            patch.containsKey('is_active') ||
            patch.containsKey('leaving_date') ||
            patch.containsKey('exit_date'));
    if (studentRollAffectingChange) {
      final affectedClasses = <String>{};
      for (final r in updatedRows) {
        final sRef = '${r['school_ref'] ?? ''}'.trim();
        final cId = '${r['class_id'] ?? ''}'.trim();
        if (sRef.isNotEmpty && cId.isNotEmpty) {
          affectedClasses.add('$sRef|$cId');
        }
      }
      for (final key in affectedClasses) {
        final parts = key.split('|');
        await _client._renumberActiveClassStudentsContinually(
          schoolRef: parts[0],
          classId: parts[1],
        );
      }
    } else if (_table == 'school_classes') {
      for (final r in updatedRows) {
        if (r['is_active'] == true) {
          await _client._seedSubjectsForClassRow(r);
        }
      }
    } else if (_table == 'school_subject_master') {
      for (final r in updatedRows) {
        await _client._syncMasterSubjectRowToClasses(r);
      }
    }
    return updatedRows;
  }

  Future<List<Map<String, dynamic>>> _executeDelete() async {
    await _client._requireSchoolWriteAccess(
      explicitSchoolRef: '${_eqFilters['school_ref'] ?? ''}',
    );
    final matching = await _executeSelect();
    if (matching.isEmpty) return <Map<String, dynamic>>[];

    final col = _client._db.collection(_table);
    var batch = _client._db.batch();
    var ops = 0;
    for (final row in matching) {
      final docId = '${row['id']}';
      if (docId.isEmpty) continue;
      batch.delete(col.doc(docId));
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _client._db.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
    invalidateCache(_table);
    if (_table == 'students') {
      final affectedClasses = <String>{};
      for (final r in matching) {
        final sRef = '${r['school_ref'] ?? ''}'.trim();
        final cId = '${r['class_id'] ?? ''}'.trim();
        if (sRef.isNotEmpty && cId.isNotEmpty) {
          affectedClasses.add('$sRef|$cId');
        }
      }
      for (final key in affectedClasses) {
        final parts = key.split('|');
        await _client._renumberActiveClassStudentsContinually(
          schoolRef: parts[0],
          classId: parts[1],
        );
      }
    }
    return matching;
  }
}

class _TeacherSessionContext {
  final String authUserId;
  final String teacherId;
  final String teacherName;
  final String schoolRef;
  final String role;
  final List<String> allowedClasses;
  final Map<String, dynamic> schoolRow;

  /// Class ids where this teacher may record attendance: every section of
  /// the standard(s) of the classes assigned by the admin or where the
  /// teacher is class teacher (e.g. 6A teacher → 6A, 6B, 6C, 6D).
  final Set<String> attendanceClassIds;

  /// class id → lower-case subject names the teacher teaches there.
  final Map<String, Set<String>> subjectsByClass;

  /// Classes where the teacher is the designated class teacher.
  final Set<String> classTeacherClassIds;

  const _TeacherSessionContext({
    required this.authUserId,
    required this.teacherId,
    required this.teacherName,
    required this.schoolRef,
    required this.role,
    required this.allowedClasses,
    required this.schoolRow,
    this.attendanceClassIds = const <String>{},
    this.subjectsByClass = const <String, Set<String>>{},
    this.classTeacherClassIds = const <String>{},
  });

  bool canRecordAttendance(String classId) =>
      isAdmin || attendanceClassIds.contains(classId.trim());

  /// Only School Admin and the designated Class Teacher of [classId] may add
  /// or deactivate students in [classId] (never Subject Teachers).
  bool canManageClassStudents(String classId) =>
      isAdmin || classTeacherClassIds.contains(classId.trim());

  /// Admin: every class. Class teacher: every subject of their own class.
  /// Subject teacher: only the subjects they teach in other classes.
  bool canEnterMarks(String classId, String subjectName) {
    if (isAdmin) return true;
    final cid = classId.trim();
    if (classTeacherClassIds.contains(cid)) return true;
    final taught = subjectsByClass[cid];
    return taught != null && taught.contains(subjectName.trim().toLowerCase());
  }

  bool get isAdmin {
    final r = role.trim().toLowerCase();
    return r == 'admin' || r == 'developer';
  }

  static String _cleanClassToken(String v) => v
      .replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '');

  bool canAccessClassIdOrKey(String candidate) {
    if (isAdmin) return true;
    final cleanCandidate = _cleanClassToken(candidate);
    if (cleanCandidate.isEmpty) return false;
    return allowedClasses.any((c) => _cleanClassToken(c) == cleanCandidate);
  }

  bool canAccessClassRow(Map<String, dynamic> classRow) {
    if (isAdmin) return true;
    if (classRow['is_active'] == false) return false;
    final tokens = <String>[
      '${classRow['id'] ?? ''}',
      '${classRow['class_key'] ?? ''}',
      '${classRow['label'] ?? ''}',
      '${classRow['sheet_name'] ?? ''}',
    ];
    for (final t in tokens) {
      if (t.trim().isNotEmpty && canAccessClassIdOrKey(t)) return true;
    }
    return false;
  }
}

class SupabaseClient {
  SupabaseClient._() {
    auth = FirestoreAuthClient(this);
    functions = FirestoreFunctionsClient(this);
    storage = FirestoreStorageClient(this);
  }

  late final FirestoreAuthClient auth;
  late final FirestoreFunctionsClient functions;
  late final FirestoreStorageClient storage;

  fs.FirebaseFirestore get _db => fs.FirebaseFirestore.instance;

  _TeacherSessionContext? _cachedContext;
  String? _cachedContextUid;
  DateTime? _cachedContextTime;
  _TeacherSessionContext? _developerImpersonatedContext;
  Map<String, dynamic>? _developerImpersonatedProfile;

  bool get isDeveloperImpersonatingSchool =>
      _developerImpersonatedContext != null;

  Map<String, dynamic>? get developerImpersonatedProfile =>
      _developerImpersonatedProfile;

  void activateDeveloperSchoolAdminSession(Map<String, dynamic> sessionPayload) {
    final school = sessionPayload['school'] is Map
        ? Map<String, dynamic>.from(sessionPayload['school'] as Map)
        : <String, dynamic>{};
    final profile = sessionPayload['profile'] is Map
        ? Map<String, dynamic>.from(sessionPayload['profile'] as Map)
        : <String, dynamic>{};
    final schoolRef = '${school['id'] ?? profile['school_ref'] ?? ''}'.trim();
    final teacherId =
        '${profile['teacher_id'] ?? school['admin_id'] ?? 'dev_admin_$schoolRef'}'
            .trim();
    final teacherName =
        '${profile['teacher_name'] ?? school['admin_name'] ?? 'School Admin (Developer)'}'
            .trim();
    _developerImpersonatedContext = _TeacherSessionContext(
      authUserId: 'dev_impersonate_${schoolRef}_$teacherId',
      teacherId: teacherId,
      teacherName: teacherName,
      schoolRef: schoolRef,
      role: 'admin',
      allowedClasses: const <String>[],
      schoolRow: school,
    );
    _developerImpersonatedProfile = <String, dynamic>{
      ...profile,
      'is_developer_session': true,
    };
    _clearIdentityCache();
    FirestoreQueryBuilder.clearAllForSessionChange();
  }

  void deactivateDeveloperSchoolAdminSession() {
    _developerImpersonatedContext = null;
    _developerImpersonatedProfile = null;
    _clearIdentityCache();
    FirestoreQueryBuilder.clearAllForSessionChange();
  }

  void _clearIdentityCache() {
    _cachedContext = null;
    _cachedContextUid = null;
    _cachedContextTime = null;
  }

  static String _generateUuid() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  static DateTime _indiaNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  static String _toFirebasePassword(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 6) return trimmed;
    return 'psm#${trimmed}#key';
  }

  static String _indiaTodayIso() {
    final now = _indiaNow();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _indiaDayEndIso() {
    final today = _indiaTodayIso();
    return DateTime.parse('${today}T23:59:59.999+05:30')
        .toUtc()
        .toIso8601String();
  }

  Future<_TeacherSessionContext?> _resolveCurrentTeacherContext({
    bool forceRefresh = false,
  }) async {
    final imp = _developerImpersonatedContext;
    if (imp != null) {
      if (forceRefresh) {
        try {
          final schoolSnap =
              await _db.collection('schools').doc(imp.schoolRef).get();
          if (schoolSnap.exists && schoolSnap.data() != null) {
            final updatedSchool = <String, dynamic>{
              ...schoolSnap.data()!,
              'id': schoolSnap.data()!['id'] ?? schoolSnap.id,
            };
            _developerImpersonatedContext = _TeacherSessionContext(
              authUserId: imp.authUserId,
              teacherId: imp.teacherId,
              teacherName: imp.teacherName,
              schoolRef: imp.schoolRef,
              role: 'admin',
              allowedClasses: imp.allowedClasses,
              schoolRow: updatedSchool,
            );
          }
        } catch (_) {}
      }
      return _developerImpersonatedContext;
    }
    final user = auth.currentUser;
    if (user == null) {
      _clearIdentityCache();
      return null;
    }
    if (!forceRefresh &&
        _cachedContext != null &&
        _cachedContextUid == user.id &&
        _cachedContextTime != null &&
        DateTime.now().difference(_cachedContextTime!).inSeconds < 300) {
      return _cachedContext;
    }

    if (_cachedContextUid != null && _cachedContextUid != user.id) {
      // A different account signed in without an explicit logout.
      FirestoreQueryBuilder.clearAllForSessionChange();
    }
    final snap = await _db
        .collection('school_teachers')
        .where('auth_user_id', isEqualTo: user.id)
        .get();
    Map<String, dynamic>? teacherRow;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['is_active'] == true) {
        teacherRow = <String, dynamic>{...d, 'id': d['id'] ?? doc.id};
        break;
      }
    }
    if (teacherRow == null) {
      _clearIdentityCache();
      return null;
    }

    final schoolRef = '${teacherRow['school_ref'] ?? ''}'.trim();
    if (schoolRef.isEmpty) {
      _clearIdentityCache();
      return null;
    }

    final schoolSnap = await _db.collection('schools').doc(schoolRef).get();
    Map<String, dynamic>? schoolRow;
    if (schoolSnap.exists && schoolSnap.data() != null) {
      schoolRow = <String, dynamic>{
        ...schoolSnap.data()!,
        'id': schoolSnap.data()!['id'] ?? schoolSnap.id,
      };
    } else {
      final q = await _db
          .collection('schools')
          .where('id', isEqualTo: schoolRef)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        schoolRow = <String, dynamic>{
          ...q.docs.first.data(),
          'id': q.docs.first.data()['id'] ?? q.docs.first.id,
        };
      }
    }
    if (schoolRow == null || schoolRow['is_active'] != true) {
      _clearIdentityCache();
      return null;
    }

    final validity = '${schoolRow['validity_date'] ?? ''}'.trim();
    if (validity.length >= 10 &&
        validity.substring(0, 10).compareTo(_indiaTodayIso()) < 0) {
      _clearIdentityCache();
      return null;
    }

    final rawAllowed = teacherRow['allowed_classes'];
    final allowed = rawAllowed is List
        ? rawAllowed.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final tId = '${teacherRow['id']}'.trim();
    final attendanceIds = <String>{};
    final classTeacherIds = <String>{};
    final subjectsByClass = <String, Set<String>>{};
    if (tId.isNotEmpty && '${teacherRow['role'] ?? 'teacher'}'.toLowerCase() != 'admin') {
      try {
        final assignSnap = await _db
            .collection('teacher_subject_assignments')
            .where('teacher_id', isEqualTo: tId)
            .get();
        for (final d in assignSnap.docs) {
          final data = d.data();
          if ('${data['school_ref'] ?? ''}' != schoolRef) continue;
          final cid = '${data['class_id'] ?? ''}'.trim();
          final subj = '${data['subject_name'] ?? ''}'.trim().toLowerCase();
          if (cid.isEmpty) continue;
          subjectsByClass.putIfAbsent(cid, () => <String>{});
          if (subj.isNotEmpty) subjectsByClass[cid]!.add(subj);
        }
        final clsSnap = await _db
            .collection('school_classes')
            .where('school_ref', isEqualTo: schoolRef)
            .get();
        final classRows = [
          for (final cd in clsSnap.docs)
            <String, dynamic>{...cd.data(), 'id': '${cd.data()['id'] ?? cd.id}'.trim()},
        ];
        String token(String v) => _TeacherSessionContext._cleanClassToken(v);
        final allowedTokens = allowed.map(token).toSet();
        final ownStandards = <String>{};
        for (final c in classRows) {
          final cid = '${c['id']}';
          final direct = <String>[cid, '${c['class_key'] ?? ''}', '${c['label'] ?? ''}']
              .any((t) => t.trim().isNotEmpty && allowedTokens.contains(token(t)));
          final explicitCt = '${c['class_teacher_id'] ?? ''}'.trim();
          final isClassTeacher = explicitCt.isNotEmpty
              ? explicitCt == tId
              : direct;
          if (isClassTeacher) classTeacherIds.add(cid);
          if (direct || isClassTeacher) {
            attendanceIds.add(cid);
            final std = _classStandardKey(c);
            if (std.isNotEmpty) ownStandards.add(std);
          }
        }
        // Same standard, any section (6A → 6B, 6C, 6D ...).
        for (final c in classRows) {
          if (c['is_active'] == false) continue;
          final std = _classStandardKey(c);
          if (std.isNotEmpty && ownStandards.contains(std)) {
            attendanceIds.add('${c['id']}');
          }
        }
        // Visible classes = attendance classes + classes where a subject is
        // taught (results). Attendance writes are checked separately.
        final visible = <String>{...attendanceIds, ...subjectsByClass.keys};
        for (final c in classRows) {
          final cid = '${c['id']}';
          if (!visible.contains(cid)) continue;
          for (final t in <String>[cid, '${c['class_key'] ?? ''}'.trim(), '${c['label'] ?? ''}'.trim()]) {
            if (t.isNotEmpty && !allowed.contains(t)) allowed.add(t);
          }
        }
      } catch (_) {}
    }

    final ctx = _TeacherSessionContext(
      authUserId: user.id,
      teacherId: '${teacherRow['id']}',
      teacherName: '${teacherRow['teacher_name'] ?? ''}',
      schoolRef: schoolRef,
      role: '${teacherRow['role'] ?? 'teacher'}',
      allowedClasses: allowed,
      schoolRow: schoolRow,
      attendanceClassIds: attendanceIds,
      subjectsByClass: subjectsByClass,
      classTeacherClassIds: classTeacherIds,
    );
    _cachedContext = ctx;
    _cachedContextUid = user.id;
    _cachedContextTime = DateTime.now();

    auth._cachedAppMetadata = <String, dynamic>{
      ...auth._cachedAppMetadata,
      'psm_school_id': '${schoolRow['school_id'] ?? ''}',
      'psm_school_ref': schoolRef,
      'psm_teacher_id': ctx.teacherId,
      'psm_role': ctx.role,
    };

    return ctx;
  }

  static String _canonicalAttendancePermissionMode(dynamic raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase();
    switch (s) {
      case 'only_class_teacher':
      case 'class_teacher_only':
        return 'only_class_teacher';
      case 'section_wise_class_teachers':
      case 'same_standard_class_teachers':
      case 'section_wise':
        return 'section_wise_class_teachers';
      case 'any_teacher_all_classes':
      case 'all_teachers_all_classes':
      case 'any_teacher':
        return 'any_teacher_all_classes';
      case 'subject_and_class_teachers':
      default:
        return 'subject_and_class_teachers';
    }
  }

  /// Computes which active classes the signed-in user may record student
  /// attendance (with PM POSHAN & Breakfast) for on [targetDateIso], honoring:
  /// 1. Admin always has access to all classes.
  /// 2. The school's `attendance_recording_permission_mode` in `school_settings.config`:
  ///    - `only_class_teacher`
  ///    - `section_wise_class_teachers` (e.g. 6A class teacher -> 6A, 6B, 6C, 6D...)
  ///    - `subject_and_class_teachers` (default / current)
  ///    - `any_teacher_all_classes`
  /// 3. Leave In-Charge logic across modes 1, 2, and 3: when a teacher is on
  ///    leave (`start_date <= date <= end_date`, status != rejected/cancelled),
  ///    the designated `charge_teacher_id` can record attendance for that
  ///    on-leave teacher's classes during the leave period only.
  Future<Map<String, dynamic>> _computeAttendanceEntryAccessForDate({
    required _TeacherSessionContext ctx,
    String? targetDateIso,
  }) async {
    final rawDate = (targetDateIso ?? '').trim();
    final parsedDate = _parseAnyDateToIso(rawDate) ?? rawDate;
    final effectiveDate = parsedDate.length >= 10
        ? parsedDate.substring(0, 10)
        : _indiaTodayIso();
    final schoolRef = ctx.schoolRef.trim();

    String mode = 'subject_and_class_teachers';
    try {
      final settingsData = await _cachedDocData('school_settings', schoolRef);
      final cfg = settingsData?['config'];
      if (cfg is Map) {
        mode = _canonicalAttendancePermissionMode(
          cfg['attendance_recording_permission_mode'],
        );
      }
    } catch (_) {}

    final clsRows = await _cachedSchoolTableRows('school_classes', schoolRef);
    final allClasses = <Map<String, dynamic>>[];
    final classById = <String, Map<String, dynamic>>{};
    for (final data in clsRows) {
      if (data['is_active'] == false) continue;
      final cid = '${data['id'] ?? ''}'.trim();
      if (cid.isEmpty) continue;
      final row = <String, dynamic>{...data, 'id': cid};
      allClasses.add(row);
      classById[cid] = row;
    }

    if (ctx.isAdmin) {
      final allIds = allClasses.map((c) => '${c['id']}').toList();
      return <String, dynamic>{
        'permission_mode': mode,
        'attendance_date': effectiveDate,
        'classes': allClasses,
        'allowed_class_ids': allIds,
        'class_teacher_ids': allIds,
        'role_by_class_id': <String, String>{
          for (final id in allIds) id: 'admin',
        },
        'in_charge_info_by_class_id': <String, Map<String, dynamic>>{},
      };
    }

    // Load school teachers, subject assignments, and leaves via shared 15-min memory cache
    final results = await Future.wait([
      _cachedSchoolTableRows('school_teachers', schoolRef),
      _cachedSchoolTableRows('teacher_subject_assignments', schoolRef),
      _cachedSchoolTableRows('teacher_leaves', schoolRef),
    ]);

    final teacherRows = results[0];
    final assignRows = results[1];
    final leaveRows = results[2];

    final teachersById = <String, Map<String, dynamic>>{};
    for (final data in teacherRows) {
      final tid = '${data['id'] ?? ''}'.trim();
      if (tid.isEmpty) continue;
      teachersById[tid] = <String, dynamic>{...data, 'id': tid};
    }

    final subjectClassesByTeacher = <String, Set<String>>{};
    for (final data in assignRows) {
      final tid = '${data['teacher_id'] ?? ''}'.trim();
      final cid = '${data['class_id'] ?? ''}'.trim();
      if (tid.isEmpty || cid.isEmpty || !classById.containsKey(cid)) continue;
      subjectClassesByTeacher.putIfAbsent(tid, () => <String>{}).add(cid);
    }

    final anyExplicitClassTeacherInSchool = allClasses.any(
      (c) => '${c['class_teacher_id'] ?? ''}'.trim().isNotEmpty,
    );

    String cleanToken(String v) => _TeacherSessionContext._cleanClassToken(v);

    ({
      Set<String> ctIds,
      Set<String> sectionIds,
      Set<String> subjectIds,
      Set<String> eligibleIds,
    }) computeForTeacher(String tid) {
      final tRow = teachersById[tid];
      final rawAllowed = tRow?['allowed_classes'];
      final allowedTokens = rawAllowed is List
          ? rawAllowed
                .map((e) => cleanToken('$e'))
                .where((s) => s.isNotEmpty)
                .toSet()
          : <String>{};

      final explicitCtIds = <String>{};
      final directAllowedClassIds = <String>{};
      for (final c in allClasses) {
        final cid = '${c['id']}';
        final ct = '${c['class_teacher_id'] ?? ''}'.trim();
        if (ct.isNotEmpty && ct == tid) {
          explicitCtIds.add(cid);
        }
        final matchesAllowed = <String>[
          cid,
          '${c['class_key'] ?? ''}',
          '${c['label'] ?? ''}',
          '${c['sheet_name'] ?? ''}',
        ].any((t) => t.trim().isNotEmpty && allowedTokens.contains(cleanToken(t)));
        if (matchesAllowed) {
          directAllowedClassIds.add(cid);
        }
      }

      // If this teacher has explicit class_teacher_id assignments, use those
      // strictly as their Class Teacher classes. Otherwise fall back to unowned
      // direct allowed classes if no explicit class teacher is set on them.
      final ctIds = <String>{...explicitCtIds};
      if (ctIds.isEmpty && !anyExplicitClassTeacherInSchool) {
        for (final cid in directAllowedClassIds) {
          final c = classById[cid];
          if (c != null && '${c['class_teacher_id'] ?? ''}'.trim().isEmpty) {
            ctIds.add(cid);
          }
        }
      }

      // Section-wise classes: all active sections of any standard where [tid]
      // is a Class Teacher (e.g. Class Teacher of 6A -> 6A, 6B, 6C, 6D...).
      final ctStandards = <String>{
        for (final cid in ctIds)
          if (classById[cid] != null) _classStandardKey(classById[cid]!),
      }..remove('');

      final sectionIds = <String>{};
      for (final c in allClasses) {
        final cid = '${c['id']}';
        final std = _classStandardKey(c);
        if (std.isNotEmpty && ctStandards.contains(std)) {
          sectionIds.add(cid);
        }
      }

      // Subject teacher classes: classes from teacher_subject_assignments + allowed_classes
      final assignedSubjIds = subjectClassesByTeacher[tid] ?? const <String>{};
      final subjectIds = <String>{
        ...assignedSubjIds,
        ...directAllowedClassIds,
      };
      // In subject_and_class_teachers mode, also include same-standard sections of direct allowed classes (matching prior behavior)
      final subjectAndSectionIds = <String>{...subjectIds};
      final directStandards = <String>{
        for (final cid in directAllowedClassIds)
          if (classById[cid] != null) _classStandardKey(classById[cid]!),
      }..remove('');
      for (final c in allClasses) {
        final std = _classStandardKey(c);
        if (std.isNotEmpty && directStandards.contains(std)) {
          subjectAndSectionIds.add('${c['id']}');
        }
      }

      final Set<String> eligibleIds;
      switch (mode) {
        case 'only_class_teacher':
          eligibleIds = <String>{...ctIds};
          break;
        case 'section_wise_class_teachers':
          eligibleIds = <String>{...ctIds, ...sectionIds};
          break;
        case 'any_teacher_all_classes':
          eligibleIds = <String>{for (final c in allClasses) '${c['id']}'};
          break;
        case 'subject_and_class_teachers':
        default:
          eligibleIds = <String>{
            ...ctIds,
            ...sectionIds,
            ...subjectAndSectionIds,
          };
          break;
      }

      return (
        ctIds: ctIds,
        sectionIds: sectionIds,
        subjectIds: subjectIds,
        eligibleIds: eligibleIds,
      );
    }

    final myId = ctx.teacherId.trim();
    final myNameLower = ctx.teacherName.trim().toLowerCase();
    final mySets = computeForTeacher(myId);

    // Check active leaves on [effectiveDate] where current teacher is In-Charge
    // (including transitive chain in-charge: if A gave charge to B, and B went
    // on leave and gave charge to C, then C gets C's own classes + B's classes + A's classes).
    final inChargeClassIds = <String>{};
    final inChargeInfoByClassId = <String, Map<String, dynamic>>{};

    final activeLeavesOnDate = <Map<String, dynamic>>[];
    for (final l in leaveRows) {
      final status = '${l['status'] ?? 'pending'}'.trim().toLowerCase();
      if (status == 'rejected' || status == 'cancelled') continue;

      final startIso = _extractIndiaDateIsoFromAny(l['start_date']);
      final endIso = _extractIndiaDateIsoFromAny(l['end_date']);
      if (startIso.isEmpty || endIso.isEmpty) continue;
      if (effectiveDate.compareTo(startIso) < 0 ||
          effectiveDate.compareTo(endIso) > 0) {
        continue;
      }
      activeLeavesOnDate.add(l);
    }

    String resolveChargeTeacherId(Map<String, dynamic> l) {
      final leaveData = l['leave_data'] is Map
          ? Map<String, dynamic>.from(l['leave_data'] as Map)
          : <String, dynamic>{};
      final cid =
          '${leaveData['charge_teacher_id'] ?? l['charge_teacher_id'] ?? ''}'
              .trim();
      if (cid.isNotEmpty) return cid;
      final cname =
          '${leaveData['charge_teacher_name'] ?? l['charge_teacher_name'] ?? ''}'
              .trim()
              .toLowerCase();
      if (cname.isEmpty) return '';
      if (myNameLower.isNotEmpty && cname == myNameLower) return myId;
      for (final t in teacherRows) {
        final tName = '${t['teacher_name'] ?? t['name'] ?? ''}'
            .trim()
            .toLowerCase();
        if (tName.isNotEmpty && tName == cname) {
          return '${t['id'] ?? ''}'.trim();
        }
      }
      return '';
    }

    final directLeavesByChargeTeacher = <String, List<Map<String, dynamic>>>{};
    final teachersOnLeaveToday = <String>{};
    for (final l in activeLeavesOnDate) {
      final onLeaveTid = '${l['teacher_id'] ?? ''}'.trim();
      if (onLeaveTid.isNotEmpty) teachersOnLeaveToday.add(onLeaveTid);
      final chargeTid = resolveChargeTeacherId(l);
      if (onLeaveTid.isEmpty || chargeTid.isEmpty || onLeaveTid == chargeTid) {
        continue;
      }
      directLeavesByChargeTeacher
          .putIfAbsent(chargeTid, () => <Map<String, dynamic>>[])
          .add(l);
    }

    // Only an active (non-on-leave) teacher—or a teacher who hasn't delegated
    // their own leave—receives the incoming transitive in-charge chain.
    final visitedTeachers = <String>{myId};
    final queue = <({String teacherId, List<String> viaNames})>[
      (teacherId: myId, viaNames: const <String>[]),
    ];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final incomingLeaves =
          directLeavesByChargeTeacher[current.teacherId] ??
          const <Map<String, dynamic>>[];

      for (final l in incomingLeaves) {
        final onLeaveTid = '${l['teacher_id'] ?? ''}'.trim();
        if (onLeaveTid.isEmpty || visitedTeachers.contains(onLeaveTid)) {
          continue;
        }
        visitedTeachers.add(onLeaveTid);

        final leaveData = l['leave_data'] is Map
            ? Map<String, dynamic>.from(l['leave_data'] as Map)
            : <String, dynamic>{};
        final startIso = _extractIndiaDateIsoFromAny(l['start_date']);
        final endIso = _extractIndiaDateIsoFromAny(l['end_date']);
        final onLeaveName =
            '${leaveData['teacher_name'] ?? teachersById[onLeaveTid]?['teacher_name'] ?? 'શિક્ષક'}'
                .trim();
        final displayLeaveName = current.viaNames.isEmpty
            ? onLeaveName
            : '$onLeaveName (via ${current.viaNames.join(' → ')})';

        final onLeaveSets = computeForTeacher(onLeaveTid);
        // Leave logic applies across modes 1, 2, and 3 (and highlights in mode 4):
        // the in-charge teacher gets the on-leave teacher's eligible classes
        // (always including the on-leave teacher's own Class Teacher classes).
        final coveredIds = mode == 'any_teacher_all_classes'
            ? <String>{...onLeaveSets.ctIds, ...onLeaveSets.sectionIds}
            : <String>{...onLeaveSets.ctIds, ...onLeaveSets.eligibleIds};

        for (final cid in coveredIds) {
          inChargeClassIds.add(cid);
          final isDirectCtOfOnLeave = onLeaveSets.ctIds.contains(cid);
          if (!inChargeInfoByClassId.containsKey(cid) || isDirectCtOfOnLeave) {
            inChargeInfoByClassId[cid] = <String, dynamic>{
              'on_leave_teacher_id': onLeaveTid,
              'on_leave_teacher_name': displayLeaveName,
              'start_date': startIso,
              'end_date': endIso,
              'leave_type': '${l['leave_type'] ?? ''}',
              'chain_depth': current.viaNames.length + 1,
            };
          }
        }

        queue.add((
          teacherId: onLeaveTid,
          viaNames: <String>[...current.viaNames, onLeaveName],
        ));
      }
    }

    final finalAllowedIds = <String>{
      ...mySets.eligibleIds,
      ...inChargeClassIds,
    };

    final roleByClassId = <String, String>{};
    for (final cid in finalAllowedIds) {
      if (mySets.ctIds.contains(cid)) {
        roleByClassId[cid] = 'class_teacher';
      } else if (inChargeInfoByClassId.containsKey(cid)) {
        roleByClassId[cid] = 'in_charge_teacher';
      } else if (mySets.sectionIds.contains(cid)) {
        roleByClassId[cid] = 'section_teacher';
      } else if (mySets.subjectIds.contains(cid)) {
        roleByClassId[cid] = 'subject_teacher';
      } else {
        roleByClassId[cid] = 'any_teacher';
      }
    }

    final allowedClassesList = allClasses
        .where((c) => finalAllowedIds.contains('${c['id']}'))
        .toList();

    return <String, dynamic>{
      'permission_mode': mode,
      'attendance_date': effectiveDate,
      'classes': allowedClassesList,
      'allowed_class_ids': finalAllowedIds.toList(),
      'class_teacher_ids': mySets.ctIds.toList(),
      'role_by_class_id': roleByClassId,
      'in_charge_info_by_class_id': inChargeInfoByClassId,
    };
  }

  static const List<int> _absenceMilestones = <int>[4, 7, 10, 15, 21, 30];

  static String _absenceMilestoneMessageGu(int milestone) {
    switch (milestone) {
      case 4:
        return 'આ વિદ્યાર્થી સતત ૪ દિવસથી ગેરહાજર છે. કૃપા કરીને અન્ય વિદ્યાર્થીઓને કહીને ફોન કરાવવો અથવા ગેરહાજરીનું કારણ પૂછવું.';
      case 7:
        return 'આ વિદ્યાર્થી સતત ૭ દિવસથી ગેરહાજર છે. કૃપા કરીને શિક્ષકે વિદ્યાર્થીના વાલીનો રૂબરૂ સંપર્ક કરવો.';
      case 10:
        return 'આ વિદ્યાર્થી સતત ૧૦ દિવસથી ગેરહાજર છે. કૃપા કરીને વર્ગ શિક્ષકને વિદ્યાર્થીની ગેરહાજરીનું કારણ પૂછવું.';
      case 15:
        return 'આ વિદ્યાર્થી સતત ૧૫ દિવસથી ગેરહાજર છે. કૃપા કરીને વાલીની રૂબરૂ મુલાકાત લેવી.';
      case 21:
        return 'આ વિદ્યાર્થી સતત ૨૧ દિવસથી ગેરહાજર છે. કૃપા કરીને CRC કો-ઓર્ડિનેટરને જાણ કરી આચાર્યશ્રી સાથે વાલીની રૂબરૂ મુલાકાત લેવી.';
      case 30:
        return 'આ વિદ્યાર્થી સતત ૩૦ દિવસથી ગેરહાજર છે. કૃપા કરીને SMC (શાળા વ્યવસ્થાપન સમિતિ) ને આ બાબતે જાણ કરવી.';
      default:
        return '';
    }
  }

  static bool _milestoneAppliesToRole(int milestone, String roleScope) {
    if (roleScope == 'admin') {
      return milestone == 10 ||
          milestone == 15 ||
          milestone == 21 ||
          milestone == 30;
    }
    return milestone == 4 ||
        milestone == 7 ||
        milestone == 15 ||
        milestone == 21 ||
        milestone == 30;
  }

  Future<Map<String, dynamic>> _computeStudentAbsenceStreaksAndAlerts({
    required String schoolRef,
    required _TeacherSessionContext ctx,
    String filterClassId = '',
    required String roleScope,
  }) async {
    final results = await Future.wait([
      _cachedSchoolTableRows('school_classes', schoolRef),
      _cachedSchoolTableRows('students', schoolRef),
      _cachedSchoolTableRows('attendance_days', schoolRef),
      _cachedSchoolTableRows('student_absence_alert_acks', schoolRef),
    ]);
    final classRows = results[0]
        .where((c) => c['is_active'] != false)
        .toList();
    final studentRows = results[1]
        .where(
          (s) =>
              s['is_active'] == true &&
              '${s['leaving_date'] ?? ''}'.trim().isEmpty &&
              '${s['exit_date'] ?? ''}'.trim().isEmpty,
        )
        .toList();
    final dayRows = results[2];
    final ackRows = results[3];

    final ackedSet = <String>{
      for (final a in ackRows) '${a['id'] ?? ''}'.trim(),
    };

    final classById = <String, Map<String, dynamic>>{
      for (final c in classRows) '${c['id'] ?? ''}'.trim(): c,
    };

    // Determine which classes are in scope for this user
    final allowedClassIds = <String>{};
    if (filterClassId.isNotEmpty) {
      allowedClassIds.add(filterClassId);
    } else if (ctx.isAdmin) {
      allowedClassIds.addAll(classById.keys);
    } else {
      for (final c in classRows) {
        final cid = '${c['id'] ?? ''}'.trim();
        if (ctx.classTeacherClassIds.contains(cid) ||
            ctx.canAccessClassRow(c)) {
          allowedClassIds.add(cid);
        }
      }
    }

    // Group ONLY student-wise attendance_days by class_id (strictly skip Direct Entry!)
    final studentWiseDaysByClass = <String, List<Map<String, dynamic>>>{};
    final fallbackDayIds = <String>[];
    for (final d in dayRows) {
      final cid = '${d['class_id'] ?? ''}'.trim();
      if (!allowedClassIds.contains(cid)) continue;
      final mode = '${d['attendance_mode'] ?? 'student'}'.trim().toLowerCase();
      if (mode == 'direct' || d['student_details_saved'] == false) continue;
      if (d['present_saved'] == false) continue;
      studentWiseDaysByClass
          .putIfAbsent(cid, () => <Map<String, dynamic>>[])
          .add(d);
      if (d['student_marks'] is! Map) {
        final did = '${d['id'] ?? ''}'.trim();
        if (did.isNotEmpty) fallbackDayIds.add(did);
      }
    }

    // Optional legacy fallback if any older attendance_days doc lacks embedded student_marks
    final legacyMarksByDay = <String, Map<String, bool>>{};
    if (fallbackDayIds.isNotEmpty) {
      try {
        final saRows = await _cachedSchoolTableRows(
          'student_attendance',
          schoolRef,
        );
        final wantSet = fallbackDayIds.toSet();
        for (final r in saRows) {
          final did = '${r['attendance_day_id'] ?? ''}'.trim();
          if (!wantSet.contains(did)) continue;
          final sid = '${r['student_id'] ?? ''}'.trim();
          if (sid.isEmpty) continue;
          legacyMarksByDay.putIfAbsent(did, () => <String, bool>{})[sid] =
              r['present'] == true;
        }
      } catch (_) {}
    }

    for (final list in studentWiseDaysByClass.values) {
      list.sort(
        (a, b) => '${a['attendance_date'] ?? ''}'.compareTo(
          '${b['attendance_date'] ?? ''}',
        ),
      );
    }

    final todayIso = _indiaTodayIso();
    final currentMonthPrefix = todayIso.length >= 7 ? todayIso.substring(0, 7) : '';

    final allAlerts = <Map<String, dynamic>>[];
    final dueMilestonePopups = <Map<String, dynamic>>[];

    for (final st in studentRows) {
      final cid = '${st['class_id'] ?? ''}'.trim();
      if (!allowedClassIds.contains(cid)) continue;
      final days = studentWiseDaysByClass[cid];
      if (days == null || days.isEmpty) continue;

      final sid = '${st['id'] ?? ''}'.trim();
      if (sid.isEmpty) continue;

      // Compute consecutive absent streak from most recent recorded student-wise day backward
      var streak = 0;
      var spellStartDate = '';
      var latestAbsentDate = '';

      for (var i = days.length - 1; i >= 0; i--) {
        final d = days[i];
        final did = '${d['id'] ?? ''}'.trim();
        final dDate = _extractIndiaDateIsoFromAny(d['attendance_date']);
        bool? isPresent;
        if (d['student_marks'] is Map) {
          final m = (d['student_marks'] as Map)[sid];
          if (m is Map) {
            isPresent = m['present'] == true;
          }
        } else if (legacyMarksByDay.containsKey(did) &&
            legacyMarksByDay[did]!.containsKey(sid)) {
          isPresent = legacyMarksByDay[did]![sid];
        }
        if (isPresent == null) {
          // Student was not in class roster on this day; skip
          continue;
        }
        if (isPresent == false) {
          streak++;
          if (latestAbsentDate.isEmpty) latestAbsentDate = dDate;
          spellStartDate = dDate;
        } else {
          break;
        }
      }

      // Compute current month attendance %
      var monthWorking = 0;
      var monthPresent = 0;
      var monthAbsent = 0;
      for (final d in days) {
        final dDate = _extractIndiaDateIsoFromAny(d['attendance_date']);
        if (currentMonthPrefix.isNotEmpty &&
            !dDate.startsWith(currentMonthPrefix)) {
          continue;
        }
        final did = '${d['id'] ?? ''}'.trim();
        bool? isPresent;
        if (d['student_marks'] is Map) {
          final m = (d['student_marks'] as Map)[sid];
          if (m is Map) isPresent = m['present'] == true;
        } else if (legacyMarksByDay.containsKey(did) &&
            legacyMarksByDay[did]!.containsKey(sid)) {
          isPresent = legacyMarksByDay[did]![sid];
        }
        if (isPresent == null) continue;
        monthWorking++;
        if (isPresent) {
          monthPresent++;
        } else {
          monthAbsent++;
        }
      }
      final monthPct = monthWorking > 0
          ? (monthPresent * 100.0 / monthWorking)
          : 100.0;

      final clsLabel =
          '${classById[cid]?['label'] ?? classById[cid]?['class_key'] ?? 'Class'}'
              .trim();
      final stName = '${st['name'] ?? st['name_en'] ?? 'Student'}'.trim();
      final rollNo = '${st['roll_number'] ?? ''}'.trim();
      final mobile = '${st['mobile'] ?? ''}'.trim();

      if (streak >= 3 || (monthWorking >= 3 && monthPct < 75.0)) {
        allAlerts.add(<String, dynamic>{
          'student_id': sid,
          'student_name': stName,
          'roll_number': rollNo,
          'class_id': cid,
          'class_label': clsLabel,
          'mobile': mobile,
          'consecutive_absent': streak,
          'spell_start_date': spellStartDate,
          'latest_absent_date': latestAbsentDate,
          'month_working_days': monthWorking,
          'month_present_days': monthPresent,
          'month_absent_days': monthAbsent,
          'month_percentage': double.parse(monthPct.toStringAsFixed(1)),
        });
      }

      // Exact milestone popup check (<= 30 days only; > 30 days = NO reminder!)
      if (streak >= 4 && streak <= 30 && spellStartDate.isNotEmpty) {
        // Trigger ONLY if streak matches one of the exact milestones for this role
        if (_absenceMilestones.contains(streak) &&
            _milestoneAppliesToRole(streak, roleScope)) {
          final ackKey =
              '${schoolRef}__${sid}__${spellStartDate}__${streak}__$roleScope';
          if (!ackedSet.contains(ackKey)) {
            dueMilestonePopups.add(<String, dynamic>{
              'ack_key': ackKey,
              'student_id': sid,
              'student_name': stName,
              'roll_number': rollNo,
              'class_id': cid,
              'class_label': clsLabel,
              'mobile': mobile,
              'milestone': streak,
              'spell_start_date': spellStartDate,
              'latest_absent_date': latestAbsentDate,
              'action_message_gu': _absenceMilestoneMessageGu(streak),
            });
          }
        }
      }
    }

    allAlerts.sort((a, b) {
      final sCmp = ((b['consecutive_absent'] as int?) ?? 0).compareTo(
        (a['consecutive_absent'] as int?) ?? 0,
      );
      if (sCmp != 0) return sCmp;
      return ((a['month_percentage'] as num?) ?? 100.0).compareTo(
        (b['month_percentage'] as num?) ?? 100.0,
      );
    });
    dueMilestonePopups.sort(
      (a, b) => ((b['milestone'] as int?) ?? 0).compareTo(
        (a['milestone'] as int?) ?? 0,
      ),
    );

    return <String, dynamic>{
      'alerts': allAlerts,
      'due_milestones': dueMilestonePopups,
      'month_prefix': currentMonthPrefix,
    };
  }

  Future<bool> _canTeacherRecordAttendanceForClassOnDate({
    required _TeacherSessionContext ctx,
    required String schoolRef,
    required String classId,
    required String attendanceDate,
  }) async {
    if (ctx.isAdmin) return true;
    final cleanCid = classId.trim();
    if (cleanCid.isEmpty) return false;
    final access = await _computeAttendanceEntryAccessForDate(
      ctx: ctx,
      targetDateIso: attendanceDate,
    );
    final allowed = access['allowed_class_ids'];
    if (allowed is List) {
      return allowed.map((e) => '$e'.trim()).contains(cleanCid);
    }
    return false;
  }

  /// Standard of a class row: '0' for Balvatika, '1'..'12' for a standard,
  /// '' when it cannot be determined (then only exact classes are allowed).
  static String _classStandardKey(Map<String, dynamic> c) {
    var raw = '${c['standard'] ?? c['grade'] ?? c['class_standard'] ?? ''}'.trim();
    if (raw.isEmpty) raw = '${c['label'] ?? c['class_key'] ?? ''}';
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    for (var i = 0; i < guj.length; i++) {
      raw = raw.replaceAll(guj[i], '$i');
    }
    final up = raw.toUpperCase();
    if (up.contains('BAL') || raw.contains('બાલ')) return '0';
    final m = RegExp(r'\d{1,2}').firstMatch(raw);
    return m?.group(0) ?? '';
  }

  /// Reads a school-scoped collection through the shared 15-minute query cache
  /// (`$table|school_ref=$schoolRef|in=`) so Attendance, Reports, Leave, and
  /// Result screens share a single Firestore read per session.
  Future<List<Map<String, dynamic>>> _cachedSchoolTableRows(
    String table,
    String schoolRef,
  ) async {
    final cleanRef = schoolRef.trim();
    if (cleanRef.isEmpty) return <Map<String, dynamic>>[];
    final cacheKey = '$table|school_ref=$cleanRef|in=';
    final now = DateTime.now();
    final ttlSec = FirestoreQueryBuilder._cacheTtlSecondsForTable(table);
    final cached = FirestoreQueryBuilder._queryCache[cacheKey];
    if (cached != null && now.difference(cached.ts).inSeconds < ttlSec) {
      return cached.rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }
    final gen = FirestoreQueryBuilder._generationOf(table);
    var pending = FirestoreQueryBuilder._inFlightReads[cacheKey];
    if (pending == null) {
      pending = _db
          .collection(table)
          .where('school_ref', isEqualTo: cleanRef)
          .get()
          .then((snap) => snap.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['id'] ??= doc.id;
                FirestoreQueryBuilder._applyTableSqlDefaults(table, data);
                FirestoreQueryBuilder._lastWrittenPayloadHash[
                    '$table/${doc.id}'] =
                    FirestoreQueryBuilder._canonicalRowSignature(data);
                return data;
              }).toList());
      FirestoreQueryBuilder._inFlightReads[cacheKey] = pending;
      pending.whenComplete(() {
        if (identical(FirestoreQueryBuilder._inFlightReads[cacheKey], pending)) {
          FirestoreQueryBuilder._inFlightReads.remove(cacheKey);
        }
      }).ignore();
    }
    final rows = await pending;
    if (gen == FirestoreQueryBuilder._generationOf(table)) {
      FirestoreQueryBuilder._pruneCacheIfLarge();
      FirestoreQueryBuilder._queryCache[cacheKey] = (ts: now, rows: rows);
    }
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Reads one master document through the shared query cache (same key
  /// format as direct-id selects, so table invalidation clears it too).
  Future<Map<String, dynamic>?> _cachedDocData(
    String collection,
    String docId, {
    int ttlSeconds = 600,
  }) async {
    if (docId.trim().isEmpty) return null;
    final key = '$collection|__doc__=$docId';
    final cached = FirestoreQueryBuilder._queryCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.ts).inSeconds < ttlSeconds) {
      return cached.rows.isEmpty
          ? null
          : Map<String, dynamic>.from(cached.rows.first);
    }
    final snap = await _db.collection(collection).doc(docId).get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      FirestoreQueryBuilder._queryCache[key] =
          (ts: DateTime.now(), rows: const <Map<String, dynamic>>[]);
      return null;
    }
    final row = <String, dynamic>{...data, 'id': data['id'] ?? snap.id};
    FirestoreQueryBuilder._queryCache[key] = (
      ts: DateTime.now(),
      rows: <Map<String, dynamic>>[Map<String, dynamic>.from(row)],
    );
    return row;
  }

  Future<bool> _isCurrentUserAdmin() async {
    final ctx = await _resolveCurrentTeacherContext();
    return ctx?.isAdmin == true;
  }

  Future<String> _requireSchoolReadAccess() async {
    final ctx = await _resolveCurrentTeacherContext();
    if (ctx == null || ctx.schoolRef.trim().isEmpty) {
      throw const PostgrestException(
        message: 'SCHOOL_ACCESS_DENIED: Please sign in to an active school.',
        code: '42501',
      );
    }
    return ctx.schoolRef.trim();
  }

  Future<void> _seedSubjectsForClassRow(Map<String, dynamic> classRow) async {
    try {
      final schoolRef = '${classRow['school_ref'] ?? ''}'.trim();
      final classId = '${classRow['id'] ?? ''}'.trim();
      if (schoolRef.isEmpty || classId.isEmpty) return;
      var masterRows = await from('school_subject_master')
          .select()
          .eq('school_ref', schoolRef)
          .eq('is_active', true);
      if (masterRows.isEmpty) {
        await functions._seedDefaultSubjectsAndGrades(schoolRef);
        FirestoreQueryBuilder.invalidateCache('school_subject_master');
        masterRows = await from('school_subject_master')
            .select()
            .eq('school_ref', schoolRef)
            .eq('is_active', true);
      }
      final std = _extractStandardNumber(
        '${classRow['standard'] ?? classRow['class_key'] ?? classRow['label'] ?? ''}',
      );
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final batch = _db.batch();
      for (final m in masterRows) {
        final sName = '${m['subject_name'] ?? ''}'.trim();
        if (sName.isEmpty || sName == 'વ્યક્તિત્વ વિકાસ') continue;
        final sortOrder = m['sort_order'] ?? 100;
        final csId = '${classId}__${FirestoreQueryBuilder._slug(sName)}';
        batch.set(_db.collection('class_subjects').doc(csId), <String, dynamic>{
          'id': csId,
          'school_ref': schoolRef,
          'class_id': classId,
          'subject_name': sName,
          'sort_order': sortOrder,
          'is_active': true,
          'updated_at': nowIso,
        }, fs.SetOptions(merge: true));
        if (std != null) {
          final catId =
              '${schoolRef}__${std}__${FirestoreQueryBuilder._slug(sName)}';
          batch.set(
            _db.collection('school_subject_catalog').doc(catId),
            <String, dynamic>{
              'id': catId,
              'school_ref': schoolRef,
              'standard': std,
              'subject_name': sName,
              'sort_order': sortOrder,
              'is_active': true,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
        }
      }
      await batch.commit();
      FirestoreQueryBuilder.invalidateCache('class_subjects');
      FirestoreQueryBuilder.invalidateCache('school_subject_catalog');
    } catch (_) {}
  }

  Future<void> _syncMasterSubjectRowToClasses(
    Map<String, dynamic> masterRow,
  ) async {
    try {
      final schoolRef = '${masterRow['school_ref'] ?? ''}'.trim();
      final sName = '${masterRow['subject_name'] ?? ''}'.trim();
      if (schoolRef.isEmpty || sName.isEmpty || sName == 'વ્યક્તિત્વ વિકાસ')
        return;
      final isActive = masterRow['is_active'] != false;
      final sortOrder = masterRow['sort_order'] ?? 100;
      final classes = await from('school_classes')
          .select('id,standard,class_key,label,is_active')
          .eq('school_ref', schoolRef)
          .eq('is_active', true);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final batch = _db.batch();
      for (final c in classes) {
        final cid = '${c['id'] ?? ''}'.trim();
        if (cid.isEmpty) continue;
        final csId = '${cid}__${FirestoreQueryBuilder._slug(sName)}';
        batch.set(_db.collection('class_subjects').doc(csId), <String, dynamic>{
          'id': csId,
          'school_ref': schoolRef,
          'class_id': cid,
          'subject_name': sName,
          'sort_order': sortOrder,
          'is_active': isActive,
          'updated_at': nowIso,
        }, fs.SetOptions(merge: true));
        final std = _extractStandardNumber(
          '${c['standard'] ?? c['class_key'] ?? c['label'] ?? ''}',
        );
        if (std != null) {
          final catId =
              '${schoolRef}__${std}__${FirestoreQueryBuilder._slug(sName)}';
          batch.set(
            _db.collection('school_subject_catalog').doc(catId),
            <String, dynamic>{
              'id': catId,
              'school_ref': schoolRef,
              'standard': std,
              'subject_name': sName,
              'sort_order': sortOrder,
              'is_active': isActive,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
        }
      }
      await batch.commit();
      FirestoreQueryBuilder.invalidateCache('class_subjects');
      FirestoreQueryBuilder.invalidateCache('school_subject_catalog');
    } catch (_) {}
  }

  static int? _extractStandardNumber(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = raw.trim().toLowerCase();
    for (var i = 0; i < guj.length; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    if (norm.contains('બાલ') ||
        norm.contains('વાટિકા') ||
        norm.contains('balvatika') ||
        norm.contains('balwatika') ||
        norm.contains('ankur') ||
        norm == 'bv' ||
        norm == 'kg' ||
        norm == '0') {
      return 0;
    }
    final m = RegExp(r'[1-8]').firstMatch(norm);
    return m != null ? int.tryParse(m.group(0)!) : null;
  }

  Future<String> _requireSchoolWriteAccess({
    String explicitSchoolRef = '',
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    if (ctx == null) {
      if (explicitSchoolRef.trim().isNotEmpty) {
        final sSnap = await _db
            .collection('schools')
            .doc(explicitSchoolRef.trim())
            .get();
        if (sSnap.exists && sSnap.data() != null) {
          final s = sSnap.data()!;
          if (s['is_active'] != true) {
            throw const PostgrestException(
              message: 'SCHOOL_INACTIVE: this school is deactivated',
              code: '42501',
            );
          }
          if (s['is_blocked'] == true) {
            throw const PostgrestException(
              message: 'SCHOOL_READ_ONLY_BLOCKED: this school is blocked; reports may be downloaded but data cannot be changed',
              code: '42501',
            );
          }
          return explicitSchoolRef.trim();
        }
      }
      throw const PostgrestException(
        message: 'SCHOOL_ACCESS_DENIED: Please sign in to an active school.',
        code: '42501',
      );
    }

    final school =
        (await _cachedDocData('schools', ctx.schoolRef, ttlSeconds: 60)) ??
            ctx.schoolRow;
    if (school['is_active'] != true) {
      throw const PostgrestException(
        message: 'SCHOOL_INACTIVE: this school is deactivated',
        code: '42501',
      );
    }
    final validity = '${school['validity_date'] ?? ''}'.trim();
    if (validity.length >= 10 &&
        validity.substring(0, 10).compareTo(_indiaTodayIso()) < 0) {
      throw const PostgrestException(
        message: 'SCHOOL_EXPIRED: school validity has expired',
        code: '42501',
      );
    }
    if (school['is_blocked'] == true) {
      throw const PostgrestException(
        message: 'SCHOOL_READ_ONLY_BLOCKED: reports may be downloaded, but school data cannot be changed',
        code: '42501',
      );
    }
    return ctx.schoolRef;
  }

  Future<void> _normalizeStudentRowOnWrite(
    Map<String, dynamic> row,
    String schoolRef,
  ) async {
    final ctx = await _resolveCurrentTeacherContext();
    final rowClassId = '${row['class_id'] ?? ''}'.trim();
    if (ctx != null &&
        rowClassId.isNotEmpty &&
        !ctx.canManageClassStudents(rowClassId)) {
      throw const PostgrestException(
        message:
            'માત્ર જે-તે વર્ગના વર્ગ શિક્ષક (Class Teacher) અથવા School Admin જ આ વર્ગમાં વિદ્યાર્થી ઉમેરી કે સુધારી શકે છે. વિષય શિક્ષક (Subject Teacher) વિદ્યાર્થી ઉમેરી શકતા નથી.',
        code: '42501',
      );
    }
    final schoolType = '${ctx?.schoolRow['school_type'] ?? 'mixed'}'
        .trim()
        .toLowerCase();
    final rawGender = '${row['gender'] ?? ''}'.trim().toUpperCase();
    if (schoolType == 'boys') {
      row['gender'] = 'BOYS';
    } else if (schoolType == 'girls') {
      row['gender'] = 'GIRLS';
    } else {
      if (rawGender != 'BOYS' && rawGender != 'GIRLS') {
        throw const PostgrestException(
          message: 'For a co-educational school, choose BOYS or GIRLS.',
          code: '23514',
        );
      }
      row['gender'] = rawGender;
    }

    final rawCat = '${row['category'] ?? 'OTHER'}'.trim().toUpperCase();
    row['category'] =
        const <String>{'SC', 'ST', 'OBC', 'OTHER'}.contains(rawCat)
        ? rawCat
        : 'OTHER';
    row['is_active'] ??= true;
    row['is_divyang'] ??= false;
    String normYesNo(dynamic v, {String def = 'NO'}) {
      final s = '${v ?? ''}'.trim().toUpperCase();
      if (s.isEmpty) return def;
      if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(s) ||
          s.startsWith('YES') ||
          s.startsWith('હા')) {
        return 'YES';
      }
      return 'NO';
    }
    row['has_aadhaar'] = normYesNo(row['has_aadhaar'], def: 'NO');
    row['ration_card_kyc'] = normYesNo(row['ration_card_kyc'], def: 'NO');
    if (row.containsKey('scholarship_done') &&
        '${row['scholarship_done'] ?? ''}'.trim().isNotEmpty) {
      final sd = normYesNo(row['scholarship_done'], def: 'NO');
      row['scholarship_done'] = sd;
      if (sd == 'YES') {
        row['scholarship_reason'] = '';
      }
    }
  }

  Future<void> _enforceAttendanceWriteGuard({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String schoolRef,
    required _TeacherSessionContext? ctx,
  }) async {
    if (rows.isEmpty) return;
    final first = rows.first;
    String attendanceDate = '${first['attendance_date'] ?? ''}'.trim();
    String classId = '${first['class_id'] ?? ''}'.trim();
    Map<String, dynamic>? existingDay;
    if (table == 'student_attendance' || attendanceDate.isEmpty) {
      final dayId = '${first['attendance_day_id'] ?? ''}'.trim();
      if (dayId.isNotEmpty) {
        final dayRow = await from('attendance_days')
            .select('id,class_id,attendance_date,school_ref,is_frozen,unfrozen_by_admin,present_frozen,mdm_frozen,breakfast_frozen')
            .eq('id', dayId)
            .maybeSingle();
        if (dayRow == null) {
          throw const PostgrestException(
            message: 'ATTENDANCE_DAY_MISSING: attendance day not found',
            code: '23503',
          );
        }
        existingDay = dayRow;
        attendanceDate = '${dayRow['attendance_date'] ?? ''}'.trim();
        if (classId.isEmpty) classId = '${dayRow['class_id'] ?? ''}'.trim();
      }
    } else if (table == 'attendance_days' &&
        classId.isNotEmpty &&
        attendanceDate.isNotEmpty) {
      existingDay = await from('attendance_days')
          .select('id,class_id,attendance_date,school_ref,is_frozen,unfrozen_by_admin,present_frozen,mdm_frozen,breakfast_frozen')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_date', attendanceDate)
          .maybeSingle();
    }
    if (attendanceDate.isEmpty) {
      throw const PostgrestException(
        message: 'ATTENDANCE_DATE_REQUIRED: attendance date is missing',
        code: '23502',
      );
    }
    if (ctx != null && !ctx.isAdmin && classId.isNotEmpty) {
      final canRecord = await _canTeacherRecordAttendanceForClassOnDate(
        ctx: ctx,
        schoolRef: schoolRef,
        classId: classId,
        attendanceDate: attendanceDate,
      );
      if (!canRecord) {
        throw const PostgrestException(
          message:
              'તમને આ તારીખે આ વર્ગની હાજરી પૂરવાની પરવાનગી નથી (અથવા રજાનો ચાર્જ સમયગાળો પૂર્ણ થઈ ગયો છે). School Admin નો સંપર્ક કરો.',
          code: '42501',
        );
      }
    }

    final today = _indiaTodayIso();
    if (attendanceDate.compareTo(today) > 0) {
      throw const PostgrestException(
        message: 'FUTURE_ATTENDANCE_FORBIDDEN: attendance cannot be entered for a future date',
        code: '22007',
      );
    }

    final isAdmin = ctx?.isAdmin == true;
    final hasStepFreezeFlags = existingDay != null &&
        (existingDay['present_frozen'] != null ||
            existingDay['mdm_frozen'] != null ||
            existingDay['breakfast_frozen'] != null);
    final allStepsFrozen = hasStepFreezeFlags
        ? (existingDay['present_frozen'] == true &&
            existingDay['mdm_frozen'] == true &&
            existingDay['breakfast_frozen'] == true)
        : (existingDay != null && existingDay['is_frozen'] == true);
    final isFrozen = existingDay != null &&
        existingDay['is_frozen'] == true &&
        allStepsFrozen;
    final unfrozenByAdmin = existingDay != null &&
        existingDay['unfrozen_by_admin'] == true &&
        !isFrozen;

    if (!isAdmin && isFrozen) {
      throw const PostgrestException(
        message:
            'ATTENDANCE_FROZEN: આ તારીખની હાજરી સબમિટ થઈ ગઈ છે અને ફ્રીઝ (Freeze) થઈ ગઈ છે. સુધારો કરવા માટે School Admin પાસેથી Unfreeze કરાવો.',
        code: '42501',
      );
    }

    if (!isAdmin && !unfrozenByAdmin && attendanceDate.compareTo(today) < 0) {
      throw const PostgrestException(
        message: 'Teachers cannot change attendance for a previous date. Contact the School Admin.',
        code: '42501',
      );
    }

    // Teachers may record or correct attendance at any time during the current
    // India calendar day. Older dates remain protected and require an Admin
    // unfreeze/override through the existing controls below.

    // Check Sunday / declared holiday / previous-date Admin override
    final parsedDate = DateTime.tryParse(attendanceDate);
    final isSunday =
        parsedDate != null && parsedDate.weekday == DateTime.sunday;
    final holidayRow = await from('school_holidays')
        .select('reason')
        .eq('school_ref', schoolRef)
        .eq('holiday_date', attendanceDate)
        .maybeSingle();
    final isHoliday = holidayRow != null;

    final isExcelBulkUpload = first['uploaded_from_excel'] == true;
    if (isAdmin && isExcelBulkUpload) {
      final sDoc = await _db.collection('schools').doc(schoolRef).get();
      final sData = sDoc.data() ?? const <String, dynamic>{};
      final enabled = sData['prev_attendance_upload_enabled'] == true;
      final expStr = '${sData['prev_attendance_upload_expires_at'] ?? ''}'.trim();
      final expDt = DateTime.tryParse(expStr)?.toUtc();
      if (enabled && expDt != null && DateTime.now().toUtc().isBefore(expDt)) {
        return;
      }
    }

    if (isSunday || isHoliday || attendanceDate.compareTo(today) < 0) {
      bool hasOverride = unfrozenByAdmin;
      if (isAdmin && ctx != null) {
        final ovId = '${schoolRef}__${ctx.authUserId}__$attendanceDate';
        final ovSnap = await _db
            .collection('attendance_admin_overrides')
            .doc(ovId)
            .get();
        if (ovSnap.exists && ovSnap.data() != null) {
          final until = '${ovSnap.data()!['authorized_until'] ?? ''}';
          if (until.compareTo(DateTime.now().toUtc().toIso8601String()) > 0) {
            hasOverride = true;
          }
        }
      }
      if (!hasOverride) {
        if (isSunday && isHoliday) {
          throw const PostgrestException(
            message: 'Attendance is closed on Sunday and the declared school holiday. School Admin password authorization is required.',
            code: '42501',
          );
        } else if (isSunday) {
          throw const PostgrestException(
            message: 'Attendance is closed on Sunday. School Admin password authorization is required.',
            code: '42501',
          );
        } else if (isHoliday) {
          final reason = '${holidayRow['reason'] ?? ''}'.trim();
          throw PostgrestException(
            message:
                'Attendance is closed on this school holiday: ${reason.isEmpty ? 'School holiday' : reason}. School Admin password authorization is required.',
            code: '42501',
          );
        } else {
          throw const PostgrestException(
            message: 'Previous-date attendance changes require School Admin password authorization.',
            code: '42501',
          );
        }
      }
    }
  }

  static DateTime _leavePeriodStart(DateTime date, int startMonth) {
    final year = date.month < startMonth ? date.year - 1 : date.year;
    return DateTime(year, startMonth, 1);
  }

  Future<void> _enforceLeaveWriteGuard(
    Map<String, dynamic> row, {
    required bool isInsert,
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    final status = '${row['status'] ?? 'pending'}'.trim().toLowerCase();
    final recordSource = '${row['record_source'] ?? 'teacher_application'}'
        .trim();
    if (recordSource == 'admin_manual') {
      if (ctx?.isAdmin != true || status != 'approved') {
        throw const PostgrestException(
          message: 'Only a School Admin can enter an already-approved handwritten leave record.',
          code: '42501',
        );
      }
    }
    if (status != 'pending' && status != 'approved') return;

    final schoolRef = '${row['school_ref'] ?? ctx?.schoolRef ?? ''}'.trim();
    final teacherId = '${row['teacher_id'] ?? ctx?.teacherId ?? ''}'.trim();
    if (schoolRef.isEmpty || teacherId.isEmpty) return;

    final allSchoolLeaves = await _cachedSchoolTableRows(
      'teacher_leaves',
      schoolRef,
    );
    final existingLeaves = allSchoolLeaves
        .where((l) => '${l['teacher_id'] ?? ''}'.trim() == teacherId)
        .toList();

    if (isInsert &&
        recordSource == 'teacher_application' &&
        status == 'pending') {
      final hasPending = existingLeaves.any(
        (l) =>
            '${l['status'] ?? ''}' == 'pending' &&
            '${l['record_source'] ?? 'teacher_application'}' ==
                'teacher_application',
      );
      if (hasPending) {
        throw const PostgrestException(
          message: 'તમારી અગાઉની રજા અરજી મંજૂર અથવા નામંજૂર થાય પછી જ નવી અરજી કરી શકશો.',
          code: '23514',
        );
      }
    }

    final startDate = DateTime.tryParse('${row['start_date'] ?? ''}');
    final endDate = DateTime.tryParse('${row['end_date'] ?? ''}');
    if (startDate == null || endDate == null || endDate.isBefore(startDate)) {
      throw const PostgrestException(message: 'Leave dates are invalid.');
    }
    final startIso = _extractIndiaDateIsoFromAny(row['start_date']);
    final endIso = _extractIndiaDateIsoFromAny(row['end_date']);
    final currentRowId = '${row['id'] ?? ''}'.trim();

    final leaveData = row['leave_data'] is Map
        ? Map<String, dynamic>.from(row['leave_data'] as Map)
        : <String, dynamic>{};
    final chargeTeacherId =
        '${leaveData['charge_teacher_id'] ?? row['charge_teacher_id'] ?? ''}'
            .trim();

    if (chargeTeacherId.isNotEmpty && chargeTeacherId == teacherId) {
      throw const PostgrestException(
        message: 'અરજદાર શિક્ષક પોતાને જ વર્ગ ચાર્જ સોંપી શકે નહીં.',
        code: '23514',
      );
    }

    if (startIso.isNotEmpty && endIso.isNotEmpty) {
      final overlappingSchoolLeaves = <Map<String, dynamic>>[];
      for (final l in allSchoolLeaves) {
        final lid = '${l['id'] ?? ''}'.trim();
        if (currentRowId.isNotEmpty && lid == currentRowId) continue;
        final lStatus = '${l['status'] ?? 'pending'}'.trim().toLowerCase();
        if (lStatus != 'pending' && lStatus != 'approved') continue;
        final lStart = _extractIndiaDateIsoFromAny(l['start_date']);
        final lEnd = _extractIndiaDateIsoFromAny(l['end_date']);
        if (lStart.isEmpty || lEnd.isEmpty) continue;
        if (lStart.compareTo(endIso) <= 0 && lEnd.compareTo(startIso) >= 0) {
          overlappingSchoolLeaves.add(l);
        }
      }

      if (isInsert && recordSource == 'teacher_application') {
        for (final l in overlappingSchoolLeaves) {
          if ('${l['teacher_id'] ?? ''}'.trim() == teacherId) {
            final lStart = _extractIndiaDateIsoFromAny(l['start_date']);
            final lEnd = _extractIndiaDateIsoFromAny(l['end_date']);
            throw PostgrestException(
              message:
                  'આ તારીખ ($lStart થી $lEnd) દરમિયાન તમારી રજા અરજી પહેલેથી જ નોંધાયેલી છે.',
              code: '23514',
            );
          }
        }
      }

      if (chargeTeacherId.isNotEmpty) {
        // Build charge map on overlapping dates: onLeaveTeacherId -> chargeTeacherId
        final chargeMap = <String, String>{};
        final leaveByTeacher = <String, Map<String, dynamic>>{};
        for (final l in overlappingSchoolLeaves) {
          final tId = '${l['teacher_id'] ?? ''}'.trim();
          if (tId.isEmpty) continue;
          leaveByTeacher[tId] = l;
          final ld = l['leave_data'] is Map
              ? Map<String, dynamic>.from(l['leave_data'] as Map)
              : <String, dynamic>{};
          final cId =
              '${ld['charge_teacher_id'] ?? l['charge_teacher_id'] ?? ''}'
                  .trim();
          if (cId.isNotEmpty) chargeMap[tId] = cId;
        }

        // 1. Check if [chargeTeacherId] gave charge (directly or transitively) to [teacherId]
        var cursor = chargeTeacherId;
        final seen = <String>{};
        var gaveChargeToApplicant = false;
        while (chargeMap.containsKey(cursor) && seen.add(cursor)) {
          final next = chargeMap[cursor]!;
          if (next == teacherId) {
            gaveChargeToApplicant = true;
            break;
          }
          cursor = next;
        }
        if (gaveChargeToApplicant) {
          final conflictLeave = leaveByTeacher[chargeTeacherId];
          final ld = conflictLeave?['leave_data'] is Map
              ? Map<String, dynamic>.from(conflictLeave!['leave_data'] as Map)
              : <String, dynamic>{};
          final tName = '${ld['teacher_name'] ?? 'પસંદ કરેલ શિક્ષક'}'.trim();
          throw PostgrestException(
            message:
                'આ તારીખે "$tName" એ પોતે રજા મૂકીને તમને વર્ગ ચાર્જ સોંપેલ છે, તેથી તમે તેમને સામો ચાર્જ સોંપી શકો નહીં. કૃપા કરીને હાજર રહેનાર અન્ય શિક્ષકને ચાર્જ સોંપો (જેથી તેમને બંને/ત્રણેય વર્ગનો ચાર્જ મળશે).',
            code: '23514',
          );
        }

        // 2. Check if [chargeTeacherId] is already on leave during [startIso..endIso]
        if (leaveByTeacher.containsKey(chargeTeacherId)) {
          final conflictLeave = leaveByTeacher[chargeTeacherId]!;
          final ld = conflictLeave['leave_data'] is Map
              ? Map<String, dynamic>.from(conflictLeave['leave_data'] as Map)
              : <String, dynamic>{};
          final tName = '${ld['teacher_name'] ?? 'પસંદ કરેલ શિક્ષક'}'.trim();
          final lStart = _extractIndiaDateIsoFromAny(
            conflictLeave['start_date'],
          );
          final lEnd = _extractIndiaDateIsoFromAny(conflictLeave['end_date']);
          throw PostgrestException(
            message:
                'આ તારીખે "$tName" પોતે રજા પર છે ($lStart થી $lEnd). રજા પર રહેલા શિક્ષકને વર્ગ ચાર્જ સોંપી શકાય નહીં; કૃપા કરીને હાજર રહેનાર અન્ય શિક્ષક પસંદ કરો.',
            code: '23514',
          );
        }
      }
    }

    final typeLower = '${row['leave_type'] ?? ''}'.trim().toLowerCase();
    final isCl =
        typeLower.contains('(cl)') ||
        typeLower == 'cl' ||
        typeLower.contains('પ્રાસંગિક');
    final isMarajiyat =
        typeLower.contains('મરજિયાત') || typeLower.contains('marajiyat');
    final isValtar = typeLower.contains('વળતર') || typeLower.contains('valtar');
    if (!isCl && !isMarajiyat && !isValtar) return;
    final requested =
        double.tryParse('${leaveData['total_days'] ?? ''}') ??
        (endDate.difference(startDate).inDays + 1).toDouble();
    if (requested <= 0) {
      throw const PostgrestException(
        message: 'Leave days must be greater than zero.',
      );
    }

    final rulesRow = await from('school_leave_settings')
        .select()
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final rules = rulesRow ?? <String, dynamic>{};

    double cap;
    int startMonth;
    int allowedStartMonth;
    int allowedEndMonth;

    if (isCl) {
      cap = (num.tryParse('${rules['cl_max_days'] ?? 12}') ?? 12).toDouble();
      startMonth = int.tryParse('${rules['cl_year_start_month'] ?? 6}') ?? 6;
      allowedStartMonth =
          int.tryParse('${rules['cl_allowed_start_month'] ?? 1}') ?? 1;
      allowedEndMonth =
          int.tryParse('${rules['cl_allowed_end_month'] ?? 12}') ?? 12;
    } else if (isMarajiyat) {
      cap = (num.tryParse('${rules['marajiyat_max_days'] ?? 2}') ?? 2)
          .toDouble();
      startMonth =
          int.tryParse('${rules['marajiyat_year_start_month'] ?? 1}') ?? 1;
      allowedStartMonth =
          int.tryParse('${rules['marajiyat_allowed_start_month'] ?? 1}') ?? 1;
      allowedEndMonth =
          int.tryParse('${rules['marajiyat_allowed_end_month'] ?? 12}') ?? 12;
    } else {
      final vData = await _cachedDocData(
            'school_teacher_valtar_rules',
            '${schoolRef}__$teacherId',
          ) ??
          <String, dynamic>{};
      final enabled = vData['enabled'] == true;
      cap = (num.tryParse('${vData['max_days'] ?? 0}') ?? 0).toDouble();
      if (!enabled || cap <= 0) {
        throw const PostgrestException(
          message: 'આ શિક્ષક માટે વળતર રજા ચાલુ નથી. School Admin ને Leave Settings માં તમારા નામ સામે checkbox ચાલુ કરવા અને દિવસોની મર્યાદા સેટ કરવા કહો.',
          code: '23514',
        );
      }
      startMonth = int.tryParse('${rules['valtar_start_month'] ?? 1}') ?? 1;
      allowedStartMonth = startMonth;
      allowedEndMonth =
          int.tryParse('${rules['valtar_end_month'] ?? 12}') ?? 12;
    }

    // Check allowed month window
    var cursor = DateTime(startDate.year, startDate.month, 1);
    final lastMonth = DateTime(endDate.year, endDate.month, 1);
    while (!cursor.isAfter(lastMonth)) {
      final m = cursor.month;
      final inWindow = allowedStartMonth <= allowedEndMonth
          ? (m >= allowedStartMonth && m <= allowedEndMonth)
          : (m >= allowedStartMonth || m <= allowedEndMonth);
      if (!inWindow) {
        final label = isCl
            ? 'C.L.'
            : (isMarajiyat ? 'મરજિયાત રજા' : 'વળતર રજા');
        throw PostgrestException(
          message:
              '$label માટે મંજૂર મહિના $allowedStartMonth થી $allowedEndMonth છે. પસંદ કરેલી તારીખો તે સમયગાળામાં નથી.',
          code: '23514',
        );
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    final periodStart = _leavePeriodStart(startDate, startMonth);
    if (_leavePeriodStart(endDate, startMonth) != periodStart) {
      throw const PostgrestException(
        message: 'એક રજા અરજી એક જ નિયત વાર્ષિક સમયગાળામાં હોવી જોઈએ. વર્ષ બદલાય તો પહેલી અરજી મંજૂર/નામંજૂર થયા પછી અલગ અરજી કરો.',
        code: '23514',
      );
    }

    double used = 0;
    final currentId = '${row['id'] ?? ''}'.trim();
    for (final l in existingLeaves) {
      if (currentId.isNotEmpty && '${l['id'] ?? ''}' == currentId) continue;
      final st = '${l['status'] ?? ''}'.toLowerCase();
      if (st != 'pending' && st != 'approved') continue;
      final lt = '${l['leave_type'] ?? ''}'.toLowerCase();
      final matchesType =
          (isCl &&
              (lt.contains('(cl)') ||
                  lt == 'cl' ||
                  lt.contains('પ્રાસંગિક'))) ||
          (isMarajiyat &&
              (lt.contains('મરજિયાત') || lt.contains('marajiyat'))) ||
          (isValtar && (lt.contains('વળતર') || lt.contains('valtar')));
      if (!matchesType) continue;
      final lStart = DateTime.tryParse('${l['start_date'] ?? ''}');
      final lEnd = DateTime.tryParse('${l['end_date'] ?? ''}');
      if (lStart == null || lEnd == null) continue;
      if (_leavePeriodStart(lStart, startMonth) != periodStart) continue;
      final ld = l['leave_data'] is Map
          ? Map<String, dynamic>.from(l['leave_data'] as Map)
          : <String, dynamic>{};
      final days =
          double.tryParse('${ld['total_days'] ?? ''}') ??
          (lEnd.difference(lStart).inDays + 1).toDouble();
      used += days;
    }

    if (used + requested > cap) {
      throw PostgrestException(
        message:
            'આ સમયગાળામાં આ પ્રકારની રજાની મર્યાદા $cap દિવસ છે. અગાઉની પેન્ડિંગ/મંજૂર નોંધો $used દિવસ અને નવી અરજી $requested દિવસ થાય છે.',
        code: '23514',
      );
    }
  }

  Future<void> _enforceResultWriteGuard({
    required String table,
    required List<Map<String, dynamic>> rows,
    required _TeacherSessionContext? ctx,
  }) async {
    if (rows.isEmpty || ctx?.isAdmin == true) return;
    final classId = '${rows.first['class_id'] ?? ''}'.trim();
    if (classId.isEmpty) return;
    final settings = await from('class_result_settings')
        .select('sem1_locked,sem2_locked')
        .eq('class_id', classId)
        .maybeSingle();
    final sem1Locked = settings?['sem1_locked'] == true;
    final sem2Locked = settings?['sem2_locked'] == true;
    if (table == 'student_subject_marks' && ctx != null) {
      for (final r in rows) {
        final subj = '${r['subject_name'] ?? ''}'.trim();
        final cid = '${r['class_id'] ?? classId}'.trim();
        if (subj.isNotEmpty && !ctx.canEnterMarks(cid, subj)) {
          throw PostgrestException(
            message: 'તમે "$subj" વિષય આ વર્ગમાં ભણાવતા નથી, તેથી તેના ગુણ દાખલ કરી શકતા નથી.',
            code: '42501',
          );
        }
      }
    }
    if (table == 'student_subject_marks') {
      for (final r in rows) {
        final sem = int.tryParse('${r['semester'] ?? 1}') ?? 1;
        if ((sem == 1 && sem1Locked) || (sem == 2 && sem2Locked)) {
          throw const PostgrestException(
            message: 'This semester is locked.',
            code: '42501',
          );
        }
      }
    }
  }

  FirestoreQueryBuilder from(String table) =>
      FirestoreQueryBuilder(this, table);

  Future<dynamic> rpc(String fnName, {Map<String, dynamic>? params}) async {
    final p = params ?? const <String, dynamic>{};
    switch (fnName) {
      case 'psm_health_check':
        return <String, dynamic>{'status': 'ok'};

      case 'current_school_ref':
        {
          final ctx = await _resolveCurrentTeacherContext();
          return ctx?.schoolRef;
        }

      case 'current_teacher_id':
        {
          final ctx = await _resolveCurrentTeacherContext();
          return ctx?.teacherId;
        }

      case 'is_school_admin':
        {
          final ctx = await _resolveCurrentTeacherContext();
          return ctx?.isAdmin == true;
        }

      case 'psm_get_attendance_entry_access':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            return <String, dynamic>{
              'permission_mode': 'subject_and_class_teachers',
              'attendance_date': _indiaTodayIso(),
              'classes': <Map<String, dynamic>>[],
              'allowed_class_ids': <String>[],
              'class_teacher_ids': <String>[],
              'role_by_class_id': <String, String>{},
              'in_charge_info_by_class_id': <String, Map<String, dynamic>>{},
            };
          }
          final reqDate = '${p['p_attendance_date'] ?? _indiaTodayIso()}'.trim();
          return _computeAttendanceEntryAccessForDate(
            ctx: ctx,
            targetDateIso: reqDate,
          );
        }

      case 'psm_attendance_class_ids':
        {
          // null = whole school (admin); otherwise the class ids the teacher
          // may record attendance for.
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <String>[];
          if (ctx.isAdmin) return null;
          return ctx.attendanceClassIds.toList();
        }

      case 'psm_class_teacher_class_ids':
        {
          // null = whole school (admin); otherwise the exact class ids where
          // this teacher is the Class Teacher (never subject-only classes).
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <String>[];
          if (ctx.isAdmin) return null;
          return ctx.classTeacherClassIds.toList();
        }

      case 'can_access_class':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return false;
          if (ctx.isAdmin) return true;
          final cid = '${p['p_class_id'] ?? ''}'.trim();
          if (cid.isEmpty) return false;
          final cRow = await from('school_classes')
              .select()
              .eq('id', cid)
              .maybeSingle();
          if (cRow == null) return false;
          return ctx.canAccessClassRow(cRow);
        }

      case 'current_school_teacher_roster':
      case 'psm_leave_teacher_roster_v2':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final teacherRows = await _cachedSchoolTableRows(
            'school_teachers',
            ctx.schoolRef,
          );
          final out = <Map<String, dynamic>>[];
          for (final r in teacherRows) {
            if (r['is_active'] != true) continue;
            final role = '${r['role'] ?? 'teacher'}'.trim().toLowerCase();
            if (role == 'admin' || role == 'developer') continue;
            out.add(<String, dynamic>{
              'id': '${r['id'] ?? ''}',
              'teacher_name': '${r['teacher_name'] ?? ''}',
              'mobile': '${r['mobile'] ?? ''}',
              'role': '${r['role'] ?? 'teacher'}',
              'is_active': true,
              'allowed_classes': r['allowed_classes'] is List
                  ? List<dynamic>.from(r['allowed_classes'] as List)
                  : <dynamic>[],
            });
          }
          out.sort(
            (a, b) => '${a['teacher_name']}'.toLowerCase().compareTo(
              '${b['teacher_name']}'.toLowerCase(),
            ),
          );
          return out;
        }

      case 'psm_leave_applicant_directory_v1':
        {
          final ctx = await _resolveCurrentTeacherContext();
          // The leave applicant directory is deliberately Admin-only. It reads
          // only this school's teacher display names and class metadata.
          if (ctx == null || !ctx.isAdmin) return <Map<String, dynamic>>[];
          final teacherRows = await _cachedSchoolTableRows(
            'school_teachers',
            ctx.schoolRef,
          );
          final out = <Map<String, dynamic>>[];
          for (final row in teacherRows) {
            final role = '${row['role'] ?? 'teacher'}'.trim().toLowerCase();
            if (role == 'admin' || role == 'developer') continue;
            out.add(<String, dynamic>{
              'id': '${row['id'] ?? ''}',
              'teacher_name': '${row['teacher_name'] ?? ''}',
              'mobile': '${row['mobile'] ?? ''}',
              'role': role.isEmpty ? 'teacher' : role,
              'is_active': row['is_active'] == true,
              'allowed_classes': row['allowed_classes'] is List
                  ? List<dynamic>.from(row['allowed_classes'] as List)
                  : <dynamic>[],
            });
          }
          out.sort(
            (a, b) => '${a['teacher_name']}'.toLowerCase().compareTo(
              '${b['teacher_name']}'.toLowerCase(),
            ),
          );
          return out;
        }

      case 'ensure_school_planning_core_subjects':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || ctx.schoolRef.isEmpty) return false;
          final schoolRef = ctx.schoolRef;
          final existingRows = await from('school_subject_master')
              .select()
              .eq('school_ref', schoolRef);
          if (existingRows.isEmpty) {
            await functions._seedDefaultSubjectsAndGrades(schoolRef);
          }
          final existingNames = existingRows
              .map(
                (r) => '${r['subject_name'] ?? ''}'.trim().toLowerCase(),
              )
              .where((name) => name.isNotEmpty)
              .toSet();
          const requiredSubjects = <(String, int)>[
            ('ગુજરાતી', 0),
            ('હિન્દી', 1),
            ('પર્યાવરણ', 2),
            ('ગણિત', 3),
            ('અંગ્રેજી', 4),
            ('વિજ્ઞાન', 5),
            ('સામાજિક વિજ્ઞાન', 6),
            ('સંસ્કૃત', 7),
            ('શ્રીમદ્ ભગવદ્ ગીતા', 8),
            ('કોમ્પ્યુટર', 9),
            ('લાયબ્રેરી', 10),
            ('રમત', 11),
            ('સંગીત', 12),
            ('કાર્યાનુભવ', 13),
            ('ચિત્ર', 14),
            ('FLN', 15),
            ('શા. શિ.', 16),
          ];
          final nowIso = DateTime.now().toUtc().toIso8601String();
          var addedAny = false;
          for (final item in requiredSubjects) {
            final name = item.$1;
            if (existingNames.contains(name.toLowerCase())) continue;
            addedAny = true;
            final id = '${schoolRef}__${FirestoreQueryBuilder._slug(name)}';
            final row = <String, dynamic>{
              'id': id,
              'school_ref': schoolRef,
              'subject_name': name,
              'sort_order': item.$2,
              'is_active': true,
              'created_at': nowIso,
              'updated_at': nowIso,
            };
            await _db
                .collection('school_subject_master')
                .doc(id)
                .set(row, fs.SetOptions(merge: true));
            await _syncMasterSubjectRowToClasses(row);
          }
          if (addedAny) {
            FirestoreQueryBuilder.invalidateCache('school_subject_master');
            FirestoreQueryBuilder.invalidateCache('class_subjects');
            FirestoreQueryBuilder.invalidateCache('school_subject_catalog');
          }
          return true;
        }

      case 'hajari_patrak_teacher_directory':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final teacherRows = await _cachedSchoolTableRows(
            'school_teachers',
            ctx.schoolRef,
          );
          final out = <Map<String, dynamic>>[];
          for (final r in teacherRows) {
            if (r['is_active'] != true) continue;
            out.add(<String, dynamic>{
              'id': '${r['id'] ?? ''}',
              'teacher_name': '${r['teacher_name'] ?? ''}',
              'role': '${r['role'] ?? 'teacher'}',
            });
          }
          out.sort(
            (a, b) => '${a['teacher_name']}'.toLowerCase().compareTo(
              '${b['teacher_name']}'.toLowerCase(),
            ),
          );
          return out;
        }

      case 'current_school_class_roster':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final classRows = await _cachedSchoolTableRows(
            'school_classes',
            ctx.schoolRef,
          );
          final out = classRows.map((c) {
            return <String, dynamic>{
              'id': '${c['id'] ?? ''}',
              'label': '${c['label'] ?? ''}',
              'class_key': '${c['class_key'] ?? ''}',
              'sheet_name': '${c['sheet_name'] ?? ''}',
              'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
              'is_active': c['is_active'] == true,
              'class_teacher_id': c['class_teacher_id'],
            };
          }).toList();
          out.sort((a, b) {
            final cmp = (a['sort_order'] as int).compareTo(
              b['sort_order'] as int,
            );
            if (cmp != 0) return cmp;
            return '${a['label']}'.toLowerCase().compareTo(
              '${b['label']}'.toLowerCase(),
            );
          });
          return out;
        }

      case 'psm_library_school_context':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            throw const PostgrestException(
              message: 'This login is not linked to an active school.',
            );
          }
          final s = ctx.schoolRow;
          final nameEn = '${s['school_name_en'] ?? ''}'.trim().isNotEmpty
              ? '${s['school_name_en']}'.trim()
              : '${s['school_name'] ?? ''}'.trim();
          return <String, dynamic>{
            'school_id': '${s['school_id'] ?? ''}',
            'school_name': '${s['school_name'] ?? nameEn}',
            'school_name_en': nameEn,
            'school_name_gu': '${s['school_name_gu'] ?? ''}',
            'school_address_en': '${s['school_address_en'] ?? ''}',
            'school_address_gu': '${s['school_address_gu'] ?? ''}',
            'school_type': '${s['school_type'] ?? 'mixed'}',
            'is_active': s['is_active'] == true,
            'is_blocked': s['is_blocked'] == true,
            'validity_date': s['validity_date'],
            'disabled_modules': s['disabled_modules'] is Iterable
                ? (s['disabled_modules'] as Iterable)
                      .map((e) => '$e'.trim().toLowerCase())
                      .where((v) => v.isNotEmpty)
                      .toList()
                : const <String>[],
          };
        }

      case 'hajari_patrak_school_meta':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <String, dynamic>{};
          final s = ctx.schoolRow;
          final settings = await from('school_settings')
              .select()
              .eq('school_ref', ctx.schoolRef)
              .maybeSingle();
          final cfg = settings?['config'] is Map
              ? Map<String, dynamic>.from(settings!['config'] as Map)
              : <String, dynamic>{};
          final name = '${s['school_name'] ?? s['school_name_en'] ?? ''}'
              .trim();
          final nameEn = '${s['school_name_en'] ?? name}'.trim();
          final nameGu = '${s['school_name_gu'] ?? ''}'.trim();
          final address =
              <String>[
                    '${s['school_address_gu'] ?? ''}',
                    '${s['school_address_en'] ?? ''}',
                    '${s['school_address'] ?? ''}',
                    '${s['address'] ?? ''}',
                    '${cfg['school_address'] ?? ''}',
                    '${cfg['address'] ?? ''}',
                  ]
                  .map((v) => v.trim())
                  .firstWhere((v) => v.isNotEmpty, orElse: () => '');
          final academicYear =
              <String>[
                    '${cfg['academic_year'] ?? ''}',
                    '${s['academic_year'] ?? ''}',
                  ]
                  .map((v) => v.trim())
                  .firstWhere((v) => v.isNotEmpty, orElse: () => '');
          return <String, dynamic>{
            'school_name': name,
            'school_name_en': nameEn,
            'school_name_gu': nameGu,
            'school_type': '${s['school_type'] ?? 'coed'}',
            'address': address,
            'academic_year': academicYear,
            'logo_path': '${settings?['logo_path'] ?? ''}',
          };
        }

      case 'hajari_patrak_set_class_teacher':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the School Admin can change the official class teacher.',
            );
          }
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final teacherIdRaw = p['p_teacher_id'];
          final teacherId = teacherIdRaw == null ? '' : '$teacherIdRaw'.trim();
          if (classId.isEmpty) {
            throw const PostgrestException(message: 'Class ID is required.');
          }
          await _db.collection('school_classes').doc(classId).set(
            <String, dynamic>{
              'class_teacher_id': teacherId.isEmpty ? null : teacherId,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            fs.SetOptions(merge: true),
          );
          FirestoreQueryBuilder.invalidateCache('school_classes');
          return true;
        }

      case 'hajari_patrak_save_present_days':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final yearStart =
              int.tryParse('${p['p_academic_year_start'] ?? 0}') ?? 0;
          final throughDate = '${p['p_through_date'] ?? ''}'.trim();
          final values = p['p_values'] is List
              ? (p['p_values'] as List)
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList()
              : <Map<String, dynamic>>[];

          final col = _db.collection('hajari_student_present_day_overrides');
          final nowIso = DateTime.now().toUtc().toIso8601String();
          var batch = _db.batch();
          var ops = 0;
          for (final item in values) {
            final studentId = '${item['student_id'] ?? ''}'.trim();
            if (studentId.isEmpty) continue;
            final docId =
                '${schoolRef}__${classId}__${studentId}__${yearStart}__$throughDate';
            final rawDays = '${item['present_days'] ?? ''}'.trim();
            if (rawDays.isEmpty) {
              batch.delete(col.doc(docId));
            } else {
              final days = int.tryParse(rawDays) ?? 0;
              batch.set(col.doc(docId), <String, dynamic>{
                'id': docId,
                'school_ref': schoolRef,
                'class_id': classId,
                'student_id': studentId,
                'academic_year_start': yearStart,
                'through_date': throughDate,
                'present_days': days,
                'updated_at': nowIso,
              });
            }
            ops++;
            if (ops >= 400) {
              await batch.commit();
              batch = _db.batch();
              ops = 0;
            }
          }
          if (ops > 0) await batch.commit();
          return true;
        }

      case 'calculate_category_gender_breakdown':
        {
          final schoolRef = '${p['p_school_ref'] ?? ''}'.trim();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final date = '${p['p_date'] ?? ''}'.trim();
          return _calculateCategoryGenderBreakdown(
            schoolRef: schoolRef,
            classId: classId,
            date: date,
          );
        }

      case 'refresh_attendance_day_counts':
        {
          final dayId = '${p['p_attendance_day_id'] ?? ''}'.trim();
          return _refreshAttendanceDayCounts(dayId);
        }

      case 'schoolwide_attendance_report_rows':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final fromDate = p['p_from_date'] == null
              ? ''
              : '${p['p_from_date']}'.trim();
          final toDate = p['p_to_date'] == null
              ? ''
              : '${p['p_to_date']}'.trim();
          return _schoolwideAttendanceReportRows(
            ctx: ctx,
            fromDate: fromDate.isEmpty ? null : fromDate,
            toDate: toDate.isEmpty ? null : toDate,
          );
        }

      case 'schoolwide_daily_report_rows':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final date = '${p['p_date'] ?? ''}'.trim();
          if (date.isEmpty) {
            throw const PostgrestException(
              message: 'A report date is required.',
            );
          }
          return _schoolwideDailyReportRows(ctx: ctx, date: date);
        }

      case 'school_attendance_day_serial':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return null;
          final date = '${p['p_date'] ?? ''}'.trim();
          if (date.isEmpty) return null;
          final days = await from('attendance_days')
              .select('attendance_date')
              .eq('school_ref', ctx.schoolRef);
          final distinctDates = <String>{
            for (final d in days)
              if ('${d['attendance_date'] ?? ''}'.trim().isNotEmpty)
                '${d['attendance_date']}'.trim(),
          };
          if (!distinctDates.contains(date)) return null;
          return distinctDates.where((d) => d.compareTo(date) <= 0).length;
        }

      case 'schoolwide_tarij_student_counts':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) return <Map<String, dynamic>>[];
          final monthStart = '${p['p_month_start'] ?? ''}'.trim();
          final monthEnd = '${p['p_month_end'] ?? ''}'.trim();
          return _schoolwideTarijStudentCounts(
            ctx: ctx,
            monthStart: monthStart,
            monthEnd: monthEnd,
          );
        }

      case 'psm_add_student_with_roll':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final studentMap = p['p_student'] is Map
              ? Map<String, dynamic>.from(
                  (p['p_student'] as Map).map((k, v) => MapEntry('$k', v)),
                )
              : <String, dynamic>{};
          final requestedRoll = p['p_roll_number'] == null
              ? null
              : int.tryParse('${p['p_roll_number']}');
          return _addStudentWithRoll(
            schoolRef: schoolRef,
            classId: classId,
            student: studentMap,
            requestedRoll: requestedRoll,
          );
        }

      case 'psm_change_student_roll':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          final newRoll = int.tryParse('${p['p_new_roll'] ?? ''}') ?? 0;
          return _changeStudentRoll(
            schoolRef: schoolRef,
            studentId: studentId,
            newRoll: newRoll,
          );
        }

      case 'psm_update_student_profile_with_roll_shift':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          final values = p['p_student_values'] is Map
              ? Map<String, dynamic>.from(
                  (p['p_student_values'] as Map).map(
                    (k, v) => MapEntry('$k', v),
                  ),
                )
              : <String, dynamic>{};
          final customFields = p['p_custom_fields'] is Map
              ? Map<String, dynamic>.from(
                  (p['p_custom_fields'] as Map).map(
                    (k, v) => MapEntry('$k', v),
                  ),
                )
              : null;
          await _updateStudentProfileWithRollShift(
            schoolRef: schoolRef,
            studentId: studentId,
            values: values,
            customFields: customFields,
          );
          return null;
        }

      case 'psm_archive_student':
      case 'psm_archive_student_and_shift_rolls':
      case 'psm_mark_student_left_and_shift_rolls':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          final exitDate = '${p['p_exit_date'] ?? _indiaTodayIso()}'.trim();
          final exitReason = '${p['p_exit_reason'] ?? 'other'}'.trim();
          await _archiveOrDeleteStudentAndShiftRolls(
            schoolRef: schoolRef,
            studentId: studentId,
            deletePermanently: false,
            exitDate: exitDate,
            exitReason: exitReason,
          );
          return true;
        }

      case 'psm_delete_student_and_shift_rolls':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          await _archiveOrDeleteStudentAndShiftRolls(
            schoolRef: schoolRef,
            studentId: studentId,
            deletePermanently: true,
          );
          return null;
        }

      case 'replace_student_result_roster_snapshot':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final semester = int.tryParse('${p['p_semester'] ?? 1}') ?? 1;
          final sourceDate = '${p['p_source_date'] ?? ''}'.trim();
          return _replaceStudentResultRosterSnapshot(
            schoolRef: schoolRef,
            classId: classId,
            semester: semester,
            sourceDate: sourceDate,
          );
        }

      case 'psm_admin_add_result_roster_member':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final semester = int.tryParse('${p['p_semester'] ?? 1}') ?? 1;
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          return _adminAddResultRosterMember(
            schoolRef: schoolRef,
            classId: classId,
            semester: semester,
            studentId: studentId,
          );
        }

      case 'psm_admin_remove_result_roster_student':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final studentId = '${p['p_student_id'] ?? ''}'.trim();
          return _adminRemoveResultRosterStudent(
            schoolRef: schoolRef,
            classId: classId,
            studentId: studentId,
          );
        }

      case 'save_school_result_grade_settings':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the authenticated School Admin can edit grade settings.',
            );
          }
          final grades = p['p_grades'] is List
              ? (p['p_grades'] as List)
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList()
              : <Map<String, dynamic>>[];
          return _saveSchoolResultGradeSettings(schoolRef, grades);
        }

      case 'psm_school_active_leave_charges':
        {
          final schoolRef = await _requireSchoolReadAccess();
          final allLeaves = await _cachedSchoolTableRows(
            'teacher_leaves',
            schoolRef,
          );
          final out = <Map<String, dynamic>>[];
          for (final l in allLeaves) {
            final status = '${l['status'] ?? 'pending'}'.trim().toLowerCase();
            if (status != 'pending' && status != 'approved') continue;
            final ld = l['leave_data'] is Map
                ? Map<String, dynamic>.from(l['leave_data'] as Map)
                : <String, dynamic>{};
            out.add(<String, dynamic>{
              'id': '${l['id'] ?? ''}',
              'teacher_id': '${l['teacher_id'] ?? ''}',
              'start_date': _extractIndiaDateIsoFromAny(l['start_date']),
              'end_date': _extractIndiaDateIsoFromAny(l['end_date']),
              'status': status,
              'leave_type': '${l['leave_type'] ?? ''}',
              'teacher_name': '${ld['teacher_name'] ?? ''}',
              'teacher_class': '${ld['teacher_class'] ?? ''}',
              'charge_teacher_id':
                  '${ld['charge_teacher_id'] ?? l['charge_teacher_id'] ?? ''}',
              'charge_teacher_name':
                  '${ld['charge_teacher_name'] ?? l['charge_teacher_name'] ?? ''}',
              'charge_teacher_class': '${ld['charge_teacher_class'] ?? ''}',
            });
          }
          return out;
        }

      case 'psm_get_or_create_teacher_leave_report_snapshot':
        {
          final leaveId = '${p['p_leave_id'] ?? ''}'.trim();
          if (leaveId.isEmpty) {
            throw const PostgrestException(
              message: 'Leave application ID is required.',
            );
          }
          final schoolRef = await _requireSchoolReadAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            throw const PostgrestException(message: 'Please sign in again.');
          }
          final leaveSnap = await _db
              .collection('teacher_leaves')
              .doc(leaveId)
              .get();
          if (!leaveSnap.exists || leaveSnap.data() == null) {
            throw const PostgrestException(
              message: 'Leave application was not found for this school.',
            );
          }
          final leave = leaveSnap.data()!;
          if ('${leave['school_ref'] ?? ''}'.trim() != schoolRef) {
            throw const PostgrestException(
              message: 'Leave application was not found for this school.',
            );
          }
          final teacherId = '${leave['teacher_id'] ?? ''}'.trim();
          if (!ctx.isAdmin && teacherId != ctx.teacherId) {
            throw const PostgrestException(
              message: 'You may only print your own leave application.',
            );
          }

          final existingSnap = await _db
              .collection('teacher_leave_report_snapshots')
              .doc(leaveId)
              .get();
          if (existingSnap.exists && existingSnap.data() != null) {
            final existing = existingSnap.data()!;
            return <String, dynamic>{
              'result': 'success',
              'snapshot': existing['utilized_snapshot'] ?? <String, dynamic>{},
              'snapshot_created_at': existing['created_at'] ?? '',
              'reused': true,
            };
          }

          int clStart = 6;
          int marajiyatStart = 1;
          int valtarStart = 1;
          try {
            final settingsRow = await from('school_leave_settings')
                .select()
                .eq('school_ref', schoolRef)
                .maybeSingle();
            if (settingsRow != null) {
              clStart =
                  (int.tryParse('${settingsRow['cl_year_start_month'] ?? 6}') ??
                          6)
                      .clamp(1, 12);
              marajiyatStart =
                  (int.tryParse(
                            '${settingsRow['marajiyat_year_start_month'] ?? 1}',
                          ) ??
                          1)
                      .clamp(1, 12);
              valtarStart =
                  (int.tryParse('${settingsRow['valtar_start_month'] ?? 1}') ??
                          1)
                      .clamp(1, 12);
            }
          } catch (_) {}

          final startDateStr = '${leave['start_date'] ?? ''}'.trim();
          final endDateStr = '${leave['end_date'] ?? startDateStr}'.trim();
          final createdAtStr = '${leave['created_at'] ?? ''}'.trim();
          final targetStart = DateTime.tryParse(startDateStr) ?? DateTime.now();

          DateTime periodStartFor(DateTime d, int startMonth) {
            final yr = d.month < startMonth ? d.year - 1 : d.year;
            return DateTime(yr, startMonth, 1);
          }

          final targetClPeriod = periodStartFor(targetStart, clStart);
          final targetMarajiyatPeriod = periodStartFor(
            targetStart,
            marajiyatStart,
          );
          final targetValtarPeriod = periodStartFor(targetStart, valtarStart);

          final allLeaves = await _cachedSchoolTableRows(
            'teacher_leaves',
            schoolRef,
          );

          double clUsed = 0;
          double valtarUsed = 0;
          double marajiyatUsed = 0;

          for (final l in allLeaves) {
            final lid = '${l['id'] ?? ''}'.trim();
            if (lid == leaveId) continue;
            if ('${l['teacher_id'] ?? ''}'.trim() != teacherId) continue;
            if ('${l['status'] ?? ''}'.trim().toLowerCase() != 'approved')
              continue;
            final lStartStr = '${l['start_date'] ?? ''}'.trim();
            final lEndStr = '${l['end_date'] ?? lStartStr}'.trim();
            if (lEndStr.compareTo(startDateStr) >= 0) continue;
            final lCreatedStr = '${l['created_at'] ?? ''}'.trim();
            if (lCreatedStr.isNotEmpty &&
                createdAtStr.isNotEmpty &&
                lCreatedStr.compareTo(createdAtStr) > 0) {
              continue;
            }
            final lStart = DateTime.tryParse(lStartStr);
            final lEnd = DateTime.tryParse(lEndStr);
            if (lStart == null || lEnd == null) continue;

            double daysUsed = (lEnd.difference(lStart).inDays + 1).toDouble();
            if (l['leave_data'] is Map) {
              final ld = l['leave_data'] as Map;
              final rawDays = '${ld['total_days'] ?? ld['days'] ?? ''}'.trim();
              final parsed = double.tryParse(rawDays);
              if (parsed != null && parsed > 0) daysUsed = parsed;
            }

            final lType = '${l['leave_type'] ?? ''}'.trim().toLowerCase();
            if ((lType.contains('પ્રાસંગિક') ||
                    lType.contains('(cl)') ||
                    lType == 'cl') &&
                periodStartFor(lStart, clStart) == targetClPeriod) {
              clUsed += daysUsed;
            } else if ((lType.contains('વળતર') || lType.contains('valtar')) &&
                periodStartFor(lStart, valtarStart) == targetValtarPeriod) {
              valtarUsed += daysUsed;
            } else if ((lType.contains('મરજિયાત') ||
                    lType.contains('marajiyat')) &&
                periodStartFor(lStart, marajiyatStart) ==
                    targetMarajiyatPeriod) {
              marajiyatUsed += daysUsed;
            }
          }

          final nowIso = DateTime.now().toUtc().toIso8601String();
          final snapshotMap = <String, dynamic>{
            'cl': clUsed % 1 == 0 ? clUsed.toInt() : clUsed,
            'valtar': valtarUsed % 1 == 0 ? valtarUsed.toInt() : valtarUsed,
            'marajiyat': marajiyatUsed % 1 == 0
                ? marajiyatUsed.toInt()
                : marajiyatUsed,
            'as_of_date': startDateStr,
          };
          await _db
              .collection('teacher_leave_report_snapshots')
              .doc(leaveId)
              .set(<String, dynamic>{
                'id': leaveId,
                'leave_id': leaveId,
                'school_ref': schoolRef,
                'teacher_id': teacherId,
                'report_start_date': startDateStr,
                'report_end_date': endDateStr,
                'leave_type': '${leave['leave_type'] ?? ''}',
                'utilized_snapshot': snapshotMap,
                'created_at': nowIso,
              });
          return <String, dynamic>{
            'result': 'success',
            'snapshot': snapshotMap,
            'snapshot_created_at': nowIso,
            'reused': false,
          };
        }

      case 'psm_result_class_teacher_name':
        {
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          if (classId.isEmpty) return '';
          final schoolRef = await _requireSchoolReadAccess();
          final classRow = await _cachedDocData('school_classes', classId);
          if (classRow == null) return '';
          if ('${classRow['school_ref'] ?? ''}'.trim() != schoolRef) return '';
          final teacherId = '${classRow['class_teacher_id'] ?? ''}'.trim();
          if (teacherId.isEmpty) return '';
          final teacherRow = await _cachedDocData('school_teachers', teacherId);
          if (teacherRow == null) return '';
          if (teacherRow['is_active'] == false) return '';
          return '${teacherRow['teacher_name'] ?? ''}'.trim();
        }

      case 'psm_rename_school_result_subject':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message:
                  'Only the authenticated School Admin can rename a subject.',
            );
          }
          final subjectId = '${p['p_subject_id'] ?? ''}'.trim();
          final newName = '${p['p_new_subject_name'] ?? ''}'.trim();
          return _renameSchoolResultSubject(
            schoolRef: schoolRef,
            subjectId: subjectId,
            newName: newName,
          );
        }

      case 'psm_leave_save_rules':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the School Admin can change leave rules.',
            );
          }
          final ctx = await _resolveCurrentTeacherContext();
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final payload = <String, dynamic>{
            'id': schoolRef,
            'school_ref': schoolRef,
            'cl_max_days': num.tryParse('${p['p_cl_max_days'] ?? 12}') ?? 12,
            'cl_year_start_month':
                int.tryParse('${p['p_cl_start_month'] ?? 6}') ?? 6,
            'cl_year_end_month':
                int.tryParse('${p['p_cl_end_month'] ?? 5}') ?? 5,
            'cl_allowed_start_month':
                int.tryParse('${p['p_cl_allowed_start_month'] ?? 1}') ?? 1,
            'cl_allowed_end_month':
                int.tryParse('${p['p_cl_allowed_end_month'] ?? 12}') ?? 12,
            'marajiyat_max_days':
                num.tryParse('${p['p_marajiyat_max_days'] ?? 2}') ?? 2,
            'marajiyat_year_start_month':
                int.tryParse('${p['p_marajiyat_start_month'] ?? 1}') ?? 1,
            'marajiyat_year_end_month':
                int.tryParse('${p['p_marajiyat_end_month'] ?? 12}') ?? 12,
            'marajiyat_allowed_start_month':
                int.tryParse('${p['p_marajiyat_allowed_start_month'] ?? 1}') ??
                1,
            'marajiyat_allowed_end_month':
                int.tryParse('${p['p_marajiyat_allowed_end_month'] ?? 12}') ??
                12,
            'valtar_max_days':
                num.tryParse('${p['p_valtar_max_days'] ?? 0}') ?? 0,
            'valtar_start_month':
                int.tryParse('${p['p_valtar_start_month'] ?? 1}') ?? 1,
            'valtar_end_month':
                int.tryParse('${p['p_valtar_end_month'] ?? 12}') ?? 12,
            'updated_by': ctx?.teacherId,
            'updated_at': nowIso,
          };
          await _db
              .collection('school_leave_settings')
              .doc(schoolRef)
              .set(payload, fs.SetOptions(merge: true));
          return payload;
        }

      case 'psm_leave_list_teacher_valtar_rules':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message:
                  'Only the School Admin can view teacher-wise Valtar rules.',
            );
          }
          final teachers = await from('school_teachers')
              .select()
              .eq('school_ref', ctx.schoolRef)
              .eq('is_active', true);
          final rules = await from('school_teacher_valtar_rules')
              .select()
              .eq('school_ref', ctx.schoolRef);
          final byTeacher = <String, Map<String, dynamic>>{
            for (final r in rules) '${r['teacher_id']}': r,
          };
          final out = <Map<String, dynamic>>[];
          for (final t in teachers) {
            final role = '${t['role'] ?? 'teacher'}'.trim().toLowerCase();
            if (role == 'developer') continue;
            final tid = '${t['id']}';
            final rule = byTeacher[tid];
            out.add(<String, dynamic>{
              'teacher_id': tid,
              'teacher_name': '${t['teacher_name'] ?? ''}',
              'role': '${t['role'] ?? 'teacher'}',
              'enabled': rule?['enabled'] == true,
              'max_days': num.tryParse('${rule?['max_days'] ?? 0}') ?? 0,
            });
          }
          out.sort(
            (a, b) => '${a['teacher_name']}'.toLowerCase().compareTo(
              '${b['teacher_name']}'.toLowerCase(),
            ),
          );
          return out;
        }

      case 'psm_leave_save_teacher_valtar_rules':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message:
                  'Only the School Admin can change teacher-wise Valtar rules.',
            );
          }
          final list = p['p_rules'] is List
              ? (p['p_rules'] as List)
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList()
              : <Map<String, dynamic>>[];
          final nowIso = DateTime.now().toUtc().toIso8601String();
          var batch = _db.batch();
          var count = 0;
          for (final item in list) {
            final tid = '${item['teacher_id'] ?? ''}'.trim();
            if (tid.isEmpty) continue;
            final enabled =
                item['enabled'] == true ||
                '${item['enabled']}'.toLowerCase() == 'true';
            final maxDays = num.tryParse('${item['max_days'] ?? 0}') ?? 0;
            if (maxDays < 0 || maxDays > 365 || (enabled && maxDays <= 0)) {
              throw const PostgrestException(
                message: 'દરેક શિક્ષક માટે વળતર દિવસો 0 થી 365 વચ્ચે હોવા જોઈએ; checkbox ચાલુ હોય તો દિવસો 0 કરતાં વધુ હોવા જોઈએ.',
              );
            }
            final docId = '${schoolRef}__$tid';
            batch.set(
              _db.collection('school_teacher_valtar_rules').doc(docId),
              <String, dynamic>{
                'id': docId,
                'school_ref': schoolRef,
                'teacher_id': tid,
                'enabled': enabled,
                'max_days': maxDays,
                'updated_by': ctx.teacherId,
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            count++;
          }
          await batch.commit();
          FirestoreQueryBuilder.invalidateCache('school_teacher_valtar_rules');
          return <String, dynamic>{'saved_teachers': count};
        }

      case 'psm_leave_my_valtar_rule':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            return <String, dynamic>{'enabled': false, 'max_days': 0};
          }
          final data = await _cachedDocData(
                'school_teacher_valtar_rules',
                '${ctx.schoolRef}__${ctx.teacherId}',
              ) ??
              const <String, dynamic>{};
          final maxDays = num.tryParse('${data['max_days'] ?? 0}') ?? 0;
          final enabled = data['enabled'] == true && maxDays > 0;
          return <String, dynamic>{'enabled': enabled, 'max_days': maxDays};
        }

      case 'psm_teacher_delete_pending_leave':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            throw const PostgrestException(
              message: 'Please sign in again to delete this application.',
            );
          }
          final leaveId = '${p['p_leave_id'] ?? ''}'.trim();
          final row = await from('teacher_leaves')
              .select()
              .eq('id', leaveId)
              .eq('school_ref', schoolRef)
              .maybeSingle();
          if (row == null || '${row['teacher_id'] ?? ''}' != ctx.teacherId) {
            throw const PostgrestException(
              message:
                  'The leave application was not found in your own account.',
            );
          }
          if ('${row['status'] ?? ''}' != 'pending') {
            throw const PostgrestException(
              message: 'Only an application awaiting approval can be deleted.',
            );
          }
          await _db.collection('teacher_leaves').doc(leaveId).delete();
          FirestoreQueryBuilder.invalidateCache('teacher_leaves');
          return <String, dynamic>{'success': true, 'deleted_id': leaveId};
        }

      case 'psm_admin_delete_leave_with_password':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'માત્ર School Admin જ પાસવર્ડથી રજા રેકોર્ડ કાઢી શકે છે.',
            );
          }
          final leaveId = '${p['p_leave_id'] ?? ''}'.trim();
          final adminPassword = '${p['p_admin_password'] ?? ''}'.trim();
          if (leaveId.isEmpty) {
            throw const PostgrestException(
              message: 'રજા રેકોર્ડ ID મળ્યો નથી.',
            );
          }
          if (adminPassword.isEmpty) {
            throw const PostgrestException(
              message: 'કૃપા કરીને School Admin પાસવર્ડ દાખલ કરો.',
            );
          }

          final leaveSnap =
              await _db.collection('teacher_leaves').doc(leaveId).get();
          if (!leaveSnap.exists || leaveSnap.data() == null) {
            throw const PostgrestException(
              message: 'આ રજા રેકોર્ડ મળ્યો નથી અથવા પહેલેથી જ કાઢી નાખવામાં આવ્યો છે.',
            );
          }
          final leaveRow = leaveSnap.data()!;
          if ('${leaveRow['school_ref'] ?? ''}'.trim() != schoolRef) {
            throw const PostgrestException(
              message: 'આ રજા રેકોર્ડ તમારી શાળાનો નથી.',
            );
          }

          // Verify School Admin password against the school's Admin teacher row or Firebase Auth
          final teacherRows = await _cachedSchoolTableRows(
            'school_teachers',
            schoolRef,
          );
          Map<String, dynamic>? adminRow;
          for (final t in teacherRows) {
            if ('${t['id'] ?? ''}'.trim() == ctx.teacherId) {
              adminRow = t;
              break;
            }
          }
          adminRow ??= teacherRows.cast<Map<String, dynamic>?>().firstWhere(
            (t) => '${t?['role'] ?? ''}'.trim().toLowerCase() == 'admin',
            orElse: () => null,
          );

          var passwordVerified = false;
          final storedPlain =
              '${adminRow?['password_plain'] ?? adminRow?['password'] ?? ''}'
                  .trim();
          if (storedPlain.isNotEmpty && storedPlain == adminPassword) {
            passwordVerified = true;
          }
          if (!passwordVerified) {
            final loginEmail =
                '${adminRow?['login_email'] ?? auth.currentUser?.email ?? ''}'
                    .trim();
            if (loginEmail.isNotEmpty) {
              try {
                final helperAuth = await functions._getHelperAuth();
                final normalizedPwd = _toFirebasePassword(adminPassword);
                try {
                  await helperAuth.signInWithEmailAndPassword(
                    email: loginEmail,
                    password: adminPassword,
                  );
                  passwordVerified = true;
                } catch (_) {
                  if (normalizedPwd != adminPassword) {
                    await helperAuth.signInWithEmailAndPassword(
                      email: loginEmail,
                      password: normalizedPwd,
                    );
                    passwordVerified = true;
                  }
                }
                try {
                  await helperAuth.signOut();
                } catch (_) {}
              } catch (_) {
                passwordVerified = false;
              }
            }
          }

          if (!passwordVerified) {
            throw const PostgrestException(
              message: 'School Admin પાસવર્ડ ખોટો છે. કૃપા કરીને સાચો પાસવર્ડ દાખલ કરો.',
            );
          }

          final targetTeacherId = '${leaveRow['teacher_id'] ?? ''}'.trim();
          await _db.collection('teacher_leaves').doc(leaveId).delete();
          try {
            await _db
                .collection('teacher_leave_report_snapshots')
                .doc(leaveId)
                .delete();
          } catch (_) {}
          try {
            final snapQuery = await _db
                .collection('teacher_leave_report_snapshots')
                .where('school_ref', isEqualTo: schoolRef)
                .get();
            for (final doc in snapQuery.docs) {
              final d = doc.data();
              final docTid = '${d['teacher_id'] ?? ''}'.trim();
              if (docTid.isEmpty ||
                  targetTeacherId.isEmpty ||
                  docTid == targetTeacherId) {
                await doc.reference.delete();
              }
            }
          } catch (_) {}

          FirestoreQueryBuilder.invalidateCache('teacher_leaves');
          FirestoreQueryBuilder.invalidateCache(
            'teacher_leave_report_snapshots',
          );
          return <String, dynamic>{
            'deleted': true,
            'leave_id': leaveId,
            'teacher_id': targetTeacherId,
          };
        }

      case 'psm_admin_promote_students_with_password':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'માત્ર School Admin જ વાર્ષિક વર્ગ બઢતી કરી શકે છે.',
            );
          }
          final adminPassword = '${p['p_admin_password'] ?? ''}'.trim();
          if (adminPassword.isEmpty) {
            throw const PostgrestException(
              message: 'કૃપા કરીને School Admin પાસવર્ડ દાખલ કરો.',
            );
          }
          final teacherRows = await _cachedSchoolTableRows(
            'school_teachers',
            schoolRef,
          );
          Map<String, dynamic>? adminRow;
          for (final t in teacherRows) {
            if ('${t['id'] ?? ''}'.trim() == ctx.teacherId) {
              adminRow = t;
              break;
            }
          }
          adminRow ??= teacherRows.cast<Map<String, dynamic>?>().firstWhere(
            (t) => '${t?['role'] ?? ''}'.trim().toLowerCase() == 'admin',
            orElse: () => null,
          );
          var passwordVerified = false;
          final storedPlain =
              '${adminRow?['password_plain'] ?? adminRow?['password'] ?? ''}'
                  .trim();
          if (storedPlain.isNotEmpty && storedPlain == adminPassword) {
            passwordVerified = true;
          }
          if (!passwordVerified) {
            final loginEmail =
                '${adminRow?['login_email'] ?? auth.currentUser?.email ?? ''}'
                    .trim();
            if (loginEmail.isNotEmpty) {
              try {
                final helperAuth = await functions._getHelperAuth();
                final normalizedPwd = _toFirebasePassword(adminPassword);
                try {
                  await helperAuth.signInWithEmailAndPassword(
                    email: loginEmail,
                    password: adminPassword,
                  );
                  passwordVerified = true;
                } catch (_) {
                  if (normalizedPwd != adminPassword) {
                    await helperAuth.signInWithEmailAndPassword(
                      email: loginEmail,
                      password: normalizedPwd,
                    );
                    passwordVerified = true;
                  }
                }
                try {
                  await helperAuth.signOut();
                } catch (_) {}
              } catch (_) {
                passwordVerified = false;
              }
            }
          }
          if (!passwordVerified) {
            throw const PostgrestException(
              message: 'School Admin પાસવર્ડ ખોટો છે. કૃપા કરીને સાચો પાસવર્ડ દાખલ કરો.',
            );
          }

          final rawMappings = p['p_class_mappings'];
          if (rawMappings is! Map || rawMappings.isEmpty) {
            throw const PostgrestException(
              message: 'વર્ગ બઢતીનું મેપિંગ પસંદ કરો.',
            );
          }
          final mappings = <String, String>{};
          rawMappings.forEach((k, v) {
            final srcId = '$k'.trim();
            final dstId = '$v'.trim();
            if (srcId.isNotEmpty && dstId.isNotEmpty) {
              mappings[srcId] = dstId;
            }
          });
          final rawExcluded = p['p_exclude_student_ids'];
          final excludedIds = rawExcluded is Iterable
              ? rawExcluded.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toSet()
              : <String>{};
          final academicYearNote = '${p['p_academic_year_label'] ?? ''}'.trim();

          final allClasses = await _cachedSchoolTableRows(
            'school_classes',
            schoolRef,
          );
          final validClassIds = <String>{
            for (final c in allClasses)
              if (c['is_active'] != false) '${c['id'] ?? ''}'.trim(),
          };

          final studentSnap = await _db
              .collection('students')
              .where('school_ref', isEqualTo: schoolRef)
              .get();
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final todayIso = _indiaTodayIso();

          var promotedCount = 0;
          var passedOutCount = 0;
          var keptCount = 0;
          var batch = _db.batch();
          var ops = 0;

          Future<void> flushBatch() async {
            if (ops > 0) {
              await batch.commit();
              batch = _db.batch();
              ops = 0;
            }
          }

          for (final doc in studentSnap.docs) {
            final st = doc.data();
            final sid = '${st['id'] ?? doc.id}'.trim();
            final isAct = st['is_active'] == true &&
                '${st['leaving_date'] ?? ''}'.trim().isEmpty &&
                '${st['exit_date'] ?? ''}'.trim().isEmpty;
            if (!isAct) continue;
            final srcClassId = '${st['class_id'] ?? ''}'.trim();
            if (!mappings.containsKey(srcClassId)) continue;
            if (excludedIds.contains(sid)) {
              keptCount++;
              continue;
            }
            final target = mappings[srcClassId]!;
            if (target == '__KEEP__' || target == srcClassId) {
              keptCount++;
              continue;
            }
            if (target == '__PASS_OUT__') {
              final reason = academicYearNote.isEmpty
                  ? 'Passed Out / ઉતીર્ણ (વાર્ષિક વર્ગ બઢતી)'
                  : 'Passed Out / ઉતીર્ણ ($academicYearNote)';
              batch.set(
                doc.reference,
                <String, dynamic>{
                  'is_active': false,
                  'exit_date': todayIso,
                  'exit_reason': reason,
                  'promoted_at': nowIso,
                  'updated_at': nowIso,
                },
                fs.SetOptions(merge: true),
              );
              passedOutCount++;
              ops++;
            } else if (validClassIds.contains(target)) {
              batch.set(
                doc.reference,
                <String, dynamic>{
                  'class_id': target,
                  'promoted_from_class_id': srcClassId,
                  'promoted_at': nowIso,
                  'updated_at': nowIso,
                },
                fs.SetOptions(merge: true),
              );
              promotedCount++;
              ops++;
            } else {
              keptCount++;
            }
            if (ops >= 400) {
              await flushBatch();
            }
          }
          await flushBatch();
          FirestoreQueryBuilder.invalidateCache('students');
          return <String, dynamic>{
            'ok': true,
            'promoted_count': promotedCount,
            'passed_out_count': passedOutCount,
            'kept_count': keptCount,
          };
        }

      case 'psm_compute_absence_streaks_and_alerts':
        {
          final schoolRef = await _requireSchoolReadAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            throw const PostgrestException(message: 'Please sign in again.');
          }
          final filterClassId = '${p['p_class_id'] ?? ''}'.trim();
          final roleScope = ctx.isAdmin ? 'admin' : 'teacher';
          return _computeStudentAbsenceStreaksAndAlerts(
            schoolRef: schoolRef,
            ctx: ctx,
            filterClassId: filterClassId,
            roleScope: roleScope,
          );
        }

      case 'psm_ack_absence_alert':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final rawKeys = p['p_ack_keys'];
          final keys = rawKeys is Iterable
              ? rawKeys.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList()
              : <String>[];
          final nowIso = DateTime.now().toUtc().toIso8601String();
          var batch = _db.batch();
          var ops = 0;
          for (final k in keys) {
            batch.set(
              _db.collection('student_absence_alert_acks').doc(k),
              <String, dynamic>{
                'id': k,
                'school_ref': schoolRef,
                'acked_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            ops++;
            if (ops >= 400) {
              await batch.commit();
              batch = _db.batch();
              ops = 0;
            }
          }
          if (ops > 0) await batch.commit();
          FirestoreQueryBuilder.invalidateCache('student_absence_alert_acks');
          return <String, dynamic>{'ok': true, 'acked': keys.length};
        }

      case 'psm_get_academic_calendar':
        {
          final schoolRef = await _requireSchoolReadAccess();
          final rows = await _cachedSchoolTableRows(
            'school_academic_events',
            schoolRef,
          );
          final list = rows
              .where((r) => r['is_active'] != false)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          list.sort(
            (a, b) => '${a['event_date'] ?? ''}'.compareTo(
              '${b['event_date'] ?? ''}',
            ),
          );
          return list;
        }

      case 'psm_save_academic_calendar_event':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'માત્ર School Admin જ શૈક્ષણિક કેલેન્ડર ઉમેરી/સુધારી શકે છે.',
            );
          }
          final eventDate = '${p['p_event_date'] ?? ''}'.trim();
          final title = '${p['p_title'] ?? ''}'.trim();
          if (eventDate.isEmpty || title.isEmpty) {
            throw const PostgrestException(
              message: 'તારીખ અને કાર્યક્રમનું નામ જરૂરી છે.',
            );
          }
          final id = '${p['p_id'] ?? ''}'.trim().isNotEmpty
              ? '${p['p_id']}'.trim()
              : _generateUuid();
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final payload = <String, dynamic>{
            'id': id,
            'school_ref': schoolRef,
            'event_date': eventDate,
            'end_date': '${p['p_end_date'] ?? eventDate}'.trim().isEmpty
                ? eventDate
                : '${p['p_end_date']}'.trim(),
            'title': title,
            'category': '${p['p_category'] ?? 'પરીક્ષા / Exam'}'.trim(),
            'notes': '${p['p_notes'] ?? ''}'.trim(),
            'is_active': true,
            'updated_by': ctx.teacherId,
            'updated_at': nowIso,
          };
          await _db
              .collection('school_academic_events')
              .doc(id)
              .set(payload, fs.SetOptions(merge: true));
          FirestoreQueryBuilder.invalidateCache('school_academic_events');
          return payload;
        }

      case 'psm_delete_academic_calendar_event':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'માત્ર School Admin જ શૈક્ષણિક કેલેન્ડર કાઢી શકે છે.',
            );
          }
          final id = '${p['p_id'] ?? ''}'.trim();
          if (id.isNotEmpty) {
            final snap = await _db.collection('school_academic_events').doc(id).get();
            if (snap.exists &&
                '${snap.data()?['school_ref'] ?? ''}'.trim() == schoolRef) {
              await snap.reference.delete();
            }
            FirestoreQueryBuilder.invalidateCache('school_academic_events');
          }
          return <String, dynamic>{'deleted': true};
        }

      case 'psm_get_weekly_meal_menu':
        {
          final schoolRef = await _requireSchoolReadAccess();
          final doc = await _cachedDocData('school_weekly_meal_menus', schoolRef);
          if (doc == null) {
            return <String, dynamic>{
              'enabled': false,
              'days': <String, dynamic>{},
            };
          }
          return <String, dynamic>{
            'enabled': doc['enabled'] != false,
            'days': doc['days'] is Map
                ? Map<String, dynamic>.from(doc['days'] as Map)
                : <String, dynamic>{},
            'updated_at': doc['updated_at'] ?? '',
          };
        }

      case 'psm_save_weekly_meal_menu':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'માત્ર School Admin જ સાપ્તાહિક PM POSHAN અને અલ્પાહાર મેનુ સેટ કરી શકે છે.',
            );
          }
          final enabled = p['p_enabled'] != false;
          final rawDays = p['p_days'];
          final days = rawDays is Map
              ? rawDays.map((k, v) => MapEntry('$k', v))
              : <String, dynamic>{};
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final payload = <String, dynamic>{
            'id': schoolRef,
            'school_ref': schoolRef,
            'enabled': enabled,
            'days': days,
            'updated_by': ctx.teacherId,
            'updated_at': nowIso,
          };
          await _db
              .collection('school_weekly_meal_menus')
              .doc(schoolRef)
              .set(payload, fs.SetOptions(merge: true));
          FirestoreQueryBuilder.invalidateCache('school_weekly_meal_menus');
          return payload;
        }

      case 'psm_restore_disappeared_or_archived_students':
        {
          final schoolRef = await _requireSchoolWriteAccess(
            explicitSchoolRef: '${p['p_school_ref'] ?? ''}',
          );
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only School Admin can restore / activate deactivated students.',
            );
          }
          final targetClassId = '${p['p_target_class_id'] ?? ''}'.trim();
          final filterClassId = '${p['p_class_id'] ?? ''}'.trim();
          final rawIds = p['p_student_ids'];
          final idSet = rawIds is List
              ? rawIds
                    .map((e) => '$e'.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet()
              : <String>{};
          return _restoreDisappearedOrArchivedStudents(
            schoolRef: schoolRef,
            classId: filterClassId,
            targetClassId: targetClassId,
            studentIds: idSet,
          );
        }

      case 'psm_move_students_to_class':
        {
          final schoolRef = await _requireSchoolWriteAccess(
            explicitSchoolRef: '${p['p_school_ref'] ?? ''}',
          );
          final fromClassId = '${p['p_from_class_id'] ?? ''}'.trim();
          final toClassId = '${p['p_to_class_id'] ?? ''}'.trim();
          final rawIds = p['p_student_ids'];
          final idSet = rawIds is List
              ? rawIds
                    .map((e) => '$e'.trim())
                    .where((s) => s.isNotEmpty)
                    .toSet()
              : <String>{};
          return _moveStudentsToClass(
            schoolRef: schoolRef,
            fromClassId: fromClassId,
            toClassId: toClassId,
            studentIds: idSet,
          );
        }

      case 'psm_library_student_roster':
        {
          final ctx = await _resolveCurrentTeacherContext();
          if (ctx == null) {
            throw const PostgrestException(
              message: 'Please sign in to the school account.',
            );
          }
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final rows = await from('students')
              .select('id,school_ref,class_id,roll_number,name,gr,is_active')
              .eq('school_ref', ctx.schoolRef)
              .eq('class_id', classId)
              .eq('is_active', true);
          rows.sort(_compareStudentsByRoll);
          return rows;
        }

      case 'psm_library_bulk_add_books':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message:
                  'Bulk book upload is available only to the School Admin.',
            );
          }
          final rows = p['p_rows'] is List
              ? (p['p_rows'] as List)
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList()
              : <Map<String, dynamic>>[];
          return _libraryBulkAddBooks(schoolRef, rows);
        }

      case 'psm_library_archive_book':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the School Admin can remove a book from the active catalogue.',
            );
          }
          final bookId = '${p['p_book_id'] ?? ''}'.trim();
          final reasonCode = '${p['p_reason_code'] ?? 'other'}'.trim();
          final reasonDetails = '${p['p_reason_details'] ?? ''}'.trim();
          return _libraryArchiveBook(
            schoolRef: schoolRef,
            bookId: bookId,
            reasonCode: reasonCode,
            reasonDetails: reasonDetails,
          );
        }

      case 'psm_library_change_book_number':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the School Admin can change book numbers.',
            );
          }
          final bookId = '${p['p_book_id'] ?? ''}'.trim();
          final newNumber = '${p['p_new_book_number'] ?? ''}'.trim();
          return _libraryChangeBookNumber(
            schoolRef: schoolRef,
            bookId: bookId,
            newNumber: newNumber,
          );
        }

      case 'psm_library_issue_book':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          return _libraryIssueBook(schoolRef: schoolRef, params: p);
        }

      case 'psm_library_return_book':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          return _libraryReturnBook(schoolRef: schoolRef, params: p);
        }

      case 'psm_library_save_settings':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          if (!await _isCurrentUserAdmin()) {
            throw const PostgrestException(
              message: 'Only the School Admin can update library settings.',
            );
          }
          final dueDays = int.tryParse('${p['p_due_days'] ?? 14}') ?? 14;
          final maxBooks =
              int.tryParse('${p['p_max_books_per_borrower'] ?? 1}') ?? 1;
          final finePerDay =
              num.tryParse('${p['p_fine_per_day'] ?? 0}')?.toDouble() ?? 0.0;
          final permission =
              '${p['p_student_issue_permission'] ?? 'class_teacher_only'}'
                  .trim();
          final allowedIds = p['p_allowed_teacher_ids'] is List
              ? (p['p_allowed_teacher_ids'] as List)
                    .map((e) => '$e'.trim())
                    .where((s) => s.isNotEmpty)
                    .toList()
              : <String>[];
          final payload = <String, dynamic>{
            'id': schoolRef,
            'school_ref': schoolRef,
            'due_days': dueDays,
            'max_books_per_borrower': maxBooks,
            'fine_per_day': finePerDay,
            'student_issue_permission': permission,
            'allowed_student_issue_teacher_ids': allowedIds,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          };
          await _db
              .collection('library_settings')
              .doc(schoolRef)
              .set(payload, fs.SetOptions(merge: true));
          FirestoreQueryBuilder.invalidateCache('library_settings');
          return payload;
        }

      case 'psm_set_attendance_freeze_status':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can freeze or unfreeze attendance.',
              code: '42501',
            );
          }
          final dayId = '${p['p_day_id'] ?? ''}'.trim();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          final attendanceDate = '${p['p_attendance_date'] ?? ''}'.trim();
          final isFrozen = p['p_is_frozen'] == true ||
              '${p['p_is_frozen']}'.toLowerCase() == 'true';

          Map<String, dynamic>? targetDay;
          if (dayId.isNotEmpty) {
            targetDay = await from('attendance_days')
                .select()
                .eq('id', dayId)
                .eq('school_ref', schoolRef)
                .maybeSingle();
          } else if (classId.isNotEmpty && attendanceDate.isNotEmpty) {
            targetDay = await from('attendance_days')
                .select()
                .eq('school_ref', schoolRef)
                .eq('class_id', classId)
                .eq('attendance_date', attendanceDate)
                .maybeSingle();
          }
          if (targetDay == null || '${targetDay['id'] ?? ''}'.trim().isEmpty) {
            throw const PostgrestException(
              message: 'Attendance record not found for the selected class and date.',
            );
          }
          final resolvedId = '${targetDay['id']}'.trim();
          final section = '${p['p_section'] ?? 'all'}'.trim().toLowerCase();
          final nowIso = DateTime.now().toUtc().toIso8601String();
          bool pFrozen = targetDay['present_frozen'] == true ||
              (targetDay['present_frozen'] == null && targetDay['is_frozen'] == true);
          bool mFrozen = targetDay['mdm_frozen'] == true ||
              (targetDay['mdm_frozen'] == null && targetDay['is_frozen'] == true);
          bool bFrozen = targetDay['breakfast_frozen'] == true ||
              (targetDay['breakfast_frozen'] == null && targetDay['is_frozen'] == true);
          if (section == 'present') {
            pFrozen = isFrozen;
          } else if (section == 'mdm') {
            mFrozen = isFrozen;
          } else if (section == 'breakfast') {
            bFrozen = isFrozen;
          } else {
            pFrozen = isFrozen;
            mFrozen = isFrozen;
            bFrozen = isFrozen;
          }
          final overallFrozen = pFrozen && mFrozen && bFrozen;
          final updated = <String, dynamic>{
            ...targetDay,
            'present_frozen': pFrozen,
            'mdm_frozen': mFrozen,
            'breakfast_frozen': bFrozen,
            'is_frozen': overallFrozen,
            'unfrozen_by_admin': !overallFrozen,
            'unfrozen_by_admin_at': !overallFrozen ? nowIso : targetDay['unfrozen_by_admin_at'],
            'updated_at': nowIso,
          };
          await _db
              .collection('attendance_days')
              .doc(resolvedId)
              .set(updated, fs.SetOptions(merge: true));
          FirestoreQueryBuilder.invalidateCache('attendance_days');
          return updated;
        }

      case 'psm_renumber_class_rolls':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final classId = '${p['p_class_id'] ?? ''}'.trim();
          if (classId.isNotEmpty) {
            await _renumberActiveClassStudentsContinually(
              schoolRef: schoolRef,
              classId: classId,
            );
          } else {
            final classes = await from('school_classes')
                .select('id')
                .eq('school_ref', schoolRef);
            for (final c in classes) {
              final cid = '${c['id'] ?? ''}'.trim();
              if (cid.isNotEmpty) {
                await _renumberActiveClassStudentsContinually(
                  schoolRef: schoolRef,
                  classId: cid,
                );
              }
            }
          }
          return true;
        }

      case 'psm_get_class_promotion_preview':
        {
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can access Class Promotion.',
              code: '42501',
            );
          }
          return _getClassPromotionPreview(schoolRef: ctx.schoolRef);
        }

      case 'psm_set_second_sem_result_date':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can update the Second Semester Result Date.',
              code: '42501',
            );
          }
          final rawDate = '${p['p_result_date'] ?? ''}'.trim();
          return _setSecondSemResultDate(
            schoolRef: schoolRef,
            rawResultDate: rawDate,
          );
        }

      case 'psm_promote_school_classes':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can promote classes.',
              code: '42501',
            );
          }
          final retainedRaw = p['p_retained_student_ids'];
          final retainedIds = retainedRaw is List
              ? retainedRaw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet()
              : <String>{};
          final targetMapRaw = p['p_student_target_class_map'];
          final targetClassMap = targetMapRaw is Map
              ? targetMapRaw.map((k, v) => MapEntry('$k'.trim(), '$v'.trim()))
              : <String, String>{};
          final classTargetMapRaw = p['p_class_target_class_map'];
          final classTargetClassMap = classTargetMapRaw is Map
              ? classTargetMapRaw.map((k, v) => MapEntry('$k'.trim(), '$v'.trim()))
              : <String, String>{};
          final newClassEnrollDate = '${p['p_new_class_enroll_date'] ?? ''}'.trim();
          final keepSameTeacher = p['p_keep_same_class_teacher'] != false;
          final rawTeacherMap = p['p_new_class_teacher_map'];
          final newClassTeacherMap = rawTeacherMap is Map
              ? rawTeacherMap.map((k, v) => MapEntry('$k'.trim(), '$v'.trim()))
              : <String, String>{};
          return _promoteSchoolClasses(
            schoolRef: schoolRef,
            retainedStudentIds: retainedIds,
            studentTargetClassMap: targetClassMap,
            classTargetClassMap: classTargetClassMap,
            newClassEnrollDate: newClassEnrollDate,
            keepSameClassTeacher: keepSameTeacher,
            newClassTeacherMap: newClassTeacherMap,
          );
        }

      case 'psm_change_student_section_only':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can change student sections.',
              code: '42501',
            );
          }
          final toClassId = '${p['p_to_class_id'] ?? ''}'.trim();
          final effectiveDateRaw = '${p['p_effective_date'] ?? ''}'.trim();
          final rawIds = p['p_student_ids'];
          final studentIds = rawIds is List
              ? rawIds.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet()
              : <String>{};
          return _changeStudentSectionOnly(
            schoolRef: schoolRef,
            toClassId: toClassId,
            studentIds: studentIds,
            rawEffectiveDate: effectiveDateRaw,
          );
        }

      case 'psm_admin_delete_school_data':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final ctx = await _resolveCurrentTeacherContext(forceRefresh: true);
          if (ctx == null || !ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only the School Admin can delete school data.',
              code: '42501',
            );
          }
          final scope = '${p['p_scope'] ?? 'all'}'.trim().toLowerCase();
          final backupDownloaded = p['p_backup_downloaded'] == true;
          if (!backupDownloaded) {
            throw const PostgrestException(
              message:
                  'ડેટા ડિલીટ કરતા પહેલાં તમામ બેકઅપ Excel રિપોર્ટ (Ekandar, Students, Book List, Library Register) એક પછી એક ડાઉનલોડ કરવા ફરજિયાત છે.',
              code: 'P0001',
            );
          }
          var deletedAttendance = 0;
          var deletedStudents = 0;
          var deletedBooks = 0;
          var deletedTransactions = 0;

          final attMode = '${p['p_attendance_mode'] ?? 'whole'}'.trim().toLowerCase();
          final fromDateIso = '${p['p_from_date'] ?? ''}'.trim();
          final toDateIso = '${p['p_to_date'] ?? ''}'.trim();
          final isDateRange = attMode == 'date_range' &&
              fromDateIso.length >= 10 &&
              toDateIso.length >= 10;

          if (scope == 'attendance' || scope == 'all') {
            if (isDateRange && scope == 'attendance') {
              final daysSnap = await _db
                  .collection('attendance_days')
                  .where('school_ref', isEqualTo: schoolRef)
                  .get();
              final targetDayIds = <String>{};
              for (final d in daysSnap.docs) {
                final data = d.data();
                final dt = '${data['attendance_date'] ?? ''}'.trim();
                final dShort = dt.length >= 10 ? dt.substring(0, 10) : dt;
                if (dShort.isNotEmpty &&
                    dShort.compareTo(fromDateIso) >= 0 &&
                    dShort.compareTo(toDateIso) <= 0) {
                  final did = '${data['id'] ?? d.id}'.trim();
                  if (did.isNotEmpty) targetDayIds.add(did);
                  targetDayIds.add(d.id);
                  await d.reference.delete();
                  deletedAttendance++;
                }
              }
              final marksSnap = await _db
                  .collection('student_attendance')
                  .where('school_ref', isEqualTo: schoolRef)
                  .get();
              for (final m in marksSnap.docs) {
                final mData = m.data();
                final dayId = '${mData['attendance_day_id'] ?? ''}'.trim();
                final mDate = '${mData['attendance_date'] ?? ''}'.trim();
                final mShort = mDate.length >= 10 ? mDate.substring(0, 10) : mDate;
                final inRange = mShort.isNotEmpty &&
                    mShort.compareTo(fromDateIso) >= 0 &&
                    mShort.compareTo(toDateIso) <= 0;
                if (targetDayIds.contains(dayId) || inRange) {
                  await m.reference.delete();
                  deletedAttendance++;
                }
              }
            } else {
              for (final col in const <String>[
                'student_attendance',
                'attendance_days',
                'hajari_patrak_present_days',
              ]) {
                final snap = await _db
                    .collection(col)
                    .where('school_ref', isEqualTo: schoolRef)
                    .get();
                for (final d in snap.docs) {
                  await d.reference.delete();
                  deletedAttendance++;
                }
              }
            }
            FirestoreQueryBuilder.invalidateCache('attendance_days');
            FirestoreQueryBuilder.invalidateCache('student_attendance');
          }
          if (scope == 'students' || scope == 'all') {
            final snap = await _db
                .collection('students')
                .where('school_ref', isEqualTo: schoolRef)
                .get();
            for (final d in snap.docs) {
              await d.reference.delete();
              deletedStudents++;
            }
          }
          if (scope == 'library' || scope == 'all') {
            final bSnap = await _db
                .collection('library_books')
                .where('school_ref', isEqualTo: schoolRef)
                .get();
            for (final d in bSnap.docs) {
              await d.reference.delete();
              deletedBooks++;
            }
            for (final col in const <String>[
              'library_transactions',
              'library_book_number_history',
            ]) {
              final tSnap = await _db
                  .collection(col)
                  .where('school_ref', isEqualTo: schoolRef)
                  .get();
              for (final d in tSnap.docs) {
                await d.reference.delete();
                deletedTransactions++;
              }
            }
          }
          return <String, dynamic>{
            'ok': true,
            'scope': scope,
            'deleted_attendance': deletedAttendance,
            'deleted_students': deletedStudents,
            'deleted_books': deletedBooks,
            'deleted_transactions': deletedTransactions,
          };
        }

      case 'psm_get_developer_shared_files':
        {
          final today = _indiaTodayIso();
          final rawRows = await from('developer_shared_files').select();
          final files = <Map<String, dynamic>>[];
          for (final data in rawRows) {
            if (data['is_active'] == false) continue;
            final dispDate = _extractIndiaDateIsoFromAny(
              data['display_date'] ?? data['created_at'] ?? data['updated_at'],
            );
            if (dispDate.isNotEmpty && dispDate.compareTo(today) < 0) {
              continue;
            }
            files.add(<String, dynamic>{
              ...data,
              'id': data['id'] ?? '',
            });
          }
          files.sort(
            (a, b) => '${b['created_at'] ?? ''}'.compareTo(
              '${a['created_at'] ?? ''}',
            ),
          );
          return files;
        }

      case 'psm_download_developer_shared_file':
        {
          final fileId = '${p['p_file_id'] ?? ''}'.trim();
          if (fileId.isEmpty) {
            throw const PostgrestException(message: 'File ID is required.');
          }
          final metaDoc = await _db
              .collection('developer_shared_files')
              .doc(fileId)
              .get();
          if (!metaDoc.exists || metaDoc.data() == null) {
            throw const PostgrestException(
              message: 'This file is no longer available.',
            );
          }
          final meta = Map<String, dynamic>.from(metaDoc.data()!);
          final dispDate = _extractIndiaDateIsoFromAny(
            meta['display_date'] ?? meta['created_at'] ?? meta['updated_at'],
          );
          if (meta['is_active'] == false ||
              (dispDate.isNotEmpty && dispDate.compareTo(_indiaTodayIso()) < 0)) {
            throw const PostgrestException(
              message: 'This file has expired and is no longer available.',
            );
          }
          final assetDocId =
              '${meta['asset_doc_id'] ?? 'dev_shared__$fileId'}'.trim();
          final assetDoc = await _db
              .collection('school_assets')
              .doc(assetDocId)
              .get();
          final b64 = '${assetDoc.data()?['base64'] ?? meta['base64'] ?? ''}';
          return <String, dynamic>{
            ...meta,
            'base64': b64,
          };
        }

      case 'psm_smart_bulk_import_students':
        {
          final schoolRef = await _requireSchoolWriteAccess();
          final rawRows = p['p_rows'];
          final rows = rawRows is List
              ? rawRows
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList()
              : <Map<String, dynamic>>[];
          final defaultClassId = '${p['p_default_class_id'] ?? ''}'.trim();
          return _smartBulkImportStudents(
            schoolRef: schoolRef,
            rows: rows,
            defaultClassId: defaultClassId,
          );
        }

      default:
        throw PostgrestException(message: 'Unsupported RPC: $fnName');
    }
  }

  static int _compareStudentsByRoll(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final ar = int.tryParse('${a['roll_number'] ?? ''}'.trim());
    final br = int.tryParse('${b['roll_number'] ?? ''}'.trim());
    if (ar != null && br != null) return ar.compareTo(br);
    if (ar != null) return -1;
    if (br != null) return 1;
    return '${a['roll_number'] ?? ''}'.compareTo('${b['roll_number'] ?? ''}');
  }

  String _canonicalReportCategory(dynamic rawValue) {
    final raw = '${rawValue ?? "OTHER"}'.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (raw == 'ST' || raw == 'S.T' || raw == 'S.T.' || raw.contains('અ.જ.જા')) {
      return 'ST';
    }
    if (raw == 'SC' || raw == 'S.C' || raw == 'S.C.' || raw.contains('અ.જા')) {
      return 'SC';
    }
    if (raw == 'OBC' || raw == 'SEBC' || raw.contains('બ.પં') || raw.contains('બક્ષી')) {
      return 'OBC';
    }
    return 'OTHER';
  }

  String _canonicalReportSchoolType(Map<String, dynamic> schoolRow) {
    // The registered school_type wins; the name is only a fallback for very
    // old schools without a type (a mixed school may be named "Kumar Shala").
    return SchoolType.resolve(
      <dynamic>[schoolRow['school_type'], schoolRow['schoolType']],
      nameCandidates: <dynamic>[
        schoolRow['school_name_gu'],
        schoolRow['school_name'],
        schoolRow['school_name_en'],
      ],
    );
  }

  String _canonicalReportGender(dynamic rawValue, [String schoolType = 'mixed']) {
    final st = SchoolType.canonical(schoolType);
    if (st == SchoolType.boys) return 'BOYS';
    if (st == SchoolType.girls) return 'GIRLS';
    final raw = '${rawValue ?? ""}'.trim().toUpperCase();
    if (const <String>{'BOYS', 'BOY', 'MALE', 'M', 'KUMAR', 'કુમાર', 'છોકરો', 'છોકરા'}.contains(raw)) {
      return 'BOYS';
    }
    if (const <String>{'GIRLS', 'GIRL', 'FEMALE', 'F', 'KANYA', 'કન્યા', 'છોકરી', 'છોકરીઓ'}.contains(raw)) {
      return 'GIRLS';
    }
    return 'UNSPECIFIED';
  }

  String? _studentAdmissionIso(Map<String, dynamic> s) {
    final isPromoted =
        '${s['last_promotion_status'] ?? ''}'.trim().toLowerCase() == 'promoted';
    const keys = <String>['enroll_school', 'enrollment_date', 'admission_date', 'enroll_class'];
    for (final key in keys) {
      if (key == 'enroll_class' && isPromoted) continue;
      final raw = '${s[key] ?? ""}'.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') continue;
      final parsed = _parseAnyDateToIso(raw);
      if (parsed != null) return parsed;
    }
    final cf = s['custom_fields'];
    if (cf is Map) {
      for (final key in keys) {
        if (key == 'enroll_class' && isPromoted) continue;
        final raw = '${cf[key] ?? ""}'.trim();
        if (raw.isEmpty || raw.toLowerCase() == 'null') continue;
        final parsed = _parseAnyDateToIso(raw);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String? _studentExitIso(Map<String, dynamic> s) {
    const keys = <String>['leaving_date', 'exit_date', 'left_date'];
    for (final key in keys) {
      final raw = '${s[key] ?? ""}'.trim();
      if (raw.isEmpty || raw.toLowerCase() == 'null') continue;
      final parsed = _parseAnyDateToIso(raw);
      if (parsed != null) return parsed;
    }
    final cf = s['custom_fields'];
    if (cf is Map) {
      for (final key in keys) {
        final raw = '${cf[key] ?? ""}'.trim();
        if (raw.isEmpty || raw.toLowerCase() == 'null') continue;
        final parsed = _parseAnyDateToIso(raw);
        if (parsed != null) return parsed;
      }
    }
    if (s['is_active'] == false) {
      final fallback = _parseAnyDateToIso('${s['updated_at'] ?? ""}');
      if (fallback != null) return fallback;
    }
    return null;
  }

  String _studentExitReasonNormalized(Map<String, dynamic> s) {
    for (final key in const <String>[
      'exit_reason',
      'leaving_reason',
      'reason_for_leaving',
      'archive_reason',
    ]) {
      final raw = '${s[key] ?? ""}'.trim();
      if (raw.isNotEmpty && raw.toLowerCase() != 'null') {
        return raw.toLowerCase();
      }
    }
    final cf = s['custom_fields'];
    if (cf is Map) {
      for (final entry in cf.entries) {
        final k = '${entry.key}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\u0A80-\u0AFF]'), '');
        if (const <String>{
          'exitreason',
          'leavingreason',
          'reasonforleaving',
          'archivereason',
          'inactivereason',
          'removalreason',
          'reason',
          'નામકમીકારણ',
          'ગેરહાજરીનાકારણ',
          'કારણ',
        }.contains(k)) {
          final v = '${entry.value ?? ""}'.trim();
          if (v.isNotEmpty && v.toLowerCase() != 'null') {
            return v.toLowerCase();
          }
        }
      }
    }
    return '';
  }

  bool _studentEligibleForReportDate(Map<String, dynamic> s, String dateIso) {
    final adm = _studentAdmissionIso(s);
    final ex = _studentExitIso(s);
    if (adm != null && dateIso.compareTo(adm) < 0) return false;
    if (ex != null && dateIso.compareTo(ex) >= 0) return false;
    if (ex == null && s['is_active'] == false) return false;
    return true;
  }

  String _effectiveClassIdForStudentOnDate(Map<String, dynamic> s, String dateIso) {
    final currentCid = '${s['class_id'] ?? ''}'.trim();
    dynamic rawHist = s['section_history'];
    if (rawHist is! List && s['custom_fields'] is Map) {
      rawHist = (s['custom_fields'] as Map)['section_history'];
    }
    if (rawHist is! List || rawHist.isEmpty) return currentCid;
    final entries = rawHist
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) =>
            '${e['from_class_id'] ?? ''}'.trim().isNotEmpty &&
            '${e['to_class_id'] ?? ''}'.trim().isNotEmpty)
        .toList();
    if (entries.isEmpty) return currentCid;
    entries.sort((a, b) {
      final da = _parseAnyDateToIso('${a['effective_date'] ?? ''}') ?? '';
      final db = _parseAnyDateToIso('${b['effective_date'] ?? ''}') ?? '';
      return da.compareTo(db);
    });
    var cid = '${entries.first['from_class_id'] ?? currentCid}'.trim();
    for (final entry in entries) {
      final effIso = _parseAnyDateToIso('${entry['effective_date'] ?? ''}');
      if (effIso != null && dateIso.compareTo(effIso) >= 0) {
        cid = '${entry['to_class_id'] ?? cid}'.trim();
      }
    }
    return cid.isEmpty ? currentCid : cid;
  }

  Future<Map<String, dynamic>> _calculateCategoryGenderBreakdown({
    required String schoolRef,
    required String classId,
    required String date,
    String? schoolTypeHint,
  }) async {
    String schoolType = schoolTypeHint ?? '';
    if (schoolType.isEmpty) {
      final schoolData = await _cachedDocData('schools', schoolRef);
      schoolType = _canonicalReportSchoolType(schoolData ?? const <String, dynamic>{});
    }
    final allSchoolStudentsForDate = await from('students')
        .select('id,class_id,category,gender,is_active,enroll_school,enrollment_date,admission_date,enroll_class,leaving_date,exit_date,section_history,custom_fields')
        .eq('school_ref', schoolRef);
    final students = allSchoolStudentsForDate
        .where((s) =>
            _effectiveClassIdForStudentOnDate(s, date) == classId &&
            _studentEligibleForReportDate(s, date))
        .toList();

    final dayRow = await from('attendance_days')
        .select('id')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_date', date)
        .maybeSingle();

    final marksByStudent = <String, Map<String, dynamic>>{};
    if (dayRow != null && '${dayRow['id'] ?? ''}'.isNotEmpty) {
      final marks = await from('student_attendance')
          .select('student_id,present,mdm,breakfast')
          .eq('school_ref', schoolRef)
          .eq('class_id', classId)
          .eq('attendance_day_id', '${dayRow['id']}');
      for (final m in marks) {
        marksByStudent['${m['student_id']}'] = m;
      }
    }

    const genders = <String>['BOYS', 'GIRLS', 'UNSPECIFIED'];
    const categories = <String>['SC', 'ST', 'OBC', 'OTHER'];
    final out = <String, dynamic>{};

    for (final g in genders) {
      final byCat = <String, dynamic>{};
      for (final c in categories) {
        byCat[c] = <String, int>{
          'registered': 0,
          'present': 0,
          'mdm': 0,
          'breakfast': 0,
        };
      }
      byCat['_OVERALL'] = <String, int>{
        'registered': 0,
        'present': 0,
        'mdm': 0,
        'breakfast': 0,
      };
      out[g] = byCat;
    }

    for (final s in students) {
      final cat = _canonicalReportCategory(s['category']);
      final gen = _canonicalReportGender(s['gender'], schoolType);
      final mark = marksByStudent['${s['id']}'];
      final present = mark?['present'] == true;
      final mdm = present && mark?['mdm'] == true;
      final breakfast = present && mark?['breakfast'] == true;

      final cell = (out[gen] as Map<String, dynamic>)[cat] as Map<String, int>;
      final overall =
          (out[gen] as Map<String, dynamic>)['_OVERALL'] as Map<String, int>;

      cell['registered'] = (cell['registered'] ?? 0) + 1;
      overall['registered'] = (overall['registered'] ?? 0) + 1;
      if (present) {
        cell['present'] = (cell['present'] ?? 0) + 1;
        overall['present'] = (overall['present'] ?? 0) + 1;
      }
      if (mdm) {
        cell['mdm'] = (cell['mdm'] ?? 0) + 1;
        overall['mdm'] = (overall['mdm'] ?? 0) + 1;
      }
      if (breakfast) {
        cell['breakfast'] = (cell['breakfast'] ?? 0) + 1;
        overall['breakfast'] = (overall['breakfast'] ?? 0) + 1;
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> _refreshAttendanceDayCounts(String dayId) async {
    final day = await from('attendance_days')
        .select()
        .eq('id', dayId)
        .maybeSingle();
    if (day == null) {
      throw const PostgrestException(message: 'Attendance day not found');
    }
    final schoolRef = '${day['school_ref']}';
    final classId = '${day['class_id']}';
    final date = '${day['attendance_date']}';

    final breakdown = await _calculateCategoryGenderBreakdown(
      schoolRef: schoolRef,
      classId: classId,
      date: date,
    );

    final registered = <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0};
    final present = <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0};
    final mdm = <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0};
    int breakfastTotal = 0;

    for (final g in const <String>['BOYS', 'GIRLS', 'UNSPECIFIED']) {
      final gMap = breakdown[g] as Map<String, dynamic>? ?? const {};
      for (final c in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
        final cell = gMap[c] as Map<String, dynamic>? ?? const {};
        registered[c] =
            (registered[c] ?? 0) +
            (int.tryParse('${cell['registered'] ?? 0}') ?? 0);
        present[c] =
            (present[c] ?? 0) + (int.tryParse('${cell['present'] ?? 0}') ?? 0);
        mdm[c] = (mdm[c] ?? 0) + (int.tryParse('${cell['mdm'] ?? 0}') ?? 0);
      }
      final overall = gMap['_OVERALL'] as Map<String, dynamic>? ?? const {};
      breakfastTotal += int.tryParse('${overall['breakfast'] ?? 0}') ?? 0;
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final updated = <String, dynamic>{
      ...day,
      'registered_counts': registered,
      'present_counts': present,
      'mdm_counts': mdm,
      'breakfast_total': breakfastTotal,
      'gender_breakdown': breakdown,
      'student_details_saved': true,
      'is_frozen': true,
      'unfrozen_by_admin': false,
      'frozen_at': nowIso,
      'updated_at': nowIso,
    };

    await _db
        .collection('attendance_days')
        .doc('${day['id']}')
        .set(updated, fs.SetOptions(merge: true));
    FirestoreQueryBuilder.invalidateCache('attendance_days');
    return updated;
  }

  Future<List<Map<String, dynamic>>> _schoolwideAttendanceReportRows({
    required _TeacherSessionContext ctx,
    String? fromDate,
    String? toDate,
  }) async {
    final allClasses = await from('school_classes')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final classes = allClasses
        .where((c) => c['is_active'] != false)
        .toList();
    classes.sort((a, b) {
      final sa = int.tryParse('${a['sort_order'] ?? 0}') ?? 0;
      final sb = int.tryParse('${b['sort_order'] ?? 0}') ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return '${a['label']}'.compareTo('${b['label']}');
    });

    final allDays = await from('attendance_days')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final daysByClass = <String, List<Map<String, dynamic>>>{};
    for (final d in allDays) {
      final dt = '${d['attendance_date'] ?? ''}'.trim();
      if (dt.isEmpty) continue;
      if (fromDate != null && toDate != null && fromDate == toDate) {
        if (dt != fromDate) continue;
      } else {
        if (fromDate != null && dt.compareTo(fromDate) < 0) continue;
        if (toDate != null && dt.compareTo(toDate) > 0) continue;
      }
      final cid = '${d['class_id'] ?? ''}';
      (daysByClass[cid] ??= <Map<String, dynamic>>[]).add(d);
    }

    final schoolType = _canonicalReportSchoolType(ctx.schoolRow);
    final out = <Map<String, dynamic>>[];

    for (final c in classes) {
      final cid = '${c['id']}';
      final cDays = daysByClass[cid] ?? <Map<String, dynamic>>[];
      cDays.sort(
        (a, b) =>
            '${a['attendance_date']}'.compareTo('${b['attendance_date']}'),
      );
      if (cDays.isEmpty) {
        out.add(<String, dynamic>{
          'class_id': cid,
          'class_key': '${c['class_key'] ?? ''}',
          'class_label': '${c['label'] ?? ''}',
          'sheet_name': '${c['sheet_name'] ?? ''}',
          'report_group': '${c['report_group'] ?? ''}',
          'standard': '${c['standard'] ?? ''}',
          'section': '${c['section'] ?? ''}',
          'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
          'school_type': schoolType,
          'attendance_date': null,
          'registered_counts': null,
          'present_counts': null,
          'mdm_counts': null,
          'breakfast_total': null,
          'gender_breakdown': null,
          'attendance_mode': null,
          'student_details_saved': null,
        });
      } else {
        for (final ad in cDays) {
          out.add(<String, dynamic>{
            'class_id': cid,
            'class_key': '${c['class_key'] ?? ''}',
            'class_label': '${c['label'] ?? ''}',
            'sheet_name': '${c['sheet_name'] ?? ''}',
            'report_group': '${c['report_group'] ?? ''}',
            'standard': '${c['standard'] ?? ''}',
            'section': '${c['section'] ?? ''}',
            'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
            'school_type': schoolType,
            'attendance_date': ad['attendance_date'],
            'registered_counts': ad['registered_counts'],
            'present_counts': ad['present_counts'],
            'mdm_counts': ad['mdm_counts'],
            'breakfast_total': ad['breakfast_total'],
            'gender_breakdown': ad['gender_breakdown'],
            'attendance_mode': ad['attendance_mode'],
            'student_details_saved': ad['student_details_saved'],
            'present_saved': ad['present_saved'],
            'mdm_saved': ad['mdm_saved'],
            'breakfast_saved': ad['breakfast_saved'],
          });
        }
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _schoolwideDailyReportRows({
    required _TeacherSessionContext ctx,
    required String date,
  }) async {
    final allClasses = await from('school_classes')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final classes = allClasses
        .where((c) => c['is_active'] != false)
        .toList();
    classes.sort((a, b) {
      final sa = int.tryParse('${a['sort_order'] ?? 0}') ?? 0;
      final sb = int.tryParse('${b['sort_order'] ?? 0}') ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return '${a['label']}'.compareTo('${b['label']}');
    });

    final allDays = await from('attendance_days')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final dayByClass = <String, Map<String, dynamic>>{};
    for (final d in allDays) {
      if ('${d['attendance_date'] ?? ''}' == date) {
        dayByClass['${d['class_id']}'] = d;
      }
    }

    final allStudents = await from('students')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final activeStudentsByClass = <String, List<Map<String, dynamic>>>{};
    for (final s in allStudents) {
      if (!_studentEligibleForReportDate(s, date)) continue;
      final cid = _effectiveClassIdForStudentOnDate(s, date);
      (activeStudentsByClass[cid] ??= <Map<String, dynamic>>[]).add(s);
    }

    final schoolType = _canonicalReportSchoolType(ctx.schoolRow);
    final out = <Map<String, dynamic>>[];

    for (final c in classes) {
      final cid = '${c['id']}';
      final day = dayByClass[cid];
      final rosterStudents =
          activeStudentsByClass[cid] ?? const <Map<String, dynamic>>[];

      final rosterCounts = <String, int>{
        'SC': 0,
        'ST': 0,
        'OBC': 0,
        'OTHER': 0,
      };
      for (final st in rosterStudents) {
        final cat = _canonicalReportCategory(st['category']);
        rosterCounts[cat] = (rosterCounts[cat] ?? 0) + 1;
      }

      Map<String, dynamic> breakdown;
      final savedBreakdownRaw = day == null ? null : day['gender_breakdown'];
      final savedBreakdown = savedBreakdownRaw is Map
          ? Map<String, dynamic>.from(savedBreakdownRaw)
          : <String, dynamic>{};
      var savedBreakdownRegistered = 0;
      for (final gender in const <String>['BOYS', 'GIRLS', 'UNSPECIFIED']) {
        final genderRow = savedBreakdown[gender];
        if (genderRow is! Map) continue;
        final overall = genderRow['_OVERALL'];
        if (overall is Map) {
          savedBreakdownRegistered +=
              int.tryParse('${overall['registered'] ?? 0}') ?? 0;
        }
      }
      // Older saved days can contain an all-zero demographic snapshot even
      // though the class currently has an active roster. Rebuild that snapshot
      // from student records and the saved student marks. This fixes the case
      // where Attendance shows a class roster but Daily Report shows 0.
      if (day == null) {
        final built = <String, dynamic>{};
        for (final g in const <String>['BOYS', 'GIRLS', 'UNSPECIFIED']) {
          final byCat = <String, dynamic>{};
          for (final cat in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
            byCat[cat] = <String, int>{'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': 0};
          }
          byCat['_OVERALL'] = <String, int>{'registered': 0, 'present': 0, 'mdm': 0, 'breakfast': 0};
          built[g] = byCat;
        }
        for (final st in rosterStudents) {
          final cat = _canonicalReportCategory(st['category']);
          final gen = _canonicalReportGender(st['gender'], schoolType);
          final cell = (built[gen] as Map<String, dynamic>)[cat] as Map<String, int>;
          final overall = (built[gen] as Map<String, dynamic>)['_OVERALL'] as Map<String, int>;
          cell['registered'] = (cell['registered'] ?? 0) + 1;
          overall['registered'] = (overall['registered'] ?? 0) + 1;
        }
        breakdown = built;
      } else if (savedBreakdown.isEmpty ||
          (savedBreakdownRegistered == 0 && rosterStudents.isNotEmpty)) {
        breakdown = await _calculateCategoryGenderBreakdown(
          schoolRef: ctx.schoolRef,
          classId: cid,
          date: date,
          schoolTypeHint: schoolType,
        );
      } else {
        breakdown = savedBreakdown;
      }

      final savedRegistered = day?['registered_counts'];
      var savedRegisteredTotal = 0;
      if (savedRegistered is Map) {
        for (final category in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
          savedRegisteredTotal +=
              int.tryParse('${savedRegistered[category] ?? 0}') ?? 0;
        }
      }
      final registeredCounts =
          day != null &&
              savedRegistered is Map &&
              (savedRegisteredTotal > 0 || rosterStudents.isEmpty)
          ? Map<String, dynamic>.from(savedRegistered)
          : rosterCounts;

      out.add(<String, dynamic>{
        'class_id': cid,
        'school_ref': ctx.schoolRef,
        'class_key': '${c['class_key'] ?? ''}',
        'class_label': '${c['label'] ?? ''}',
        'label': '${c['label'] ?? ''}',
        'sheet_name': '${c['sheet_name'] ?? ''}',
        'standard': '${c['standard'] ?? ''}',
        'section': '${c['section'] ?? ''}',
        'report_group': '${c['report_group'] ?? ''}',
        'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
        'school_type': schoolType,
        'attendance_date': day?['attendance_date'],
        'registered_counts': registeredCounts,
        'present_counts':
            day?['present_counts'] ??
            const <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0},
        'mdm_counts':
            day?['mdm_counts'] ??
            const <String, int>{'SC': 0, 'ST': 0, 'OBC': 0, 'OTHER': 0},
        'breakfast_total': int.tryParse('${day?['breakfast_total'] ?? 0}') ?? 0,
        'gender_breakdown': breakdown,
        'attendance_mode': '${day?['attendance_mode'] ?? 'none'}',
        'student_details_saved': day?['student_details_saved'] == true,
        'present_saved': day?['present_saved'],
        'mdm_saved': day?['mdm_saved'],
        'breakfast_saved': day?['breakfast_saved'],
        'present_frozen': day?['present_frozen'],
        'mdm_frozen': day?['mdm_frozen'],
        'breakfast_frozen': day?['breakfast_frozen'],
        'is_frozen': day?['is_frozen'],
        'unfrozen_by_admin': day?['unfrozen_by_admin'],
        'class_teacher_id': c['class_teacher_id'],
      });
    }
    return out;
  }

  DateTime? _parseStudentDobForTarij(Map<String, dynamic> s) {
    String normDigits(dynamic v) {
      var str = '${v ?? ""}'.trim();
      if (str.isEmpty) return '';
      const guj = <String, String>{
        '૦': '0',
        '૧': '1',
        '૨': '2',
        '૩': '3',
        '૪': '4',
        '૫': '5',
        '૬': '6',
        '૭': '7',
        '૮': '8',
        '૯': '9',
      };
      guj.forEach((g, a) => str = str.replaceAll(g, a));
      return str;
    }

    final ddStr = normDigits(s['dd']);
    final mmStr = normDigits(s['mm']);
    final yyyyStr = normDigits(s['yyyy']);
    final y = int.tryParse(yyyyStr);
    if (y != null && y >= 1980 && y <= 2100) {
      final m = (int.tryParse(mmStr) ?? 1).clamp(1, 12);
      final d = (int.tryParse(ddStr) ?? 1).clamp(1, 31);
      return DateTime(y, m, d);
    }

    for (final key in const <String>[
      'dob',
      'birth_date',
      'dob_as_aadhaar',
      'dobAsAadhaar',
    ]) {
      final raw = normDigits(s[key]);
      if (raw.isEmpty) continue;
      final iso = DateTime.tryParse(raw);
      if (iso != null) return DateTime(iso.year, iso.month, iso.day);
      final parts = raw.split(RegExp(r'[/\-\.]'));
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          final py = int.tryParse(parts[0]);
          final pm = int.tryParse(parts[1]);
          final pd = int.tryParse(parts[2]);
          if (py != null && pm != null && pd != null) {
            return DateTime(py, pm.clamp(1, 12), pd.clamp(1, 31));
          }
        } else if (parts[2].length == 4) {
          final pd = int.tryParse(parts[0]);
          final pm = int.tryParse(parts[1]);
          final py = int.tryParse(parts[2]);
          if (py != null && pm != null && pd != null) {
            return DateTime(py, pm.clamp(1, 12), pd.clamp(1, 31));
          }
        }
      }
    }
    return null;
  }

  bool _studentHasAadhaarForTarij(Map<String, dynamic> s) {
    final raw = '${s['has_aadhaar'] ?? ""}'.trim().toUpperCase();
    if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(raw) ||
        raw.startsWith('YES') ||
        raw.startsWith('હા')) {
      return true;
    }
    if (const <String>{'NO', 'N', 'FALSE', '0', 'ના'}.contains(raw)) {
      return false;
    }
    final cf = s['custom_fields'];
    if (cf is Map) {
      for (final entry in cf.entries) {
        final k = '${entry.key}'.toLowerCase();
        if (k.contains('aadhaar') || k.contains('aadhar') || k.contains('આધાર')) {
          final v = '${entry.value ?? ""}'.trim().toUpperCase();
          if (const <String>{'YES', 'Y', 'TRUE', '1', 'હા'}.contains(v) ||
              v.startsWith('YES') ||
              v.startsWith('હા')) {
            return true;
          }
        }
      }
    }
    final digits = '${s['aadhaar'] ?? s['aadhar'] ?? ""}'.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12) return true;
    return false;
  }

  bool _studentIsMinorityForTarij(Map<String, dynamic> s) {
    final relGu = '${s['religion'] ?? ""}'.trim().toLowerCase();
    final relEn = '${s['religion_en'] ?? ""}'.trim().toLowerCase();
    final combinedRel = '$relGu $relEn'.trim();
    if (combinedRel.isNotEmpty &&
        combinedRel != '-' &&
        combinedRel != 'na' &&
        combinedRel != 'n/a' &&
        combinedRel != 'null') {
      if (combinedRel.contains('હિન્દુ') ||
          combinedRel.contains('હિંદુ') ||
          combinedRel.contains('hindu')) {
        return false;
      }
      return true;
    }
    final casteCombined = '${s['caste'] ?? ""} ${s['caste_en'] ?? ""}'.trim().toLowerCase();
    if (casteCombined.isEmpty) return false;
    if (casteCombined.contains('હિન્દુ') ||
        casteCombined.contains('હિંદુ') ||
        casteCombined.contains('hindu')) {
      return false;
    }
    for (final kw in const <String>[
      'મુસ્લિમ',
      'ઇસ્લામ',
      'muslim',
      'islam',
      'જૈન',
      'jain',
      'ખ્રિસ્તી',
      'ક્રિશ્ચિયન',
      'christian',
      'શીખ',
      'સિખ',
      'sikh',
      'બૌદ્ધ',
      'buddh',
      'પારસી',
      'parsi',
    ]) {
      if (casteCombined.contains(kw)) return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> _schoolwideTarijStudentCounts({
    required _TeacherSessionContext ctx,
    required String monthStart,
    required String monthEnd,
  }) async {
    final allClasses = await from('school_classes')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final classes = allClasses
        .where((c) => c['is_active'] != false)
        .toList();
    classes.sort((a, b) {
      final sa = int.tryParse('${a['sort_order'] ?? 0}') ?? 0;
      final sb = int.tryParse('${b['sort_order'] ?? 0}') ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      return '${a['label']}'.compareTo('${b['label']}');
    });

    final students = await from('students')
        .select()
        .eq('school_ref', ctx.schoolRef);

    final studentById = <String, Map<String, dynamic>>{};
    for (final s in students) {
      final sid = '${s['id'] ?? ""}'.trim();
      if (sid.isNotEmpty) studentById[sid] = s;
    }

    final libBooksByClass = <String, int>{};
    try {
      final libRows = await from('library_transactions')
          .select()
          .eq('school_ref', ctx.schoolRef);
      for (final tx in libRows) {
        final issueDate = '${tx['issue_date'] ?? ""}'.trim();
        final dShort = issueDate.length >= 10 ? issueDate.substring(0, 10) : issueDate;
        if (dShort.isNotEmpty) {
          if (dShort.compareTo(monthStart) < 0 || dShort.compareTo(monthEnd) > 0) {
            continue;
          }
        }
        var cid = '${tx['class_id'] ?? ""}'.trim();
        if (cid.isEmpty) {
          final sid = '${tx['student_id'] ?? ""}'.trim();
          if (sid.isNotEmpty && studentById.containsKey(sid)) {
            cid = '${studentById[sid]!['class_id'] ?? ""}'.trim();
          }
        }
        if (cid.isNotEmpty) {
          libBooksByClass[cid] = (libBooksByClass[cid] ?? 0) + 1;
        }
      }
    } catch (_) {}

    final allDays = await from('attendance_days')
        .select()
        .eq('school_ref', ctx.schoolRef);
    final monthDaysByClass = <String, List<Map<String, dynamic>>>{};
    final dayIds = <String>{};
    for (final d in allDays) {
      final dt = '${d['attendance_date'] ?? ""}'.trim();
      if (dt.compareTo(monthStart) >= 0 && dt.compareTo(monthEnd) <= 0) {
        final cid = '${d['class_id'] ?? ""}';
        (monthDaysByClass[cid] ??= <Map<String, dynamic>>[]).add(d);
        dayIds.add('${d['id']}');
      }
    }

    final allMarks = dayIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await from('student_attendance')
            .select()
            .eq('school_ref', ctx.schoolRef);
    final presentMarks = <String>{};
    for (final m in allMarks) {
      final did = '${m['attendance_day_id'] ?? ""}';
      if (dayIds.contains(did) && m['present'] == true) {
        presentMarks.add('${did}__${m['student_id']}');
      }
    }

    final schoolType = _canonicalReportSchoolType(ctx.schoolRow);
    final monthEndDate = DateTime.tryParse(monthEnd);

    String admissionDateOf(Map<String, dynamic> s) {
      final explicit = _studentAdmissionIso(s);
      if (explicit != null) return explicit;
      return '2000-01-01';
    }

    String? exitDateOf(Map<String, dynamic> s) {
      return _studentExitIso(s);
    }

    int sumMapCounts(dynamic raw) {
      if (raw is! Map) return 0;
      var sum = 0;
      for (final v in raw.values) {
        sum += int.tryParse('$v') ?? 0;
      }
      return sum;
    }

    final out = <Map<String, dynamic>>[];
    for (final c in classes) {
      final cid = '${c['id']}';
      final cStudents = students
          .where((s) => _effectiveClassIdForStudentOnDate(s, monthEnd) == cid)
          .toList();
      final mDays = monthDaysByClass[cid] ?? <Map<String, dynamic>>[];

      final workingDateSet = <String>{};
      final mdmDateSet = <String>{};
      for (final d in mDays) {
        final dt = '${d['attendance_date'] ?? ""}'.trim();
        if (dt.isEmpty) continue;
        final presSum = sumMapCounts(d['present_counts']);
        final mdmSum = sumMapCounts(d['mdm_counts']);
        if (presSum > 0 ||
            d['present_saved'] == true ||
            d['student_details_saved'] == true) {
          workingDateSet.add(dt);
        }
        if (mdmSum > 0 || (d['mdm_saved'] == true && mdmSum > 0)) {
          mdmDateSet.add(dt);
        }
      }
      final workingDays = workingDateSet.isNotEmpty
          ? workingDateSet.length
          : mDays.map((d) => '${d['attendance_date'] ?? ""}'.trim()).where((dt) => dt.isNotEmpty).toSet().length;
      final mdmDays = mdmDateSet.length;
      final tithiDays = workingDays >= mdmDays ? workingDays - mdmDays : 0;
      final classLibBooks = libBooksByClass[cid] ?? 0;

      final individualComplete =
          mDays.isNotEmpty &&
          mDays.every(
            (d) =>
                '${d['attendance_mode'] ?? ""}'.toLowerCase() != 'direct' &&
                d['student_details_saved'] == true,
          );

      bool isStudentPerfect(Map<String, dynamic> s) {
        final adm = admissionDateOf(s);
        final ex = exitDateOf(s);
        int expected = 0;
        int pres = 0;
        for (final d in mDays) {
          final dt = '${d['attendance_date']}';
          if (dt.compareTo(adm) >= 0 && (ex == null || dt.compareTo(ex) <= 0)) {
            expected++;
            if (presentMarks.contains('${d['id']}__${s['id']}')) {
              pres++;
            }
          }
        }
        return expected > 0 && expected == pres;
      }

      int perfectCount = 0;
      for (final s in cStudents) {
        if (isStudentPerfect(s)) perfectCount++;
      }

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final s in cStudents) {
        final cat = _canonicalReportCategory(s['category']);
        final gen = _canonicalReportGender(s['gender'], schoolType);
        final key = '$cat|$gen';
        (grouped[key] ??= <Map<String, dynamic>>[]).add(s);
      }

      if (grouped.isEmpty) {
        final sortedDays = List<Map<String, dynamic>>.from(mDays)
          ..sort((a, b) => '${a['attendance_date']}'.compareTo('${b['attendance_date']}'));
        final firstDayReg = sortedDays.isNotEmpty && sortedDays.first['registered_counts'] is Map
            ? Map<String, dynamic>.from(sortedDays.first['registered_counts'] as Map)
            : <String, dynamic>{};
        final lastDayReg = sortedDays.isNotEmpty && sortedDays.last['registered_counts'] is Map
            ? Map<String, dynamic>.from(sortedDays.last['registered_counts'] as Map)
            : <String, dynamic>{};
        final targetGen = schoolType == 'girls' ? 'GIRLS' : 'BOYS';
        for (final cat in const <String>['SC', 'ST', 'OBC', 'OTHER']) {
          final op = int.tryParse('${firstDayReg[cat] ?? 0}') ?? 0;
          final cl = int.tryParse('${lastDayReg[cat] ?? 0}') ?? 0;
          final adm = cl > op ? cl - op : 0;
          final ex = op > cl ? op - cl : 0;
          out.add(<String, dynamic>{
            'class_id': cid,
            'class_key': '${c['class_key'] ?? ""}',
            'class_label': '${c['label'] ?? ""}',
            'sheet_name': '${c['sheet_name'] ?? ""}',
            'report_group': '${c['report_group'] ?? ""}',
            'standard': '${c['standard'] ?? ""}',
            'section': '${c['section'] ?? ""}',
            'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
            'school_type': schoolType,
            'category': cat,
            'gender': targetGen,
            'opening_count': op,
            'admission_count': adm,
            'lc_exit_count': ex,
            'continuous_absence_exit_count': 0,
            'other_exit_count': 0,
            'closing_count': cl,
            'working_days': workingDays,
            'mdm_days': mdmDays,
            'tithi_days': tithiDays,
            'individual_records_complete': individualComplete,
            'perfect_attendance_count': perfectCount,
            'perfect_attendance_gender_count': 0,
            'age_5_6_count': 0,
            'age_6_14_count': 0,
            'age_above_14_count': 0,
            'aadhaar_count': 0,
            'minority_count': 0,
            'class_library_books_count': classLibBooks,
          });
        }
        continue;
      }

      for (final entry in grouped.entries) {
        final parts = entry.key.split('|');
        final cat = parts[0];
        final gen = parts[1];
        final groupStudents = entry.value;

        int opening = 0;
        int admissions = 0;
        int lcExit = 0;
        int absExit = 0;
        int otherExit = 0;
        int closing = 0;
        int groupPerfect = 0;
        int age5to6 = 0;
        int age6to14 = 0;
        int ageAbove14 = 0;
        int aadhaarCount = 0;
        int minorityCount = 0;

        for (final s in groupStudents) {
          final adm = admissionDateOf(s);
          final ex = exitDateOf(s);
          final reason = _studentExitReasonNormalized(s);
          final reasonCompact = reason.replaceAll(RegExp(r'\s+'), '');
          final isAbsenceReason = const <String>{
                'continuous_absence',
                'long_absence',
                'removed_for_absence',
              }.contains(reason) ||
              (reasonCompact.contains('continuous') &&
                  reasonCompact.contains('absence')) ||
              (reasonCompact.contains('સતત') &&
                  reasonCompact.contains('ગેરહાજ')) ||
              (reasonCompact.contains('ગેરહાજરી') &&
                  reasonCompact.contains('કમી'));

          if (adm.compareTo(monthStart) < 0 &&
              (ex == null || ex.compareTo(monthStart) >= 0)) {
            opening++;
          }
          if (adm.compareTo(monthStart) >= 0 && adm.compareTo(monthEnd) <= 0) {
            admissions++;
          }
          if (adm.compareTo(monthEnd) <= 0 &&
              ex != null &&
              ex.compareTo(monthStart) >= 0 &&
              ex.compareTo(monthEnd) <= 0) {
            if (isAbsenceReason) {
              absExit++;
            } else {
              lcExit++;
            }
          }
          if (adm.compareTo(monthEnd) <= 0 &&
              (ex == null || ex.compareTo(monthEnd) > 0)) {
            closing++;
            if (isStudentPerfect(s)) groupPerfect++;
            final dob = _parseStudentDobForTarij(s);
            if (dob != null && monthEndDate != null) {
              int ageYears = monthEndDate.year - dob.year;
              if (monthEndDate.month < dob.month ||
                  (monthEndDate.month == dob.month && monthEndDate.day < dob.day)) {
                ageYears--;
              }
              if (ageYears >= 5 && ageYears < 6) {
                age5to6++;
              } else if (ageYears >= 6 && ageYears <= 14) {
                age6to14++;
              } else if (ageYears > 14) {
                ageAbove14++;
              }
            }
            if (_studentHasAadhaarForTarij(s)) {
              aadhaarCount++;
            }
            if (_studentIsMinorityForTarij(s)) {
              minorityCount++;
            }
          }
        }

        out.add(<String, dynamic>{
          'class_id': cid,
          'class_key': '${c['class_key'] ?? ""}',
          'class_label': '${c['label'] ?? ""}',
          'sheet_name': '${c['sheet_name'] ?? ""}',
          'report_group': '${c['report_group'] ?? ""}',
          'standard': '${c['standard'] ?? ""}',
          'section': '${c['section'] ?? ""}',
          'sort_order': int.tryParse('${c['sort_order'] ?? 0}') ?? 0,
          'school_type': schoolType,
          'category': cat,
          'gender': gen,
          'opening_count': opening,
          'admission_count': admissions,
          'lc_exit_count': lcExit,
          'continuous_absence_exit_count': absExit,
          'other_exit_count': otherExit,
          'closing_count': closing,
          'working_days': workingDays,
          'mdm_days': mdmDays,
          'tithi_days': tithiDays,
          'individual_records_complete': individualComplete,
          'perfect_attendance_count': perfectCount,
          'perfect_attendance_gender_count': groupPerfect,
          'age_5_6_count': age5to6,
          'age_6_14_count': age6to14,
          'age_above_14_count': ageAbove14,
          'aadhaar_count': aadhaarCount,
          'minority_count': minorityCount,
          'class_library_books_count': classLibBooks,
        });
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> _addStudentWithRoll({
    required String schoolRef,
    required String classId,
    required Map<String, dynamic> student,
    int? requestedRoll,
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    if (ctx != null && !ctx.canManageClassStudents(classId)) {
      throw const PostgrestException(
        message:
            'માત્ર જે-તે વર્ગના વર્ગ શિક્ષક (Class Teacher) અથવા School Admin જ આ વર્ગમાં નવો વિદ્યાર્થી ઉમેરી શકે છે. વિષય શિક્ષક (Subject Teacher) વિદ્યાર્થી ઉમેરી શકતા નથી.',
        code: '42501',
      );
    }
    final name = '${student['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      throw const PostgrestException(message: 'Student name is required.');
    }
    final activeStudents = await from('students')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true);

    int maxRoll = 0;
    for (final s in activeStudents) {
      final r = int.tryParse('${s['roll_number'] ?? ''}'.trim());
      if (r != null && r > maxRoll) maxRoll = r;
    }
    final targetRoll = requestedRoll ?? (maxRoll + 1);
    if (targetRoll < 1) {
      throw const PostgrestException(message: 'Roll number must be positive.');
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    var batch = _db.batch();
    final col = _db.collection('students');

    // Shift existing active students with roll_number >= targetRoll upward by 1
    for (final s in activeStudents) {
      final r = int.tryParse('${s['roll_number'] ?? ''}'.trim());
      if (r != null && r >= targetRoll) {
        final sid = '${s['id']}';
        batch.update(col.doc(sid), <String, dynamic>{
          'roll_number': '${r + 1}',
          'updated_at': nowIso,
        });
      }
    }

    final newId = _generateUuid();
    final row = <String, dynamic>{
      'id': newId,
      'school_ref': schoolRef,
      'class_id': classId,
      'roll_number': '$targetRoll',
      'gr': '${student['gr'] ?? ''}',
      'dd': '${student['dd'] ?? ''}',
      'mm': '${student['mm'] ?? ''}',
      'yyyy': '${student['yyyy'] ?? ''}',
      'name': name,
      'religion': '${student['religion'] ?? ''}',
      'religion_en': '${student['religion_en'] ?? ''}',
      'caste': '${student['caste'] ?? ''}',
      'category': '${student['category'] ?? 'OTHER'}'.trim().toUpperCase(),
      'gender': '${student['gender'] ?? 'UNSPECIFIED'}'.trim().toUpperCase(),
      'enroll_school': '${student['enroll_school'] ?? ''}',
      'enroll_class': '${student['enroll_class'] ?? ''}',
      'mobile': '${student['mobile'] ?? ''}',
      'father_name': '${student['father_name'] ?? ''}',
      'mother_name': '${student['mother_name'] ?? ''}',
      'address': '${student['address'] ?? ''}',
      'birth_place': '${student['birth_place'] ?? ''}',
      'native_place': '${student['native_place'] ?? ''}',
      'dob_words': '${student['dob_words'] ?? ''}',
      'last_school': '${student['last_school'] ?? ''}',
      'enroll_sch_class': '${student['enroll_sch_class'] ?? ''}',
      'enroll_sch_class_words': '${student['enroll_sch_class_words'] ?? ''}',
      'name_en': '${student['name_en'] ?? ''}',
      'caste_en': '${student['caste_en'] ?? ''}',
      'category_en': '${student['category_en'] ?? ''}',
      'mother_en': '${student['mother_en'] ?? ''}',
      'birth_place_en': '${student['birth_place_en'] ?? ''}',
      'native_place_en': '${student['native_place_en'] ?? ''}',
      'dob_en': '${student['dob_en'] ?? ''}',
      'last_school_en': '${student['last_school_en'] ?? ''}',
      'enroll_sch_class_en': '${student['enroll_sch_class_en'] ?? ''}',
      'enroll_sch_class_words_en':
          '${student['enroll_sch_class_words_en'] ?? ''}',
      'uid': '${student['uid'] ?? ''}',
      'pen': '${student['pen'] ?? ''}',
      'apaar_id': '${student['apaar_id'] ?? ''}',
      'present_days': int.tryParse('${student['present_days'] ?? 0}') ?? 0,
      'is_divyang': student['is_divyang'] == true,
      'has_aadhaar': '${student['has_aadhaar'] ?? 'NO'}',
      'ration_card_kyc': '${student['ration_card_kyc'] ?? 'NO'}',
      'scholarship_done': '${student['scholarship_done'] ?? 'NO'}',
      'scholarship_reason': '${student['scholarship_reason'] ?? ''}',
      'scholarship_other': '${student['scholarship_other'] ?? ''}',
      'custom_fields': student['custom_fields'] is Map
          ? Map<String, dynamic>.from(student['custom_fields'] as Map)
          : <String, dynamic>{},
      'is_active': true,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
    await _normalizeStudentRowOnWrite(row, schoolRef);
    batch.set(col.doc(newId), row);
    await batch.commit();
    await _renumberActiveClassStudentsContinually(
      schoolRef: schoolRef,
      classId: classId,
    );
    return row;
  }

  Future<Map<String, dynamic>> _changeStudentRoll({
    required String schoolRef,
    required String studentId,
    required int newRoll,
  }) async {
    if (newRoll < 1) {
      throw const PostgrestException(message: 'Roll number must be positive.');
    }
    final target = await from('students')
        .select()
        .eq('id', studentId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (target == null || target['is_active'] != true) {
      throw const PostgrestException(
        message: 'Student was not found or is inactive.',
      );
    }
    final classId = '${target['class_id']}';
    final oldRoll = int.tryParse('${target['roll_number'] ?? ''}'.trim());
    if (oldRoll == null) {
      throw const PostgrestException(
        message: 'Student must have a numeric roll number before moving it.',
      );
    }
    if (oldRoll == newRoll) return target;

    final activeStudents = await from('students')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    final col = _db.collection('students');

    for (final s in activeStudents) {
      final sid = '${s['id']}';
      if (sid == studentId) continue;
      final r = int.tryParse('${s['roll_number'] ?? ''}'.trim());
      if (r == null) continue;
      if (oldRoll < newRoll && r > oldRoll && r <= newRoll) {
        batch.update(col.doc(sid), <String, dynamic>{
          'roll_number': '${r - 1}',
          'updated_at': nowIso,
        });
      } else if (newRoll < oldRoll && r >= newRoll && r < oldRoll) {
        batch.update(col.doc(sid), <String, dynamic>{
          'roll_number': '${r + 1}',
          'updated_at': nowIso,
        });
      }
    }

    final updated = <String, dynamic>{
      ...target,
      'roll_number': '$newRoll',
      'updated_at': nowIso,
    };
    batch.set(col.doc(studentId), updated, fs.SetOptions(merge: true));
    await batch.commit();
    FirestoreQueryBuilder.invalidateCache('students');
    return updated;
  }

  Future<void> _updateStudentProfileWithRollShift({
    required String schoolRef,
    required String studentId,
    required Map<String, dynamic> values,
    Map<String, dynamic>? customFields,
  }) async {
    final target = await from('students')
        .select()
        .eq('id', studentId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (target == null || target['is_active'] != true) {
      throw const PostgrestException(
        message: 'STUDENT_NOT_FOUND: This active student was not found.',
      );
    }

    final oldRollText = '${target['roll_number'] ?? ''}'.trim();
    final reqRollText = '${values['roll_number'] ?? oldRollText}'.trim();
    if (reqRollText.isEmpty) {
      throw const PostgrestException(
        message: 'ROLL_NUMBER_REQUIRED: Roll number cannot be blank.',
      );
    }
    if (reqRollText != oldRollText) {
      final newRoll = int.tryParse(reqRollText);
      if (newRoll == null || newRoll < 1) {
        throw const PostgrestException(
          message:
              'ROLL_NUMBER_INVALID: Enter a positive whole-number roll number.',
        );
      }
      await _changeStudentRoll(
        schoolRef: schoolRef,
        studentId: studentId,
        newRoll: newRoll,
      );
    }

    final allowedKeys = <String>[
      'class_id',
      'gr',
      'dd',
      'mm',
      'yyyy',
      'name',
      'religion',
      'religion_en',
      'caste',
      'category',
      'gender',
      'enroll_school',
      'enroll_class',
      'mobile',
      'father_name',
      'mother_name',
      'address',
      'birth_place',
      'native_place',
      'dob_words',
      'last_school',
      'enroll_sch_class',
      'enroll_sch_class_words',
      'present_days',
      'name_en',
      'caste_en',
      'category_en',
      'mother_en',
      'birth_place_en',
      'native_place_en',
      'dob_en',
      'last_school_en',
      'enroll_sch_class_en',
      'enroll_sch_class_words_en',
      'apaar_id',
      'has_aadhaar',
      'ration_card_kyc',
      'scholarship_done',
      'scholarship_reason',
      'scholarship_other',
      'uid',
      'pen',
      'is_divyang',
    ];
    final patch = <String, dynamic>{
      'roll_number': reqRollText,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    for (final k in allowedKeys) {
      if (values.containsKey(k) && values[k] != null) {
        patch[k] = values[k];
      }
    }
    if (customFields != null) {
      patch['custom_fields'] = customFields;
    }
    await _db
        .collection('students')
        .doc(studentId)
        .set(patch, fs.SetOptions(merge: true));
    final oldCid = '${target['class_id'] ?? ''}'.trim();
    final newCid = '${patch['class_id'] ?? oldCid}'.trim();
    if (oldCid.isNotEmpty) {
      await _renumberActiveClassStudentsContinually(
        schoolRef: schoolRef,
        classId: oldCid,
      );
    }
    if (newCid.isNotEmpty && newCid != oldCid) {
      await _renumberActiveClassStudentsContinually(
        schoolRef: schoolRef,
        classId: newCid,
      );
    }
  }

  Future<void> _renumberActiveClassStudentsContinually({
    required String schoolRef,
    required String classId,
  }) async {
    if (schoolRef.trim().isEmpty || classId.trim().isEmpty) return;
    final snap = await _db
        .collection('students')
        .where('class_id', isEqualTo: classId)
        .get();
    final classDocs = snap.docs
        .where((d) => '${d.data()['school_ref'] ?? ''}'.trim() == schoolRef)
        .toList();
    if (classDocs.isEmpty) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final activeList = <Map<String, dynamic>>[];

    for (final doc in classDocs) {
      final row = <String, dynamic>{...doc.data(), 'id': doc.data()['id'] ?? doc.id};
      // IMPORTANT: Never auto-deactivate students during roll renumbering!
      // A student is active unless explicitly marked is_active == false.
      final rawActive = row['is_active'];
      final isExplicitlyInactive =
          rawActive == false || '${rawActive ?? ''}'.trim().toLowerCase() == 'false';
      if (!isExplicitlyInactive) {
        activeList.add(row);
      }
    }

    activeList.sort((a, b) {
      final ar = int.tryParse('${a['roll_number'] ?? ''}'.trim());
      final br = int.tryParse('${b['roll_number'] ?? ''}'.trim());
      if (ar != null && br != null && ar != br) return ar.compareTo(br);
      if (ar != null && br == null) return -1;
      if (ar == null && br != null) return 1;
      final nameCmp =
          '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
      if (nameCmp != 0) return nameCmp;
      return '${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}');
    });

    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;

    for (var i = 0; i < activeList.length; i++) {
      final row = activeList[i];
      final sid = '${row['id']}'.trim();
      if (sid.isEmpty) continue;
      final desiredRoll = '${i + 1}';
      final curRoll = '${row['roll_number'] ?? ''}'.trim();
      if (curRoll != desiredRoll || row['is_active'] != true) {
        batch.set(
          col.doc(sid),
          <String, dynamic>{
            'roll_number': desiredRoll,
            'is_active': true,
            'updated_at': nowIso,
          },
          fs.SetOptions(merge: true),
        );
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
    }

    if (ops > 0) {
      await batch.commit();
      try {
        final desiredRollByStudentId = <String, String>{
          for (var i = 0; i < activeList.length; i++)
            '${activeList[i]['id'] ?? ''}'.trim(): '${i + 1}',
        };
        final txSnap = await _db
            .collection('library_transactions')
            .where('school_ref', isEqualTo: schoolRef)
            .get();
        var txBatch = _db.batch();
        var txOps = 0;
        for (final txDoc in txSnap.docs) {
          final td = txDoc.data();
          final status = '${td['status'] ?? ''}'.trim().toLowerCase();
          final retDate = '${td['return_date'] ?? ''}'.trim();
          if (status == 'returned' || retDate.isNotEmpty) continue;
          final sid = '${td['student_id'] ?? ''}'.trim();
          final newRoll = desiredRollByStudentId[sid];
          if (newRoll != null &&
              '${td['roll_number_snapshot'] ?? ''}'.trim() != newRoll) {
            txBatch.set(
              _db.collection('library_transactions').doc(txDoc.id),
              <String, dynamic>{
                'roll_number_snapshot': newRoll,
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            txOps++;
          }
        }
        if (txOps > 0) {
          await txBatch.commit();
          FirestoreQueryBuilder.invalidateCache('library_transactions');
        }
      } catch (_) {}
    }
    FirestoreQueryBuilder.invalidateCache('students');
  }

  Future<Map<String, dynamic>> _restoreDisappearedOrArchivedStudents({
    required String schoolRef,
    String classId = '',
    String targetClassId = '',
    Set<String> studentIds = const <String>{},
  }) async {
    FirestoreQueryBuilder.invalidateCache('students');
    final snap = await _db
        .collection('students')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;
    int restoredCount = 0;
    final affectedClasses = <String>{};

    for (final doc in snap.docs) {
      final d = doc.data();
      final sid = '${d['id'] ?? doc.id}'.trim();
      if (sid.isEmpty) continue;
      if (studentIds.isNotEmpty && !studentIds.contains(sid)) continue;

      final curClassId = '${d['class_id'] ?? ''}'.trim();
      if (studentIds.isEmpty &&
          classId.isNotEmpty &&
          classId != '__ALL__' &&
          curClassId != classId) {
        continue;
      }

      final isInactive = d['is_active'] != true ||
          '${d['leaving_date'] ?? ''}'.trim().isNotEmpty ||
          '${d['exit_date'] ?? ''}'.trim().isNotEmpty;
      if (!isInactive && studentIds.isEmpty) continue;

      final destClassId =
          (targetClassId.isNotEmpty && targetClassId != '__ALL__')
              ? targetClassId
              : curClassId;
      final restoredRoll = '${d['roll_number'] ?? ''}'.trim().isNotEmpty
          ? '${d['roll_number']}'.trim()
          : ('${d['previous_roll_number'] ?? ''}'.trim().isNotEmpty
              ? '${d['previous_roll_number']}'.trim()
              : '999');

      batch.set(
        col.doc(sid),
        <String, dynamic>{
          'is_active': true,
          'class_id': destClassId,
          'roll_number': restoredRoll,
          'leaving_date': null,
          'exit_date': null,
          'exit_reason': '',
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
      affectedClasses.add(destClassId);
      if (curClassId.isNotEmpty) affectedClasses.add(curClassId);
      restoredCount++;
      ops++;
      if (ops >= 380) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }

    for (final cid in affectedClasses) {
      if (cid.isNotEmpty) {
        await _renumberActiveClassStudentsContinually(
          schoolRef: schoolRef,
          classId: cid,
        );
      }
    }
    FirestoreQueryBuilder.invalidateCache('students');
    return <String, dynamic>{
      'restored_count': restoredCount,
      'affected_classes': affectedClasses.toList(),
    };
  }

  Future<Map<String, dynamic>> _moveStudentsToClass({
    required String schoolRef,
    required String fromClassId,
    required String toClassId,
    Set<String> studentIds = const <String>{},
  }) async {
    if (toClassId.isEmpty) {
      throw const PostgrestException(message: 'Target class is required.');
    }
    FirestoreQueryBuilder.invalidateCache('students');
    final snap = await _db
        .collection('students')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;
    int movedCount = 0;
    final affectedClasses = <String>{toClassId};
    if (fromClassId.isNotEmpty) affectedClasses.add(fromClassId);

    for (final doc in snap.docs) {
      final d = doc.data();
      final sid = '${d['id'] ?? doc.id}'.trim();
      if (sid.isEmpty) continue;
      final curClassId = '${d['class_id'] ?? ''}'.trim();
      if (studentIds.isNotEmpty) {
        if (!studentIds.contains(sid)) continue;
      } else if (fromClassId.isNotEmpty && curClassId != fromClassId) {
        continue;
      } else if (fromClassId.isEmpty) {
        continue;
      }

      batch.set(
        col.doc(sid),
        <String, dynamic>{
          'class_id': toClassId,
          'is_active': true,
          'leaving_date': null,
          'exit_date': null,
          'exit_reason': '',
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
      if (curClassId.isNotEmpty) affectedClasses.add(curClassId);
      movedCount++;
      ops++;
      if (ops >= 380) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();

    for (final cid in affectedClasses) {
      if (cid.isNotEmpty) {
        await _renumberActiveClassStudentsContinually(
          schoolRef: schoolRef,
          classId: cid,
        );
      }
    }
    FirestoreQueryBuilder.invalidateCache('students');
    return <String, dynamic>{
      'moved_count': movedCount,
      'affected_classes': affectedClasses.toList(),
    };
  }

  Future<void> _archiveOrDeleteStudentAndShiftRolls({
    required String schoolRef,
    required String studentId,
    required bool deletePermanently,
    String? exitDate,
    String exitReason = 'other',
  }) async {
    final cleanStudentId = studentId.trim();
    if (cleanStudentId.isEmpty) {
      throw const PostgrestException(
        message: 'STUDENT_ID_REQUIRED: Student ID cannot be empty.',
      );
    }
    final docSnap = await _db.collection('students').doc(cleanStudentId).get();
    Map<String, dynamic>? target;
    if (docSnap.exists && docSnap.data() != null) {
      final d = docSnap.data()!;
      if ('${d['school_ref'] ?? ''}'.trim() == schoolRef.trim()) {
        target = <String, dynamic>{...d, 'id': d['id'] ?? docSnap.id};
      }
    }
    target ??= await from('students')
        .select()
        .eq('id', cleanStudentId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (target == null || '${target['id'] ?? ''}'.trim() != cleanStudentId) {
      throw const PostgrestException(
        message: 'STUDENT_NOT_FOUND: This student was not found.',
      );
    }
    final classId = '${target['class_id'] ?? ''}'.trim();
    final ctx = await _resolveCurrentTeacherContext();
    if (ctx != null && !ctx.canManageClassStudents(classId)) {
      throw const PostgrestException(
        message:
            'માત્ર જે-તે વર્ગના વર્ગ શિક્ષક (Class Teacher) અથવા School Admin જ વિદ્યાર્થીને નિષ્ક્રિય (Deactive) કરી શકે છે. વિષય શિક્ષક (Subject Teacher) વિદ્યાર્થીને Deactive કરી શકતા નથી.',
        code: '42501',
      );
    }
    final oldRollText = '${target['roll_number'] ?? ''}'.trim();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final col = _db.collection('students');

    if (deletePermanently) {
      await col.doc(studentId).delete();
    } else {
      final rawEx = (exitDate ?? _indiaTodayIso()).trim();
      final normEx = _parseAnyDateToIso(rawEx) ?? (rawEx.isEmpty ? _indiaTodayIso() : rawEx);
      final admIso = _studentAdmissionIso(target);
      if (admIso != null && normEx.length >= 10 && normEx.substring(0, 10).compareTo(admIso) < 0) {
        throw const PostgrestException(
          message: 'LEAVING_DATE_BEFORE_ENROLLMENT: શાળા છોડ્યાની તારીખ શાળામાં દાખલ તારીખ કરતાં પહેલાંની હોઈ શકે નહીં.',
        );
      }
      final cleanReason = exitReason.trim().isEmpty ? 'lc' : exitReason.trim();
      final existingCf = target['custom_fields'] is Map
          ? Map<String, dynamic>.from(target['custom_fields'] as Map)
          : <String, dynamic>{};
      existingCf['leaving_date'] = normEx;
      existingCf['exit_date'] = normEx;
      existingCf['exit_reason'] = cleanReason;
      existingCf['leaving_reason'] = cleanReason;
      // Step 1: Save leaving_date & exit_reason (both top-level and custom_fields), then set is_active = false.
      await col.doc(studentId).set(<String, dynamic>{
        'leaving_date': normEx,
        'exit_date': normEx,
        'exit_reason': cleanReason,
        'leaving_reason': cleanReason,
        'custom_fields': existingCf,
        if (oldRollText.isNotEmpty) 'previous_roll_number': oldRollText,
        'roll_number': '',
        'is_active': false,
        'updated_at': nowIso,
      }, fs.SetOptions(merge: true));
    }

    await _renumberActiveClassStudentsContinually(
      schoolRef: schoolRef,
      classId: classId,
    );

    // Clean up any saved attendance marks & refresh attendance_days counts on or after leaving_date
    try {
      final rawEx = (exitDate ?? _indiaTodayIso()).trim();
      final normEx = _parseAnyDateToIso(rawEx) ?? (rawEx.isEmpty ? _indiaTodayIso() : rawEx);
      final cutoffIso = deletePermanently
          ? '1900-01-01'
          : (normEx.length >= 10 ? normEx.substring(0, 10) : _indiaTodayIso());
      if (classId.isNotEmpty) {
        final affectedDays = await from('attendance_days')
            .select('id,attendance_date')
            .eq('school_ref', schoolRef)
            .eq('class_id', classId)
            .gte('attendance_date', cutoffIso);
        for (final dayRow in affectedDays) {
          final dayId = '${dayRow['id'] ?? ''}'.trim();
          if (dayId.isEmpty) continue;
          try {
            await _db.collection('attendance_days').doc(dayId).update(
              <String, dynamic>{
                'student_marks.$cleanStudentId': fs.FieldValue.delete(),
              },
            );
          } catch (_) {}
          try {
            await _db
                .collection('student_attendance')
                .doc('${dayId}__$cleanStudentId')
                .delete();
          } catch (_) {}
          FirestoreQueryBuilder.invalidateCache('student_attendance');
          await _refreshAttendanceDayCounts(dayId);
        }
      }
    } catch (_) {}
  }

  static String? _parseAnyDateToIso(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var norm = raw.trim();
    if (norm.isEmpty) return null;
    for (var i = 0; i < guj.length; i++) {
      norm = norm.replaceAll(guj[i], '$i');
    }
    final isoMatch = RegExp(r'^(\d{4})[./-](\d{1,2})[./-](\d{1,2})').firstMatch(norm);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!) ?? 0;
      final m = int.tryParse(isoMatch.group(2)!) ?? 0;
      final d = int.tryParse(isoMatch.group(3)!) ?? 0;
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    final dmyMatch = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(norm);
    if (dmyMatch != null) {
      final d = int.tryParse(dmyMatch.group(1)!) ?? 0;
      final m = int.tryParse(dmyMatch.group(2)!) ?? 0;
      final y = int.tryParse(dmyMatch.group(3)!) ?? 0;
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    final dt = DateTime.tryParse(norm);
    if (dt != null) {
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  static String _isoToDmySlash(String iso) {
    final parts = iso.split('-');
    if (parts.length == 3) {
      return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
    }
    return iso;
  }

  Future<Map<String, dynamic>> _getClassPromotionPreview({
    required String schoolRef,
  }) async {
    final settingsRow = await from('school_settings')
        .select()
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final cfg = settingsRow?['config'] is Map
        ? Map<String, dynamic>.from(settingsRow!['config'] as Map)
        : <String, dynamic>{};

    final resultSettings = await from('class_result_settings')
        .select()
        .eq('school_ref', schoolRef);

    // Collect all configured result dates from class_result_settings (Result module) and school_settings.config
    final candidateIsoDates = <String>[];
    final cfgRawDate = '${cfg['second_sem_result_date'] ?? ''}'.trim();
    if (cfgRawDate.isNotEmpty) {
      final parsedCfg = _parseAnyDateToIso(cfgRawDate);
      if (parsedCfg != null) candidateIsoDates.add(parsedCfg);
    }
    for (final rs in resultSettings) {
      final rd = '${rs['second_sem_result_date'] ?? rs['result_date'] ?? ''}'.trim();
      if (rd.isNotEmpty) {
        final parsedRd = _parseAnyDateToIso(rd);
        if (parsedRd != null) candidateIsoDates.add(parsedRd);
      }
    }
    final nowDt = DateTime.now();
    final eduEndYear = nowDt.month >= 6 ? nowDt.year + 1 : nowDt.year;
    String resultDateIso = '$eduEndYear-04-30';
    if (candidateIsoDates.isNotEmpty) {
      // If cfg['second_sem_result_date'] was explicitly saved, use it; otherwise use the latest result_date from Result module
      if (cfgRawDate.isNotEmpty && _parseAnyDateToIso(cfgRawDate) != null) {
        resultDateIso = _parseAnyDateToIso(cfgRawDate)!;
      } else {
        candidateIsoDates.sort();
        resultDateIso = candidateIsoDates.last;
      }
    }
    final resultDateDmy = _isoToDmySlash(resultDateIso);
    final todayIso = _indiaTodayIso();
    // STRICT RULE: Admin can promote ONLY on or after Second Semester Result Date (todayIso >= resultDateIso)
    final canPromote = todayIso.compareTo(resultDateIso) >= 0;

    final classRows = await from('school_classes')
        .select()
        .eq('school_ref', schoolRef)
        .eq('is_active', true);

    final classes = classRows.map((c) => Map<String, dynamic>.from(c)).toList();
    classes.sort((a, b) {
      final sa = _extractStandardNumber('${a['standard'] ?? a['label'] ?? a['class_key'] ?? ''}') ?? 99;
      final sb = _extractStandardNumber('${b['standard'] ?? b['label'] ?? b['class_key'] ?? ''}') ?? 99;
      if (sa != sb) return sa.compareTo(sb);
      final oa = int.tryParse('${a['sort_order'] ?? 0}') ?? 0;
      final ob = int.tryParse('${b['sort_order'] ?? 0}') ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return '${a['label'] ?? ''}'.compareTo('${b['label'] ?? ''}');
    });

    String normalizeSection(Map<String, dynamic> cls) {
      var rawSec = '${cls['section'] ?? ''}'.trim().toUpperCase();
      if (rawSec.isEmpty) {
        final lbl = '${cls['label'] ?? cls['class_key'] ?? ''}'.trim();
        final m = RegExp(r'(?:[-\s]|^)([A-Dઅબકડ])$', caseSensitive: false).firstMatch(lbl);
        if (m != null) rawSec = m.group(1)!.toUpperCase();
      }
      if (rawSec == 'અ') return 'A';
      if (rawSec == 'બ') return 'B';
      if (rawSec == 'ક') return 'C';
      if (rawSec == 'ડ') return 'D';
      return rawSec;
    }

    final allSchoolStudents = await from('students')
        .select()
        .eq('school_ref', schoolRef);
    final allActiveStudents = <Map<String, dynamic>>[];
    final graduatedStd8Students = <Map<String, dynamic>>[];
    final promotedStudentsHistory = <Map<String, dynamic>>[];

    for (final raw in allSchoolStudents) {
      final s = Map<String, dynamic>.from(raw);
      final lv = '${s['leaving_date'] ?? ''}'.trim();
      final leftByDate = lv.length >= 10 && lv.substring(0, 10).compareTo(todayIso) <= 0;
      final isAct = (s['is_active'] == true) && !leftByDate;
      if (isAct) {
        allActiveStudents.add(s);
        if ('${s['last_promotion_status'] ?? ''}' == 'promoted') {
          promotedStudentsHistory.add(s);
        }
      } else if ('${s['exit_reason'] ?? ''}' == 'promoted_graduated' ||
          '${s['last_promotion_status'] ?? ''}' == 'graduated_std_9') {
        graduatedStd8Students.add(s);
      }
    }

    // Map each class to its next standard class (Balvatika=0 -> Std 1, Std 1..7 -> +1, Std 8 -> Class 9 / Removed)
    final classPreviewList = <Map<String, dynamic>>[];
    for (final c in classes) {
      final cid = '${c['id'] ?? ''}'.trim();
      final std = _extractStandardNumber(
        '${c['standard'] ?? c['label'] ?? c['class_key'] ?? ''}',
      );
      final sec = normalizeSection(c);

      Map<String, dynamic>? nextClass;
      var candidates = <Map<String, dynamic>>[];
      if (std != null && std < 8) {
        final targetStd = std + 1;
        candidates = classes.where((other) {
          final oStd = _extractStandardNumber(
            '${other['standard'] ?? other['label'] ?? other['class_key'] ?? ''}',
          );
          return oStd == targetStd;
        }).toList();
        if (candidates.isNotEmpty) {
          nextClass = candidates.firstWhere(
            (other) => normalizeSection(other) == sec,
            orElse: () => candidates.first,
          );
        }
      }

      final sameStdClasses = classes.where((other) {
        final oStd = _extractStandardNumber(
          '${other['standard'] ?? other['label'] ?? other['class_key'] ?? ''}',
        );
        return std != null && oStd == std;
      }).toList();

      final classStudents = allActiveStudents
          .where((s) => '${s['class_id'] ?? ''}'.trim() == cid)
          .map((s) => <String, dynamic>{
                ...s,
                'id': '${s['id']}',
                'roll_number': '${s['roll_number'] ?? ''}',
                'gr': '${s['gr'] ?? ''}',
                'name': '${s['name'] ?? ''}',
                'class_id': cid,
              })
          .toList();
      classStudents.sort(_compareStudentsByRoll);

      classPreviewList.add(<String, dynamic>{
        'class_id': cid,
        'label': '${c['label'] ?? c['class_key'] ?? ''}',
        'standard': std ?? 0,
        'section': sec,
        'next_class_id': nextClass != null ? '${nextClass['id']}' : null,
        'next_class_label': nextClass != null
            ? '${nextClass['label'] ?? nextClass['class_key'] ?? ''}'
            : 'ધોરણ - 9 (શાળા પૂર્ણ / કમી — Goes to Class 9)',
        'candidate_next_classes': candidates
            .map((cand) => <String, dynamic>{
                  'id': '${cand['id']}',
                  'label': '${cand['label'] ?? cand['class_key'] ?? ''}',
                  'section': normalizeSection(cand),
                })
            .toList(),
        'same_standard_classes': sameStdClasses
            .map((sc) => <String, dynamic>{
                  'id': '${sc['id']}',
                  'label': '${sc['label'] ?? sc['class_key'] ?? ''}',
                  'section': normalizeSection(sc),
                })
            .toList(),
        'students': classStudents,
      });
    }

    return <String, dynamic>{
      'result_date_iso': resultDateIso,
      'result_date_dmy': resultDateDmy,
      'today_iso': todayIso,
      'can_promote': canPromote,
      'last_promoted_at': cfg['last_class_promotion_at'],
      'classes': classPreviewList,
      'graduated_std8_students': graduatedStd8Students,
      'promoted_students_history': promotedStudentsHistory,
    };
  }

  Future<Map<String, dynamic>> _setSecondSemResultDate({
    required String schoolRef,
    required String rawResultDate,
  }) async {
    final iso = _parseAnyDateToIso(rawResultDate);
    if (iso == null) {
      throw const PostgrestException(
        message: 'Enter a valid Second Semester Result Date (DD/MM/YYYY or YYYY-MM-DD).',
      );
    }
    final dmy = _isoToDmySlash(iso);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final settingsRow = await from('school_settings')
        .select()
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final cfg = settingsRow?['config'] is Map
        ? Map<String, dynamic>.from(settingsRow!['config'] as Map)
        : <String, dynamic>{};
    cfg['second_sem_result_date'] = iso;

    await _db.collection('school_settings').doc(schoolRef).set(<String, dynamic>{
      'id': schoolRef,
      'school_ref': schoolRef,
      'config': cfg,
      'updated_at': nowIso,
    }, fs.SetOptions(merge: true));

    final resultSnap = await _db
        .collection('class_result_settings')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    var batch = _db.batch();
    var ops = 0;
    for (final doc in resultSnap.docs) {
      batch.set(
        doc.reference,
        <String, dynamic>{
          'second_sem_result_date': dmy,
          'result_date': dmy,
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();

    FirestoreQueryBuilder.invalidateCache('school_settings');
    FirestoreQueryBuilder.invalidateCache('class_result_settings');
    return _getClassPromotionPreview(schoolRef: schoolRef);
  }

  static String _normGrKey(dynamic raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = '${raw ?? ''}'.trim();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    return s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static bool _isGenericExcelSheetName(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (s.isEmpty) return true;
    if (RegExp(r'^sheet\d*$').hasMatch(s)) return true;
    return const <String>{
      'students',
      'student',
      'data',
      'export',
      'grpartialupdate',
      'wholeschoolstudents',
      'exporttempforsinglegender',
      'exporttempforcoed',
      'instructions',
      'સૂચનાઓ',
    }.contains(s);
  }

  static String _normClassMatchKey(String raw) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var s = raw.trim().toLowerCase();
    for (var i = 0; i < guj.length; i++) {
      s = s.replaceAll(guj[i], '$i');
    }
    if (s.contains('બાલ') ||
        s.contains('વાટિકા') ||
        s.contains('balvatika') ||
        s.contains('balwatika') ||
        s.contains('ankur') ||
        s == 'bv' ||
        s == 'kg') {
      return 'balvatika';
    }
    s = s
        .replaceAll('ધોરણ', '')
        .replaceAll('વર્ગ', '')
        .replaceAll('standard', '')
        .replaceAll('std', '')
        .replaceAll('class', '')
        .replaceAll('અ', 'a')
        .replaceAll('બ', 'b')
        .replaceAll('ક', 'c')
        .replaceAll('ડ', 'd')
        .replaceAll(RegExp(r'[^a-z0-9\u0a80-\u0aff]+'), '');
    return s;
  }

  Future<Map<String, dynamic>> _smartBulkImportStudents({
    required String schoolRef,
    required List<Map<String, dynamic>> rows,
    String defaultClassId = '',
  }) async {
    if (rows.isEmpty) {
      return <String, dynamic>{
        'inserted_count': 0,
        'updated_count': 0,
        'skipped_count': 0,
        'warnings': <String>[],
      };
    }

    final classRows = await from('school_classes')
        .select()
        .eq('school_ref', schoolRef)
        .eq('is_active', true);
    final classes = classRows.map((c) => Map<String, dynamic>.from(c)).toList();

    String resolveClassId(String hint, String explicitId) {
      if (explicitId.isNotEmpty &&
          classes.any((c) => '${c['id']}' == explicitId)) {
        return explicitId;
      }
      final trimmed = hint.trim();
      if (trimmed.isNotEmpty && !_isGenericExcelSheetName(trimmed)) {
        final normHint = _normClassMatchKey(trimmed);
        for (final c in classes) {
          final cid = '${c['id']}';
          final candidates = <String>[
            '${c['label'] ?? ''}',
            '${c['class_key'] ?? ''}',
            '${c['sheet_name'] ?? ''}',
            '${c['standard'] ?? ''}${'${c['section'] ?? ''}'.isNotEmpty ? '-${c['section']}' : ''}',
            '${c['standard'] ?? ''}',
          ];
          for (final cand in candidates) {
            if (cand.trim().isEmpty) continue;
            if (cand.trim().toLowerCase() == trimmed.toLowerCase() ||
                _normClassMatchKey(cand) == normHint) {
              return cid;
            }
          }
        }
        // Fallback by standard number if only one class of that standard exists
        final stdNum = _extractStandardNumber(trimmed);
        if (stdNum != null) {
          final stdMatches = classes.where((c) {
            final cStd = _extractStandardNumber(
              '${c['standard'] ?? c['label'] ?? c['class_key'] ?? ''}',
            );
            return cStd == stdNum;
          }).toList();
          if (stdMatches.isNotEmpty) {
            return '${stdMatches.first['id']}';
          }
        }
      }
      return defaultClassId;
    }

    final existingSnap = await _db
        .collection('students')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final allStudents = existingSnap.docs
        .map((d) => <String, dynamic>{...d.data(), 'id': d.data()['id'] ?? d.id})
        .toList();

    final byGr = <String, Map<String, dynamic>>{};
    final byClassAndRoll = <String, Map<String, dynamic>>{};
    final byClassAndName = <String, Map<String, dynamic>>{};
    final maxRollByClass = <String, int>{};

    for (final s in allStudents) {
      final grKey = _normGrKey(s['gr']);
      if (grKey.isNotEmpty) {
        // Prefer active student if duplicate GR exists
        if (!byGr.containsKey(grKey) || s['is_active'] == true) {
          byGr[grKey] = s;
        }
      }
      if (s['is_active'] == true) {
        final cid = '${s['class_id'] ?? ''}'.trim();
        final roll = '${s['roll_number'] ?? ''}'.trim();
        final nameLower = '${s['name'] ?? ''}'.trim().toLowerCase();
        if (cid.isNotEmpty && roll.isNotEmpty) {
          byClassAndRoll['$cid|$roll'] = s;
          final rNum = int.tryParse(roll);
          if (rNum != null) {
            final curMax = maxRollByClass[cid] ?? 0;
            if (rNum > curMax) maxRollByClass[cid] = rNum;
          }
        }
        if (cid.isNotEmpty && nameLower.isNotEmpty) {
          byClassAndName['$cid|$nameLower'] = s;
        }
      }
    }

    const updatableFields = <String>{
      'roll_number',
      'gr',
      'dd',
      'mm',
      'yyyy',
      'name',
      'religion',
      'religion_en',
      'caste',
      'category',
      'gender',
      'enroll_school',
      'enroll_class',
      'mobile',
      'father_name',
      'mother_name',
      'address',
      'birth_place',
      'native_place',
      'dob_words',
      'last_school',
      'enroll_sch_class',
      'enroll_sch_class_words',
      'present_days',
      'name_en',
      'caste_en',
      'category_en',
      'mother_en',
      'birth_place_en',
      'native_place_en',
      'dob_en',
      'last_school_en',
      'enroll_sch_class_en',
      'enroll_sch_class_words_en',
      'uid',
      'pen',
      'apaar_id',
      'is_divyang',
      'has_aadhaar',
      'ration_card_kyc',
      'scholarship_done',
      'scholarship_reason',
      'scholarship_other',
      'leaving_date',
    };

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;
    int insertedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    final warnings = <String>[];
    final affectedClasses = <String>{};

    for (var idx = 0; idx < rows.length; idx++) {
      final item = rows[idx];
      final rowNum = int.tryParse('${item['row_number'] ?? (idx + 2)}') ?? (idx + 2);
      final values = item['values'] is Map
          ? Map<String, dynamic>.from(
              (item['values'] as Map).map((k, v) => MapEntry('$k', v)),
            )
          : Map<String, dynamic>.from(item);
      final customIn = values['custom_fields'] is Map
          ? Map<String, dynamic>.from(
              (values['custom_fields'] as Map).map((k, v) => MapEntry('$k', v)),
            )
          : <String, dynamic>{};

      final grKey = _normGrKey(values['gr']);
      final classHint = '${item['class_hint'] ?? values['class_hint'] ?? values['class_name'] ?? ''}'.trim();
      final explicitClassId = '${item['class_id'] ?? values['class_id'] ?? ''}'.trim();
      final resolvedClassId = resolveClassId(classHint, explicitClassId);

      Map<String, dynamic>? matched;
      // 1. Primary identity match: Unique GR Number across the whole school
      if (grKey.isNotEmpty && byGr.containsKey(grKey)) {
        matched = byGr[grKey];
      }
      // 2. Secondary match within resolved class: Roll Number or Student Name
      if (matched == null && resolvedClassId.isNotEmpty) {
        final rollText = '${values['roll_number'] ?? ''}'.trim();
        final nameText = '${values['name'] ?? ''}'.trim().toLowerCase();
        if (grKey.isEmpty && rollText.isNotEmpty && byClassAndRoll.containsKey('$resolvedClassId|$rollText')) {
          final cand = byClassAndRoll['$resolvedClassId|$rollText']!;
          final candName = '${cand['name'] ?? ''}'.trim().toLowerCase();
          if (nameText.isEmpty || candName == nameText) {
            matched = cand;
          }
        }
        if (matched == null && nameText.isNotEmpty && byClassAndName.containsKey('$resolvedClassId|$nameText')) {
          matched = byClassAndName['$resolvedClassId|$nameText'];
        }
      }

      if (matched != null) {
        // Smart Partial Column Merge: update ONLY non-empty fields provided in this Excel row, and reactivate if archived!
        final sid = '${matched['id']}';
        final patch = <String, dynamic>{
          'is_active': true,
          'leaving_date': null,
          'exit_date': null,
          'exit_reason': '',
          'updated_at': nowIso,
        };
        matched['is_active'] = true;
        matched['leaving_date'] = null;
        matched['exit_date'] = null;
        matched['exit_reason'] = '';
        if ('${matched['roll_number'] ?? ''}'.trim().isEmpty &&
            '${matched['previous_roll_number'] ?? ''}'.trim().isNotEmpty) {
          patch['roll_number'] = '${matched['previous_roll_number']}'.trim();
          matched['roll_number'] = patch['roll_number'];
        }
        if (explicitClassId.isNotEmpty || classHint.isNotEmpty) {
          if (resolvedClassId.isNotEmpty && resolvedClassId != '${matched['class_id']}') {
            affectedClasses.add('${matched['class_id']}');
            patch['class_id'] = resolvedClassId;
            matched['class_id'] = resolvedClassId;
          }
        }
        for (final field in updatableFields) {
          if (!values.containsKey(field)) continue;
          final val = values[field];
          if (val == null) continue;
          final strVal = '$val'.trim();
          if (strVal.isEmpty) continue;
          if (field == 'present_days') {
            patch[field] = int.tryParse(strVal) ?? matched[field] ?? 0;
          } else if (field == 'is_divyang') {
            patch[field] = val == true ||
                const <String>{'true', 'yes', '1', 'હા'}.contains(strVal.toLowerCase());
          } else if (field == 'category') {
            final up = strVal.toUpperCase();
            patch[field] = const <String>{'SC', 'ST', 'OBC', 'OTHER'}.contains(up)
                ? up
                : (up.contains('બક્ષી') ? 'OBC' : 'OTHER');
          } else if (field == 'gender') {
            final up = strVal.toUpperCase();
            if (up.contains('GIRL') || up == 'F' || up.contains('કન્યા')) {
              patch[field] = 'GIRLS';
            } else if (up.contains('BOY') || up == 'M' || up.contains('કુમાર')) {
              patch[field] = 'BOYS';
            }
          } else {
            patch[field] = strVal;
          }
          matched[field] = patch[field];
        }
        if (customIn.isNotEmpty) {
          final mergedCustom = matched['custom_fields'] is Map
              ? Map<String, dynamic>.from(
                  (matched['custom_fields'] as Map).map((k, v) => MapEntry('$k', v)),
                )
              : <String, dynamic>{};
          for (final entry in customIn.entries) {
            final vStr = '${entry.value ?? ''}'.trim();
            if (vStr.isNotEmpty) {
              mergedCustom[entry.key] = vStr;
            }
          }
          patch['custom_fields'] = mergedCustom;
          matched['custom_fields'] = mergedCustom;
        }
        if (grKey.isNotEmpty) {
          byGr[grKey] = matched;
        }
        affectedClasses.add('${matched['class_id'] ?? ''}');
        batch.set(col.doc(sid), patch, fs.SetOptions(merge: true));
        updatedCount++;
        ops++;
      } else {
        // New student insertion
        final nameText = '${values['name'] ?? ''}'.trim();
        if (nameText.isEmpty) {
          skippedCount++;
          warnings.add(
            grKey.isNotEmpty
                ? 'Row $rowNum: GR "$grKey" ડેટાબેઝમાં મળ્યો નથી અને નવા વિદ્યાર્થી માટે નામ (Name) આપેલ નથી.'
                : 'Row $rowNum: GR નંબર કે વિદ્યાર્થીનું નામ આપેલ નથી.',
          );
          continue;
        }
        if (resolvedClassId.isEmpty) {
          skippedCount++;
          warnings.add(
            'Row $rowNum ($nameText): વર્ગ (Class) ઓળખી શકાયો નથી ("$classHint").',
          );
          continue;
        }
        final nextRoll = (maxRollByClass[resolvedClassId] ?? 0) + 1;
        maxRollByClass[resolvedClassId] = nextRoll;
        final reqRoll = '${values['roll_number'] ?? ''}'.trim();
        final newId = _generateUuid();
        final newRow = <String, dynamic>{
          'id': newId,
          'school_ref': schoolRef,
          'class_id': resolvedClassId,
          'roll_number': reqRoll.isNotEmpty ? reqRoll : '$nextRoll',
          'gr': '${values['gr'] ?? ''}'.trim(),
          'dd': '${values['dd'] ?? ''}'.trim(),
          'mm': '${values['mm'] ?? ''}'.trim(),
          'yyyy': '${values['yyyy'] ?? ''}'.trim(),
          'name': nameText,
          'religion': '${values['religion'] ?? ''}'.trim(),
          'religion_en': '${values['religion_en'] ?? ''}'.trim(),
          'caste': '${values['caste'] ?? ''}'.trim(),
          'category': '${values['category'] ?? 'OTHER'}'.trim().toUpperCase(),
          'gender': '${values['gender'] ?? 'BOYS'}'.trim().toUpperCase(),
          'enroll_school': '${values['enroll_school'] ?? ''}'.trim(),
          'enroll_class': '${values['enroll_class'] ?? ''}'.trim(),
          'mobile': '${values['mobile'] ?? ''}'.trim(),
          'father_name': '${values['father_name'] ?? ''}'.trim(),
          'mother_name': '${values['mother_name'] ?? ''}'.trim(),
          'address': '${values['address'] ?? ''}'.trim(),
          'birth_place': '${values['birth_place'] ?? ''}'.trim(),
          'native_place': '${values['native_place'] ?? ''}'.trim(),
          'dob_words': '${values['dob_words'] ?? ''}'.trim(),
          'last_school': '${values['last_school'] ?? ''}'.trim(),
          'enroll_sch_class': '${values['enroll_sch_class'] ?? ''}'.trim(),
          'enroll_sch_class_words': '${values['enroll_sch_class_words'] ?? ''}'.trim(),
          'name_en': '${values['name_en'] ?? ''}'.trim(),
          'caste_en': '${values['caste_en'] ?? ''}'.trim(),
          'category_en': '${values['category_en'] ?? ''}'.trim(),
          'mother_en': '${values['mother_en'] ?? ''}'.trim(),
          'birth_place_en': '${values['birth_place_en'] ?? ''}'.trim(),
          'native_place_en': '${values['native_place_en'] ?? ''}'.trim(),
          'dob_en': '${values['dob_en'] ?? ''}'.trim(),
          'last_school_en': '${values['last_school_en'] ?? ''}'.trim(),
          'enroll_sch_class_en': '${values['enroll_sch_class_en'] ?? ''}'.trim(),
          'enroll_sch_class_words_en': '${values['enroll_sch_class_words_en'] ?? ''}'.trim(),
          'uid': '${values['uid'] ?? ''}'.trim(),
          'pen': '${values['pen'] ?? ''}'.trim(),
          'apaar_id': '${values['apaar_id'] ?? ''}'.trim(),
          'present_days': int.tryParse('${values['present_days'] ?? 0}') ?? 0,
          'is_divyang': values['is_divyang'] == true ||
              const <String>{'true', 'yes', '1', 'હા'}
                  .contains('${values['is_divyang'] ?? ''}'.trim().toLowerCase()),
          'has_aadhaar': '${values['has_aadhaar'] ?? 'NO'}'.trim(),
          'ration_card_kyc': '${values['ration_card_kyc'] ?? 'NO'}'.trim(),
          'scholarship_done': '${values['scholarship_done'] ?? 'NO'}'.trim(),
          'scholarship_reason': '${values['scholarship_reason'] ?? ''}'.trim(),
          'scholarship_other': '${values['scholarship_other'] ?? ''}'.trim(),
          'custom_fields': customIn,
          'is_active': true,
          'created_at': nowIso,
          'updated_at': nowIso,
        };
        try {
          await _normalizeStudentRowOnWrite(newRow, schoolRef);
        } catch (_) {}
        batch.set(col.doc(newId), newRow);
        if (grKey.isNotEmpty) byGr[grKey] = newRow;
        byClassAndName['$resolvedClassId|${nameText.toLowerCase()}'] = newRow;
        affectedClasses.add(resolvedClassId);
        insertedCount++;
        ops++;
      }

      if (ops >= 380) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    if (ops > 0) {
      await batch.commit();
    }

    for (final cid in affectedClasses) {
      if (cid.trim().isNotEmpty) {
        await _renumberActiveClassStudentsContinually(
          schoolRef: schoolRef,
          classId: cid.trim(),
        );
      }
    }
    FirestoreQueryBuilder.invalidateCache('students');

    return <String, dynamic>{
      'inserted_count': insertedCount,
      'updated_count': updatedCount,
      'skipped_count': skippedCount,
      'warnings': warnings,
    };
  }

  Future<Map<String, dynamic>> _changeStudentSectionOnly({
    required String schoolRef,
    required String toClassId,
    required Set<String> studentIds,
    String rawEffectiveDate = '',
  }) async {
    if (toClassId.isEmpty) {
      throw const PostgrestException(message: 'Target section/class is required.');
    }
    if (studentIds.isEmpty) {
      return <String, dynamic>{'changed_count': 0, 'affected_classes': <String>[]};
    }
    final targetClassRow = await from('school_classes')
        .select('id,label,class_key,standard')
        .eq('school_ref', schoolRef)
        .eq('id', toClassId)
        .maybeSingle();
    if (targetClassRow == null) {
      throw const PostgrestException(message: 'Selected target section was not found.');
    }
    final targetStd = _extractStandardNumber(
      '${targetClassRow['standard'] ?? targetClassRow['label'] ?? targetClassRow['class_key'] ?? ''}',
    );
    final allClassRows = await from('school_classes')
        .select('id,label,class_key,standard')
        .eq('school_ref', schoolRef);
    final stdByCid = <String, int?>{
      for (final c in allClassRows)
        '${c['id']}': _extractStandardNumber(
          '${c['standard'] ?? c['label'] ?? c['class_key'] ?? ''}',
        ),
    };
    final effectiveDateIso =
        _parseAnyDateToIso(rawEffectiveDate) ?? _indiaTodayIso();
    FirestoreQueryBuilder.invalidateCache('students');
    final snap = await _db
        .collection('students')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;
    int changedCount = 0;
    final affectedClasses = <String>{toClassId};

    for (final doc in snap.docs) {
      final d = doc.data();
      final sid = '${d['id'] ?? doc.id}'.trim();
      if (!studentIds.contains(sid)) continue;
      final oldClassId = '${d['class_id'] ?? ''}'.trim();
      if (oldClassId == toClassId) continue;
      final oldStd = stdByCid[oldClassId];
      // STRICT RULE: Section Change Anytime is ALWAYS only for sections of the SAME standard (e.g. Class 6 A <-> B <-> C), never across different standards!
      if (oldStd != targetStd) {
        throw const PostgrestException(
          message:
              'વિભાગ બદલો (Section Change) માં વિદ્યાર્થીને માત્ર તે જ ધોરણના અન્ય વિભાગ (A ↔ B ↔ C) માં જ ખસેડી શકાય છે, બીજા ધોરણમાં નહીં.',
          code: '42501',
        );
      }
      if (oldClassId.isNotEmpty) affectedClasses.add(oldClassId);

      // Append section_history so attendance before effectiveDateIso stays in oldClassId,
      // and Hajari Patrak reprints for months up to the change month print in oldClassId
      // while months after the change month print in toClassId!
      final existingCustom = d['custom_fields'] is Map
          ? Map<String, dynamic>.from(d['custom_fields'] as Map)
          : <String, dynamic>{};
      final rawHist = d['section_history'] is List
          ? (d['section_history'] as List)
          : (existingCustom['section_history'] is List
              ? (existingCustom['section_history'] as List)
              : const <dynamic>[]);
      final sectionHistory = rawHist
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      sectionHistory.add(<String, dynamic>{
        'from_class_id': oldClassId,
        'to_class_id': toClassId,
        'effective_date': effectiveDateIso,
        'old_roll_number': '${d['roll_number'] ?? ''}',
        'changed_at': nowIso,
      });
      existingCustom['section_history'] = sectionHistory;

      // Move all student profile data to the new section while keeping previous attendance records in oldClassId
      batch.set(
        col.doc(sid),
        <String, dynamic>{
          'class_id': toClassId,
          'section_history': sectionHistory,
          'custom_fields': existingCustom,
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
      changedCount++;
      ops++;
      if (ops >= 380) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();

    // Also update class_id on student_result_profiles and student_subject_marks so result entries follow the student's new section
    try {
      for (final table in const <String>['student_result_profiles', 'student_subject_marks']) {
        final rSnap = await _db
            .collection(table)
            .where('school_ref', isEqualTo: schoolRef)
            .get();
        var rBatch = _db.batch();
        var rOps = 0;
        for (final rDoc in rSnap.docs) {
          final rd = rDoc.data();
          final stId = '${rd['student_id'] ?? ''}'.trim();
          if (studentIds.contains(stId) && '${rd['class_id'] ?? ''}' != toClassId) {
            rBatch.set(
              rDoc.reference,
              <String, dynamic>{'class_id': toClassId, 'updated_at': nowIso},
              fs.SetOptions(merge: true),
            );
            rOps++;
            if (rOps >= 380) {
              await rBatch.commit();
              rBatch = _db.batch();
              rOps = 0;
            }
          }
        }
        if (rOps > 0) await rBatch.commit();
        FirestoreQueryBuilder.invalidateCache(table);
      }
    } catch (_) {}

    for (final cid in affectedClasses) {
      if (cid.isNotEmpty) {
        await _renumberActiveClassStudentsContinually(
          schoolRef: schoolRef,
          classId: cid,
        );
      }
    }
    FirestoreQueryBuilder.invalidateCache('students');
    return <String, dynamic>{
      'changed_count': changedCount,
      'to_class_id': toClassId,
      'to_class_label': '${targetClassRow['label'] ?? targetClassRow['class_key'] ?? ''}',
      'affected_classes': affectedClasses.toList(),
    };
  }

  Future<Map<String, dynamic>> _promoteSchoolClasses({
    required String schoolRef,
    required Set<String> retainedStudentIds,
    Map<String, String> studentTargetClassMap = const <String, String>{},
    Map<String, String> classTargetClassMap = const <String, String>{},
    String newClassEnrollDate = '',
    bool keepSameClassTeacher = true,
    Map<String, String> newClassTeacherMap = const <String, String>{},
  }) async {
    final preview = await _getClassPromotionPreview(schoolRef: schoolRef);
    final canPromote = preview['can_promote'] == true;
    final resultDateDmy = '${preview['result_date_dmy'] ?? ''}';
    if (!canPromote) {
      throw PostgrestException(
        message:
            'વર્ગ બઢતી (Class Promote) માત્ર બીજા સત્રના પરિણામની તારીખ ($resultDateDmy) ના રોજ અથવા ત્યારબાદ જ કરી શકાશે.',
        code: '42501',
      );
    }

    final classList = (preview['classes'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final classLabelById = <String, String>{
      for (final c in classList)
        '${c['class_id'] ?? ''}': '${c['label'] ?? ''}',
    };
    final classKeyById = <String, String>{
      for (final c in classList)
        '${c['class_id'] ?? ''}': '${c['class_key'] ?? c['label'] ?? ''}',
    };
    // Process in descending order of standard (8 -> 7 -> ... -> 1 -> 0 Balvatika)
    classList.sort((a, b) {
      final sa = int.tryParse('${a['standard'] ?? 0}') ?? 0;
      final sb = int.tryParse('${b['standard'] ?? 0}') ?? 0;
      return sb.compareTo(sa);
    });

    final todayIso = _indiaTodayIso();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final cleanEnrollDate = newClassEnrollDate.trim();
    final col = _db.collection('students');
    var batch = _db.batch();
    var ops = 0;
    int promotedCount = 0;
    int graduatedCount = 0;
    int retainedCount = 0;
    final affectedClasses = <String>{};
    // Track class-to-class promotion pairs so we can preserve the same Class Teacher on the new class
    final promotedClassPairs = <String, String>{};

    for (final c in classList) {
      final currentClassId = '${c['class_id'] ?? ''}'.trim();
      final currentClassLabel = '${c['label'] ?? ''}'.trim();
      final wholeClassOverrideId = '${classTargetClassMap[currentClassId] ?? ''}'.trim();
      final defaultNextClassId = (wholeClassOverrideId.isNotEmpty &&
              (wholeClassOverrideId == '__GRADUATE_9__' || classLabelById.containsKey(wholeClassOverrideId)))
          ? (wholeClassOverrideId == '__GRADUATE_9__' ? '' : wholeClassOverrideId)
          : (c['next_class_id'] == null ? '' : '${c['next_class_id']}'.trim());
      final defaultNextClassLabel = defaultNextClassId.isNotEmpty
          ? (classLabelById[defaultNextClassId] ?? '${c['next_class_label'] ?? ''}'.trim())
          : 'ધોરણ - 9 (Class 9)';
      if (currentClassId.isNotEmpty) affectedClasses.add(currentClassId);
      if (defaultNextClassId.isNotEmpty) {
        affectedClasses.add(defaultNextClassId);
        promotedClassPairs[currentClassId] = defaultNextClassId;
      }

      final students = (c['students'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      students.sort(_compareStudentsByRoll);

      for (var idx = 0; idx < students.length; idx++) {
        final st = students[idx];
        final sid = '${st['id'] ?? ''}'.trim();
        if (sid.isEmpty) continue;
        final oldRoll = '${st['roll_number'] ?? ''}'.trim();
        if (retainedStudentIds.contains(sid)) {
          // Non-promoted student: DO NOT change enroll_class (class enrolled date remains the exact same as before promotion)
          batch.set(
            col.doc(sid),
            <String, dynamic>{
              'last_promotion_status': 'retained',
              'promoted_from_class_id': currentClassId,
              'promoted_from_class_label': currentClassLabel,
              'promoted_to_class_id': currentClassId,
              'promoted_to_class_label': currentClassLabel,
              'promoted_at': todayIso,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          retainedCount++;
          ops++;
          continue;
        }
        final overrideClassId = '${studentTargetClassMap[sid] ?? ''}'.trim();
        final effectiveNextClassId = (overrideClassId.isNotEmpty &&
                classLabelById.containsKey(overrideClassId))
            ? overrideClassId
            : (overrideClassId == '__GRADUATE_9__' ? '' : defaultNextClassId);
        final effectiveNextClassLabel = effectiveNextClassId.isNotEmpty
            ? (classLabelById[effectiveNextClassId] ?? defaultNextClassLabel)
            : 'ધોરણ - 9 (Class 9)';

        if (effectiveNextClassId.isNotEmpty) {
          affectedClasses.add(effectiveNextClassId);
          promotedClassPairs.putIfAbsent(currentClassId, () => effectiveNextClassId);
          // Promote to next class and update enroll_class to the Admin-selected new class enroll date
          // while preserving previous_enroll_class + promotion_history so Hajari Patrak can print
          // BOTH old class (old enroll date) and new class (new enroll date) in the promotion month,
          // and all previous year attendance & result records remain 100% intact.
          final oldEnrollClass = '${st['enroll_class'] ?? ''}'.trim();
          final existingPromoHist = st['promotion_history'] is List
              ? (st['promotion_history'] as List)
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList()
              : <Map<String, dynamic>>[];
          existingPromoHist.add(<String, dynamic>{
            'from_class_id': currentClassId,
            'from_class_label': currentClassLabel,
            'to_class_id': effectiveNextClassId,
            'to_class_label': effectiveNextClassLabel,
            'old_enroll_class': oldEnrollClass,
            'new_enroll_class': cleanEnrollDate.isNotEmpty
                ? cleanEnrollDate
                : oldEnrollClass,
            'old_roll_number': oldRoll,
            'new_roll_number': '${idx + 1}',
            'promoted_at': todayIso,
          });
          batch.set(
            col.doc(sid),
            <String, dynamic>{
              'class_id': effectiveNextClassId,
              'roll_number': '${idx + 1}',
              if (oldRoll.isNotEmpty) 'previous_roll_number': oldRoll,
              if (oldEnrollClass.isNotEmpty)
                'previous_enroll_class': oldEnrollClass,
              if (cleanEnrollDate.isNotEmpty) 'enroll_class': cleanEnrollDate,
              'promotion_history': existingPromoHist,
              'promoted_from_class_id': currentClassId,
              'promoted_from_class_label': currentClassLabel,
              'promoted_to_class_id': effectiveNextClassId,
              'promoted_to_class_label': effectiveNextClassLabel,
              'promoted_at': todayIso,
              'last_promotion_status': 'promoted',
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          promotedCount++;
        } else {
          // Std 8 completed -> remove from active classes because they go to Class 9,
          // and preserve full student data for the Promoted / Std-8 Graduated Excel Export!
          batch.set(
            col.doc(sid),
            <String, dynamic>{
              'is_active': false,
              'roll_number': '',
              if (oldRoll.isNotEmpty) 'previous_roll_number': oldRoll,
              'leaving_date': todayIso,
              'exit_date': todayIso,
              'exit_reason': 'promoted_graduated',
              'promoted_from_class_id': currentClassId,
              'promoted_from_class_label': currentClassLabel,
              'promoted_to_class_id': '',
              'promoted_to_class_label': 'ધોરણ - 9 (Class 9)',
              'promoted_at': todayIso,
              'last_promotion_status': 'graduated_std_9',
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          graduatedCount++;
        }
        ops++;
        if (ops >= 380) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
    }

    if (ops > 0) {
      await batch.commit();
    }

    // Apply explicit New Class Teacher mapping if provided by Admin during promotion
    if (newClassTeacherMap.isNotEmpty) {
      try {
        var cBatch = _db.batch();
        var cOps = 0;
        final assignedClassesByTeacher = <String, Set<String>>{};
        for (final entry in newClassTeacherMap.entries) {
          final cid = entry.key.trim();
          final tid = entry.value.trim();
          if (cid.isEmpty || !classLabelById.containsKey(cid)) continue;
          cBatch.set(
            _db.collection('school_classes').doc(cid),
            <String, dynamic>{
              'class_teacher_id': tid.isEmpty ? null : tid,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          cOps++;
          if (tid.isNotEmpty) {
            assignedClassesByTeacher
                .putIfAbsent(tid, () => <String>{})
                .add(cid);
          }
        }
        if (cOps > 0) {
          await cBatch.commit();
          FirestoreQueryBuilder.invalidateCache('school_classes');
        }
        if (assignedClassesByTeacher.isNotEmpty) {
          final tSnap = await _db
              .collection('school_teachers')
              .where('school_ref', isEqualTo: schoolRef)
              .get();
          var tBatch = _db.batch();
          var tOps = 0;
          for (final tDoc in tSnap.docs) {
            final td = tDoc.data();
            final tid = '${td['id'] ?? tDoc.id}'.trim();
            final newCids = assignedClassesByTeacher[tid];
            if (newCids == null || newCids.isEmpty) continue;
            final existingAllowed = td['allowed_classes'] is List
                ? (td['allowed_classes'] as List)
                      .map((e) => '$e'.trim())
                      .where((s) => s.isNotEmpty)
                      .toSet()
                : <String>{};
            for (final cid in newCids) {
              existingAllowed.add(cid);
              final k = classKeyById[cid] ?? '';
              final l = classLabelById[cid] ?? '';
              if (k.isNotEmpty) existingAllowed.add(k);
              if (l.isNotEmpty) existingAllowed.add(l);
            }
            tBatch.set(
              tDoc.reference,
              <String, dynamic>{
                'allowed_classes': existingAllowed.toList(),
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            tOps++;
          }
          if (tOps > 0) {
            await tBatch.commit();
            FirestoreQueryBuilder.invalidateCache('school_teachers');
          }
        }
      } catch (_) {}
    }

    // Record a promotion archive entry (attendance & result records remain preserved untouched)
    try {
      final archiveId = '${schoolRef}__promo__${todayIso}_${DateTime.now().millisecondsSinceEpoch}';
      await _db.collection('school_promotion_archives').doc(archiveId).set(
        <String, dynamic>{
          'id': archiveId,
          'school_ref': schoolRef,
          'promoted_at': todayIso,
          'new_class_enroll_date': cleanEnrollDate,
          'promoted_count': promotedCount,
          'graduated_count': graduatedCount,
          'retained_count': retainedCount,
          'new_class_teacher_map': newClassTeacherMap,
          'attendance_and_result_archived': true,
          'created_at': nowIso,
        },
      );
    } catch (_) {}

    // If keepSameClassTeacher is enabled and no explicit teacher map was given,
    // keep the same Class Teacher assigned to the promoted class.
    if (newClassTeacherMap.isEmpty && keepSameClassTeacher && promotedClassPairs.isNotEmpty) {
      try {
        final tSnap = await _db
            .collection('school_teachers')
            .where('school_ref', isEqualTo: schoolRef)
            .get();
        // Snapshot each teacher's original allowed_classes before updating so chains (1->2->3) don't cascade
        final origAllowedByDocId = <String, List<String>>{};
        for (final tDoc in tSnap.docs) {
          final td = tDoc.data();
          if ('${td['role'] ?? ''}'.toLowerCase() == 'admin') continue;
          final rawAllowed = td['allowed_classes'];
          final list = rawAllowed is List
              ? rawAllowed.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList()
              : <String>[];
          origAllowedByDocId[tDoc.id] = list;
        }
        var tBatch = _db.batch();
        var tOps = 0;
        for (final tDoc in tSnap.docs) {
          final origList = origAllowedByDocId[tDoc.id];
          if (origList == null || origList.isEmpty) continue;
          final updatedSet = <String>{...origList};
          for (final entry in promotedClassPairs.entries) {
            final fromCid = entry.key;
            final toCid = entry.value;
            final fromLbl = classLabelById[fromCid] ?? '';
            final fromKey = classKeyById[fromCid] ?? '';
            final toLbl = classLabelById[toCid] ?? '';
            final toKey = classKeyById[toCid] ?? '';
            final taughtFrom = origList.any((item) =>
                item == fromCid ||
                (fromLbl.isNotEmpty && item.toLowerCase() == fromLbl.toLowerCase()) ||
                (fromKey.isNotEmpty && item.toLowerCase() == fromKey.toLowerCase()));
            if (taughtFrom) {
              if (toKey.isNotEmpty) updatedSet.add(toKey);
              if (toLbl.isNotEmpty) updatedSet.add(toLbl);
              updatedSet.add(toCid);
            }
          }
          if (updatedSet.length != origList.length) {
            tBatch.set(
              tDoc.reference,
              <String, dynamic>{
                'allowed_classes': updatedSet.toList(),
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            tOps++;
          }
        }
        if (tOps > 0) {
          await tBatch.commit();
          FirestoreQueryBuilder.invalidateCache('school_teachers');
        }
      } catch (_) {}
    }

    // Renumber all classes 1..N continuously
    for (final cid in affectedClasses) {
      if (cid.isNotEmpty) {
        await _renumberActiveClassStudentsContinually(
          schoolRef: schoolRef,
          classId: cid,
        );
      }
    }

    final settingsRow = await from('school_settings')
        .select()
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final cfg = settingsRow?['config'] is Map
        ? Map<String, dynamic>.from(settingsRow!['config'] as Map)
        : <String, dynamic>{};
    cfg['last_class_promotion_at'] = nowIso;
    await _db.collection('school_settings').doc(schoolRef).set(<String, dynamic>{
      'id': schoolRef,
      'school_ref': schoolRef,
      'config': cfg,
      'updated_at': nowIso,
    }, fs.SetOptions(merge: true));
    FirestoreQueryBuilder.invalidateCache('school_settings');
    FirestoreQueryBuilder.invalidateCache('students');

    return <String, dynamic>{
      'promoted_count': promotedCount,
      'graduated_count': graduatedCount,
      'retained_count': retainedCount,
      'promoted_at': nowIso,
    };
  }

  Future<Map<String, dynamic>> _replaceStudentResultRosterSnapshot({
    required String schoolRef,
    required String classId,
    required int semester,
    required String sourceDate,
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    if (ctx == null) {
      throw const PostgrestException(
        message: 'An active authenticated school teacher is required.',
      );
    }
    if (!ctx.isAdmin && !auth.hasRecentPasswordAuth) {
      throw const PostgrestException(
        message:
            'Confirm your account password again before replacing this roster.',
      );
    }
    final settings = await from('class_result_settings')
        .select()
        .eq('class_id', classId)
        .maybeSingle();
    final year = '${settings?['academic_year'] ?? '2026 - 27'}'.trim();
    final locked = semester == 1
        ? (settings != null && settings['sem1_locked'] == true)
        : (settings != null && settings['sem2_locked'] == true);
    if (locked && !ctx.isAdmin) {
      throw const PostgrestException(
        message: 'This semester is locked. A teacher cannot replace its roster until it is unlocked.',
      );
    }

    final existingSnaps = await from('student_result_roster_snapshots')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year', year);

    if (semester == 2 && !ctx.isAdmin) {
      final hasSem1 = existingSnaps.any(
        (s) => int.tryParse('${s['semester']}') == 1 && s['is_current'] == true,
      );
      if (!hasSem1) {
        throw const PostgrestException(
          message: 'Create the First Semester roster snapshot before importing the Second Semester roster.',
        );
      }
    }

    final dayRow = await from('attendance_days')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_date', sourceDate)
        .maybeSingle();
    if (dayRow == null || dayRow['student_details_saved'] != true) {
      throw const PostgrestException(
        message: 'No saved student-wise attendance register exists for this class and date.',
      );
    }

    final dayId = '${dayRow['id']}';
    final marks = await from('student_attendance')
        .select('student_id')
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('attendance_day_id', dayId);
    final studentIds = marks.map((m) => '${m['student_id']}').toSet();

    final activeStudents = await from('students')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('is_active', true);
    final rosterStudents = activeStudents
        .where((s) => studentIds.contains('${s['id']}'))
        .toList();
    if (rosterStudents.isEmpty) {
      throw const PostgrestException(
        message: 'The selected register date has no student detail rows.',
      );
    }
    rosterStudents.sort(_compareStudentsByRoll);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    var batch = _db.batch();
    var ops = 0;

    final snapCol = _db.collection('student_result_roster_snapshots');
    for (final old in existingSnaps) {
      if (int.tryParse('${old['semester']}') == semester &&
          old['is_current'] == true) {
        batch.update(snapCol.doc('${old['id']}'), <String, dynamic>{
          'is_current': false,
        });
        ops++;
      }
    }

    final newSnapId = _generateUuid();
    batch.set(snapCol.doc(newSnapId), <String, dynamic>{
      'id': newSnapId,
      'school_ref': schoolRef,
      'class_id': classId,
      'academic_year': year,
      'semester': semester,
      'source_date': sourceDate,
      'source_attendance_day_id': dayId,
      'roster_count': rosterStudents.length,
      'captured_by_teacher': ctx.teacherId,
      'captured_at': nowIso,
      'is_current': true,
    });
    ops++;

    final memberCol = _db.collection('student_result_roster_members');
    for (var i = 0; i < rosterStudents.length; i++) {
      final s = rosterStudents[i];
      final sid = '${s['id']}';
      final mId = '${newSnapId}__$sid';
      batch.set(memberCol.doc(mId), <String, dynamic>{
        'id': mId,
        'snapshot_id': newSnapId,
        'school_ref': schoolRef,
        'class_id': classId,
        'student_id': sid,
        'roll_number': '${s['roll_number'] ?? ''}',
        'student_name': '${s['name'] ?? ''}',
        'category': '${s['category'] ?? ''}',
        'gender': '${s['gender'] ?? 'UNSPECIFIED'}',
        'snapshot_order': i + 1,
        'student_data': <String, dynamic>{
          'id': sid,
          'studentId': sid,
          'roll_number': '${s['roll_number'] ?? ''}',
          'name': '${s['name'] ?? ''}',
          'gr': '${s['gr'] ?? ''}',
          'dd': '${s['dd'] ?? ''}',
          'mm': '${s['mm'] ?? ''}',
          'yyyy': '${s['yyyy'] ?? ''}',
          'uid': '${s['uid'] ?? ''}',
          'pen': '${s['pen'] ?? ''}',
          'mobile': '${s['mobile'] ?? ''}',
          'father_name': '${s['father_name'] ?? ''}',
          'mother_name': '${s['mother_name'] ?? ''}',
          'address': '${s['address'] ?? ''}',
          'category': '${s['category'] ?? ''}',
          'gender': '${s['gender'] ?? 'UNSPECIFIED'}',
          'caste': '${s['caste'] ?? ''}',
          'birth_place': '${s['birth_place'] ?? ''}',
          'dob_words': '${s['dob_words'] ?? ''}',
          'last_school': '${s['last_school'] ?? ''}',
          'is_active': s['is_active'] == true,
        },
      });
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    // Ensure student_result_profiles exist
    final profileCol = _db.collection('student_result_profiles');
    final slugYear = FirestoreQueryBuilder._slug(year);
    for (final s in rosterStudents) {
      final sid = '${s['id']}';
      final pId = '${schoolRef}__${classId}__${sid}__$slugYear';
      batch.set(profileCol.doc(pId), <String, dynamic>{
        'id': pId,
        'school_ref': schoolRef,
        'class_id': classId,
        'student_id': sid,
        'academic_year': year,
        'studied_in_sem2': true,
        'updated_at': nowIso,
      }, fs.SetOptions(merge: true));
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    if (ops > 0) await batch.commit();

    final versionCount =
        existingSnaps
            .where((s) => int.tryParse('${s['semester']}') == semester)
            .length +
        1;
    return <String, dynamic>{
      'result': 'success',
      'snapshotId': newSnapId,
      'sourceDate': sourceDate,
      'semester': semester,
      'academicYear': year,
      'count': rosterStudents.length,
      'versionCount': versionCount,
    };
  }

  Future<Map<String, dynamic>> _adminAddResultRosterMember({
    required String schoolRef,
    required String classId,
    required int semester,
    required String studentId,
  }) async {
    if (!await _isCurrentUserAdmin()) {
      throw const PostgrestException(
        message: 'Only the school administrator can add a student to a Result roster.',
      );
    }
    final settings = await from('class_result_settings')
        .select()
        .eq('class_id', classId)
        .maybeSingle();
    final year = '${settings?['academic_year'] ?? '2026 - 27'}'.trim();
    final currentSnap = await from('student_result_roster_snapshots')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year', year)
        .eq('semester', semester)
        .eq('is_current', true)
        .maybeSingle();
    if (currentSnap == null) {
      return <String, dynamic>{
        'result': 'no_snapshot',
        'message': 'Student was created, but this semester has no current roster snapshot yet. Import an attendance register to create one.',
      };
    }

    final student = await from('students')
        .select()
        .eq('id', studentId)
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .maybeSingle();
    if (student == null) {
      throw const PostgrestException(
        message: 'The student must be active in this class before being added to Result.',
      );
    }

    final baseId = '${currentSnap['id']}';
    final members = await from('student_result_roster_members')
        .select()
        .eq('snapshot_id', baseId);
    if (members.any((m) => '${m['student_id']}' == studentId)) {
      return <String, dynamic>{
        'result': 'success',
        'alreadyPresent': true,
        'count': members.length,
      };
    }

    final mId = '${baseId}__$studentId';
    final nextOrder = members.length + 1;
    await _db.collection('student_result_roster_members').doc(mId).set(
      <String, dynamic>{
        'id': mId,
        'snapshot_id': baseId,
        'school_ref': schoolRef,
        'class_id': classId,
        'student_id': studentId,
        'roll_number': '${student['roll_number'] ?? ''}',
        'student_name': '${student['name'] ?? ''}',
        'category': '${student['category'] ?? ''}',
        'gender': '${student['gender'] ?? 'UNSPECIFIED'}',
        'snapshot_order': nextOrder,
        'student_data': student,
      },
    );
    await _db.collection('student_result_roster_snapshots').doc(baseId).update(
      <String, dynamic>{'roster_count': nextOrder},
    );

    return <String, dynamic>{
      'result': 'success',
      'snapshotId': baseId,
      'count': nextOrder,
      'semester': semester,
      'academicYear': year,
    };
  }

  Future<Map<String, dynamic>> _adminRemoveResultRosterStudent({
    required String schoolRef,
    required String classId,
    required String studentId,
  }) async {
    if (!await _isCurrentUserAdmin()) {
      throw const PostgrestException(
        message:
            'Only the school administrator can remove a student from Result.',
      );
    }
    await _archiveOrDeleteStudentAndShiftRolls(
      schoolRef: schoolRef,
      studentId: studentId,
      deletePermanently: false,
    );

    final settings = await from('class_result_settings')
        .select()
        .eq('class_id', classId)
        .maybeSingle();
    final year = '${settings?['academic_year'] ?? '2026 - 27'}'.trim();
    final snaps = await from('student_result_roster_snapshots')
        .select()
        .eq('school_ref', schoolRef)
        .eq('class_id', classId)
        .eq('academic_year', year)
        .eq('is_current', true);

    int removed = 0;
    for (final snap in snaps) {
      final snapId = '${snap['id']}';
      final mId = '${snapId}__$studentId';
      final mDoc = await _db
          .collection('student_result_roster_members')
          .doc(mId)
          .get();
      if (mDoc.exists) {
        await mDoc.reference.delete();
        final nextCount = math.max(
          0,
          (int.tryParse('${snap['roster_count'] ?? 1}') ?? 1) - 1,
        );
        await _db
            .collection('student_result_roster_snapshots')
            .doc(snapId)
            .update(<String, dynamic>{'roster_count': nextCount});
        removed++;
      }
    }
    return <String, dynamic>{
      'result': 'success',
      'removedSnapshots': removed,
      'message': 'Current Result roster updated. Historical snapshots and stored marks were retained.',
    };
  }

  Future<Map<String, dynamic>> _saveSchoolResultGradeSettings(
    String schoolRef,
    List<Map<String, dynamic>> grades,
  ) async {
    if (grades.length < 2 || grades.length > 20) {
      throw const PostgrestException(
        message: 'Grade settings must contain between 2 and 20 grades.',
      );
    }
    final existing = await from('school_result_grade_settings')
        .select('id')
        .eq('school_ref', schoolRef);
    final batch = _db.batch();
    final col = _db.collection('school_result_grade_settings');
    for (final old in existing) {
      batch.delete(col.doc('${old['id']}'));
    }

    final sorted = List<Map<String, dynamic>>.from(grades)
      ..sort((a, b) {
        final ma = num.tryParse('${a['minimum_percent'] ?? 0}') ?? 0;
        final mb = num.tryParse('${b['minimum_percent'] ?? 0}') ?? 0;
        return mb.compareTo(ma);
      });

    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      final label = '${item['grade_label'] ?? item['label'] ?? ''}'.trim();
      final minPct =
          num.tryParse('${item['minimum_percent'] ?? 0}')?.toDouble() ?? 0.0;
      final docId = '${schoolRef}__${FirestoreQueryBuilder._slug(label)}';
      batch.set(col.doc(docId), <String, dynamic>{
        'id': docId,
        'school_ref': schoolRef,
        'grade_label': label,
        'minimum_percent': minPct,
        'sort_order': i,
        'is_active': true,
        'updated_at': nowIso,
      });
    }
    await batch.commit();
    return <String, dynamic>{'result': 'success', 'count': sorted.length};
  }

  Future<Map<String, dynamic>> _renameSchoolResultSubject({
    required String schoolRef,
    required String subjectId,
    required String newName,
  }) async {
    if (newName.isEmpty ||
        newName.length > 100 ||
        newName == 'વ્યક્તિત્વ વિકાસ') {
      throw const PostgrestException(
        message: 'Subject names must contain 1 to 100 characters; the reserved V.V. label cannot be renamed here.',
      );
    }
    final masterRow = await from('school_subject_master')
        .select()
        .eq('id', subjectId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (masterRow == null) {
      throw const PostgrestException(
        message: 'Subject was not found in this school.',
      );
    }
    final oldName = '${masterRow['subject_name'] ?? ''}'.trim();
    if (oldName.toLowerCase() == newName.toLowerCase()) {
      return <String, dynamic>{'result': 'success', 'renamed': false};
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    batch.update(
      _db.collection('school_subject_master').doc(subjectId),
      <String, dynamic>{'subject_name': newName, 'updated_at': nowIso},
    );

    for (final tbl in const <String>[
      'class_subjects',
      'teacher_subject_assignments',
      'school_subject_catalog',
    ]) {
      final rows = await from(tbl).select().eq('school_ref', schoolRef);
      for (final r in rows) {
        if ('${r['subject_name'] ?? ''}'.trim().toLowerCase() ==
            oldName.toLowerCase()) {
          batch.update(_db.collection(tbl).doc('${r['id']}'), <String, dynamic>{
            'subject_name': newName,
            'updated_at': nowIso,
          });
        }
      }
    }
    await batch.commit();
    return <String, dynamic>{
      'result': 'success',
      'renamed': true,
      'oldName': oldName,
      'newName': newName,
    };
  }

  Future<Map<String, dynamic>> _libraryBulkAddBooks(
    String schoolRef,
    List<Map<String, dynamic>> rows,
  ) async {
    final ctx = await _resolveCurrentTeacherContext();
    final existingBooks = await from('library_books')
        .select()
        .eq('school_ref', schoolRef);
    final existingHistory = await from('library_book_number_history')
        .select()
        .eq('school_ref', schoolRef);

    final usedNumbers = <String>{
      for (final b in existingBooks)
        '${b['book_number'] ?? ''}'.trim().toUpperCase(),
      for (final h in existingHistory)
        '${h['book_number'] ?? ''}'.trim().toUpperCase(),
    }..remove('');

    int added = 0;
    int skipped = 0;
    int invalid = 0;
    final duplicates = <String>[];
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var batch = _db.batch();
    var ops = 0;

    final booksCol = _db.collection('library_books');
    final histCol = _db.collection('library_book_number_history');

    for (final raw in rows) {
      final number = '${raw['book_number'] ?? raw['serial'] ?? ''}'.trim();
      final name = '${raw['book_name'] ?? raw['name'] ?? ''}'.trim();
      if (number.isEmpty || name.isEmpty) {
        invalid++;
        skipped++;
        continue;
      }
      final upperNum = number.toUpperCase();
      if (usedNumbers.contains(upperNum)) {
        skipped++;
        duplicates.add(number);
        continue;
      }
      final rawPrice = '${raw['price'] ?? ''}'.replaceAll(
        RegExp(r'(₹|inr|rs\.?|\s|,)', caseSensitive: false),
        '',
      );
      final price = rawPrice.isEmpty ? 0.0 : double.tryParse(rawPrice);
      if (price == null || price < 0) {
        invalid++;
        skipped++;
        continue;
      }

      final bookId = _generateUuid();
      batch.set(booksCol.doc(bookId), <String, dynamic>{
        'id': bookId,
        'school_ref': schoolRef,
        'book_number': number,
        'book_name': name,
        'author': '${raw['author'] ?? ''}'.trim(),
        'publication': '${raw['publication'] ?? ''}'.trim(),
        'isbn': '${raw['isbn'] ?? ''}'.trim(),
        'price': price,
        'is_active': true,
        'created_by_teacher': ctx?.teacherId,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      final histId = _generateUuid();
      batch.set(histCol.doc(histId), <String, dynamic>{
        'id': histId,
        'school_ref': schoolRef,
        'book_id': bookId,
        'book_number': number,
        'previous_book_number': '',
        'change_type': 'registered',
        'changed_by_teacher_id': ctx?.teacherId,
        'changed_by_teacher_name': ctx?.teacherName ?? '',
        'changed_at': nowIso,
      });

      usedNumbers.add(upperNum);
      added++;
      ops += 2;
      if (ops >= 400) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    FirestoreQueryBuilder.invalidateCache('library_books');
    FirestoreQueryBuilder.invalidateCache('library_book_number_history');

    return <String, dynamic>{
      'added': added,
      'skipped': skipped,
      'invalid': invalid,
      'duplicate_numbers': duplicates,
    };
  }

  Future<Map<String, dynamic>> _libraryArchiveBook({
    required String schoolRef,
    required String bookId,
    required String reasonCode,
    required String reasonDetails,
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    final book = await from('library_books')
        .select()
        .eq('id', bookId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (book == null || book['is_active'] != true) {
      throw const PostgrestException(
        message: 'Book not found or already removed.',
      );
    }
    final activeLoans = await from('library_transactions')
        .select('id')
        .eq('school_ref', schoolRef)
        .eq('book_id', bookId)
        .eq('status', 'issued');
    if (activeLoans.isNotEmpty) {
      throw const PostgrestException(
        message: 'This book is currently issued. Return it before removing it.',
      );
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _db.collection('library_books').doc(bookId).update(<String, dynamic>{
      'is_active': false,
      'retired_reason_code': reasonCode,
      'retired_reason_details': reasonDetails,
      'retired_at': nowIso,
      'retired_by_teacher_id': ctx?.teacherId,
      'retired_by_teacher_name': ctx?.teacherName ?? '',
      'updated_at': nowIso,
    });
    FirestoreQueryBuilder.invalidateCache('library_books');
    return <String, dynamic>{
      'archived': true,
      'book_number': book['book_number'],
      'book_name': book['book_name'],
      'reason_code': reasonCode,
      'reason_details': reasonDetails,
      'retired_at': nowIso,
    };
  }

  Future<Map<String, dynamic>> _libraryChangeBookNumber({
    required String schoolRef,
    required String bookId,
    required String newNumber,
  }) async {
    if (newNumber.isEmpty) {
      throw const PostgrestException(message: 'Book number cannot be empty.');
    }
    final ctx = await _resolveCurrentTeacherContext();
    final book = await from('library_books')
        .select()
        .eq('id', bookId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (book == null || book['is_active'] != true) {
      throw const PostgrestException(message: 'Active book not found.');
    }
    final oldNumber = '${book['book_number'] ?? ''}'.trim();
    if (oldNumber.toUpperCase() == newNumber.toUpperCase()) {
      return <String, dynamic>{
        'changed': false,
        'old_book_number': oldNumber,
        'new_book_number': oldNumber,
      };
    }
    final activeLoans = await from('library_transactions')
        .select('id')
        .eq('school_ref', schoolRef)
        .eq('book_id', bookId)
        .eq('status', 'issued');
    if (activeLoans.isNotEmpty) {
      throw const PostgrestException(
        message: 'Return this book before changing its number.',
      );
    }
    final history = await from('library_book_number_history')
        .select('book_number')
        .eq('school_ref', schoolRef);
    final used = history.any(
      (h) =>
          '${h['book_number']}'.trim().toUpperCase() == newNumber.toUpperCase(),
    );
    if (used) {
      throw const PostgrestException(
        message: 'This number has already been used in this school, including older/removed books. Choose a new number.',
      );
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    batch.update(_db.collection('library_books').doc(bookId), <String, dynamic>{
      'book_number': newNumber,
      'updated_at': nowIso,
    });
    final histId = _generateUuid();
    batch.set(
      _db.collection('library_book_number_history').doc(histId),
      <String, dynamic>{
        'id': histId,
        'school_ref': schoolRef,
        'book_id': bookId,
        'book_number': newNumber,
        'previous_book_number': oldNumber,
        'change_type': 'renumbered',
        'changed_by_teacher_id': ctx?.teacherId,
        'changed_by_teacher_name': ctx?.teacherName ?? '',
        'changed_at': nowIso,
      },
    );
    await batch.commit();
    FirestoreQueryBuilder.invalidateCache('library_books');
    FirestoreQueryBuilder.invalidateCache('library_book_number_history');
    return <String, dynamic>{
      'changed': true,
      'old_book_number': oldNumber,
      'new_book_number': newNumber,
    };
  }

  Future<Map<String, dynamic>> _libraryIssueBook({
    required String schoolRef,
    required Map<String, dynamic> params,
  }) async {
    final ctx = await _resolveCurrentTeacherContext();
    final bookId = '${params['p_book_id'] ?? ''}'.trim();
    final borrowerType = '${params['p_borrower_type'] ?? ''}'.trim();
    final classId = '${params['p_class_id'] ?? ''}'.trim();
    final studentId = '${params['p_student_id'] ?? ''}'.trim();
    final teacherBorrowerId = '${params['p_teacher_borrower_id'] ?? ''}'.trim();
    final issueDate = '${params['p_issue_date'] ?? _indiaTodayIso()}'.trim();
    final remarks = '${params['p_remarks'] ?? ''}'.trim();

    if (issueDate.compareTo(_indiaTodayIso()) > 0) {
      throw const PostgrestException(
        message: 'Issue date must be today or an earlier date.',
      );
    }

    final settingsRow = await from('library_settings')
        .select()
        .eq('school_ref', schoolRef)
        .maybeSingle();
    final dueDays = int.tryParse('${settingsRow?['due_days'] ?? 14}') ?? 14;
    final maxBooks =
        int.tryParse('${settingsRow?['max_books_per_borrower'] ?? 1}') ?? 1;
    final finePerDay =
        num.tryParse('${settingsRow?['fine_per_day'] ?? 0}')?.toDouble() ?? 0.0;

    final book = await from('library_books')
        .select()
        .eq('id', bookId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (book == null || book['is_active'] != true) {
      throw const PostgrestException(
        message: 'Book number not found or the book has been deleted.',
      );
    }

    final activeForBook = await from('library_transactions')
        .select('id')
        .eq('school_ref', schoolRef)
        .eq('book_id', bookId)
        .eq('status', 'issued');
    if (activeForBook.isNotEmpty) {
      throw const PostgrestException(
        message:
            'This book is already issued. Return it before issuing it again.',
      );
    }

    String borrowerName = '';
    String rollNumber = '';
    String classLabel = '';

    if (borrowerType == 'student') {
      final student = await from('students')
          .select()
          .eq('id', studentId)
          .eq('school_ref', schoolRef)
          .maybeSingle();
      if (student == null || student['is_active'] != true) {
        throw const PostgrestException(
          message: 'Student not found in the selected registered class.',
        );
      }
      final cls = await from('school_classes')
          .select()
          .eq('id', classId)
          .eq('school_ref', schoolRef)
          .maybeSingle();
      borrowerName = '${student['name'] ?? ''}';
      rollNumber = '${student['roll_number'] ?? ''}';
      classLabel = '${cls?['label'] ?? ''}';

      final borrowerLoans = await from('library_transactions')
          .select('id')
          .eq('school_ref', schoolRef)
          .eq('student_id', studentId)
          .eq('status', 'issued');
      if (borrowerLoans.length >= maxBooks) {
        throw PostgrestException(
          message:
              'Borrower has reached the maximum of $maxBooks active book(s).',
        );
      }
    } else {
      final teacher = await from('school_teachers')
          .select()
          .eq('id', teacherBorrowerId)
          .eq('school_ref', schoolRef)
          .maybeSingle();
      if (teacher == null || teacher['is_active'] != true) {
        throw const PostgrestException(
          message: 'Select a registered active teacher.',
        );
      }
      borrowerName = '${teacher['teacher_name'] ?? ''}';
      final borrowerLoans = await from('library_transactions')
          .select('id')
          .eq('school_ref', schoolRef)
          .eq('teacher_borrower_id', teacherBorrowerId)
          .eq('status', 'issued');
      if (borrowerLoans.length >= maxBooks) {
        throw PostgrestException(
          message:
              'Borrower has reached the maximum of $maxBooks active book(s).',
        );
      }
    }

    final parsedIssue = DateTime.parse(issueDate);
    final dueDateDt = parsedIssue.add(Duration(days: dueDays));
    final dueDate =
        '${dueDateDt.year.toString().padLeft(4, '0')}-${dueDateDt.month.toString().padLeft(2, '0')}-${dueDateDt.day.toString().padLeft(2, '0')}';

    final txId = _generateUuid();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _db.collection('library_transactions').doc(txId).set(
      <String, dynamic>{
        'id': txId,
        'school_ref': schoolRef,
        'book_id': bookId,
        'book_number_snapshot': '${book['book_number'] ?? ''}',
        'book_name_snapshot': '${book['book_name'] ?? ''}',
        'author_snapshot': '${book['author'] ?? ''}',
        'borrower_type': borrowerType,
        'student_id': borrowerType == 'student' ? studentId : null,
        'teacher_borrower_id': borrowerType == 'teacher'
            ? teacherBorrowerId
            : null,
        'class_id': borrowerType == 'student' ? classId : null,
        'class_label_snapshot': classLabel,
        'borrower_name_snapshot': borrowerName,
        'roll_number_snapshot': rollNumber,
        'issue_date': issueDate,
        'due_date': dueDate,
        'due_days_at_issue': dueDays,
        'fine_per_day_at_issue': finePerDay,
        'return_date': null,
        'status': 'issued',
        'issue_remarks': remarks,
        'return_remarks': '',
        'recorded_by_teacher_id': ctx?.teacherId,
        'recorded_by_teacher_name': ctx?.teacherName ?? '',
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );

    FirestoreQueryBuilder.invalidateCache('library_transactions');
    return <String, dynamic>{
      'id': txId,
      'book_number': book['book_number'],
      'book_name': book['book_name'],
      'borrower_name': borrowerName,
      'issue_date': issueDate,
      'due_date': dueDate,
    };
  }

  Future<Map<String, dynamic>> _libraryReturnBook({
    required String schoolRef,
    required Map<String, dynamic> params,
  }) async {
    final txId = '${params['p_transaction_id'] ?? ''}'.trim();
    final returnDate = '${params['p_return_date'] ?? _indiaTodayIso()}'.trim();
    final remarks = '${params['p_return_remarks'] ?? ''}'.trim();

    if (returnDate.compareTo(_indiaTodayIso()) > 0) {
      throw const PostgrestException(
        message: 'Return date must be today or an earlier date.',
      );
    }

    final tx = await from('library_transactions')
        .select()
        .eq('id', txId)
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (tx == null || '${tx['status']}' != 'issued') {
      throw const PostgrestException(
        message:
            'The selected loan was already returned or is no longer available.',
      );
    }
    if (returnDate.compareTo('${tx['issue_date']}') < 0) {
      throw const PostgrestException(
        message: 'Return date cannot be earlier than the issue date.',
      );
    }

    await _db.collection('library_transactions').doc(txId).update(
      <String, dynamic>{
        'status': 'returned',
        'return_date': returnDate,
        'return_remarks': remarks,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );

    FirestoreQueryBuilder.invalidateCache('library_transactions');
    return <String, dynamic>{
      'id': txId,
      'book_number': tx['book_number_snapshot'],
      'book_name': tx['book_name_snapshot'],
      'borrower_name': tx['borrower_name_snapshot'],
      'return_date': returnDate,
    };
  }

  static String? _lastAutoCloudPurgeDateIso;

  static String _extractIndiaDateIsoFromAny(dynamic rawValue) {
    final raw = '${rawValue ?? ''}'.trim();
    if (raw.isEmpty) return '';
    final parsedIso = _parseAnyDateToIso(raw);
    if (parsedIso != null && parsedIso.length >= 10) {
      return parsedIso.substring(0, 10);
    }
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
      return '${ist.year.toString().padLeft(4, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.day.toString().padLeft(2, '0')}';
    }
    if (raw.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
      return raw.substring(0, 10);
    }
    return '';
  }

  /// Automatically deletes expired developer shared files, developer messages,
  /// message dismissals, validity reminder dismissals, school admin messages,
  /// and temporary file shares after their display date (< India today).
  Future<Map<String, int>> purgeExpiredCloudStorageAndMessages({
    bool force = false,
    bool deleteAllSharedFiles = false,
  }) async {
    final today = _indiaTodayIso();
    if (!force && !deleteAllSharedFiles) {
      if (_lastAutoCloudPurgeDateIso == today) {
        return const <String, int>{};
      }
      final ctx = _cachedContext;
      if (ctx != null && !ctx.isAdmin) {
        // Skip multi-collection background cleanup for regular teacher sessions
        _lastAutoCloudPurgeDateIso = today;
        return const <String, int>{};
      }
    }
    _lastAutoCloudPurgeDateIso = today;
    int deletedDevMessages = 0;
    int deletedDismissals = 0;
    int deletedValidityDismissals = 0;
    int deletedAdminMessages = 0;
    int deletedDevFiles = 0;
    int deletedSchoolSharedFiles = 0;

    final activeDevMessageIds = <String>{};

    // 1. developer_messages: delete any message where display_date < today
    try {
      final snap = await _db.collection('developer_messages').get();
      for (final d in snap.docs) {
        final data = d.data();
        final dispDate = _extractIndiaDateIsoFromAny(
          data['display_date'] ?? data['created_at'],
        );
        if (dispDate.isNotEmpty && dispDate.compareTo(today) < 0) {
          try {
            await d.reference.delete();
            deletedDevMessages++;
          } catch (_) {}
        } else {
          activeDevMessageIds.add('${data['id'] ?? d.id}'.trim());
          activeDevMessageIds.add(d.id);
        }
      }
      if (deletedDevMessages > 0) {
        FirestoreQueryBuilder.invalidateCache('developer_messages');
      }
    } catch (_) {}

    // 2. developer_message_dismissals: delete if message_id is no longer in active developer_messages OR dismissed_at date < today
    try {
      final snap = await _db.collection('developer_message_dismissals').get();
      for (final d in snap.docs) {
        final data = d.data();
        final mid = '${data['message_id'] ?? ''}'.trim();
        final dismDate = _extractIndiaDateIsoFromAny(data['dismissed_at']);
        final isOrphan = mid.isEmpty || !activeDevMessageIds.contains(mid);
        final isOld = dismDate.isNotEmpty && dismDate.compareTo(today) < 0;
        if (isOrphan || isOld) {
          try {
            await d.reference.delete();
            deletedDismissals++;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. school_validity_reminder_dismissals: delete if reminder_date < today
    try {
      final snap =
          await _db.collection('school_validity_reminder_dismissals').get();
      for (final d in snap.docs) {
        final data = d.data();
        final rDate = _extractIndiaDateIsoFromAny(
          data['reminder_date'] ?? data['dismissed_at'],
        );
        final docParts = d.id.split('__');
        final idDate = docParts.length >= 3 ? docParts.last.trim() : '';
        final checkDate = rDate.isNotEmpty ? rDate : idDate;
        if (checkDate.isNotEmpty && checkDate.compareTo(today) < 0) {
          try {
            await d.reference.delete();
            deletedValidityDismissals++;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 4. school_admin_messages: delete if message_date < today
    try {
      final snap = await _db.collection('school_admin_messages').get();
      for (final d in snap.docs) {
        final data = d.data();
        final mDate = _extractIndiaDateIsoFromAny(
          data['message_date'] ?? data['created_at'],
        );
        final docParts = d.id.split('__');
        final idDate = docParts.length >= 2 ? docParts.last.trim() : '';
        final checkDate = mDate.isNotEmpty ? mDate : idDate;
        if (checkDate.isNotEmpty && checkDate.compareTo(today) < 0) {
          try {
            await d.reference.delete();
            deletedAdminMessages++;
          } catch (_) {}
        }
      }
      if (deletedAdminMessages > 0) {
        FirestoreQueryBuilder.invalidateCache('school_admin_messages');
      }
    } catch (_) {}

    // 5. developer_shared_files + school_assets (dev_shared__*): delete if display_date (or created_at date) < today
    final activeDevAssetDocIds = <String>{};
    try {
      final snap = await _db.collection('developer_shared_files').get();
      for (final d in snap.docs) {
        final data = d.data();
        final fileId = '${data['id'] ?? d.id}'.trim();
        final assetDocId =
            '${data['asset_doc_id'] ?? 'dev_shared__$fileId'}'.trim();
        final dispDate = _extractIndiaDateIsoFromAny(
          data['display_date'] ?? data['created_at'] ?? data['updated_at'],
        );
        final isExpired =
            deleteAllSharedFiles ||
            data['is_active'] == false ||
            (dispDate.isNotEmpty && dispDate.compareTo(today) < 0);
        if (isExpired) {
          if (assetDocId.isNotEmpty) {
            try {
              await _db.collection('school_assets').doc(assetDocId).delete();
            } catch (_) {}
          }
          try {
            await d.reference.delete();
            deletedDevFiles++;
          } catch (_) {}
        } else {
          if (assetDocId.isNotEmpty) activeDevAssetDocIds.add(assetDocId);
          activeDevAssetDocIds.add('dev_shared__$fileId');
          activeDevAssetDocIds.add('dev_shared__${d.id}');
        }
      }
      // Also clean any orphaned dev_shared__* assets in school_assets (pushed filter so school logos are never read)
      final assetSnap = await _db
          .collection('school_assets')
          .where('bucket', isEqualTo: 'developer-shared-files')
          .get();
      for (final aDoc in assetSnap.docs) {
        final aData = aDoc.data();
        final isDevAsset = aDoc.id.startsWith('dev_shared__') ||
            '${aData['bucket'] ?? ''}' == 'developer-shared-files';
        if (!isDevAsset) continue;
        final aDate = _extractIndiaDateIsoFromAny(
          aData['display_date'] ?? aData['updated_at'] ?? aData['created_at'],
        );
        final isOrphanOrExpired =
            deleteAllSharedFiles ||
            !activeDevAssetDocIds.contains(aDoc.id) ||
            (aDate.isNotEmpty && aDate.compareTo(today) < 0);
        if (isOrphanOrExpired) {
          try {
            await aDoc.reference.delete();
            deletedDevFiles++;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 6. school_shared_files & file_beam_rooms (+ chunks): delete if display/created date < today or expired
    for (final colName in const <String>[
      'school_shared_files',
      'file_beam_rooms',
    ]) {
      try {
        final snap = await _db.collection(colName).get();
        for (final d in snap.docs) {
          final data = d.data();
          final cDate = _extractIndiaDateIsoFromAny(
            data['display_date'] ?? data['created_at'] ?? data['updated_at'],
          );
          final expRaw = '${data['expires_at'] ?? ''}'.trim();
          final expDt = expRaw.isNotEmpty ? DateTime.tryParse(expRaw) : null;
          final isExpiredByTime =
              expDt != null && DateTime.now().toUtc().isAfter(expDt.toUtc());
          final isExpiredByDate =
              cDate.isNotEmpty && cDate.compareTo(today) < 0;
          if (deleteAllSharedFiles || isExpiredByTime || isExpiredByDate) {
            try {
              final chunkSnap =
                  await d.reference.collection('chunks').limit(400).get();
              for (final ch in chunkSnap.docs) {
                try {
                  await ch.reference.delete();
                } catch (_) {}
              }
              await d.reference.delete();
              deletedSchoolSharedFiles++;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return <String, int>{
      'deleted_developer_messages': deletedDevMessages,
      'deleted_message_dismissals': deletedDismissals,
      'deleted_validity_dismissals': deletedValidityDismissals,
      'deleted_school_admin_messages': deletedAdminMessages,
      'deleted_developer_shared_files': deletedDevFiles,
      'deleted_school_shared_files': deletedSchoolSharedFiles,
    };
  }
}

class FirestoreFunctionsClient {
  FirestoreFunctionsClient(this._client);

  final SupabaseClient _client;
  fb_core.FirebaseApp? _helperApp;

  fs.FirebaseFirestore get _db => _client._db;

  Future<fb_auth.FirebaseAuth> _getHelperAuth() async {
    if (_helperApp == null) {
      try {
        _helperApp = fb_core.Firebase.app('psm_auth_helper');
      } catch (_) {
        _helperApp = await fb_core.Firebase.initializeApp(
          name: 'psm_auth_helper',
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    }
    return fb_auth.FirebaseAuth.instanceFor(app: _helperApp!);
  }

  Future<Map<String, dynamic>?> _tryCallableCloudFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    try {
      final functions = fn.FirebaseFunctions.instanceFor(region: 'asia-south1');
      final callable = functions.httpsCallable('psmEdgeFunction');
      final res = await callable
          .call(<String, dynamic>{'functionName': functionName, 'body': body})
          .timeout(const Duration(seconds: 15));
      if (res.data is Map) {
        return Map<String, dynamic>.from(
          (res.data as Map).map((k, v) => MapEntry('$k', v)),
        );
      }
    } catch (_) {
      // Fall back to direct Firestore + Firebase Auth execution when Cloud Functions
      // are not deployed or unreachable.
    }
    return null;
  }

  Future<FunctionResponse> invoke(String functionName, {Object? body}) async {
    final mapBody = body is Map
        ? Map<String, dynamic>.from(body.map((k, v) => MapEntry('$k', v)))
        : <String, dynamic>{};

    try {
      Map<String, dynamic> result;
      switch (functionName) {
        case 'psm-school-directory-v2':
        case 'list-school-teachers':
          result = await _handleSchoolDirectory(mapBody);
          break;
        case 'psm-school-login-v2':
          result = await _handleSchoolLogin(mapBody);
          break;
        case 'psm-attendance-admin-override':
          result = await _handleAttendanceAdminOverride(mapBody);
          break;
        case 'psm-platform-admin':
          result = await _handlePlatformAdmin(mapBody);
          break;
        case 'admin-school-management':
          result = await _handleAdminSchoolManagement(mapBody);
          break;
        case 'psm-password-reset-otp':
          result = await _handlePasswordResetOtp(mapBody);
          break;
        default:
          final remote = await _tryCallableCloudFunction(functionName, mapBody);
          if (remote != null) {
            result = remote;
          } else {
            throw FunctionException(
              status: 404,
              details: <String, dynamic>{
                'error': 'Unknown function: $functionName',
              },
              reasonPhrase: 'Not Found',
            );
          }
      }
      return FunctionResponse(status: 200, data: result);
    } on FunctionException {
      rethrow;
    } on PostgrestException catch (e) {
      throw FunctionException(
        status: 400,
        details: <String, dynamic>{'error': e.message},
        reasonPhrase: e.message,
      );
    } on AuthException catch (e) {
      throw FunctionException(
        status: 401,
        details: <String, dynamic>{'error': e.message},
        reasonPhrase: e.message,
      );
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      throw FunctionException(
        status: 400,
        details: <String, dynamic>{'error': msg},
        reasonPhrase: msg,
      );
    }
  }

  Future<Map<String, dynamic>> _handleSchoolDirectory(
    Map<String, dynamic> body,
  ) async {
    final schoolId = '${body['schoolId'] ?? ''}'.trim();
    if (schoolId.isEmpty) {
      throw const PostgrestException(
        message: 'Enter a numeric DISE/UDISE number (4–20 digits). Leading zeros are preserved.',
      );
    }

    final snap = await _db
        .collection('schools')
        .where('school_id', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      throw const PostgrestException(
        message: 'School not found or deactivated.',
      );
    }
    final schoolDoc = snap.docs.first;
    final school = <String, dynamic>{
      ...schoolDoc.data(),
      'id': schoolDoc.data()['id'] ?? schoolDoc.id,
    };
    if (school['is_active'] != true) {
      throw const PostgrestException(
        message: 'School not found or deactivated.',
      );
    }
    final validity = '${school['validity_date'] ?? ''}'.trim();
    if (validity.length >= 10 &&
        validity.substring(0, 10).compareTo(SupabaseClient._indiaTodayIso()) <
            0) {
      throw const PostgrestException(
        message: 'School validity has expired. Contact the Developer.',
      );
    }

    final teachersSnap = await _db
        .collection('school_teachers')
        .where('school_ref', isEqualTo: '${school['id']}')
        .get();
    final teachers = <Map<String, dynamic>>[];
    for (final doc in teachersSnap.docs) {
      final t = doc.data();
      if (t['is_active'] != true) continue;
      final tid = '${t['id'] ?? doc.id}';
      final email = '${t['login_email'] ?? ''}'.trim().isNotEmpty
          ? '${t['login_email']}'.trim()
          : 'teacher-${tid.toLowerCase()}@login.psm.example.com';
      teachers.add(<String, dynamic>{
        'id': tid,
        'name': '${t['teacher_name'] ?? ''}',
        'teacher_name': '${t['teacher_name'] ?? ''}',
        'role': '${t['role'] ?? 'teacher'}',
        'loginEmail': email,
        'login_email': email,
        'allowed_classes': t['allowed_classes'] ?? const <String>[],
      });
    }
    teachers.sort((a, b) {
      final ra = '${a['role']}'.toLowerCase() == 'admin' ? 0 : 1;
      final rb = '${b['role']}'.toLowerCase() == 'admin' ? 0 : 1;
      if (ra != rb) return ra.compareTo(rb);
      return '${a['name']}'.toLowerCase().compareTo(
        '${b['name']}'.toLowerCase(),
      );
    });

    return <String, dynamic>{
      'school': <String, dynamic>{
        'id': school['id'],
        'school_id': school['school_id'],
        'schoolId': school['school_id'],
        'school_name': school['school_name'],
        'schoolName': school['school_name'],
        'school_name_en': school['school_name_en'] ?? school['school_name'],
        'school_name_gu': school['school_name_gu'] ?? '',
        'school_type': school['school_type'] ?? 'mixed',
        'validity_date': school['validity_date'],
        'is_blocked': school['is_blocked'] == true,
        'block_reason': '${school['block_reason'] ?? ''}',
      },
      'teachers': teachers,
    };
  }

  Future<Map<String, dynamic>> _handleSchoolLogin(
    Map<String, dynamic> body,
  ) async {
    final schoolId = '${body['schoolId'] ?? ''}'.trim();
    final teacherId = '${body['teacherId'] ?? ''}'.trim();
    final password = '${body['password'] ?? ''}';
    if (schoolId.isEmpty || teacherId.isEmpty || password.isEmpty) {
      throw const PostgrestException(
        message: 'Enter a numeric DISE/UDISE number (4–20 digits), select a user, and enter the password.',
      );
    }

    final snap = await _db
        .collection('schools')
        .where('school_id', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      throw const PostgrestException(
        message: 'School is not active. Contact the Developer.',
      );
    }
    final school = <String, dynamic>{
      ...snap.docs.first.data(),
      'id': snap.docs.first.data()['id'] ?? snap.docs.first.id,
    };
    if (school['is_active'] != true) {
      throw const PostgrestException(
        message: 'School is not active. Contact the Developer.',
      );
    }
    final validity = '${school['validity_date'] ?? ''}'.trim();
    if (validity.length >= 10 &&
        validity.substring(0, 10).compareTo(SupabaseClient._indiaTodayIso()) <
            0) {
      throw const PostgrestException(
        message: 'School validity has expired. Contact the Developer.',
      );
    }

    final tDoc = await _db.collection('school_teachers').doc(teacherId).get();
    Map<String, dynamic>? profile;
    if (tDoc.exists && tDoc.data() != null) {
      profile = <String, dynamic>{
        ...tDoc.data()!,
        'id': tDoc.data()!['id'] ?? tDoc.id,
      };
    } else {
      final tQuery = await _db
          .collection('school_teachers')
          .where('id', isEqualTo: teacherId)
          .limit(1)
          .get();
      if (tQuery.docs.isNotEmpty) {
        profile = <String, dynamic>{
          ...tQuery.docs.first.data(),
          'id': tQuery.docs.first.data()['id'] ?? tQuery.docs.first.id,
        };
      }
    }

    if (profile == null ||
        profile['is_active'] != true ||
        '${profile['school_ref']}' != '${school['id']}') {
      throw const PostgrestException(
        message: 'This user account is inactive or not yet configured. Contact the Admin.',
      );
    }

    final loginEmail = '${profile['login_email'] ?? ''}'.trim();
    if (loginEmail.isEmpty) {
      throw const PostgrestException(
        message: 'This user account is inactive or not yet configured. Contact the Admin.',
      );
    }

    try {
      await _client.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
    } catch (_) {
      throw const AuthException(
        'Incorrect password. Check the selected user and try again.',
      );
    }

    final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (fbUser != null && '${profile['auth_user_id'] ?? ''}' != fbUser.uid) {
      await _db.collection('school_teachers').doc('${profile['id']}').update(
        <String, dynamic>{'auth_user_id': fbUser.uid},
      );
    }
    final idToken =
        (await fbUser?.getIdToken()) ?? 'firebase_session_${fbUser?.uid ?? ''}';

    final isBlocked = school['is_blocked'] == true;
    return <String, dynamic>{
      'access_token': idToken,
      'refresh_token': idToken,
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': <String, dynamic>{'id': fbUser?.uid ?? ''},
      'profile': <String, dynamic>{
        'teacher_id': '${profile['id']}',
        'teacher_name': '${profile['teacher_name'] ?? ''}',
        'role': '${profile['role'] ?? 'teacher'}',
        'allowed_classes': profile['allowed_classes'] ?? const <String>[],
        'school_ref': '${school['id']}',
        'school_id': '${school['school_id']}',
        'school_name': '${school['school_name']}',
        'school_name_en':
            '${school['school_name_en'] ?? school['school_name'] ?? ''}',
        'school_name_gu': '${school['school_name_gu'] ?? ''}',
        'school_address_en': '${school['school_address_en'] ?? ''}',
        'school_address_gu': '${school['school_address_gu'] ?? ''}',
        'school_type': '${school['school_type'] ?? 'mixed'}',
        'validity_date': school['validity_date'],
        'is_blocked': isBlocked,
        'block_reason': '${school['block_reason'] ?? ''}',
        'disabled_modules': school['disabled_modules'] is Iterable
            ? (school['disabled_modules'] as Iterable)
                  .map((e) => '$e'.trim().toLowerCase())
                  .where((v) => v.isNotEmpty)
                  .toList()
            : const <String>[],
        'can_edit': !isBlocked,
        'can_download_reports': true,
      },
    };
  }

  Future<Map<String, dynamic>> _handleAttendanceAdminOverride(
    Map<String, dynamic> body,
  ) async {
    final action = '${body['action'] ?? 'authorize'}'.trim();
    final attendanceDate = '${body['attendanceDate'] ?? ''}'.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(attendanceDate)) {
      throw const PostgrestException(
        message: 'A valid attendance date is required.',
      );
    }
    if (attendanceDate.compareTo(SupabaseClient._indiaTodayIso()) > 0) {
      throw const PostgrestException(
        message: 'Future-date attendance is not allowed.',
      );
    }

    final ctx = await _client._resolveCurrentTeacherContext(forceRefresh: true);
    if (ctx == null || !ctx.isAdmin) {
      throw const PostgrestException(
        message: 'Only the School Admin can authorize this attendance change.',
      );
    }
    await _client._requireSchoolWriteAccess();

    final docId = '${ctx.schoolRef}__${ctx.authUserId}__$attendanceDate';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    if (action == 'check') {
      final snap = await _db
          .collection('attendance_admin_overrides')
          .doc(docId)
          .get();
      if (snap.exists && snap.data() != null) {
        final until = '${snap.data()!['authorized_until'] ?? ''}';
        if (until.compareTo(nowIso) > 0) {
          return <String, dynamic>{
            'authorized': true,
            'attendanceDate': attendanceDate,
            'authorizedUntil': until,
          };
        }
      }
      return <String, dynamic>{
        'authorized': false,
        'attendanceDate': attendanceDate,
        'authorizedUntil': null,
      };
    }

    final password = '${body['password'] ?? ''}';
    if (password.isEmpty) {
      throw const PostgrestException(
        message: 'Admin login password is required.',
      );
    }
    final email = _client.auth.currentUser?.email ?? '';
    if (email.isEmpty) {
      throw const PostgrestException(
        message: 'Admin login identity could not be verified.',
      );
    }

    try {
      final helperAuth = await _getHelperAuth();
      await helperAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await helperAuth.signOut();
    } catch (_) {
      throw const AuthException('Admin password is incorrect.');
    }

    final authorizedUntil = SupabaseClient._indiaDayEndIso();
    await _db.collection('attendance_admin_overrides').doc(docId).set(
      <String, dynamic>{
        'id': docId,
        'school_ref': ctx.schoolRef,
        'authorized_by': ctx.authUserId,
        'attendance_date': attendanceDate,
        'authorized_at': nowIso,
        'authorized_until': authorizedUntil,
      },
    );

    return <String, dynamic>{
      'authorized': true,
      'attendanceDate': attendanceDate,
      'authorizedUntil': authorizedUntil,
    };
  }

  static String _normalizeMobile(dynamic value, {bool required = true}) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty && !required) return '';
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 10) {
      digits = '91$digits';
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = '91${digits.substring(1)}';
    }
    if (!RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
      throw const PostgrestException(
        message: 'Enter a valid Indian mobile number with 10 digits.',
      );
    }
    return '+$digits';
  }

  static String _internalLoginEmail() {
    final uuid = SupabaseClient._generateUuid().replaceAll('-', '');
    return 'u$uuid@psm-login.invalid';
  }

  static String _normDiseDigits(String input) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var out = input.trim();
    for (var i = 0; i < guj.length; i++) {
      out = out.replaceAll(guj[i], '$i');
    }
    return out;
  }

  Future<void> _ensureDeveloperAuthSession(String devKey) async {
    final fbAuth = fb_auth.FirebaseAuth.instance;
    if (fbAuth.currentUser != null) return;
    const devEmail = 'dev_console_service@psm-login.invalid';
    final devPassword = SupabaseClient._toFirebasePassword('dev_$devKey');
    try {
      await fbAuth.signInWithEmailAndPassword(
        email: devEmail,
        password: devPassword,
      );
      return;
    } catch (_) {
      try {
        await fbAuth.createUserWithEmailAndPassword(
          email: devEmail,
          password: devPassword,
        );
        return;
      } catch (_) {
        // Fallback: if dev_console_service@psm-login.invalid already exists with an
        // older developer key password, sign in or create a dedicated per-key dev session
        // so FirebaseAuth.instance.currentUser is never null during school delete/edit.
        final altKeySlug = devKey.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        final altEmail = 'dev_service_${altKeySlug.isEmpty ? "admin" : altKeySlug}@psm-login.invalid';
        try {
          await fbAuth.signInWithEmailAndPassword(
            email: altEmail,
            password: devPassword,
          );
          return;
        } catch (_) {
          try {
            await fbAuth.createUserWithEmailAndPassword(
              email: altEmail,
              password: devPassword,
            );
            return;
          } catch (_) {
            try {
              await fbAuth.signInAnonymously();
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<List<fs.QueryDocumentSnapshot<Map<String, dynamic>>>> _safeGetCollectionDocs(
    String collectionName,
  ) async {
    try {
      final snap = await _db.collection(collectionName).get();
      return snap.docs;
    } catch (_) {
      return const <fs.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  /// Every collection whose documents carry `school_ref`. A permanent school
  /// delete removes all of them, so nothing is left behind in Firestore.
  static const List<String> _schoolOwnedCollections = <String>[
    'school_teachers', 'school_classes', 'students', 'student_private_details',
    'attendance_days', 'student_attendance', 'attendance_admin_overrides',
    'school_settings', 'school_holidays', 'school_admin_messages', 'school_custom_headers',
    'school_report_settings', 'school_hajari_patrak_settings', 'hajari_student_present_day_overrides',
    'school_subject_master', 'school_subject_catalog', 'class_subjects', 'teacher_subject_assignments',
    'class_result_settings', 'school_result_grade_settings', 'student_result_profiles',
    'student_subject_marks', 'student_result_roster_snapshots', 'student_result_roster_members',
    'teacher_leaves', 'teacher_leave_report_snapshots', 'school_leave_settings',
    'school_teacher_valtar_rules', 'library_books', 'library_book_number_history', 'library_settings',
    'library_transactions', 'school_assets', 'school_shared_files', 'school_rojmel_state',
    'developer_message_dismissals', 'school_validity_reminder_dismissals',
  ];

  /// Collections whose documents have a `chunks` subcollection (large data
  /// split into pieces) that must be deleted with them.
  static const Set<String> _chunkedCollections = <String>{'school_rojmel_state', 'school_shared_files'};

  Future<int> _deleteDocWithChunks(fs.DocumentReference<Map<String, dynamic>> ref) async {
    var count = 0;
    while (true) {
      final chunks = await ref.collection('chunks').limit(300).get();
      if (chunks.docs.isEmpty) break;
      final batch = _db.batch();
      for (final c in chunks.docs) {
        batch.delete(c.reference);
      }
      await batch.commit();
      count += chunks.docs.length;
    }
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      count++;
    }
    return count;
  }

  Future<int> _deleteAllSchoolData(String schoolRef, String diseNo) async {
    if (schoolRef.trim().isEmpty) return 0;
    var total = 0;

    // Also delete student_result_roster_members belonging to snapshots of this school
    try {
      final snapQuery = await _db
          .collection('student_result_roster_snapshots')
          .where('school_ref', isEqualTo: schoolRef)
          .get();
      for (final sDoc in snapQuery.docs) {
        try {
          final memSnap = await _db
              .collection('student_result_roster_members')
              .where('snapshot_id', isEqualTo: sDoc.id)
              .get();
          if (memSnap.docs.isNotEmpty) {
            final b = _db.batch();
            for (final m in memSnap.docs) {
              b.delete(m.reference);
            }
            await b.commit();
            total += memSnap.docs.length;
          }
        } catch (_) {}
      }
    } catch (_) {}

    for (final name in _schoolOwnedCollections) {
      final col = _db.collection(name);
      while (true) {
        fs.QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await col.where('school_ref', isEqualTo: schoolRef).limit(300).get();
        } catch (_) {
          break; // collection not readable / not used: skip it
        }
        if (snap.docs.isEmpty) break;
        try {
          if (_chunkedCollections.contains(name)) {
            for (final d in snap.docs) {
              total += await _deleteDocWithChunks(d.reference);
            }
          } else {
            final batch = _db.batch();
            for (final d in snap.docs) {
              batch.delete(d.reference);
            }
            await batch.commit();
            total += snap.docs.length;
          }
        } catch (_) {
          // Fallback to per-document delete; if blocked by rules, break out of while loop
          var anyDeleted = false;
          for (final d in snap.docs) {
            try {
              await d.reference.delete();
              total++;
              anyDeleted = true;
            } catch (_) {}
          }
          if (!anyDeleted) break;
        }
        if (snap.docs.length < 300) break;
      }
    }
    // Documents keyed by the school id itself.
    for (final name in _chunkedCollections) {
      try {
        total += await _deleteDocWithChunks(_db.collection(name).doc(schoolRef));
      } catch (_) {}
    }
    for (final name in const ['school_settings', 'library_settings', 'school_leave_settings', 'school_hajari_patrak_settings', 'school_report_settings']) {
      try {
        final ref = _db.collection(name).doc(schoolRef);
        if ((await ref.get()).exists) {
          await ref.delete();
          total++;
        }
      } catch (_) {}
    }
    // Delete any subcollections under schools/{schoolRef} if present
    for (final subName in const ['settings', 'classes', 'students', 'teachers', 'attendance']) {
      try {
        final subSnap = await _db.collection('schools').doc(schoolRef).collection(subName).limit(300).get();
        for (final d in subSnap.docs) {
          try {
            await d.reference.delete();
            total++;
          } catch (_) {}
        }
      } catch (_) {}
    }
    // Registration request for this DISE number, so the school can register afresh.
    final dise = diseNo.trim();
    if (dise.isNotEmpty) {
      try {
        final req = _db.collection('school_registration_requests').doc(dise);
        if ((await req.get()).exists) {
          await req.delete();
          total++;
        }
        final more = await _db.collection('school_registration_requests').where('dise_number', isEqualTo: dise).get();
        for (final d in more.docs) {
          await d.reference.delete();
          total++;
        }
      } catch (_) {}
    }
    // Always delete the school record itself.
    await _db.collection('schools').doc(schoolRef).delete();
    return total + 1;
  }

  Future<void> _verifyDeveloperKey(String providedKey) async {
    final clean = providedKey.trim();
    if (clean.length < 4) {
      throw const AuthException('Developer key is invalid.');
    }
    final cfgRef = _db.collection('platform_config').doc('developer');
    final snap = await cfgRef.get();
    if (!snap.exists || snap.data() == null) {
      // First-time bootstrap: persist the developer key in Firestore
      await cfgRef.set(<String, dynamic>{
        'developer_key': clean,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _ensureDeveloperAuthSession(clean);
      return;
    }
    final expected = '${snap.data()!['developer_key'] ?? ''}'.trim();
    if (expected.isNotEmpty && expected != clean) {
      throw const AuthException('Developer key is invalid.');
    }
    await _ensureDeveloperAuthSession(expected.isNotEmpty ? expected : clean);
  }

  Future<void> _seedDefaultSubjectsAndGrades(String schoolRef) async {
    const defaultSubjects = <String>[
      'ગુજરાતી',
      'હિન્દી',
      'પર્યાવરણ',
      'ગણિત',
      'અંગ્રેજી',
      'વિજ્ઞાન',
      'સામાજિક વિજ્ઞાન',
      'સંસ્કૃત',
      'શ્રીમદ્ ભગવદ્ ગીતા',
      'કોમ્પ્યુટર',
      'લાયબ્રેરી',
      'રમત',
      'સંગીત',
      'કાર્યાનુભવ',
      'ચિત્ર',
      'FLN',
      'શા. શિ.',
    ];
    const defaultGrades = <Map<String, dynamic>>[
      {'label': 'A', 'min': 80, 'order': 0},
      {'label': 'B', 'min': 65, 'order': 1},
      {'label': 'C', 'min': 50, 'order': 2},
      {'label': 'D', 'min': 35, 'order': 3},
      {'label': 'E', 'min': 0, 'order': 4},
    ];
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final batch = _db.batch();
    for (var i = 0; i < defaultSubjects.length; i++) {
      final name = defaultSubjects[i];
      final id = '${schoolRef}__${FirestoreQueryBuilder._slug(name)}';
      batch.set(
        _db.collection('school_subject_master').doc(id),
        <String, dynamic>{
          'id': id,
          'school_ref': schoolRef,
          'subject_name': name,
          'sort_order': i,
          'is_active': true,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
    }
    for (final g in defaultGrades) {
      final label = '${g['label']}';
      final id = '${schoolRef}__${FirestoreQueryBuilder._slug(label)}';
      batch.set(
        _db.collection('school_result_grade_settings').doc(id),
        <String, dynamic>{
          'id': id,
          'school_ref': schoolRef,
          'grade_label': label,
          'minimum_percent': g['min'],
          'sort_order': g['order'],
          'is_active': true,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        fs.SetOptions(merge: true),
      );
    }
    batch.set(
      _db.collection('school_leave_settings').doc(schoolRef),
      <String, dynamic>{
        'id': schoolRef,
        'school_ref': schoolRef,
        'cl_max_days': 12,
        'cl_year_start_month': 6,
        'cl_year_end_month': 5,
        'cl_allowed_start_month': 1,
        'cl_allowed_end_month': 12,
        'marajiyat_max_days': 2,
        'marajiyat_year_start_month': 1,
        'marajiyat_year_end_month': 12,
        'marajiyat_allowed_start_month': 1,
        'marajiyat_allowed_end_month': 12,
        'valtar_max_days': 0,
        'valtar_start_month': 1,
        'valtar_end_month': 12,
        'updated_at': nowIso,
      },
      fs.SetOptions(merge: true),
    );
    await batch.commit();
  }

  static const String _kRegistrationRequests = 'school_registration_requests';
  static const List<String> _kRegistrationEditableFields = <String>[
    'school_name_en', 'school_name_gu', 'school_address_en', 'school_address_gu',
    'dise_number', 'admin_name', 'admin_mobile', 'admin_password', 'school_type', 'note',
  ];

  /// Saves a pending new-school request (document id = DISE number, so one
  /// school cannot send two requests). Checked again by Firestore rules.
  Future<Map<String, dynamic>> _submitSchoolRegistrationRequest(Map<String, dynamic> body) async {
    String t(String k, [int max = 200]) {
      final v = '${body[k] ?? ''}'.trim();
      return v.length > max ? v.substring(0, max) : v;
    }

    final dise = t('dise_number', 20).replaceAll(RegExp(r'\s+'), '');
    final nameEn = t('school_name_en');
    final adminName = t('admin_name', 100);
    final password = '${body['admin_password'] ?? ''}';
    if (nameEn.length < 2) {
      throw const PostgrestException(message: 'શાળાનું નામ (English) લખો.');
    }
    if (!RegExp(r'^\d{4,20}$').hasMatch(dise)) {
      throw const PostgrestException(message: 'સાચો DISE / UDISE નંબર લખો (માત્ર અંક, 4 થી 20).');
    }
    if (adminName.length < 2) {
      throw const PostgrestException(message: 'Admin (આચાર્ય) નું નામ લખો.');
    }
    final mobile = _normalizeMobile(body['admin_mobile'], required: true);
    if (password.length < 4 || password.length > 15) {
      throw const PostgrestException(message: 'Admin પાસવર્ડ 4 થી 15 અક્ષરનો રાખો.');
    }
    final existing = await _db.collection('schools').doc(dise).get();
    if (existing.exists) {
      throw const PostgrestException(
          message: 'આ DISE નંબરની શાળા પહેલેથી નોંધાયેલ છે. School Login થી પ્રવેશ કરો.');
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _db.collection(_kRegistrationRequests).doc(dise).set(<String, dynamic>{
        'school_name_en': nameEn,
        'school_name_gu': t('school_name_gu'),
        'school_address_en': t('school_address_en', 400),
        'school_address_gu': t('school_address_gu', 400),
        'dise_number': dise,
        'admin_name': adminName,
        'admin_mobile': mobile,
        'admin_password': password,
        'school_type': SchoolType.canonical(body['school_type']),
        'note': t('note', 500),
        'status': 'pending',
        'source': 'login_screen',
        'created_at': nowIso,
      });
    } on fs.FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const PostgrestException(
            message: 'આ DISE નંબરની નોંધણી વિનંતી પહેલેથી મોકલેલ છે. Developer મંજૂરી આપે ત્યાં સુધી રાહ જુઓ.');
      }
      rethrow;
    }
    return <String, dynamic>{'ok': true, 'requestId': dise};
  }

  Future<Map<String, dynamic>> _developerCreateSchool(
    Map<String, dynamic> body,
  ) async {
    final schoolNameEn = '${body['schoolNameEn'] ?? body['schoolName'] ?? ''}'
        .trim();
    final schoolNameGu = '${body['schoolNameGu'] ?? ''}'.trim().isNotEmpty
        ? '${body['schoolNameGu']}'.trim()
        : schoolNameEn;
    final schoolAddressEn = '${body['schoolAddressEn'] ?? ''}'.trim();
    final schoolAddressGu = '${body['schoolAddressGu'] ?? ''}'.trim();
    final schoolName = schoolNameEn.isNotEmpty ? schoolNameEn : schoolNameGu;
    final schoolId = '${body['diseNumber'] ?? ''}'.replaceAll(
      RegExp(r'\s+'),
      '',
    );
    final adminName = '${body['adminName'] ?? ''}'.trim();
    final adminMobile = _normalizeMobile(body['adminMobile'], required: true);
    final password = '${body['adminPassword'] ?? ''}';
    final schoolType = SchoolType.canonical(body['schoolType']);
    final validityDate = '${body['validityDate'] ?? ''}'.trim();

    if (schoolNameEn.length < 2) {
      throw const PostgrestException(
        message: 'Enter the school name in English.',
      );
    }
    if (!RegExp(r'^\d{4,20}$').hasMatch(schoolId)) {
      throw const PostgrestException(
        message: 'Enter a numeric DISE/UDISE number (4–20 digits). Leading zeros are preserved.',
      );
    }
    if (adminName.length < 2) {
      throw const PostgrestException(message: 'Enter the Admin name.');
    }
    if (password.length < 4 || password.length > 15) {
      throw const PostgrestException(
        message: 'Admin password must contain 4 to 15 characters.',
      );
    }

    final dup = await _db
        .collection('schools')
        .where('school_id', isEqualTo: schoolId)
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw const PostgrestException(
        message: 'This DISE/UDISE number already exists.',
      );
    }

    final loginEmail = _internalLoginEmail();
    final helperAuth = await _getHelperAuth();
    fb_auth.UserCredential cred;
    try {
      cred = await helperAuth.createUserWithEmailAndPassword(
        email: loginEmail,
        password: SupabaseClient._toFirebasePassword(password),
      );
      await helperAuth.signOut();
    } catch (e) {
      throw PostgrestException(
        message: 'Could not create Admin Auth account: $e',
      );
    }

    final authUid = cred.user!.uid;
    final schoolUuid = SupabaseClient._generateUuid();
    final adminUuid = SupabaseClient._generateUuid();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final schoolRow = <String, dynamic>{
      'id': schoolUuid,
      'school_id': schoolId,
      'school_name': schoolName,
      'school_name_en': schoolNameEn,
      'school_name_gu': schoolNameGu,
      'school_address_en': schoolAddressEn,
      'school_address_gu': schoolAddressGu,
      'admin_name': adminName,
      'principal_name': adminName,
      'school_type': schoolType,
      'validity_date': validityDate,
      'is_active': true,
      'is_blocked': false,
      'block_reason': '',
      'report_gender_split_enabled': true,
      'created_at': nowIso,
      'updated_at': nowIso,
    };

    final adminRow = <String, dynamic>{
      'id': adminUuid,
      'school_ref': schoolUuid,
      'auth_user_id': authUid,
      'teacher_name': adminName,
      'mobile': adminMobile,
      'role': 'admin',
      'allowed_classes': <String>[],
      'is_active': true,
      'login_email': loginEmail,
      'created_at': nowIso,
      'updated_at': nowIso,
    };

    await _db.collection('schools').doc(schoolUuid).set(schoolRow);
    await _db.collection('school_teachers').doc(adminUuid).set(adminRow);
    await _seedDefaultSubjectsAndGrades(schoolUuid);

    return <String, dynamic>{
      'school': schoolRow,
      'admin': adminRow,
      'message': 'School and Admin account created.',
    };
  }

  Future<void> _syncTeacherResultAssignments({
    required String schoolRef,
    required String teacherId,
    required List<Map<String, dynamic>> assignments,
  }) async {
    final existingSnap = await _db
        .collection('teacher_subject_assignments')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var batch = _db.batch();
    var ops = 0;

    for (final doc in existingSnap.docs) {
      final d = doc.data();
      if ('${d['teacher_id'] ?? ''}'.trim() == teacherId) {
        batch.delete(doc.reference);
        ops++;
      }
    }

    final classesSnap = await _db
        .collection('school_classes')
        .where('school_ref', isEqualTo: schoolRef)
        .get();
    final classes = classesSnap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
    final classById = <String, Map<String, dynamic>>{};
    for (final c in classes) {
      final id = '${c['id'] ?? ''}'.trim();
      final key = '${c['class_key'] ?? ''}'.trim().toLowerCase();
      final label = '${c['label'] ?? ''}'.trim().toLowerCase();
      if (id.isNotEmpty) classById[id] = c;
      if (key.isNotEmpty) classById.putIfAbsent(key, () => c);
      if (label.isNotEmpty) classById.putIfAbsent(label, () => c);
    }
    for (final c in classes) {
      if ('${c['class_teacher_id'] ?? ''}' == teacherId) {
        batch.update(
          _db.collection('school_classes').doc('${c['id']}'),
          <String, dynamic>{'class_teacher_id': null, 'updated_at': nowIso},
        );
        ops++;
      }
    }

    for (final a in assignments) {
      final rawCid = '${a['classId'] ?? a['class_id'] ?? a['classKey'] ?? a['class_key'] ?? ''}'.trim();
      final cls = classById[rawCid] ?? classById[rawCid.toLowerCase()];
      if (cls == null) continue;
      final cid = '${cls['id']}'.trim();
      if (cid.isEmpty) continue;
      final isClassTeacher =
          a['isClassTeacher'] == true ||
          '${a['isClassTeacher']}'.toLowerCase() == 'true';
      if (isClassTeacher) {
        batch.update(
          _db.collection('school_classes').doc(cid),
          <String, dynamic>{
            'class_teacher_id': teacherId,
            'updated_at': nowIso,
          },
        );
        ops++;
      }

      final rawSubjects = a['subjectNames'] ?? a['subjects'];
      final subjectNames = rawSubjects is List
          ? rawSubjects
                .map((e) => '$e'.trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : (rawSubjects is String
                ? rawSubjects
                      .split(RegExp(r'[;,|]'))
                      .map((e) => e.trim())
                      .where((s) => s.isNotEmpty)
                      .toList()
                : <String>[]);
      final rawMaxMap = a['subjectMaxPeriods'] ?? a['subject_max_periods'];
      final maxPeriodsBySubject = <String, int>{};
      if (rawMaxMap is Map) {
        rawMaxMap.forEach((k, v) {
          final parsed = v is num ? v.toInt() : int.tryParse('$v');
          if (parsed != null && parsed > 0) {
            maxPeriodsBySubject['$k'.trim()] = parsed;
            maxPeriodsBySubject['$k'.trim().toLowerCase()] = parsed;
          }
        });
      }
      final standard = '${cls['standard'] ?? ''}'.trim();

      for (var i = 0; i < subjectNames.length; i++) {
        var sName = subjectNames[i];
        if (sName.toLowerCase() == 'fln') sName = 'FLN';
        if (sName == 'શા.શિ.' || sName == 'શા. શિ' || sName == 'શા.શિ') {
          sName = 'શા. શિ.';
        }
        if (sName == 'વ્યક્તિત્વ વિકાસ') continue;
        final slugSub = FirestoreQueryBuilder._slug(sName);
        final maxPeriodsVal = maxPeriodsBySubject[sName] ??
            maxPeriodsBySubject[sName.toLowerCase()];

        if (standard.isNotEmpty) {
          final catId =
              '${schoolRef}__${FirestoreQueryBuilder._slug(standard)}__$slugSub';
          batch.set(
            _db.collection('school_subject_catalog').doc(catId),
            <String, dynamic>{
              'id': catId,
              'school_ref': schoolRef,
              'standard': standard,
              'subject_name': sName,
              'sort_order': i,
              'is_active': true,
              'updated_at': nowIso,
            },
            fs.SetOptions(merge: true),
          );
          ops++;
        }

        final csId = '${schoolRef}__${cid}__$slugSub';
        batch.set(_db.collection('class_subjects').doc(csId), <String, dynamic>{
          'id': csId,
          'school_ref': schoolRef,
          'class_id': cid,
          'subject_name': sName,
          'sort_order': i,
          'is_active': true,
          'updated_at': nowIso,
        }, fs.SetOptions(merge: true));
        ops++;

        final masterId = '${schoolRef}__$slugSub';
        batch.set(
          _db.collection('school_subject_master').doc(masterId),
          <String, dynamic>{
            'id': masterId,
            'school_ref': schoolRef,
            'subject_name': sName,
            'sort_order': i,
            'is_active': true,
            'updated_at': nowIso,
          },
          fs.SetOptions(merge: true),
        );
        ops++;

        final tsaId = '${schoolRef}__${teacherId}__${cid}__$slugSub';
        batch.set(
          _db.collection('teacher_subject_assignments').doc(tsaId),
          <String, dynamic>{
            'id': tsaId,
            'school_ref': schoolRef,
            'teacher_id': teacherId,
            'class_id': cid,
            'subject_name': sName,
            if (maxPeriodsVal != null && maxPeriodsVal > 0)
              'max_periods': maxPeriodsVal,
            'created_at': nowIso,
            'updated_at': nowIso,
          },
          fs.SetOptions(merge: true),
        );
        ops++;

        if (ops >= 380) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
    }
    if (ops > 0) await batch.commit();
    FirestoreQueryBuilder.invalidateCache('teacher_subject_assignments');
    FirestoreQueryBuilder.invalidateCache('school_classes');
    FirestoreQueryBuilder.invalidateCache('school_teachers');
    FirestoreQueryBuilder.invalidateCache('class_subjects');
    FirestoreQueryBuilder.invalidateCache('school_subject_master');
    FirestoreQueryBuilder.invalidateCache('school_subject_catalog');
  }

  Future<Map<String, dynamic>> _handlePlatformAdmin(
    Map<String, dynamic> body,
  ) async {
    final action = '${body['action'] ?? ''}'.trim();
    if (action.isEmpty) {
      throw const PostgrestException(message: 'Missing action.');
    }

    // New-school registration request from the login screen (no login yet).
    // It only creates a pending request; the developer reviews and approves.
    if (action == 'public.submit_school_registration') {
      return _submitSchoolRegistrationRequest(body);
    }

    // Developer actions
    if (action.startsWith('developer.')) {
      await _verifyDeveloperKey('${body['developerKey'] ?? ''}');
      final today = SupabaseClient._indiaTodayIso();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      switch (action) {
        case 'developer.list_registration_requests':
          {
            final snap = await _db.collection(_kRegistrationRequests).get();
            final rows = snap.docs
                .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
                .where((r) => body['includeClosed'] == true || '${r['status'] ?? 'pending'}' == 'pending')
                .toList()
              ..sort((a, b) => '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
            return <String, dynamic>{'requests': rows};
          }

        case 'developer.update_registration_request':
          {
            final id = '${body['requestId'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(message: 'Request id is required.');
            }
            final patch = <String, dynamic>{'updated_at': nowIso};
            for (final k in _kRegistrationEditableFields) {
              if (body[k] != null) patch[k] = '${body[k]}'.trim();
            }
            await _db.collection(_kRegistrationRequests).doc(id).set(patch, fs.SetOptions(merge: true));
            return <String, dynamic>{'ok': true};
          }

        case 'developer.approve_registration_request':
          {
            final id = '${body['requestId'] ?? ''}'.trim();
            final ref = _db.collection(_kRegistrationRequests).doc(id);
            final snap = await ref.get();
            final r = snap.data();
            if (id.isEmpty || r == null) {
              throw const PostgrestException(message: 'Registration request not found.');
            }
            if ('${r['status'] ?? 'pending'}' != 'pending') {
              throw const PostgrestException(message: 'This request is already closed.');
            }
            // Same path as the developer's own registration form.
            final created = await _developerCreateSchool(<String, dynamic>{
              'schoolNameEn': r['school_name_en'],
              'schoolNameGu': r['school_name_gu'],
              'schoolAddressEn': r['school_address_en'],
              'schoolAddressGu': r['school_address_gu'],
              'diseNumber': r['dise_number'],
              'adminName': r['admin_name'],
              'adminMobile': r['admin_mobile'],
              'adminPassword': r['admin_password'],
              'schoolType': r['school_type'],
              'validityDate': '${body['validityDate'] ?? ''}'.trim(),
            });
            await ref.set(<String, dynamic>{
              'status': 'approved',
              'admin_password': '',
              'approved_at': nowIso,
              'validity_date': '${body['validityDate'] ?? ''}'.trim(),
              'updated_at': nowIso,
            }, fs.SetOptions(merge: true));
            return created;
          }

        case 'developer.reject_registration_request':
          {
            final id = '${body['requestId'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(message: 'Request id is required.');
            }
            await _db.collection(_kRegistrationRequests).doc(id).set(<String, dynamic>{
              'status': 'rejected',
              'admin_password': '',
              'reject_reason': '${body['reason'] ?? ''}'.trim(),
              'updated_at': nowIso,
            }, fs.SetOptions(merge: true));
            return <String, dynamic>{'ok': true};
          }

        case 'developer.list_schools':
          {
            final sSnap = await _db.collection('schools').get();
            final tSnap = await _db
                .collection('school_teachers')
                .where('role', isEqualTo: 'admin')
                .get();
            final adminBySchool = <String, Map<String, dynamic>>{};
            for (final d in tSnap.docs) {
              final row = d.data();
              final ref = '${row['school_ref'] ?? ''}';
              adminBySchool.putIfAbsent(ref, () => row);
            }
            final schools = sSnap.docs.map((d) {
              final s = <String, dynamic>{
                ...d.data(),
                'id': d.data()['id'] ?? d.id,
              };
              final adm = adminBySchool['${s['id']}'];
              final validity = '${s['validity_date'] ?? ''}'.trim();
              final expired =
                  validity.length >= 10 &&
                  validity.substring(0, 10).compareTo(today) < 0;
              bool prevUploadEnabled = s['prev_attendance_upload_enabled'] == true;
              final prevUploadExpStr =
                  '${s['prev_attendance_upload_expires_at'] ?? ''}'.trim();
              if (prevUploadEnabled) {
                final expDt = DateTime.tryParse(prevUploadExpStr)?.toUtc();
                if (expDt == null || DateTime.now().toUtc().isAfter(expDt)) {
                  prevUploadEnabled = false;
                  d.reference.set(<String, dynamic>{
                    'prev_attendance_upload_enabled': false,
                  }, fs.SetOptions(merge: true));
                }
              }
              final disabledModules = s['disabled_modules'] is Iterable
                  ? (s['disabled_modules'] as Iterable)
                        .map((e) => '$e'.trim().toLowerCase())
                        .where((v) => v.isNotEmpty)
                        .toList()
                  : const <String>[];
              return <String, dynamic>{
                ...s,
                'disabled_modules': disabledModules,
                'prev_attendance_upload_enabled': prevUploadEnabled,
                'admin_id': '${adm?['id'] ?? ''}',
                'admin_name': '${adm?['teacher_name'] ?? ''}',
                'admin_mobile': '${adm?['mobile'] ?? ''}',
                'admin_active': adm?['is_active'] == true,
                'expired': expired,
              };
            }).toList();
            schools.sort(
              (a, b) => '${a['school_name']}'.compareTo('${b['school_name']}'),
            );
            return <String, dynamic>{'schools': schools};
          }

        case 'developer.create_school':
          return _developerCreateSchool(body);

        case 'developer.bulk_create_schools':
          {
            final rows = body['rows'] is List
                ? (body['rows'] as List)
                      .whereType<Map>()
                      .map((m) => m.map((k, v) => MapEntry('$k', v)))
                      .toList()
                : <Map<String, dynamic>>[];
            final results = <Map<String, dynamic>>[];
            for (var i = 0; i < rows.length; i++) {
              final raw = rows[i];
              final rowNum =
                  int.tryParse('${raw['rowNumber'] ?? ''}') ?? (i + 2);
              final dise = '${raw['diseNumber'] ?? ''}'.trim();
              try {
                final created = await _developerCreateSchool(raw);
                final schoolMap = created['school'] as Map<String, dynamic>;
                results.add(<String, dynamic>{
                  'rowNumber': rowNum,
                  'diseNumber': dise,
                  'success': true,
                  'schoolName': schoolMap['school_name'],
                  'schoolRef': schoolMap['id'],
                });
              } catch (e) {
                results.add(<String, dynamic>{
                  'rowNumber': rowNum,
                  'diseNumber': dise,
                  'success': false,
                  'error': '$e'.replaceFirst('Exception: ', ''),
                });
              }
            }
            return <String, dynamic>{
              'results': results,
              'succeeded': results.where((r) => r['success'] == true).length,
              'failed': results.where((r) => r['success'] != true).length,
            };
          }

        case 'developer.update_school':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(
                message: 'School reference is required.',
              );
            }
            final patch = <String, dynamic>{'updated_at': nowIso};
            if (body['schoolNameEn'] != null) {
              patch['school_name_en'] = '${body['schoolNameEn']}'.trim();
              patch['school_name'] = '${body['schoolNameEn']}'.trim();
            } else if (body['schoolName'] != null) {
              patch['school_name'] = '${body['schoolName']}'.trim();
              patch['school_name_en'] = '${body['schoolName']}'.trim();
            }
            if (body['schoolNameGu'] != null) {
              patch['school_name_gu'] = '${body['schoolNameGu']}'.trim();
            }
            if (body['schoolAddressEn'] != null) {
              patch['school_address_en'] = '${body['schoolAddressEn']}'.trim();
            }
            if (body['schoolAddressGu'] != null) {
              patch['school_address_gu'] = '${body['schoolAddressGu']}'.trim();
            }
            if (body['schoolType'] != null) {
              patch['school_type'] = SchoolType.canonical(body['schoolType']);
            }
            if (body['validityDate'] != null) {
              patch['validity_date'] = '${body['validityDate']}'.trim();
            }
            await _db
                .collection('schools')
                .doc(id)
                .set(patch, fs.SetOptions(merge: true));

            if (body['adminName'] != null ||
                body['adminMobile'] != null ||
                (body['adminPassword'] != null &&
                    '${body['adminPassword']}'.isNotEmpty)) {
              final admSnap = await _db
                  .collection('school_teachers')
                  .where('school_ref', isEqualTo: id)
                  .get();
              for (final doc in admSnap.docs) {
                if ('${doc.data()['role']}'.toLowerCase() == 'admin') {
                  final admPatch = <String, dynamic>{'updated_at': nowIso};
                  if (body['adminName'] != null) {
                    admPatch['teacher_name'] = '${body['adminName']}'.trim();
                  }
                  if (body['adminMobile'] != null &&
                      '${body['adminMobile']}'.trim().isNotEmpty) {
                    admPatch['mobile'] = _normalizeMobile(
                      body['adminMobile'],
                      required: true,
                    );
                  }
                  if (body['adminPassword'] != null &&
                      '${body['adminPassword']}'.isNotEmpty) {
                    final newEmail = _internalLoginEmail();
                    final helperAuth = await _getHelperAuth();
                    final newAdminPwd = '${body['adminPassword']}';
                    if (newAdminPwd.length < 4 || newAdminPwd.length > 15) {
                      throw const PostgrestException(
                        message:
                            'Admin password must contain 4 to 15 characters.',
                      );
                    }
                    final cred = await helperAuth
                        .createUserWithEmailAndPassword(
                          email: newEmail,
                          password: SupabaseClient._toFirebasePassword(
                            newAdminPwd,
                          ),
                        );
                    await helperAuth.signOut();
                    admPatch['auth_user_id'] = cred.user!.uid;
                    admPatch['login_email'] = newEmail;
                  }
                  await doc.reference.set(admPatch, fs.SetOptions(merge: true));
                  break;
                }
              }
            }
            final updated = await _db.collection('schools').doc(id).get();
            return <String, dynamic>{'school': updated.data() ?? patch};
          }

        case 'developer.set_active':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final active =
                body['isActive'] == true ||
                '${body['isActive']}'.toLowerCase() == 'true';
            await _db.collection('schools').doc(id).update(<String, dynamic>{
              'is_active': active,
              'updated_at': nowIso,
            });
            final updated = await _db.collection('schools').doc(id).get();
            return <String, dynamic>{'school': updated.data()};
          }

        case 'developer.set_blocked':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final blocked =
                body['isBlocked'] == true ||
                '${body['isBlocked']}'.toLowerCase() == 'true';
            await _db.collection('schools').doc(id).update(<String, dynamic>{
              'is_blocked': blocked,
              'block_reason': blocked
                  ? '${body['blockReason'] ?? ''}'.trim()
                  : '',
              'updated_at': nowIso,
            });
            final updated = await _db.collection('schools').doc(id).get();
            return <String, dynamic>{'school': updated.data()};
          }

        case 'developer.delete_school':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final confirm = _normDiseDigits('${body['confirmSchoolId'] ?? ''}');
            final sDoc = await _db.collection('schools').doc(id).get();
            if (!sDoc.exists) {
              throw const PostgrestException(
                message: 'School record not found.',
              );
            }
            final sData = sDoc.data()!;
            final storedDise = _normDiseDigits(
              '${sData['school_id'] ?? sData['udise_code'] ?? sData['dise_code'] ?? ''}',
            );
            final matchesDise = storedDise.isNotEmpty
                ? (confirm == storedDise || confirm.toUpperCase() == 'DELETE')
                : (confirm.isNotEmpty);
            if (!matchesDise) {
              throw PostgrestException(
                message: 'Confirmation DISE number ($confirm) does not match this school ($storedDise).',
              );
            }
            final deleted = await _deleteAllSchoolData(id, storedDise.isNotEmpty ? storedDise : confirm);
            return <String, dynamic>{
              'ok': true,
              'deleted_school_id': sData['school_id'],
              'deleted_school_name': sData['school_name'],
              'deleted_documents': deleted,
            };
          }

        case 'developer.get_library_books_backup_data':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(message: 'School reference is required.');
            }
            final bSnap = await _db
                .collection('library_books')
                .where('school_ref', isEqualTo: id)
                .get();
            final books = bSnap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] ??= d.id;
              return m;
            }).toList();
            books.sort((a, b) => (int.tryParse('${a['book_number'] ?? 0}') ?? 0).compareTo(int.tryParse('${b['book_number'] ?? 0}') ?? 0));

            final txSnap = await _db
                .collection('library_transactions')
                .where('school_ref', isEqualTo: id)
                .get();
            final transactions = txSnap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] ??= d.id;
              return m;
            }).toList();

            final stSnap = await _db
                .collection('students')
                .where('school_ref', isEqualTo: id)
                .get();
            final students = stSnap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] ??= d.id;
              return m;
            }).toList();

            return <String, dynamic>{
              'ok': true,
              'books': books,
              'transactions': transactions,
              'students': students,
            };
          }

        case 'developer.get_attendance_backup_data':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final fromDateFilter = '${body['fromDate'] ?? ''}'.trim();
            final toDateFilter = '${body['toDate'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(message: 'School reference is required.');
            }
            final sDoc = await _db.collection('schools').doc(id).get();
            final sData = sDoc.data() ?? <String, dynamic>{};
            final schoolType = '${sData['school_type'] ?? 'mixed'}';
            final cSnap = await _db
                .collection('school_classes')
                .where('school_ref', isEqualTo: id)
                .get();
            final classRows = <Map<String, dynamic>>[];
            final classById = <String, Map<String, dynamic>>{};
            for (final d in cSnap.docs) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] ??= d.id;
              m['school_type'] ??= schoolType;
              if (m['is_active'] == false) continue;
              classRows.add(m);
              classById['${m['id']}'] = m;
            }
            final aSnap = await _db
                .collection('attendance_days')
                .where('school_ref', isEqualTo: id)
                .get();
            final attendanceRows = <Map<String, dynamic>>[];
            for (final d in aSnap.docs) {
              final m = Map<String, dynamic>.from(d.data());
              m['id'] ??= d.id;
              final dt = '${m['attendance_date'] ?? ''}'.trim();
              final dShort = dt.length >= 10 ? dt.substring(0, 10) : dt;
              if (fromDateFilter.length >= 10 &&
                  dShort.isNotEmpty &&
                  dShort.compareTo(fromDateFilter) < 0) {
                continue;
              }
              if (toDateFilter.length >= 10 &&
                  dShort.isNotEmpty &&
                  dShort.compareTo(toDateFilter) > 0) {
                continue;
              }
              final cid = '${m['class_id'] ?? ''}';
              final cRow = classById[cid] ?? const <String, dynamic>{};
              m['class_key'] ??= cRow['class_key'] ?? '';
              m['class_label'] ??= cRow['label'] ?? cRow['class_key'] ?? '';
              m['label'] ??= cRow['label'] ?? cRow['class_key'] ?? '';
              m['sheet_name'] ??= cRow['sheet_name'] ?? cRow['label'] ?? '';
              m['standard'] ??= cRow['standard'] ?? '';
              m['section'] ??= cRow['section'] ?? '';
              m['report_group'] ??= cRow['report_group'] ?? '';
              m['sort_order'] ??= cRow['sort_order'] ?? 0;
              m['school_type'] ??= schoolType;
              attendanceRows.add(m);
            }
            return <String, dynamic>{
              'ok': true,
              'school_name': sData['school_name_gu'] ?? sData['school_name_en'] ?? sData['school_name'] ?? 'School',
              'school_id': sData['school_id'] ?? '',
              'school_type': schoolType,
              'classes': classRows,
              'attendance_rows': attendanceRows,
            };
          }

        case 'developer.delete_all_attendance_records':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final confirm = '${body['confirmSchoolId'] ?? ''}'.trim();
            final fromDateFilter = '${body['fromDate'] ?? ''}'.trim();
            final toDateFilter = '${body['toDate'] ?? ''}'.trim();
            final isRange = fromDateFilter.length >= 10 && toDateFilter.length >= 10;
            final sDoc = await _db.collection('schools').doc(id).get();
            if (!sDoc.exists ||
                '${sDoc.data()?['school_id'] ?? ''}' != confirm) {
              throw const PostgrestException(
                message: 'Confirmation DISE number does not match the selected school.',
              );
            }
            int daysDeleted = 0;
            int marksDeleted = 0;
            if (isRange) {
              final targetDayIds = <String>{};
              for (final d
                  in (await _db
                          .collection('attendance_days')
                          .where('school_ref', isEqualTo: id)
                          .get())
                      .docs) {
                final data = d.data();
                final dt = '${data['attendance_date'] ?? ''}'.trim();
                final dShort = dt.length >= 10 ? dt.substring(0, 10) : dt;
                if (dShort.isNotEmpty &&
                    dShort.compareTo(fromDateFilter) >= 0 &&
                    dShort.compareTo(toDateFilter) <= 0) {
                  final did = '${data['id'] ?? d.id}'.trim();
                  if (did.isNotEmpty) targetDayIds.add(did);
                  targetDayIds.add(d.id);
                  await d.reference.delete();
                  daysDeleted++;
                }
              }
              for (final d
                  in (await _db
                          .collection('student_attendance')
                          .where('school_ref', isEqualTo: id)
                          .get())
                      .docs) {
                final mData = d.data();
                final dayId = '${mData['attendance_day_id'] ?? ''}'.trim();
                final mDate = '${mData['attendance_date'] ?? ''}'.trim();
                final mShort = mDate.length >= 10 ? mDate.substring(0, 10) : mDate;
                final inRange = mShort.isNotEmpty &&
                    mShort.compareTo(fromDateFilter) >= 0 &&
                    mShort.compareTo(toDateFilter) <= 0;
                if (targetDayIds.contains(dayId) || inRange) {
                  await d.reference.delete();
                  marksDeleted++;
                }
              }
            } else {
              for (final d
                  in (await _db
                          .collection('student_attendance')
                          .where('school_ref', isEqualTo: id)
                          .get())
                      .docs) {
                await d.reference.delete();
                marksDeleted++;
              }
              for (final d
                  in (await _db
                          .collection('attendance_days')
                          .where('school_ref', isEqualTo: id)
                          .get())
                      .docs) {
                await d.reference.delete();
                daysDeleted++;
              }
            }
            FirestoreQueryBuilder.invalidateCache('attendance_days');
            FirestoreQueryBuilder.invalidateCache('student_attendance');
            return <String, dynamic>{
              'ok': true,
              'school_id': confirm,
              'school_name': sDoc.data()?['school_name'] ?? '',
              'attendance_days_deleted': daysDeleted,
              'student_marks_deleted': marksDeleted,
            };
          }

        case 'developer.delete_all_library_books':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            final confirm = '${body['confirmSchoolId'] ?? ''}'.trim();
            final sDoc = await _db.collection('schools').doc(id).get();
            if (!sDoc.exists ||
                '${sDoc.data()?['school_id'] ?? ''}' != confirm) {
              throw const PostgrestException(
                message: 'Confirmation DISE number does not match the selected school.',
              );
            }
            int booksDeleted = 0;
            int txDeleted = 0;
            int histDeleted = 0;
            for (final d
                in (await _db
                        .collection('library_transactions')
                        .where('school_ref', isEqualTo: id)
                        .get())
                    .docs) {
              await d.reference.delete();
              txDeleted++;
            }
            for (final d
                in (await _db
                        .collection('library_books')
                        .where('school_ref', isEqualTo: id)
                        .get())
                    .docs) {
              await d.reference.delete();
              booksDeleted++;
            }
            for (final d
                in (await _db
                        .collection('library_book_number_history')
                        .where('school_ref', isEqualTo: id)
                        .get())
                    .docs) {
              await d.reference.delete();
              histDeleted++;
            }
            return <String, dynamic>{
              'ok': true,
              'school_id': confirm,
              'school_name': sDoc.data()?['school_name'] ?? '',
              'books_deleted': booksDeleted,
              'transactions_deleted': txDeleted,
              'number_history_deleted': histDeleted,
            };
          }

        case 'developer.set_prev_attendance_upload':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(
                message: 'School reference is required.',
              );
            }
            final enabled = body['enabled'] == true ||
                '${body['enabled']}'.toLowerCase() == 'true';
            final nowUtc = DateTime.now().toUtc();
            final expiresIso = enabled
                ? nowUtc.add(const Duration(hours: 24)).toIso8601String()
                : '';
            final schoolPatch = <String, dynamic>{
              'prev_attendance_upload_enabled': enabled,
              'prev_attendance_upload_activated_at': enabled ? nowIso : '',
              'prev_attendance_upload_expires_at': expiresIso,
              'updated_at': nowIso,
            };
            await _db
                .collection('schools')
                .doc(id)
                .set(schoolPatch, fs.SetOptions(merge: true));

            final settingsSnap =
                await _db.collection('school_settings').doc(id).get();
            final existingCfg = settingsSnap.data()?['config'] is Map
                ? Map<String, dynamic>.from(
                    settingsSnap.data()!['config'] as Map,
                  )
                : <String, dynamic>{};
            existingCfg['prev_attendance_upload_enabled'] = enabled;
            existingCfg['prev_attendance_upload_activated_at'] =
                enabled ? nowIso : '';
            existingCfg['prev_attendance_upload_expires_at'] = expiresIso;
            await _db.collection('school_settings').doc(id).set(
              <String, dynamic>{
                'id': id,
                'school_ref': id,
                'config': existingCfg,
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            FirestoreQueryBuilder.invalidateCache('schools');
            FirestoreQueryBuilder.invalidateCache('school_settings');
            final updated = await _db.collection('schools').doc(id).get();
            return <String, dynamic>{
              'school': updated.data() ?? schoolPatch,
              'prev_attendance_upload_enabled': enabled,
              'prev_attendance_upload_expires_at': expiresIso,
            };
          }

        case 'developer.list_messages':
          {
            await _client.purgeExpiredCloudStorageAndMessages();
            final snap = await _db.collection('developer_messages').get();
            final list = <Map<String, dynamic>>[];
            final expiredDeletes = <Future<void>>[];
            for (final d in snap.docs) {
              final data = d.data();
              final displayDate = '${data['display_date'] ?? ''}'.trim();
              // A popup is valid for its selected India calendar date only.
              // Delete it automatically when that date has passed.
              if (displayDate.isNotEmpty && displayDate.compareTo(today) < 0) {
                expiredDeletes.add(d.reference.delete());
                continue;
              }
              list.add(<String, dynamic>{
                ...data,
                'id': data['id'] ?? d.id,
              });
            }
            if (expiredDeletes.isNotEmpty) {
              await Future.wait(expiredDeletes);
            }
            list.sort(
              (a, b) => '${b['created_at'] ?? ''}'.compareTo(
                '${a['created_at'] ?? ''}',
              ),
            );
            return <String, dynamic>{'messages': list.take(50).toList()};
          }

        case 'developer.create_message':
          {
            final msg = '${body['message'] ?? ''}'.trim();
            final scope = '${body['recipientScope'] ?? 'admin_only'}'.trim();
            final rawDate = '${body['displayDate'] ?? today}'.trim();
            final displayDate =
                SupabaseClient._parseAnyDateToIso(rawDate) ?? rawDate;
            final id = SupabaseClient._generateUuid();
            final row = <String, dynamic>{
              'id': id,
              'message': msg,
              'recipient_scope': scope,
              'display_date': displayDate,
              'is_active': true,
              'created_at': nowIso,
              'updated_at': nowIso,
            };
            await _db.collection('developer_messages').doc(id).set(row);
            return <String, dynamic>{'message': row};
          }

        case 'developer.bulk_create_messages':
          {
            final rawList = body['messages'];
            final items = rawList is List ? rawList : const <dynamic>[];
            final defaultScope =
                '${body['recipientScope'] ?? 'admins_and_teachers'}'.trim();
            final col = _db.collection('developer_messages');
            var batch = _db.batch();
            var ops = 0;
            final created = <Map<String, dynamic>>[];
            var seq = 0;
            for (final item in items) {
              if (item is! Map) continue;
              final msg = '${item['message'] ?? ''}'.trim();
              final rawDate = '${item['displayDate'] ?? item['date'] ?? today}'.trim();
              final displayDate =
                  SupabaseClient._parseAnyDateToIso(rawDate) ?? today;
              if (msg.isEmpty) continue;
              var scope = '${item['recipientScope'] ?? defaultScope}'.trim();
              if (scope != 'admin_only' && scope != 'admins_and_teachers') {
                scope = defaultScope;
              }
              final id = SupabaseClient._generateUuid();
              final ts = DateTime.now()
                  .toUtc()
                  .add(Duration(milliseconds: seq++))
                  .toIso8601String();
              final row = <String, dynamic>{
                'id': id,
                'message': msg,
                'recipient_scope': scope,
                'display_date': displayDate,
                'is_active': true,
                'created_at': ts,
                'updated_at': ts,
              };
              batch.set(col.doc(id), row);
              created.add(row);
              ops++;
              if (ops >= 400) {
                await batch.commit();
                batch = _db.batch();
                ops = 0;
              }
            }
            if (ops > 0) {
              await batch.commit();
            }
            return <String, dynamic>{
              'createdCount': created.length,
              'messages': created,
            };
          }

        case 'developer.set_message_active':
          {
            final id = '${body['messageId'] ?? ''}'.trim();
            final active =
                body['isActive'] == true ||
                '${body['isActive']}'.toLowerCase() == 'true';
            await _db.collection('developer_messages').doc(id).update(
              <String, dynamic>{'is_active': active, 'updated_at': nowIso},
            );
            final doc = await _db
                .collection('developer_messages')
                .doc(id)
                .get();
            return <String, dynamic>{'message': doc.data()};
          }

        case 'developer.get_usage':
          {
            await _client.purgeExpiredCloudStorageAndMessages();
            final results = await Future.wait([
              _safeGetCollectionDocs('schools'),
              _safeGetCollectionDocs('school_teachers'),
              _safeGetCollectionDocs('students'),
              _safeGetCollectionDocs('attendance_days'),
              _safeGetCollectionDocs('student_subject_marks'),
              _safeGetCollectionDocs('school_assets'),
              _safeGetCollectionDocs('developer_shared_files'),
            ]);
            final sDocs = results[0];
            final tDocs = results[1];
            final stDocs = results[2];
            final attDocs = results[3];
            final marksDocs = results[4];
            final assetsDocs = results[5];
            final devFilesDocs = results[6];

            final sCount = sDocs.length;
            final tCount = tDocs.length;
            final stCount = stDocs.length;
            final attCount = attDocs.length;
            final marksCount = marksDocs.length;
            final assetsCount = assetsDocs.length + devFilesDocs.length;

            int storageBytes = 0;
            final bucketTotals = <String, Map<String, int>>{};
            for (final doc in assetsDocs) {
              final d = doc.data();
              final b64 = '${d['base64'] ?? d['data_base64'] ?? ''}';
              final sizeBytes = int.tryParse('${d['size_bytes'] ?? 0}') ??
                  ((b64.length * 3) ~/ 4);
              storageBytes += sizeBytes;
              final bucket = '${d['bucket'] ?? 'school-assets'}';
              final entry = bucketTotals.putIfAbsent(
                bucket,
                () => <String, int>{'bytes': 0, 'object_count': 0},
              );
              entry['bytes'] = (entry['bytes'] ?? 0) + sizeBytes;
              entry['object_count'] = (entry['object_count'] ?? 0) + 1;
            }
            final bucketUsage = bucketTotals.entries
                .map((e) => <String, dynamic>{
                      'bucket_id': e.key,
                      'bytes': e.value['bytes'] ?? 0,
                      'object_count': e.value['object_count'] ?? 0,
                    })
                .toList();

            final estimatedFirestoreBytes =
                (sCount * 1024) +
                (tCount * 1024) +
                (stCount * 1536) +
                (attCount * 1024) +
                (marksCount * 512);

            return <String, dynamic>{
              'usage': <String, dynamic>{
                'provider': 'Firebase (Cloud Firestore & Cloud Storage)',
                'database_bytes': estimatedFirestoreBytes,
                'storage_bytes': storageBytes,
                'school_count': sCount,
                'teacher_count': tCount,
                'student_count': stCount,
                'attendance_day_count': attCount,
                'marks_doc_count': marksCount,
                'asset_count': assetsCount,
                'student_count_available': true,
                'bucket_usage': bucketUsage,
                'database_free_plan_reference_bytes': 1073741824,
                'storage_free_plan_reference_bytes': 5368709120,
                'measured_at': nowIso,
              },
            };
          }

        case 'developer.export_directory':
          {
            final sSnap = await _db.collection('schools').get();
            final schoolsById = <String, Map<String, dynamic>>{
              for (final d in sSnap.docs)
                '${d.data()['id'] ?? d.id}': <String, dynamic>{
                  ...d.data(),
                  'id': d.data()['id'] ?? d.id,
                },
            };
            final tSnap = await _db.collection('school_teachers').get();
            final records = <Map<String, dynamic>>[];
            for (final d in tSnap.docs) {
              final t = d.data();
              final school = schoolsById['${t['school_ref']}'];
              if (school == null) continue;
              final classes = t['allowed_classes'] is List
                  ? (t['allowed_classes'] as List).join('; ')
                  : '';
              records.add(<String, dynamic>{
                'school_ref': school['id'],
                'school_id': school['school_id'],
                'school_name': school['school_name'],
                'school_name_en':
                    school['school_name_en'] ?? school['school_name'],
                'school_name_gu': school['school_name_gu'] ?? '',
                'school_address_en': school['school_address_en'] ?? '',
                'school_address_gu': school['school_address_gu'] ?? '',
                'school_type': school['school_type'],
                'validity_date': school['validity_date'],
                'school_active': school['is_active'],
                'school_blocked': school['is_blocked'],
                'school_created_at': school['created_at'],
                'account_id': t['id'] ?? d.id,
                'account_name': t['teacher_name'],
                'account_role': t['role'],
                'registered_mobile': t['mobile'] ?? '',
                'account_active': t['is_active'],
                'assigned_classes': classes,
                'account_created_at': t['created_at'],
              });
            }
            return <String, dynamic>{'records': records};
          }

        case 'developer.list_shared_files':
          {
            await _client.purgeExpiredCloudStorageAndMessages();
            final snap = await _db.collection('developer_shared_files').get();
            final files = snap.docs
                .map((d) => <String, dynamic>{
                      ...d.data(),
                      'id': d.data()['id'] ?? d.id,
                    })
                .where((f) => f['is_active'] != false)
                .toList();
            files.sort(
              (a, b) => '${b['created_at'] ?? ''}'.compareTo(
                '${a['created_at'] ?? ''}',
              ),
            );
            return <String, dynamic>{'files': files};
          }

        case 'developer.upload_shared_file':
          {
            await _client.purgeExpiredCloudStorageAndMessages();
            final fileName = '${body['fileName'] ?? 'file'}'.trim();
            final title = '${body['title'] ?? fileName}'.trim();
            final description = '${body['description'] ?? ''}'.trim();
            final rawDisplayDate = '${body['displayDate'] ?? today}'.trim();
            final displayDate =
                SupabaseClient._parseAnyDateToIso(rawDisplayDate) ?? today;
            final mimeType =
                '${body['mimeType'] ?? 'application/octet-stream'}'.trim();
            final base64Data = '${body['base64Data'] ?? ''}'.trim();
            if (base64Data.isEmpty) {
              throw const PostgrestException(
                message: 'File content is empty.',
              );
            }
            final sizeBytes = int.tryParse('${body['sizeBytes'] ?? 0}') ??
                ((base64Data.length * 3) ~/ 4);
            final id = SupabaseClient._generateUuid();
            final assetDocId = 'dev_shared__$id';
            final storagePath = 'developer_shared/$id/$fileName';

            // Store in Cloud Storage (school_assets)
            await _db.collection('school_assets').doc(assetDocId).set(
              <String, dynamic>{
                'id': assetDocId,
                'bucket': 'developer-shared-files',
                'path': storagePath,
                'file_name': fileName,
                'content_type': mimeType,
                'size_bytes': sizeBytes,
                'base64': base64Data,
                'display_date': displayDate,
                'created_at': nowIso,
                'updated_at': nowIso,
              },
            );

            final metaRow = <String, dynamic>{
              'id': id,
              'title': title.isEmpty ? fileName : title,
              'description': description,
              'file_name': fileName,
              'mime_type': mimeType,
              'size_bytes': sizeBytes,
              'asset_doc_id': assetDocId,
              'storage_bucket': 'developer-shared-files',
              'storage_path': storagePath,
              'display_date': displayDate,
              'is_active': true,
              'created_at': nowIso,
              'updated_at': nowIso,
            };
            await _db.collection('developer_shared_files').doc(id).set(metaRow);
            return <String, dynamic>{'file': metaRow};
          }

        case 'developer.purge_expired_cloud_data':
          {
            final deleteAllFiles =
                body['deleteAllSharedFiles'] == true ||
                '${body['deleteAllSharedFiles']}'.toLowerCase() == 'true';
            final stats = await _client.purgeExpiredCloudStorageAndMessages(
              force: true,
              deleteAllSharedFiles: deleteAllFiles,
            );
            return <String, dynamic>{
              'ok': true,
              'stats': stats,
            };
          }

        case 'developer.delete_shared_file':
          {
            final fileId = '${body['fileId'] ?? ''}'.trim();
            if (fileId.isEmpty) {
              throw const PostgrestException(message: 'fileId is required.');
            }
            final docRef = _db.collection('developer_shared_files').doc(fileId);
            final docSnap = await docRef.get();
            final data = docSnap.data();
            final assetDocId =
                '${data?['asset_doc_id'] ?? 'dev_shared__$fileId'}'.trim();
            final storagePath = '${data?['storage_path'] ?? ''}'.trim();

            // Delete from Cloud Storage (school_assets) as well as metadata collection
            if (assetDocId.isNotEmpty) {
              try {
                await _db.collection('school_assets').doc(assetDocId).delete();
              } catch (_) {}
            }
            if (storagePath.isNotEmpty) {
              try {
                final pathSnap = await _db
                    .collection('school_assets')
                    .where('path', isEqualTo: storagePath)
                    .get();
                for (final d in pathSnap.docs) {
                  await d.reference.delete();
                }
              } catch (_) {}
            }
            await docRef.delete();
            return <String, dynamic>{'ok': true};
          }

        case 'developer.set_school_modules':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(
                message: 'School reference is required.',
              );
            }
            final rawDisabled =
                body['disabledModules'] ?? body['disabled_modules'];
            final disabledList = rawDisabled is Iterable
                ? rawDisabled
                      .map((e) => '$e'.trim().toLowerCase())
                      .where((s) => s.isNotEmpty)
                      .toSet()
                      .toList()
                : <String>[];
            disabledList.sort();
            await _db.collection('schools').doc(id).set(<String, dynamic>{
              'disabled_modules': disabledList,
              'updated_at': nowIso,
            }, fs.SetOptions(merge: true));
            try {
              final settingsSnap =
                  await _db.collection('school_settings').doc(id).get();
              final existingCfg = settingsSnap.data()?['config'] is Map
                  ? Map<String, dynamic>.from(
                      settingsSnap.data()!['config'] as Map,
                    )
                  : <String, dynamic>{};
              existingCfg['disabled_modules'] = disabledList;
              await _db.collection('school_settings').doc(id).set(
                <String, dynamic>{
                  'id': id,
                  'school_ref': id,
                  'config': existingCfg,
                  'updated_at': nowIso,
                },
                fs.SetOptions(merge: true),
              );
            } catch (_) {}
            FirestoreQueryBuilder.invalidateCache('schools');
            FirestoreQueryBuilder.invalidateCache('school_settings');
            return <String, dynamic>{
              'ok': true,
              'schoolRef': id,
              'disabled_modules': disabledList,
            };
          }

        case 'developer.impersonate_school_admin':
          {
            final id = '${body['schoolRef'] ?? ''}'.trim();
            if (id.isEmpty) {
              throw const PostgrestException(
                message: 'School reference is required.',
              );
            }
            final schoolSnap = await _db.collection('schools').doc(id).get();
            if (!schoolSnap.exists || schoolSnap.data() == null) {
              throw const PostgrestException(
                message: 'School not found.',
              );
            }
            final school = <String, dynamic>{
              ...schoolSnap.data()!,
              'id': schoolSnap.data()!['id'] ?? schoolSnap.id,
            };
            final tSnap = await _db
                .collection('school_teachers')
                .where('school_ref', isEqualTo: id)
                .get();
            Map<String, dynamic>? adminProfile;
            for (final d in tSnap.docs) {
              final row = d.data();
              if ('${row['role'] ?? ''}'.trim().toLowerCase() == 'admin') {
                adminProfile = <String, dynamic>{
                  ...row,
                  'id': row['id'] ?? d.id,
                };
                break;
              }
            }
            final disabledRaw = school['disabled_modules'];
            final disabledList = disabledRaw is Iterable
                ? disabledRaw
                      .map((e) => '$e'.trim().toLowerCase())
                      .where((s) => s.isNotEmpty)
                      .toList()
                : <String>[];
            final isBlocked = school['is_blocked'] == true;
            final profile = <String, dynamic>{
              'teacher_id': '${adminProfile?['id'] ?? 'dev_admin_$id'}',
              'teacher_name':
                  '${adminProfile?['teacher_name'] ?? 'School Admin (Developer)'}',
              'role': 'admin',
              'allowed_classes': const <String>[],
              'school_ref': id,
              'school_id': '${school['school_id'] ?? ''}',
              'school_name': '${school['school_name'] ?? ''}',
              'school_name_en':
                  '${school['school_name_en'] ?? school['school_name'] ?? ''}',
              'school_name_gu': '${school['school_name_gu'] ?? ''}',
              'school_address_en': '${school['school_address_en'] ?? ''}',
              'school_address_gu': '${school['school_address_gu'] ?? ''}',
              'school_type': '${school['school_type'] ?? 'mixed'}',
              'validity_date': school['validity_date'],
              'is_blocked': isBlocked,
              'block_reason': '${school['block_reason'] ?? ''}',
              'disabled_modules': disabledList,
              'can_edit': true,
              'can_download_reports': true,
              'is_developer_session': true,
            };
            return <String, dynamic>{
              'ok': true,
              'school': school,
              'profile': profile,
            };
          }

        default:
          throw PostgrestException(
            message: 'Unsupported Developer action: $action',
          );
      }
    }

    // Admin / school-user actions
    final ctx = await _client._resolveCurrentTeacherContext(forceRefresh: true);
    if (ctx == null) {
      throw const AuthException('Sign in to the school account first.');
    }
    final school = ctx.schoolRow;
    final schoolRef = ctx.schoolRef;
    final today = SupabaseClient._indiaTodayIso();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    switch (action) {
      case 'admin.get_due_popups':
        {
          await _client.purgeExpiredCloudStorageAndMessages();
          final msgSnap = await _db
              .collection('developer_messages')
              .where('display_date', isEqualTo: today)
              .get();
          final dismissSnap = await _db
              .collection('developer_message_dismissals')
              .where('auth_user_id', isEqualTo: ctx.authUserId)
              .get();
          final dismissedIds = <String>{
            for (final d in dismissSnap.docs) '${d.data()['message_id'] ?? ''}',
          };
          final rawMessages = msgSnap.docs
              .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.data()['id'] ?? doc.id})
              .toList();
          rawMessages.sort(
            (a, b) => '${a['created_at'] ?? ''}'.compareTo(
              '${b['created_at'] ?? ''}',
            ),
          );
          final popups = <Map<String, dynamic>>[];
          for (final m in rawMessages) {
            if (m['is_active'] != true) continue;
            final mid = '${m['id'] ?? ''}';
            if (dismissedIds.contains(mid)) continue;
            final scope = '${m['recipient_scope'] ?? ''}';
            if (scope == 'admins_and_teachers' ||
                (scope == 'admin_only' && ctx.isAdmin)) {
              popups.add(<String, dynamic>{
                'kind': 'developer_message',
                'messageId': mid,
                'title': 'Developer Message',
                'message': '${m['message'] ?? ''}',
                'recipientScope': scope,
                'displayDate': '${m['display_date'] ?? today}',
              });
            }
          }

          // Check account validity expiry reminders (once daily per user):
          // - 5 days or fewer left -> daily once popup for Admin (account renewal)
          // - 2 days or fewer left -> daily once popup for Teachers & Admin with Gujarati backup warning
          final validityRaw = '${school['validity_date'] ?? ''}'.trim();
          final validityIso = SupabaseClient._parseAnyDateToIso(validityRaw);
          if (validityIso != null) {
            final vDt = DateTime.tryParse(validityIso);
            final tDt = DateTime.tryParse(today);
            if (vDt != null && tDt != null) {
              final daysRemaining = DateTime(vDt.year, vDt.month, vDt.day)
                  .difference(DateTime(tDt.year, tDt.month, tDt.day))
                  .inDays;
              if (daysRemaining >= 0 && daysRemaining <= 5) {
                final reminderDocId = '${schoolRef}__${ctx.authUserId}__$today';
                final rSnap = await _db
                    .collection('school_validity_reminder_dismissals')
                    .doc(reminderDocId)
                    .get();
                if (!rSnap.exists) {
                  final validityDmy =
                      '${vDt.day.toString().padLeft(2, '0')}-${vDt.month.toString().padLeft(2, '0')}-${vDt.year.toString().padLeft(4, '0')}';
                  if (daysRemaining <= 2) {
                    final gujWarning =
                        'તમારો બધો ડેટા ડાઉનલોડ કરી લેજો, ખાતાની વેલીડિટી તારીખ $validityDmy સુધી જ છે.';
                    final msgText = ctx.isAdmin
                        ? '$gujWarning\n\nતમારા શાળા ખાતાની વેલીડિટી પૂર્ણ થવામાં માત્ર $daysRemaining દિવસ બાકી છે. કૃપા કરીને ખાતું રિન્યુ (Renew) કરાવો.'
                        : gujWarning;
                    popups.add(<String, dynamic>{
                      'kind': 'validity_reminder',
                      'reminderDate': today,
                      'validityDate': validityIso,
                      'daysRemaining': daysRemaining,
                      'title': 'ખાતાની વેલીડિટી ચેતવણી (Account Validity Alert)',
                      'message': msgText,
                    });
                  } else if (ctx.isAdmin) {
                    popups.add(<String, dynamic>{
                      'kind': 'validity_reminder',
                      'reminderDate': today,
                      'validityDate': validityIso,
                      'daysRemaining': daysRemaining,
                      'title': 'ખાતું રિન્યુ કરવા અંગે (Account Renewal Reminder)',
                      'message':
                          'તમારા શાળા ખાતાની વેલીડિટી પૂર્ણ થવામાં માત્ર $daysRemaining દિવસ બાકી છે (વેલીડિટી તારીખ: $validityDmy). કૃપા કરીને સમયસર ખાતું રિન્યુ (Renew) કરાવો.',
                    });
                  }
                }
              }
            }
          }

          // Check school leave popups:
          // 1) For Admin: show popup on EVERY start while any leave request is pending
          // 2) For Teacher: show popup ONCE after their leave request is approved or rejected
          try {
            final allSchoolLeaves = await _client._cachedSchoolTableRows(
              'teacher_leaves',
              schoolRef,
            );
            if (ctx.isAdmin) {
              final pendingLeaves = allSchoolLeaves.where((l) {
                final st = '${l['status'] ?? 'pending'}'.trim().toLowerCase();
                return st == 'pending';
              }).toList();
              if (pendingLeaves.isNotEmpty) {
                pendingLeaves.sort(
                  (a, b) => '${b['start_date'] ?? ''}'.compareTo(
                    '${a['start_date'] ?? ''}',
                  ),
                );
                final lines = <String>[
                  'તમારી શાળામાં ${pendingLeaves.length} રજા અરજી મંજૂર અથવા નામંજૂર કરવાની બાકી છે:',
                  '',
                ];
                for (var i = 0; i < pendingLeaves.length; i++) {
                  final l = pendingLeaves[i];
                  final ld = l['leave_data'] is Map
                      ? Map<String, dynamic>.from(l['leave_data'] as Map)
                      : <String, dynamic>{};
                  final tName =
                      '${ld['teacher_name'] ?? 'શિક્ષક'}'.trim();
                  final tClass = '${ld['teacher_class'] ?? ''}'.trim();
                  final lType = '${l['leave_type'] ?? ''}'.trim();
                  final sDate = '${l['start_date'] ?? ''}'.trim();
                  final eDate = '${l['end_date'] ?? sDate}'.trim();
                  final days = '${ld['total_days'] ?? ''}'.trim();
                  final chargeName =
                      '${ld['charge_teacher_name'] ?? ''}'.trim();
                  final reason = '${l['reason'] ?? ''}'.trim();
                  lines.add(
                    '${i + 1}. $tName${tClass.isNotEmpty && tClass != '—' ? ' (ધોરણ: $tClass)' : ''}\n'
                    '   • રજા: $lType ($sDate થી $eDate${days.isNotEmpty ? ' • $days દિવસ' : ''})\n'
                    '   • ચાર્જ શિક્ષક: ${chargeName.isEmpty ? '—' : chargeName}'
                    '${reason.isEmpty ? '' : '\n   • કારણ: $reason'}',
                  );
                }
                lines.add('');
                lines.add(
                  'નોંધ: જ્યાં સુધી આ રજા અરજી મંજૂર (Approve) કે નામંજૂર (Reject) કરવામાં નહીં આવે ત્યાં સુધી એપ શરૂ કરતી વખતે આ નોટિફિકેશન દેખાશે.',
                );
                popups.add(<String, dynamic>{
                  'kind': 'admin_pending_leaves',
                  'pendingCount': pendingLeaves.length,
                  'title':
                      '🔔 રજા મંજૂરી બાકી (${pendingLeaves.length} Pending Leave Request${pendingLeaves.length == 1 ? '' : 's'})',
                  'message': lines.join('\n'),
                });
              }
            } else {
              for (final l in allSchoolLeaves) {
                if ('${l['teacher_id'] ?? ''}'.trim() != ctx.teacherId) {
                  continue;
                }
                if ('${l['record_source'] ?? 'teacher_application'}'.trim() ==
                    'admin_manual') {
                  continue;
                }
                final st = '${l['status'] ?? ''}'.trim().toLowerCase();
                if (st != 'approved' && st != 'rejected') continue;
                final ld = l['leave_data'] is Map
                    ? Map<String, dynamic>.from(l['leave_data'] as Map)
                    : <String, dynamic>{};
                final unnotified =
                    l['teacher_decision_notified'] == false ||
                    ld['teacher_decision_notified'] == false;
                if (!unnotified) continue;

                final lid = '${l['id'] ?? ''}'.trim();
                if (lid.isEmpty) continue;
                final isApproved = st == 'approved';
                final lType = '${l['leave_type'] ?? 'રજા'}'.trim();
                final sDate = '${l['start_date'] ?? ''}'.trim();
                final eDate = '${l['end_date'] ?? sDate}'.trim();
                final days = '${ld['total_days'] ?? ''}'.trim();
                final chargeName = '${ld['charge_teacher_name'] ?? ''}'.trim();
                final note = '${l['decision_note'] ?? ''}'.trim();
                final msgLines = <String>[
                  isApproved
                      ? 'તમારી રજાની અરજી શાળા Admin દ્વારા મંજૂર (Approved) કરવામાં આવી છે.'
                      : 'તમારી રજાની અરજી શાળા Admin દ્વારા નામંજૂર (Rejected) કરવામાં આવી છે.',
                  '',
                  '• રજાનો પ્રકાર: $lType',
                  '• તારીખ: $sDate થી $eDate${days.isNotEmpty ? ' ($days દિવસ)' : ''}',
                  if (chargeName.isNotEmpty) '• ચાર્જ શિક્ષક: $chargeName',
                  if (note.isNotEmpty) '• Admin નોંધ: $note',
                ];
                popups.add(<String, dynamic>{
                  'kind': 'teacher_leave_decision',
                  'leaveId': lid,
                  'status': st,
                  'title': isApproved
                      ? '✅ રજા અરજી મંજૂર (Leave Approved)'
                      : '❌ રજા અરજી નામંજૂર (Leave Rejected)',
                  'message': msgLines.join('\n'),
                });
              }
            }
          } catch (_) {}

          // 3) Daily PM POSHAN & Breakfast Menu popup (Monday–Saturday, once per day per user)
          try {
            final menuDoc = await _client._cachedDocData(
              'school_weekly_meal_menus',
              schoolRef,
            );
            if (menuDoc != null && menuDoc['enabled'] != false) {
              final todayDt = DateTime.tryParse(today);
              final weekday = todayDt?.weekday ?? 0; // 1=Mon .. 6=Sat, 7=Sun
              if (weekday >= 1 && weekday <= 6) {
                final daysMap = menuDoc['days'] is Map
                    ? Map<String, dynamic>.from(menuDoc['days'] as Map)
                    : <String, dynamic>{};
                final dayEntry = daysMap['$weekday'] is Map
                    ? Map<String, dynamic>.from(daysMap['$weekday'] as Map)
                    : <String, dynamic>{};
                final pmItem = '${dayEntry['pm_poshan_item'] ?? ''}'.trim();
                final pmIng =
                    '${dayEntry['pm_poshan_ingredients'] ?? ''}'.trim();
                final bfItem = '${dayEntry['breakfast_item'] ?? ''}'.trim();
                final bfIng =
                    '${dayEntry['breakfast_ingredients'] ?? ''}'.trim();
                if (pmItem.isNotEmpty || bfItem.isNotEmpty) {
                  final dismissDocId =
                      '${schoolRef}__${ctx.authUserId}__$today';
                  final dSnap = await _db
                      .collection('school_meal_menu_dismissals')
                      .doc(dismissDocId)
                      .get();
                  if (!dSnap.exists) {
                    const dayNamesGu = <int, String>{
                      1: 'સોમવાર (Monday)',
                      2: 'મંગળવાર (Tuesday)',
                      3: 'બુધવાર (Wednesday)',
                      4: 'ગુરુવાર (Thursday)',
                      5: 'શુક્રવાર (Friday)',
                      6: 'શનિવાર (Saturday)',
                    };
                    final lines = <String>[
                      '📅 આજનો વાર: ${dayNamesGu[weekday] ?? ''}',
                      '',
                    ];
                    if (bfItem.isNotEmpty) {
                      lines.add('🥣 અલ્પાહાર (Breakfast): $bfItem');
                      if (bfIng.isNotEmpty) {
                        lines.add('   સામગ્રી અને જથ્થો: $bfIng');
                      }
                      lines.add('');
                    }
                    if (pmItem.isNotEmpty) {
                      lines.add('🍲 PM POSHAN (મધ્યાહન ભોજન): $pmItem');
                      if (pmIng.isNotEmpty) {
                        lines.add('   સામગ્રી અને જથ્થો: $pmIng');
                      }
                    }
                    popups.add(<String, dynamic>{
                      'kind': 'daily_meal_menu',
                      'menuDate': today,
                      'title': '🍽️ આજનું PM POSHAN અને અલ્પાહાર મેનુ',
                      'message': lines.join('\n').trim(),
                    });
                  }
                }
              }
            }
          } catch (_) {}

          // 4) Continuous Absence Milestone Popups (student-wise attendance only, once per spell)
          try {
            final absRes = await _client._computeStudentAbsenceStreaksAndAlerts(
              schoolRef: schoolRef,
              ctx: ctx,
              roleScope: ctx.isAdmin ? 'admin' : 'teacher',
            );
            final dueList = (absRes['due_milestones'] as List? ?? const [])
                .whereType<Map>()
                .map((m) => m.map((k, v) => MapEntry('$k', v)))
                .toList();
            if (dueList.isNotEmpty) {
              final ackKeys = <String>[];
              final lines = <String>[
                ctx.isAdmin
                    ? 'નીચેના વિદ્યાર્થીઓ સતત ગેરહાજર છે (વર્ગવાર student-wise હાજરી મુજબ):'
                    : 'તમારા વર્ગના નીચેના વિદ્યાર્થીઓ સતત ગેરહાજર છે:',
                '',
              ];
              for (var i = 0; i < dueList.length; i++) {
                final item = dueList[i];
                final ackKey = '${item['ack_key'] ?? ''}'.trim();
                if (ackKey.isNotEmpty) ackKeys.add(ackKey);
                final stName = '${item['student_name'] ?? ''}'.trim();
                final rollNo = '${item['roll_number'] ?? ''}'.trim();
                final clsLabel = '${item['class_label'] ?? ''}'.trim();
                final mDays = item['milestone'] ?? 0;
                final actionGu = '${item['action_message_gu'] ?? ''}'.trim();
                lines.add(
                  '${i + 1}. $stName${rollNo.isNotEmpty ? ' (રોલ નં. $rollNo)' : ''} — $clsLabel\n'
                  '   • સતત ગેરહાજર: $mDays દિવસ\n'
                  '   • સૂચના: $actionGu',
                );
              }
              popups.add(<String, dynamic>{
                'kind': 'absence_milestone_alert',
                'ackKeys': ackKeys,
                'title':
                    '⚠️ સતત ગેરહાજર વિદ્યાર્થી સૂચના (${dueList.length})',
                'message': lines.join('\n'),
              });
            }
          } catch (_) {}

          return <String, dynamic>{'popups': popups, 'serverDate': today};
        }

      case 'admin.dismiss_daily_meal_menu':
        {
          final mDate = '${body['menuDate'] ?? today}'.trim();
          final docId = '${schoolRef}__${ctx.authUserId}__$mDate';
          await _db.collection('school_meal_menu_dismissals').doc(docId).set(
            <String, dynamic>{
              'id': docId,
              'school_ref': schoolRef,
              'auth_user_id': ctx.authUserId,
              'menu_date': mDate,
              'dismissed_at': nowIso,
            },
          );
          return <String, dynamic>{'ok': true};
        }

      case 'admin.dismiss_absence_milestone_alert':
        {
          final rawKeys = body['ackKeys'];
          final keys = rawKeys is Iterable
              ? rawKeys.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList()
              : <String>[];
          var batch = _db.batch();
          var ops = 0;
          for (final k in keys) {
            batch.set(
              _db.collection('student_absence_alert_acks').doc(k),
              <String, dynamic>{
                'id': k,
                'school_ref': schoolRef,
                'acked_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            ops++;
            if (ops >= 400) {
              await batch.commit();
              batch = _db.batch();
              ops = 0;
            }
          }
          if (ops > 0) await batch.commit();
          FirestoreQueryBuilder.invalidateCache('student_absence_alert_acks');
          return <String, dynamic>{'ok': true, 'acked': keys.length};
        }

      case 'admin.dismiss_teacher_leave_decision':
        {
          final leaveId = '${body['leaveId'] ?? ''}'.trim();
          if (leaveId.isNotEmpty) {
            await _db.collection('teacher_leaves').doc(leaveId).set(
              <String, dynamic>{
                'teacher_decision_notified': true,
                'updated_at': nowIso,
              },
              fs.SetOptions(merge: true),
            );
            FirestoreQueryBuilder.invalidateCache('teacher_leaves');
          }
          return <String, dynamic>{'ok': true};
        }

      case 'admin.dismiss_developer_message':
        {
          final mid = '${body['messageId'] ?? ''}'.trim();
          final docId = '${mid}__${ctx.authUserId}';
          await _db.collection('developer_message_dismissals').doc(docId).set(
            <String, dynamic>{
              'id': docId,
              'message_id': mid,
              'auth_user_id': ctx.authUserId,
              'dismissed_at': nowIso,
            },
          );
          return <String, dynamic>{'ok': true};
        }

      case 'admin.dismiss_validity_reminder':
        {
          final rDate = '${body['reminderDate'] ?? today}'.trim();
          final docId = '${schoolRef}__${ctx.authUserId}__$rDate';
          await _db
              .collection('school_validity_reminder_dismissals')
              .doc(docId)
              .set(<String, dynamic>{
                'id': docId,
                'school_ref': schoolRef,
                'auth_user_id': ctx.authUserId,
                'reminder_date': rDate,
                'dismissed_at': nowIso,
              });
          return <String, dynamic>{'ok': true};
        }

      case 'admin.get_context':
        {
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can manage classes and teachers.',
            );
          }
          final isBlocked = school['is_blocked'] == true;
          return <String, dynamic>{
            'teacher': <String, dynamic>{
              'id': ctx.teacherId,
              'name': ctx.teacherName,
              'role': ctx.role,
              'allowed_classes': ctx.allowedClasses,
            },
            'school': <String, dynamic>{
              'id': school['id'],
              'school_id': school['school_id'],
              'school_name': school['school_name'],
              'school_name_en':
                  school['school_name_en'] ?? school['school_name'],
              'school_name_gu': school['school_name_gu'] ?? '',
              'school_address_en': school['school_address_en'] ?? '',
              'school_address_gu': school['school_address_gu'] ?? '',
              'school_type': school['school_type'] ?? 'mixed',
              'validity_date': school['validity_date'],
              'is_active': school['is_active'] == true,
              'is_blocked': isBlocked,
              'block_reason': '${school['block_reason'] ?? ''}',
              'disabled_modules': school['disabled_modules'] is Iterable
                  ? (school['disabled_modules'] as Iterable)
                        .map((e) => '$e'.trim().toLowerCase())
                        .where((v) => v.isNotEmpty)
                        .toList()
                  : const <String>[],
            },
            'can_edit': school['is_active'] == true && !isBlocked,
            'can_download_reports': school['is_active'] == true,
          };
        }

      case 'admin.list_classes':
        {
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can manage classes.',
            );
          }
          final classes = await _client
              .from('school_classes')
              .select()
              .eq('school_ref', schoolRef)
              .order('sort_order')
              .order('label');
          return <String, dynamic>{
            'classes': classes,
            'can_edit': school['is_blocked'] != true,
          };
        }

      case 'admin.list_teachers':
        {
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can manage teachers.',
            );
          }
          final rows = await _client
              .from('school_teachers')
              .select()
              .eq('school_ref', schoolRef)
              .eq('role', 'teacher')
              .order('created_at');
          return <String, dynamic>{
            'teachers': rows,
            'can_edit': school['is_blocked'] != true,
          };
        }

      case 'admin.create_class':
        {
          await _client._requireSchoolWriteAccess();
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can create classes.',
            );
          }
          final standard = '${body['standard'] ?? ''}'.trim();
          final section = '${body['section'] ?? ''}'.trim().toUpperCase();
          var classKey = '${body['classKey'] ?? ''}'.trim();
          if (classKey.isEmpty && standard.isNotEmpty) {
            final stdToken = standard
                .toUpperCase()
                .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
                .replaceAll(RegExp(r'^_+|_+$'), '');
            final prefix = stdToken.contains('BALVATIKA')
                ? 'BALVATIKA'
                : 'STD_$stdToken';
            classKey = section.isNotEmpty ? '${prefix}_$section' : prefix;
          }
          var label = '${body['label'] ?? ''}'.trim();
          if (label.isEmpty && standard.isNotEmpty) {
            label = standard.toLowerCase().contains('balvatika')
                ? 'બાલવાટિકા${section.isNotEmpty ? ' - $section' : ''}'
                : 'ધોરણ $standard${section.isNotEmpty ? ' - $section' : ''}';
          }
          if (classKey.isEmpty || label.isEmpty || standard.isEmpty) {
            throw const PostgrestException(
              message: 'Standard and class name are required.',
            );
          }
          var reportGroup = '${body['reportGroup'] ?? ''}'.trim();
          if (reportGroup.isEmpty) {
            final stdLower = standard.toLowerCase();
            final n = int.tryParse(standard);
            if (stdLower.contains('balvatika') ||
                stdLower.contains('બાલવાટિકા')) {
              reportGroup = 'balvatika';
            } else if (n != null && n >= 1 && n <= 5) {
              reportGroup = 'std1to5';
            } else if (n != null && n >= 6 && n <= 8) {
              reportGroup = 'std6to8';
            } else {
              reportGroup = 'other';
            }
          }
          final cid = SupabaseClient._generateUuid();
          final row = <String, dynamic>{
            'id': cid,
            'school_ref': schoolRef,
            'class_key': classKey,
            'label': label,
            'sheet_name': '${body['sheetName'] ?? label}'.trim(),
            'standard': standard,
            'section': section,
            'report_group': reportGroup,
            'sort_order': int.tryParse('${body['sortOrder'] ?? 0}') ?? 0,
            'is_active': true,
            'created_at': nowIso,
            'updated_at': nowIso,
          };
          await _db.collection('school_classes').doc(cid).set(row);
          FirestoreQueryBuilder.invalidateCache('school_classes');
          await _client._seedSubjectsForClassRow(row);
          return <String, dynamic>{'class': row};
        }

      case 'admin.set_class_status':
        {
          await _client._requireSchoolWriteAccess();
          final classId = '${body['classId'] ?? ''}'.trim();
          final active =
              body['isActive'] == true ||
              '${body['isActive']}'.toLowerCase() == 'true';
          await _db.collection('school_classes').doc(classId).update(
            <String, dynamic>{'is_active': active, 'updated_at': nowIso},
          );
          FirestoreQueryBuilder.invalidateCache('school_classes');
          final doc = await _db.collection('school_classes').doc(classId).get();
          return <String, dynamic>{'class': doc.data()};
        }

      case 'admin.create_teacher':
        {
          await _client._requireSchoolWriteAccess();
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can create teachers.',
            );
          }
          final teacherName = '${body['teacherName'] ?? ''}'.trim();
          final mobile = _normalizeMobile(body['mobile'], required: true);
          final password = '${body['password'] ?? ''}';
          if (teacherName.length < 2) {
            throw const PostgrestException(
              message: 'Teacher name is too short.',
            );
          }
          final allowedClasses = body['allowedClasses'] is List
              ? (body['allowedClasses'] as List)
                    .map((e) => '$e'.trim())
                    .where((s) => s.isNotEmpty)
                    .toList()
              : <String>[];

          // Check if a teacher with the same 10-digit mobile or exact name already exists in this school
          final existingTeachersSnap = await _db
              .collection('school_teachers')
              .where('school_ref', isEqualTo: schoolRef)
              .get();
          final cleanDigits = mobile.replaceAll(RegExp(r'\D'), '');
          final mobile10 = cleanDigits.length >= 10
              ? cleanDigits.substring(cleanDigits.length - 10)
              : cleanDigits;
          Map<String, dynamic>? existingDocData;
          String? existingTid;
          for (final d in existingTeachersSnap.docs) {
            final data = d.data();
            if ('${data['role'] ?? 'teacher'}'.toLowerCase() == 'admin') {
              continue;
            }
            final dMobDigits = '${data['mobile'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
            final dMob10 = dMobDigits.length >= 10
                ? dMobDigits.substring(dMobDigits.length - 10)
                : dMobDigits;
            final dName = '${data['teacher_name'] ?? ''}'.trim().toLowerCase();
            if ((mobile10.isNotEmpty && dMob10 == mobile10) ||
                dName == teacherName.toLowerCase()) {
              existingDocData = data;
              existingTid = '${data['id'] ?? d.id}'.trim();
              break;
            }
          }

          if (existingTid != null && existingTid.isNotEmpty) {
            final patch = <String, dynamic>{
              'teacher_name': teacherName,
              'mobile': mobile,
              'allowed_classes': allowedClasses,
              'is_active': true,
              'updated_at': nowIso,
            };
            if (password.isNotEmpty) {
              if (password.length < 4 || password.length > 15) {
                throw const PostgrestException(
                  message: 'Teacher password must contain 4 to 15 characters.',
                );
              }
              final newEmail = _internalLoginEmail();
              final helperAuth = await _getHelperAuth();
              final cred = await helperAuth.createUserWithEmailAndPassword(
                email: newEmail,
                password: SupabaseClient._toFirebasePassword(password),
              );
              await helperAuth.signOut();
              patch['auth_user_id'] = cred.user!.uid;
              patch['login_email'] = newEmail;
            }
            await _db
                .collection('school_teachers')
                .doc(existingTid)
                .set(patch, fs.SetOptions(merge: true));
            final rawAssign = body['classSubjectAssignments'];
            if (rawAssign is List) {
              await _syncTeacherResultAssignments(
                schoolRef: schoolRef,
                teacherId: existingTid,
                assignments: rawAssign
                    .whereType<Map>()
                    .map((m) => m.map((k, v) => MapEntry('$k', v)))
                    .toList(),
              );
            }
            FirestoreQueryBuilder.invalidateCache('school_teachers');
            FirestoreQueryBuilder.invalidateCache('school_classes');
            FirestoreQueryBuilder.invalidateCache('teacher_subject_assignments');
            return <String, dynamic>{
              'teacher': <String, dynamic>{...?existingDocData, ...patch},
            };
          }

          if (password.length < 4 || password.length > 15) {
            throw const PostgrestException(
              message: 'Teacher password must contain 4 to 15 characters.',
            );
          }

          final loginEmail = _internalLoginEmail();
          final helperAuth = await _getHelperAuth();
          final cred = await helperAuth.createUserWithEmailAndPassword(
            email: loginEmail,
            password: SupabaseClient._toFirebasePassword(password),
          );
          await helperAuth.signOut();

          final tid = SupabaseClient._generateUuid();
          final row = <String, dynamic>{
            'id': tid,
            'school_ref': schoolRef,
            'auth_user_id': cred.user!.uid,
            'teacher_name': teacherName,
            'mobile': mobile,
            'role': 'teacher',
            'allowed_classes': allowedClasses,
            'is_active': true,
            'login_email': loginEmail,
            'created_at': nowIso,
            'updated_at': nowIso,
          };
          await _db.collection('school_teachers').doc(tid).set(row);
          FirestoreQueryBuilder.invalidateCache('school_teachers');

          final rawAssign = body['classSubjectAssignments'];
          if (rawAssign is List && rawAssign.isNotEmpty) {
            await _syncTeacherResultAssignments(
              schoolRef: schoolRef,
              teacherId: tid,
              assignments: rawAssign
                  .whereType<Map>()
                  .map((m) => m.map((k, v) => MapEntry('$k', v)))
                  .toList(),
            );
          }
          FirestoreQueryBuilder.invalidateCache('school_teachers');
          FirestoreQueryBuilder.invalidateCache('school_classes');
          FirestoreQueryBuilder.invalidateCache('teacher_subject_assignments');
          return <String, dynamic>{'teacher': row};
        }

      case 'admin.update_teacher':
        {
          await _client._requireSchoolWriteAccess();
          if (!ctx.isAdmin) {
            throw const PostgrestException(
              message: 'Only a school Admin can update teachers.',
            );
          }
          final tid = '${body['teacherId'] ?? ''}'.trim();
          final patch = <String, dynamic>{'updated_at': nowIso};
          if (body['isActive'] != null) {
            patch['is_active'] =
                body['isActive'] == true ||
                '${body['isActive']}'.toLowerCase() == 'true';
          }
          if (body['allowedClasses'] is List) {
            patch['allowed_classes'] = (body['allowedClasses'] as List)
                .map((e) => '$e'.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          if (body['teacherName'] != null) {
            patch['teacher_name'] = '${body['teacherName']}'.trim();
          }
          if (body['mobile'] != null && '${body['mobile']}'.trim().isNotEmpty) {
            patch['mobile'] = _normalizeMobile(body['mobile'], required: true);
          }
          if (body['newPassword'] != null &&
              '${body['newPassword']}'.isNotEmpty) {
            final newEmail = _internalLoginEmail();
            final helperAuth = await _getHelperAuth();
            final nextPwd = '${body['newPassword']}';
            if (nextPwd.length < 4 || nextPwd.length > 15) {
              throw const PostgrestException(
                message: 'Teacher password must contain 4 to 15 characters.',
              );
            }
            final cred = await helperAuth.createUserWithEmailAndPassword(
              email: newEmail,
              password: SupabaseClient._toFirebasePassword(nextPwd),
            );
            await helperAuth.signOut();
            patch['auth_user_id'] = cred.user!.uid;
            patch['login_email'] = newEmail;
          }
          await _db
              .collection('school_teachers')
              .doc(tid)
              .set(patch, fs.SetOptions(merge: true));

          if (body['classSubjectAssignments'] is List) {
            await _syncTeacherResultAssignments(
              schoolRef: schoolRef,
              teacherId: tid,
              assignments: (body['classSubjectAssignments'] as List)
                  .whereType<Map>()
                  .map((m) => m.map((k, v) => MapEntry('$k', v)))
                  .toList(),
            );
          }
          FirestoreQueryBuilder.invalidateCache('school_teachers');
          FirestoreQueryBuilder.invalidateCache('school_classes');
          FirestoreQueryBuilder.invalidateCache('teacher_subject_assignments');
          final updated = await _db
              .collection('school_teachers')
              .doc(tid)
              .get();
          return <String, dynamic>{'teacher': updated.data() ?? patch};
        }

      default:
        throw PostgrestException(message: 'Unsupported Admin action: $action');
    }
  }

  Future<Map<String, dynamic>> _handleAdminSchoolManagement(
    Map<String, dynamic> body,
  ) async {
    final action = '${body['action'] ?? ''}'.trim();
    switch (action) {
      case 'create_teacher':
        {
          final res = await _handlePlatformAdmin(<String, dynamic>{
            'action': 'admin.create_teacher',
            'teacherName': body['teacher_name'],
            'password': body['temporary_password'],
            'allowedClasses': body['allowed_classes'] ?? const <String>[],
            'mobile': body['mobile'] ?? '9876543210',
          });
          return <String, dynamic>{'success': true, ...res};
        }
      case 'change_teacher_password':
        {
          await _handlePlatformAdmin(<String, dynamic>{
            'action': 'admin.update_teacher',
            'teacherId': body['teacher_id'],
            'newPassword': body['new_password'],
          });
          return <String, dynamic>{'success': true};
        }
      case 'create_class':
        {
          final res = await _handlePlatformAdmin(<String, dynamic>{
            'action': 'admin.create_class',
            'classKey': body['class_key'],
            'label': body['label'],
            'sheetName': body['sheet_name'],
            'standard': body['standard'] ?? body['label'],
            'section': body['section'] ?? '',
            'reportGroup': body['report_group'] ?? '',
            'sortOrder': body['sort_order'] ?? 0,
          });
          return <String, dynamic>{'success': true, ...res};
        }
      case 'set_teacher_classes':
        {
          await _handlePlatformAdmin(<String, dynamic>{
            'action': 'admin.update_teacher',
            'teacherId': body['teacher_id'],
            'allowedClasses': body['allowed_classes'] ?? const <String>[],
          });
          return <String, dynamic>{
            'success': true,
            'allowed_classes': body['allowed_classes'],
          };
        }
      case 'set_teacher_active':
        {
          await _handlePlatformAdmin(<String, dynamic>{
            'action': 'admin.update_teacher',
            'teacherId': body['teacher_id'],
            'isActive': body['is_active'] == true,
          });
          return <String, dynamic>{'success': true};
        }
      default:
        throw PostgrestException(message: 'Unknown action: $action');
    }
  }

  Future<Map<String, dynamic>> _handlePasswordResetOtp(
    Map<String, dynamic> body,
  ) async {
    final remote = await _tryCallableCloudFunction(
      'psm-password-reset-otp',
      body,
    );
    if (remote != null) return remote;
    throw const PostgrestException(
      message: 'SMS OTP password reset requires the Firebase Cloud Function psmEdgeFunction with MSG91 secrets configured, or ask your School Admin / Developer to reset your password.',
    );
  }
}
