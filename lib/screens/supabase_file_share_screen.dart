import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/firebase_backend_client.dart';
import '../services/psm_file_export_helper.dart';
import '../services/school_name_language_service.dart';

class _QueuedBeamFile {
  final String name;
  final int size;
  final String mimeType;
  final Uint8List bytes;
  String status; // '⏳', '📤', '✅'

  _QueuedBeamFile({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.bytes,
    this.status = '⏳',
  });
}

class _ReceivedBeamFile {
  final String name;
  final int size;
  final String mimeType;
  final Uint8List bytes;

  const _ReceivedBeamFile({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.bytes,
  });
}

/// 100% Native Flutter/Dart School File & Text Sharing Studio
/// (`<School Name> File Sharing`).
/// Works seamlessly across iOS (iPhone/iPad), Android, Web, and Desktop
/// with zero HTML/iframe/WebRTC-CDN dependencies.
class SupabaseFileShareScreen extends StatefulWidget {
  const SupabaseFileShareScreen({
    super.key,
    this.profile = const <String, dynamic>{},
    this.embedded = false,
    this.schoolNameOverride,
  });

  final Map<String, dynamic> profile;
  final bool embedded;
  final String? schoolNameOverride;

  @override
  State<SupabaseFileShareScreen> createState() =>
      _SupabaseFileShareScreenState();
}

class _SupabaseFileShareScreenState extends State<SupabaseFileShareScreen> {
  static const int _firestoreChunkSize = 180 * 1024; // 180 KB raw -> ~240 KB B64

  static const List<String> _gujaratWords = <String>[
    'girnar',
    'somnath',
    'dwarka',
    'sabarmati',
    'kutch',
    'patola',
    'navratri',
    'garba',
    'surya',
    'narmada',
    'sardar',
    'bapu',
    'karnavati',
    'valsad',
    'rajkot',
    'surat',
    'morbi',
    'pavagadh',
    'ambaji',
    'modhera',
    'lothal',
    'saputara',
    'kesar',
    'anand',
  ];

  static const List<String> _techWords = <String>[
    'alpha',
    'beam',
    'cloud',
    'delta',
    'echo',
    'flash',
    'grid',
    'hive',
    'indigo',
    'jade',
    'kite',
    'luna',
    'matrix',
    'nova',
    'orbit',
    'pixel',
    'quark',
    'relay',
    'surge',
    'theta',
    'ultra',
    'vortex',
    'wave',
    'zenith',
  ];

  final TextEditingController _senderTextCtrl = TextEditingController();
  final TextEditingController _senderCodeCtrl = TextEditingController();
  final TextEditingController _receiveCodeCtrl = TextEditingController();

  String _langMode = 'bi'; // 'bi', 'gu', 'en'
  String _resolvedSchoolName = '';
  final List<_QueuedBeamFile> _selectedFiles = <_QueuedBeamFile>[];
  String _activeShareCode = '';
  bool _isUploading = false;
  double _uploadProgress = 0;
  String _uploadStatus = '';
  String _uploadSpeedText = 'Native Dart Cloud Relay (iOS • Android • Desktop Ready)';

  bool _isDownloading = false;
  bool _liveAutoReceive = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  String _downloadBytesText = '0 B / 0 B';
  String _downloadMessage = '';
  bool _downloadHasError = false;
  String _receivedTextNote = '';
  String _lastReceivedUpdatedAt = '';
  final List<_ReceivedBeamFile> _receivedFiles = <_ReceivedBeamFile>[];

  List<Map<String, dynamic>> _recentSchoolShares = <Map<String, dynamic>>[];
  bool _loadingRecent = false;

  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _senderRoomSub;
  StreamSubscription<fs.DocumentSnapshot<Map<String, dynamic>>>? _receiverRoomSub;

  fs.FirebaseFirestore get _db => fs.FirebaseFirestore.instance;

  String get _schoolShareTitle {
    final override = (widget.schoolNameOverride ?? '').trim();
    final baseName = override.isNotEmpty
        ? override
        : _resolvedSchoolName.trim().isNotEmpty
            ? _resolvedSchoolName.trim()
            : '${widget.profile['school_name_gu'] ?? widget.profile['school_name'] ?? widget.profile['schoolName'] ?? 'School'}'
                .trim();
    if (baseName.isEmpty) return 'School File Sharing';
    return '$baseName File Sharing';
  }

  @override
  void initState() {
    super.initState();
    _generateCode(useGujaratPool: true);
    _senderTextCtrl.addListener(_onSenderInputChanged);
    _senderCodeCtrl.addListener(_onSenderInputChanged);
    _loadSchoolNameAndRecentShares();
    _sweepExpiredRooms();
  }

  @override
  void dispose() {
    // Leaving the screen before anyone received it: remove it from the server.
    if (_activeShareCode.isNotEmpty && !_activeShareReceived) {
      _deleteRoom(_activeShareCode);
    }
    _senderRoomSub?.cancel();
    _receiverRoomSub?.cancel();
    _senderTextCtrl.dispose();
    _senderCodeCtrl.dispose();
    _receiveCodeCtrl.dispose();
    super.dispose();
  }

  /// True once the receiver got the files (the room is then deleted).
  bool _activeShareReceived = false;

  /// File Share only passes files through: a room (and every chunk) is
  /// deleted as soon as it is received, when the sender stops, or after
  /// [_roomMaxAge] if nobody received it. Nothing is kept on the server.
  static const Duration _roomMaxAge = Duration(minutes: 15);

  /// Largest total size of one share. Files pass through Firestore in
  /// 180 KB pieces; 100 MB ≈ 570 writes, which keeps File Share inside the
  /// Firebase free tier for normal school use. (Phones also hold the whole
  /// file in memory, so much larger files would not work reliably.)
  static const int _maxShareBytes = 100 * 1024 * 1024;

  Future<void> _deleteRoom(String code) async {
    if (code.isEmpty) return;
    try {
      final roomRef = _db.collection('file_beam_rooms').doc(code);
      final chunks = await roomRef.collection('chunks').get();
      var batch = _db.batch();
      var n = 0;
      for (final d in chunks.docs) {
        batch.delete(d.reference);
        if (++n >= 400) {
          await batch.commit();
          batch = _db.batch();
          n = 0;
        }
      }
      batch.delete(roomRef);
      await batch.commit();
    } catch (_) {
      // Best effort; the expiry sweep removes anything left behind.
    }
  }

  /// Removes rooms nobody received within [_roomMaxAge] (any school).
  Future<void> _sweepExpiredRooms() async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(_roomMaxAge).toIso8601String();
      final old = await _db
          .collection('file_beam_rooms')
          .where('created_at', isLessThan: cutoff)
          .limit(50)
          .get();
      for (final d in old.docs) {
        await _deleteRoom(d.id);
      }
    } catch (_) {}
  }

  void _onSenderInputChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSchoolNameAndRecentShares() async {
    try {
      final client = Supabase.instance.client;
      final schoolRef = await SchoolNameLanguageService.currentSchoolRef(client);
      final lang = await SchoolNameLanguageService.loadLanguage(schoolRef: schoolRef);
      final ctx = await SchoolNameLanguageService.loadCurrentSchoolContext(client);
      final name = SchoolNameLanguageService.resolveSchoolName(
        language: lang,
        profile: widget.profile,
        schoolContext: ctx,
        fallbackEnglish:
            '${widget.profile['school_name_en'] ?? widget.profile['school_name'] ?? widget.profile['schoolName'] ?? 'School'}'
                .trim(),
      );
      if (mounted && name.trim().isNotEmpty) {
        setState(() => _resolvedSchoolName = name.trim());
      }
    } catch (_) {}
    await _loadRecentSchoolShares();
  }

  String _normalizeShareCode(String rawInput) {
    if (rawInput.trim().isEmpty) return '';
    var str = rawInput.trim();
    try {
      if (str.toLowerCase().startsWith('http') && str.contains('code=')) {
        final uri = Uri.parse(str);
        str = uri.queryParameters['code'] ?? str;
      }
    } catch (_) {}

    const gujDigits = '૦૧૨૩૪૫૬૭૮૯';
    const hinDigits = '०१२३४५६७८९';
    for (var i = 0; i < 10; i++) {
      str = str.replaceAll(gujDigits[i], '$i').replaceAll(hinDigits[i], '$i');
    }

    return str
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _generateCode({required bool useGujaratPool}) {
    final rng = Random();
    final pool = useGujaratPool ? _gujaratWords : _techWords;
    final word = pool[rng.nextInt(pool.length)];
    final numPart = 10 + rng.nextInt(90);
    _senderCodeCtrl.text = '$word-$numPart';
    if (mounted) setState(() {});
  }

  String _inferMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'pdf': 'application/pdf',
      'txt': 'text/plain;charset=utf-8',
      'csv': 'text/csv;charset=utf-8',
      'html': 'text/html;charset=utf-8',
      'json': 'application/json',
      'zip': 'application/zip',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  bool _isImageMime(String mime, String name) {
    final m = mime.toLowerCase();
    final ext = name.split('.').last.toLowerCase();
    return m.startsWith('image/') ||
        const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(ext);
  }

  bool _isTextMime(String mime, String name) {
    final m = mime.toLowerCase();
    final ext = name.split('.').last.toLowerCase();
    return m.startsWith('text/') ||
        m.contains('json') ||
        const <String>{'txt', 'csv', 'json', 'md'}.contains(ext);
  }

  String _fmtSize(num bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var val = bytes.toDouble();
    var idx = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx++;
    }
    return '${val.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
  }

  void _notify(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor:
            isError ? const Color(0xFFFF4D6D) : const Color(0xFF0099AD),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      int added = 0;
      final skipped = <String>[];
      var total = _selectedFiles.fold<int>(0, (a, f) => a + f.size);
      setState(() {
        for (final f in result.files) {
          final bytes = f.bytes;
          if (bytes == null) continue;
          if (total + bytes.length > _maxShareBytes) {
            skipped.add(f.name);
            continue;
          }
          total += bytes.length;
          final exists = _selectedFiles
              .any((x) => x.name == f.name && x.size == bytes.length);
          if (!exists) {
            _selectedFiles.add(
              _QueuedBeamFile(
                name: f.name,
                size: bytes.length,
                mimeType: _inferMimeType(f.name),
                bytes: bytes,
              ),
            );
            added++;
          }
        }
      });
      if (skipped.isNotEmpty) {
        _notify('⚠ એક વખતમાં કુલ ${_fmtSize(_maxShareBytes)} સુધી જ મોકલી શકાય — ઉમેરાઈ નહીં: ${skipped.join(', ')}',
            isError: true);
      } else if (added > 0) {
        _notify('📄 $added ફાઇલ ઉમેરાઈ ગઈ (Added $added files)');
      }
    } catch (e) {
      _notify('ફાઇલ પસંદ કરવામાં ભૂલ: $e', isError: true);
    }
  }

  void _loadDemoFile() {
    final sampleText = <String>[
      '॥ શ્રી ગણેશાય નમઃ ॥',
      '$_schoolShareTitle — ડાયરેક્ટ ફાઇલ અને ટેક્સ્ટ ટ્રાન્સફર ટેસ્ટ ફાઇલ',
      '------------------------------------------------------------',
      'આ ફાઇલ Android, iPhone (iOS) અને PC વચ્ચે 100% Native Dart દ્વારા સીધી ટ્રાન્સફર થઈ છે.',
      'શાળા: $_schoolShareTitle',
    ].join('\r\n');
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$sampleText'));
    setState(() {
      const demoName = 'ગુજરાતી_માહિતી_પત્રક_Demo.txt';
      if (!_selectedFiles.any((f) => f.name == demoName)) {
        _selectedFiles.add(
          _QueuedBeamFile(
            name: demoName,
            size: bytes.length,
            mimeType: 'text/plain;charset=utf-8',
            bytes: bytes,
          ),
        );
      }
      if (_senderTextCtrl.text.trim().isEmpty) {
        _senderTextCtrl.text =
            'જય શ્રી કૃષ્ણ! આ સાથે $_schoolShareTitle મારફતે ફાઇલ અને ટેક્સ્ટ સંદેશ મોકલેલ છે.';
      }
    });
    _notify('✨ ડેમો ગુજરાતી ફાઇલ અને ટેક્સ્ટ ઉમેરાઈ ગયા!');
  }

  void _clearQueue() {
    setState(() {
      _selectedFiles.clear();
      _senderTextCtrl.clear();
    });
    _notify('ફાઇલ લિસ્ટ ક્લિયર કર્યું (Cleared queue)');
  }

  Future<void> _nativeShareDirect() async {
    final note = _senderTextCtrl.text.trim();
    if (_selectedFiles.isEmpty && note.isEmpty) {
      _notify('કૃપા કરીને પહેલાં ફાઇલ પસંદ કરો અથવા ટેક્સ્ટ લખો!', isError: true);
      return;
    }
    try {
      final xFiles = _selectedFiles
          .map((f) => XFile.fromData(f.bytes, name: f.name, mimeType: f.mimeType))
          .toList();
      await SharePlus.instance.share(
        ShareParams(
          text: note.isEmpty ? null : note,
          files: xFiles.isEmpty ? null : xFiles,
          title: _schoolShareTitle,
        ),
      );
    } catch (e) {
      _notify('Direct Share માટે નીચે "🚀 શેર ચાલુ કરો" વાપરો.');
    }
  }

  /// Pure Native Flutter Share Code & Link Card Dialog (replaces the old HTML asset popup,
  /// 100% compatible with iOS Safari, iPhone, iPad, Android, and Desktop).
  Future<void> _showNativeShareCardDialog([String? customCode]) async {
    final code = _normalizeShareCode(
      customCode ?? (_activeShareCode.isNotEmpty ? _activeShareCode : _senderCodeCtrl.text),
    );
    if (code.isEmpty) {
      _notify('કૃપા કરીને પહેલાં શેર કોડ જનરેટ કરો!', isError: true);
      return;
    }
    final shareSummary =
        '⚡ $_schoolShareTitle\n🔑 શેર કોડ (Share Code): $code\n(એપમાં File Sharing ખોલી કોડ "$code" નાખી Receive દબાવો)';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1421),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2A4070), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.qr_code_2_rounded, color: Color(0xFF00E5FF), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _schoolShareTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF060A12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Text(
                      'સામેવાળાના iPhone (iOS), Android કે PC માં આ શેર કોડ નાખો:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8AA0C0),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      code,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00FFA3),
                        fontFamily: 'monospace',
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x2600FFA3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '✔ iOS • Android • Windows • Mac Native Dart Ready',
                        style: TextStyle(
                          color: Color(0xFF00FFA3),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      _notify('✔ શેર કોડ કોપી થઈ ગયો: $code');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text(
                      '📋 કોડ કોપી કરો',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF131C2E),
                      foregroundColor: const Color(0xFF00FFA3),
                    ),
                    onPressed: () async {
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            text: shareSummary,
                            title: _schoolShareTitle,
                          ),
                        );
                      } catch (_) {
                        Clipboard.setData(ClipboardData(text: shareSummary));
                        _notify('✔ શેર વિગત કોપી થઈ ગઈ!');
                      }
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 17),
                    label: const Text(
                      '📲 શેર કરો (WhatsApp / iOS)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('બંધ કરો (Close)', style: TextStyle(color: Color(0xFF8AA0C0))),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRecentSchoolShares() async {
    setState(() => _loadingRecent = true);
    try {
      final schoolRef = await _resolveSchoolRef();
      if (schoolRef.isEmpty) {
        if (mounted) setState(() => _loadingRecent = false);
        return;
      }
      final snap = await _db
          .collection('file_beam_rooms')
          .where('school_ref', isEqualTo: schoolRef)
          .get();
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['code'] ??= d.id;
        return m;
      }).toList();
      list.sort((a, b) =>
          '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
      if (mounted) {
        setState(() {
          _recentSchoolShares = list.take(12).toList();
          _loadingRecent = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<String> _resolveSchoolRef() async {
    final fromProfile =
        '${widget.profile['school_ref'] ?? widget.profile['schoolRef'] ?? ''}'
            .trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    try {
      final ref = await Supabase.instance.client.rpc('current_school_ref');
      return '${ref ?? ''}'.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _startShare() async {
    final note = _senderTextCtrl.text.trim();
    final totalSize = _selectedFiles.fold<int>(0, (a, f) => a + f.size);
    if (totalSize > _maxShareBytes) {
      _notify('કુલ ફાઇલ ${_fmtSize(totalSize)} છે — એક વખતમાં ${_fmtSize(_maxShareBytes)} સુધી જ મોકલી શકાય. કેટલીક ફાઇલ કાઢી નાખો.',
          isError: true);
      return;
    }
    if (_selectedFiles.isEmpty && note.isEmpty) {
      _notify(
        'કૃપા કરીને પહેલાં ફાઇલ પસંદ કરો અથવા ટેક્સ્ટ બોક્સમાં કંઈક લખો!',
        isError: true,
      );
      return;
    }
    final code = _normalizeShareCode(_senderCodeCtrl.text);
    if (code.isEmpty) {
      _notify('કોડમાં ઓછામાં ઓછો એક અક્ષર કે અંક હોવો જરૂરી છે.', isError: true);
      return;
    }
    _senderCodeCtrl.text = code;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.02;
      _uploadStatus = 'લાઇવ રૂમ તૈયાર થઈ રહ્યો છે (Preparing room "$code")…';
      for (final f in _selectedFiles) {
        f.status = '⏳';
      }
    });

    final sw = Stopwatch()..start();
    try {
      final schoolRef = await _resolveSchoolRef();
      final senderName =
          '${widget.profile['teacher_name'] ?? widget.profile['admin_name'] ?? 'School User'}'
              .trim();
      final totalBytes = _selectedFiles.fold<int>(0, (s, f) => s + f.size);
      final roomRef = _db.collection('file_beam_rooms').doc(code);

      try {
        final oldChunks = await roomRef.collection('chunks').get();
        var delBatch = _db.batch();
        var delOps = 0;
        for (final doc in oldChunks.docs) {
          delBatch.delete(doc.reference);
          delOps++;
          if (delOps >= 400) {
            await delBatch.commit();
            delBatch = _db.batch();
            delOps = 0;
          }
        }
        if (delOps > 0) await delBatch.commit();
      } catch (_) {}

      final fileManifest = <Map<String, dynamic>>[];
      int sentBytes = 0;

      for (var i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        setState(() {
          file.status = '📤';
          _uploadStatus =
              'મોકલાઈ રહ્યું છે (${i + 1}/${_selectedFiles.length}): ${file.name}';
        });

        int chunkCount = 0;
        for (var offset = 0;
            offset < file.bytes.length;
            offset += _firestoreChunkSize) {
          final end = min(offset + _firestoreChunkSize, file.bytes.length);
          final slice = file.bytes.sublist(offset, end);
          final b64 = base64Encode(slice);
          final chunkId =
              'f${i.toString().padLeft(3, '0')}_c${chunkCount.toString().padLeft(5, '0')}';

          await roomRef.collection('chunks').doc(chunkId).set(<String, dynamic>{
            'fileIndex': i,
            'seq': chunkCount,
            'b64': b64,
            'byteLen': slice.length,
          });

          chunkCount++;
          sentBytes += slice.length;
          final elapsedSec = max(0.1, sw.elapsedMilliseconds / 1000.0);
          final speedBps = sentBytes / elapsedSec;
          if (mounted) {
            setState(() {
              _uploadProgress = totalBytes > 0
                  ? (sentBytes / totalBytes).clamp(0.05, 0.99)
                  : 1.0;
              _uploadSpeedText =
                  'Native Dart Cloud Relay (HTTPS/443) · ${_fmtSize(speedBps)}/s';
            });
          }
        }

        fileManifest.add(<String, dynamic>{
          'fileIndex': i,
          'name': file.name,
          'size': file.size,
          'mime': file.mimeType,
          'chunkCount': chunkCount,
        });

        if (mounted) {
          setState(() {
            file.status = '✅';
          });
        }
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      await roomRef.set(<String, dynamic>{
        'code': code,
        'school_ref': schoolRef,
        'school_name': _schoolShareTitle,
        'sender_name': senderName,
        'text_note': note,
        'total_files': _selectedFiles.length,
        'total_bytes': totalBytes,
        'files': fileManifest,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      _activeShareReceived = false;
      _senderRoomSub?.cancel();
      _senderRoomSub = roomRef.snapshots().listen((snap) {
        if (!mounted) return;
        if (!snap.exists) {
          // The receiver got everything and deleted it from the server.
          if (_activeShareCode == code) {
            setState(() {
              _activeShareReceived = true;
              _uploadSpeedText = '✔ સામેવાળાએ ફાઇલ/ટેક્સ્ટ મેળવી લીધી — સર્વર પરથી આપોઆપ ડિલીટ થઈ ગઈ.';
            });
          }
          return;
        }
        final d = snap.data();
        final recvCount = int.tryParse('${d?['receiver_downloads'] ?? 0}') ?? 0;
        if (recvCount > 0) {
          setState(() {
            _uploadSpeedText =
                '✔ સામેવાળાએ $recvCount વાર ફાઇલ/ટેક્સ્ટ મેળવી લીધી છે!';
          });
        }
      });

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _activeShareCode = code;
        _uploadProgress = 1.0;
        _uploadStatus = _selectedFiles.isNotEmpty
            ? '✔ લાઇવ છે! સામેવાળાના iPhone/Android/PC માં કોડ "$code" નાખી Receive દબાવો! (મળતાં જ સર્વર પરથી ડિલીટ થશે, ${_roomMaxAge.inMinutes} મિનિટમાં કોઈ ન લે તો પણ ડિલીટ)'
            : '✔ તમારો ટેક્સ્ટ મેસેજ લાઇવ છે — કોડ "$code" નાખી Receive દબાવો! (મળતાં જ ડિલીટ થશે)';
        if (_receiveCodeCtrl.text.trim().isEmpty) {
          _receiveCodeCtrl.text = code;
        }
      });
      _loadRecentSchoolShares();
      _notify('🚀 લાઇવ શેર કોડ તૈયાર છે: $code');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '❌ ભૂલ: $e';
      });
      _notify('શેર શરૂ કરવામાં ભૂલ: $e', isError: true);
    }
  }

  void _stopSharing() {
    _senderRoomSub?.cancel();
    _senderRoomSub = null;
    if (_activeShareCode.isNotEmpty && !_activeShareReceived) {
      _deleteRoom(_activeShareCode);
    }
    setState(() {
      _activeShareCode = '';
      _isUploading = false;
      _uploadProgress = 0;
      _uploadStatus = '';
    });
    _notify('શેરિંગ સેશન રીસેટ કર્યું (Reset session)');
  }

  void _toggleLiveAutoReceive(bool enabled) {
    _receiverRoomSub?.cancel();
    _receiverRoomSub = null;
    setState(() => _liveAutoReceive = enabled);
    if (!enabled) return;

    final code = _normalizeShareCode(_receiveCodeCtrl.text);
    if (code.isEmpty) {
      _notify('ઓટો-રિસીવ માટે પહેલાં શેર કોડ લખો!', isError: true);
      setState(() => _liveAutoReceive = false);
      return;
    }
    _receiverRoomSub =
        _db.collection('file_beam_rooms').doc(code).snapshots().listen((snap) {
      if (!mounted || !snap.exists) return;
      final updatedAt = '${snap.data()?['updated_at'] ?? ''}';
      if (updatedAt.isNotEmpty &&
          updatedAt != _lastReceivedUpdatedAt &&
          !_isDownloading) {
        _lastReceivedUpdatedAt = updatedAt;
        _startReceive(code);
      }
    });
    _notify('📡 કોડ "$code" માટે લાઇવ ઓટો-રિસીવ ચાલુ થયું!');
  }

  Future<void> _startReceive([String? overrideCode]) async {
    final raw = overrideCode ?? _receiveCodeCtrl.text;
    final code = _normalizeShareCode(raw);
    if (code.isEmpty) {
      setState(() {
        _downloadHasError = true;
        _downloadMessage =
            '⚠ કૃપા કરીને પહેલાં મોકલનારનો શેર કોડ નાખો (Please enter the share code).';
      });
      _notify('કૃપા કરીને શેર કોડ નાખો!', isError: true);
      return;
    }
    _receiveCodeCtrl.text = code;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.05;
      _downloadStatus = '"$code" સાથે જોડાઈ રહ્યું છે (Connecting)…';
      _downloadMessage = '';
      _downloadHasError = false;
      _receivedTextNote = '';
      _receivedFiles.clear();
    });

    try {
      final roomRef = _db.collection('file_beam_rooms').doc(code);
      final roomSnap = await roomRef.get();
      if (!roomSnap.exists || roomSnap.data() == null) {
        setState(() {
          _isDownloading = false;
          _downloadHasError = true;
          _downloadMessage =
              '❌ કોડ "$code" મળ્યો નહીં: મોકલનારે (Sender) "🚀 શેર ચાલુ કરો" બટન દબાવ્યું છે અને કોડ સાચો છે તેની ખાતરી કરો.';
        });
        return;
      }

      final data = roomSnap.data()!;
      _lastReceivedUpdatedAt = '${data['updated_at'] ?? ''}';
      final textNote = '${data['text_note'] ?? ''}'.trim();
      final totalBytes = int.tryParse('${data['total_bytes'] ?? 0}') ?? 0;
      final rawFiles = data['files'] is List ? data['files'] as List : const [];

      if (textNote.isNotEmpty) {
        setState(() {
          _receivedTextNote = textNote;
        });
      }

      if (rawFiles.isEmpty) {
        // Received: remove it from the server (transfer only, no storage).
        await _deleteRoom(code);
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
          _downloadStatus = '✔ ટેક્સ્ટ મેસેજ સફળતાપૂર્વક મળી ગયો!';
          _downloadMessage =
              '✔ ટેક્સ્ટ મેસેજ મળી ગયો છે! ઉપર "📋 કોપી" બટન દબાવીને કોપી કરો.';
        });
        _notify('🎉 ટેક્સ્ટ મેસેજ મળી ગયો!');
        return;
      }

      final chunkSnap = await roomRef.collection('chunks').get();
      final chunksByFile = <int, List<Map<String, dynamic>>>{};
      for (final doc in chunkSnap.docs) {
        final cData = doc.data();
        final fIdx = int.tryParse('${cData['fileIndex'] ?? 0}') ?? 0;
        (chunksByFile[fIdx] ??= <Map<String, dynamic>>[]).add(cData);
      }

      int receivedBytes = 0;
      final assembled = <_ReceivedBeamFile>[];

      for (var i = 0; i < rawFiles.length; i++) {
        final fMeta = rawFiles[i] is Map
            ? Map<String, dynamic>.from(rawFiles[i] as Map)
            : <String, dynamic>{};
        final fIdx = int.tryParse('${fMeta['fileIndex'] ?? i}') ?? i;
        final fName = '${fMeta['name'] ?? 'file_${i + 1}'}';
        final fMime = _inferMimeType(fName);
        final fileChunks = chunksByFile[fIdx] ?? <Map<String, dynamic>>[];
        fileChunks.sort((a, b) =>
            (int.tryParse('${a['seq'] ?? 0}') ?? 0)
                .compareTo(int.tryParse('${b['seq'] ?? 0}') ?? 0));

        final collectedBytes = <int>[];
        for (final ch in fileChunks) {
          final b64 = '${ch['b64'] ?? ''}';
          if (b64.isNotEmpty) {
            final decoded = base64Decode(b64);
            collectedBytes.addAll(decoded);
            receivedBytes += decoded.length;
          }
        }
        final fullBytes = Uint8List.fromList(collectedBytes);
        assembled.add(
          _ReceivedBeamFile(
            name: fName,
            size: fullBytes.length,
            mimeType: fMime,
            bytes: fullBytes,
          ),
        );

        if (mounted) {
          setState(() {
            _downloadProgress = totalBytes > 0
                ? (receivedBytes / totalBytes).clamp(0.1, 1.0)
                : ((i + 1) / rawFiles.length);
            _downloadBytesText =
                '${_fmtSize(receivedBytes)} / ${_fmtSize(max(totalBytes, receivedBytes))}';
            _downloadStatus =
                'ફાઇલ ${i + 1}/${rawFiles.length}: $fName તૈયાર!';
          });
        }
      }

      // All files are now in this device's memory: delete them from the
      // server right away (transfer only, nothing is stored).
      await _deleteRoom(code);

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _receivedFiles
          ..clear()
          ..addAll(assembled);
        _downloadStatus =
            '✔ બધી ${assembled.length} ફાઇલ સફળતાપૂર્વક મળી ગઈ!';
        _downloadMessage =
            '✔ ${assembled.length} ફાઇલ ડાઉનલોડ માટે તૈયાર છે — નીચે "⬇ સેવ (Save)" દબાવો. (સર્વર પરથી ડિલીટ થઈ ગઈ છે, એટલે આ સ્ક્રીન બંધ કરતા પહેલાં સેવ કરી લો.)';
      });
      _notify('🎉 ટ્રાન્સફર પૂર્ણ (Transfer Complete)!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadHasError = true;
        _downloadMessage = '❌ ભૂલ: $e';
      });
      _notify('ફાઇલ મેળવવામાં ભૂલ: $e', isError: true);
    }
  }

  Future<void> _saveReceivedFile(_ReceivedBeamFile file) async {
    try {
      await PsmFileExportHelper.saveOrShare(
        bytes: file.bytes,
        filename: file.name,
        title: file.name,
        mimeType: file.mimeType,
      );
      _notify('⬇ "${file.name}" સેવ થઈ ગઈ!');
    } catch (e) {
      _notify('સેવ કરવામાં ભૂલ: $e', isError: true);
    }
  }

  Future<void> _saveAllReceivedFiles() async {
    for (final file in _receivedFiles) {
      await _saveReceivedFile(file);
    }
  }

  Future<void> _previewReceivedFile(_ReceivedBeamFile file) async {
    final isImg = _isImageMime(file.mimeType, file.name);
    final isTxt = _isTextMime(file.mimeType, file.name);
    if (!isImg && !isTxt) {
      await _saveReceivedFile(file);
      return;
    }
    String decodedText = '';
    if (isTxt) {
      try {
        decodedText = utf8.decode(file.bytes, allowMalformed: true);
      } catch (_) {
        decodedText = String.fromCharCodes(file.bytes);
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1421),
        title: Text(
          file.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: isImg
              ? InteractiveViewer(
                  child: Image.memory(file.bytes, fit: BoxFit.contain),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    decodedText,
                    style: const TextStyle(
                      color: Color(0xFFDCE7FA),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('બંધ કરો (Close)',
                style: TextStyle(color: Color(0xFF8AA0C0))),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00FFA3),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _saveReceivedFile(file);
            },
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text(
              '⬇ સેવ (Save)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = _selectedFiles.fold<int>(0, (s, f) => s + f.size);
    final hasPayload =
        _selectedFiles.isNotEmpty || _senderTextCtrl.text.trim().isNotEmpty;
    final hasCode = _normalizeShareCode(_senderCodeCtrl.text).isNotEmpty;
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 640;

    final content = Container(
      decoration: const BoxDecoration(
        color: Color(0xFF060A12),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 18,
          isMobile ? 14 : 18,
          isMobile ? 12 : 18,
          48,
        ),
        children: [
          // Top Toolbar
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1421),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFF1E2D47)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded,
                            color: Color(0xFF00FFA3), size: 16),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '100% Native Flutter/Dart • iPhone (iOS) • Android • PC Ready',
                            style: TextStyle(
                              color: Color(0xFF8AA0C0),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF131C2E),
                          foregroundColor: const Color(0xFF00E5FF),
                        ),
                        onPressed: () => _showNativeShareCardDialog(),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                        label: const Text(
                          '📲 શેર કોડ અને લિંક કાર્ડ',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1421),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF2A4070)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildLangBtn('bi', 'ગુજરાતી + EN'),
                            _buildLangBtn('gu', 'ગુજરાતી'),
                            _buildLangBtn('en', 'English'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with School Name + File Sharing
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: isMobile ? 38 : 44,
                      height: isMobile ? 38 : 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF006EFF)],
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x5500E5FF),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('⚡', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _schoolShareTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _langMode == 'en'
                      ? 'Direct School File & Text Sharing • Works Natively on iPhone (iOS), Android & Desktop'
                      : 'શાળાનું ડાયરેક્ટ ફાઇલ અને ટેક્સ્ટ શેરિંગ • iPhone (iOS), Android અને PC માં સીધું કાર્યરત',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8AA0C0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Main Send & Receive Cards (Side-by-Side on Desktop, Stacked on Mobile)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final sendCard = _buildSendCard(
                    totalBytes: totalBytes,
                    hasPayload: hasPayload,
                    hasCode: hasCode,
                    isMobile: isMobile,
                  );
                  final recvCard = _buildReceiveCard(isMobile: isMobile);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: sendCard),
                        const SizedBox(width: 20),
                        Expanded(child: recvCard),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      sendCard,
                      const SizedBox(height: 18),
                      recvCard,
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 20),

          // School Recent Shared Board
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: _buildSchoolRecentSharesCard(),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1421),
        foregroundColor: Colors.white,
        title: Text(
          '⚡ $_schoolShareTitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh recent school shares',
            onPressed: _loadRecentSchoolShares,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E5FF)),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildLangBtn(String code, String label) {
    final active = _langMode == code;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _langMode = code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF006EFF)],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : const Color(0xFF8AA0C0),
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSendCard({
    required int totalBytes,
    required bool hasPayload,
    required bool hasCode,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1421),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E2D47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x2600E5FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x5500E5FF)),
                    ),
                    child: Text(
                      _langMode == 'en' ? '↑ SEND' : '↑ મોકલો · SEND',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(
                    _langMode == 'en'
                        ? 'Share Files & Text'
                        : 'ફાઇલ અને ટેક્સ્ટ શેર કરો',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                    ),
                  )),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDCE7FA),
                  side: const BorderSide(color: Color(0xFF2A4070)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _nativeShareDirect,
                icon: const Icon(Icons.ios_share_rounded, size: 15),
                label: const Text('📲 Direct App Share',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pick Zone
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickFiles,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF131C2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedFiles.isNotEmpty
                      ? const Color(0xFF00FFA3)
                      : const Color(0xFF2A4070),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  const Text('🗂️', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(
                    _langMode == 'en'
                        ? 'Tap here to choose files (Photos, PDF, Excel, ZIP, Videos)'
                        : 'ફાઇલ પસંદ કરવા અહીં ટચ/ક્લિક કરો (Photos, PDF, Excel, Video)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _langMode == 'en'
                        ? 'Or type a Gujarati/English text note below without any file'
                        : 'અથવા નીચે ફાઇલ વગર માત્ર ગુજરાતી/English ટેક્સ્ટ લખીને પણ શેર કરી શકાય',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8AA0C0),
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _langMode == 'en'
                        ? 'Up to ${_fmtSize(_maxShareBytes)} per share • deleted from the server as soon as it is received (or after ${_roomMaxAge.inMinutes} minutes)'
                        : 'એક વખતમાં ${_fmtSize(_maxShareBytes)} સુધી • મળતાં જ સર્વર પરથી ડિલીટ (કોઈ ન લે તો ${_roomMaxAge.inMinutes} મિનિટ પછી)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniDarkBtn('➕ ફાઇલ ઉમેરો (Add)', _pickFiles),
              _miniDarkBtn('✨ ડેમો ફાઇલ (Demo)', _loadDemoFile),
              _miniDarkBtn('🗑 ક્લિયર (Clear)', _clearQueue, isDanger: true),
            ],
          ),

          if (_selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 165),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _selectedFiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) {
                  final f = _selectedFiles[i];
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF060A12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFF1E2D47)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '📄 ${f.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF00FFA3),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _fmtSize(f.size),
                          style: const TextStyle(
                            color: Color(0xFF8AA0C0),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(f.status, style: const TextStyle(fontSize: 13)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0xFFFF4D6D)),
                          onPressed: () =>
                              setState(() => _selectedFiles.removeAt(i)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(
                  '${_selectedFiles.length} ફાઇલ (Files)',
                  style:
                      const TextStyle(color: Color(0xFF8AA0C0), fontSize: 12),
                )),
                Text(
                  'કુલ (Total): ${_fmtSize(totalBytes)}',
                  style:
                      const TextStyle(color: Color(0xFF8AA0C0), fontSize: 12),
                ),
              ],
            ),
          ],

          // Text Beam Box
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF131C2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2D47)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _langMode == 'en'
                      ? '💬 Instant Text / Gujarati Note / URL (Works with or without files)'
                      : '💬 ગુજરાતી કે English ટેક્સ્ટ / લિંક મોકલો (ફાઇલ વગર એકલું ટેક્સ્ટ પણ મોકલી શકાશે)',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _senderTextCtrl,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText:
                        'અહીં ગુજરાતી લખાણ, સરનામું કે લિંક લખો — ફાઇલ સાથે અથવા ફાઇલ વગર પણ મોકલી શકાશે...',
                    hintStyle: const TextStyle(
                        color: Color(0xFF475F82), fontSize: 12.5),
                    filled: true,
                    fillColor: const Color(0xFF060A12),
                    contentPadding: const EdgeInsets.all(10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF2A4070)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Share Code Row
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _langMode == 'en'
                      ? 'Share Code — Auto-generated or type your own'
                      : 'શેર કોડ (Share Code) — ઓટોમેટિક અથવા તમારો પોતાનો લખો',
                  style: const TextStyle(
                    color: Color(0xFF8AA0C0),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Text(
                '૦-૯ / a-z',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _senderCodeCtrl,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF060A12),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF2A4070)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _miniDarkBtn(
                  '🦁 ગુજ.', () => _generateCode(useGujaratPool: true)),
              const SizedBox(width: 6),
              _miniDarkBtn(
                  '🎲 નવો', () => _generateCode(useGujaratPool: false)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'સામેવાળાના iPhone (iOS), Android કે PC માં આ કોડ નાખો અથવા નીચેથી કોપી કરો.',
            style: TextStyle(color: Color(0xFF8AA0C0), fontSize: 11.5),
          ),

          // Start Sharing Button
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xFF131C2E),
                disabledForegroundColor: const Color(0xFF475F82),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (!hasPayload || !hasCode || _isUploading)
                  ? null
                  : _startShare,
              icon: Icon(_isUploading
                  ? Icons.hourglass_top_rounded
                  : Icons.rocket_launch_rounded),
              label: Text(
                _isUploading
                    ? 'અપલોડ થઈ રહ્યું છે (${(_uploadProgress * 100).round()}%)…'
                    : (_activeShareCode.isEmpty
                        ? '🚀 શેર ચાલુ કરો (Start Sharing)'
                        : '📤 ફરીથી અપડેટ / પુશ કરો (Push Update)'),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
              ),
            ),
          ),

          if (_activeShareCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8FA3),
                  side: const BorderSide(color: Color(0x66FF4D6D)),
                ),
                onPressed: _stopSharing,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text(
                  '⏹ શેરિંગ બંધ કરો / નવો કોડ બનાવો (Stop & Reset)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ),
          ],

          if (_isUploading || _uploadStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _uploadStatus,
                    style: const TextStyle(
                      color: Color(0xFF8AA0C0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(_uploadProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 8,
                backgroundColor: const Color(0xFF131C2E),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _uploadSpeedText,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],

          // Live Box
          if (_activeShareCode.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF131C2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A4070)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, color: Color(0xFF00FFA3), size: 10),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'લાઇવ કોડ તૈયાર છે — સામેવાળાના ફોન/PC માં આ કોડ નાખો:',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF060A12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A4070)),
                    ),
                    child: SelectableText(
                      _activeShareCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontFamily: 'monospace',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _miniDarkBtn('📋 કોડ કોપી (Copy Code)', () {
                        Clipboard.setData(
                            ClipboardData(text: _activeShareCode));
                        _notify('✔ શેર કોડ કોપી થઈ ગયો: $_activeShareCode');
                      }),
                      _miniDarkBtn('📲 શેર કાર્ડ (Share Card)', () {
                        _showNativeShareCardDialog(_activeShareCode);
                      }),
                      _miniDarkBtn('📥 અહીં જ ટેસ્ટ (Test Receive)', () {
                        _receiveCodeCtrl.text = _activeShareCode;
                        _startReceive(_activeShareCode);
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveCard({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1421),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E2D47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x2600FFA3),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x5500FFA3)),
                    ),
                    child: Text(
                      _langMode == 'en' ? '↓ RECEIVE' : '↓ મેળવો · RECEIVE',
                      style: const TextStyle(
                        color: Color(0xFF00FFA3),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(
                    _langMode == 'en'
                        ? 'Receive Files & Text'
                        : 'ફાઇલ અને ટેક્સ્ટ મેળવો',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                    ),
                  )),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDCE7FA),
                  side: const BorderSide(color: Color(0xFF2A4070)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  final txt = data?.text ?? '';
                  if (txt.trim().isNotEmpty) {
                    setState(() {
                      _receiveCodeCtrl.text = _normalizeShareCode(txt);
                    });
                    _notify('📋 ક્લિપબોર્ડમાંથી કોડ પેસ્ટ કર્યો!');
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 15),
                label: const Text('📋 પેસ્ટ (Paste Code)',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            _langMode == 'en'
                ? "Paste or type the sender's share code below"
                : 'મોકલનારનો શેર કોડ અહીં લખો અથવા પેસ્ટ કરો',
            style: const TextStyle(
              color: Color(0xFF8AA0C0),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _receiveCodeCtrl,
            style: const TextStyle(
              color: Color(0xFF00FFA3),
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              hintText: 'દા.ત. girnar-42 અહીં લખો…',
              hintStyle:
                  const TextStyle(color: Color(0xFF475F82), fontSize: 13.5),
              filled: true,
              fillColor: const Color(0xFF060A12),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2A4070)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF00FFA3)),
              ),
            ),
            onSubmitted: (_) => _startReceive(),
          ),
          const SizedBox(height: 8),

          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xFF00FFA3),
            title: const Text(
              '📡 લાઇવ ઓટો-રિસીવ (Auto-Receive Updates for this Code)',
              style: TextStyle(
                color: Color(0xFFDCE7FA),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: _liveAutoReceive,
            onChanged: _toggleLiveAutoReceive,
          ),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isDownloading ? null : () => _startReceive(),
              icon: Icon(_isDownloading
                  ? Icons.downloading_rounded
                  : Icons.download_rounded),
              label: Text(
                _isDownloading
                    ? 'કનેક્ટ થઈ રહ્યું છે (Receiving)…'
                    : '📥 ફાઇલ અને ટેક્સ્ટ મેળવો (Receive Now)',
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
              ),
            ),
          ),

          if (_isDownloading || _downloadStatus.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _downloadStatus,
                    style: const TextStyle(
                      color: Color(0xFF8AA0C0),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(_downloadProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFF00FFA3),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 8,
                backgroundColor: const Color(0xFF131C2E),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF00FFA3)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _downloadBytesText,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],

          // Received Text Note Box
          if (_receivedTextNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14FBBF24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x73FBBF24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '📩 મળેલો ટેક્સ્ટ મેસેજ (Received Text Note):',
                          style: TextStyle(
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      _miniDarkBtn('📋 કોપી (Copy)', () {
                        Clipboard.setData(
                            ClipboardData(text: _receivedTextNote));
                        _notify('✔ મળેલો ટેક્સ્ટ મેસેજ કોપી થઈ ગયો!');
                      }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF060A12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E2D47)),
                    ),
                    child: SelectableText(
                      _receivedTextNote,
                      style: const TextStyle(
                        color: Color(0xFFDCE7FA),
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Received Files List
          if (_receivedFiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            if (_receivedFiles.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _saveAllReceivedFiles,
                    icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                    label: Text(
                      '⬇ બધી ${_receivedFiles.length} ફાઇલ એકસાથે સેવ કરો (Save All)',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            for (final rf in _receivedFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131C2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x7300FFA3)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF060A12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF1E2D47)),
                            ),
                            child: const Center(
                              child: Text('📄', style: TextStyle(fontSize: 19)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isMobile ? 180 : 230,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rf.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF00FFA3),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${_fmtSize(rf.size)} · ${rf.mimeType.split('/').last.toUpperCase()}',
                                  style: const TextStyle(
                                    color: Color(0xFF8AA0C0),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isImageMime(rf.mimeType, rf.name) ||
                              _isTextMime(rf.mimeType, rf.name)) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00E5FF),
                                side: const BorderSide(color: Color(0xFF2A4070)),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _previewReceivedFile(rf),
                              child: const Text(
                                '👁 જુઓ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 11.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FFA3),
                              foregroundColor: Colors.black,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _saveReceivedFile(rf),
                            icon: const Icon(Icons.download_rounded, size: 15),
                            label: const Text(
                              '⬇ સેવ (Save)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],

          if (_downloadMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _downloadMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _downloadHasError
                    ? const Color(0xFFFF4D6D)
                    : const Color(0xFF00FFA3),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSchoolRecentSharesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1421),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E2D47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🏫 $_schoolShareTitle — તાજેતરમાં શેર થયેલ ફાઇલો (1-Click Receive)',
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _loadRecentSchoolShares,
                icon: const Icon(Icons.refresh_rounded,
                    color: Color(0xFF00E5FF), size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_loadingRecent)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentSchoolShares.isEmpty)
            const Text(
              'હજુ સુધી શાળામાં કોઈ લાઇવ ફાઇલ શેર થઈ નથી. ઉપરથી ફાઇલ કે ટેક્સ્ટ શેર કરો!',
              style: TextStyle(color: Color(0xFF8AA0C0), fontSize: 12.5),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _recentSchoolShares.map((item) {
                final code = '${item['code'] ?? ''}';
                final filesCount =
                    int.tryParse('${item['total_files'] ?? 0}') ?? 0;
                final sender = '${item['sender_name'] ?? 'School'}';
                final note = '${item['text_note'] ?? ''}'.trim();
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _receiveCodeCtrl.text = code;
                    _startReceive(code);
                  },
                  child: Container(
                    width: 240,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131C2E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A4070)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '🔑 $code',
                              style: const TextStyle(
                                color: Color(0xFF00FFA3),
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            Flexible(child: Text(
                              '$filesCount ફાઇલ',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '👤 $sender',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFDCE7FA),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (note.isNotEmpty)
                          Text(
                            '💬 $note',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8AA0C0),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _miniDarkBtn(String label, VoidCallback onTap,
      {bool isDanger = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF131C2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDanger
                ? const Color(0x66FF4D6D)
                : const Color(0xFF2A4070),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDanger
                ? const Color(0xFFFF8FA3)
                : const Color(0xFFDCE7FA),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
