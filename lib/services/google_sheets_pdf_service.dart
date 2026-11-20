import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Developer-managed Google Sheets + Apps Script PDF Converter Service.
///
/// - Configured ONLY in the Developer Panel (never shown on Admin or Teacher screens).
/// - Supports multiple comma-separated Apps Script Web App URLs so 50+ concurrent
///   teachers are automatically load-balanced across multiple Gmail/Apps Script
///   endpoints.
/// - If no URL is configured yet (or if all endpoints are busy when 50+ teachers
///   print at the exact same second), `XlsxBrowserPrintService` silently and
///   automatically falls back to the local Browser Print Template Engine so
///   zero teachers ever see an error or setup popup.
class GoogleSheetsPdfService {
  const GoogleSheetsPdfService();

  static const String _prefsKey = 'psm_dev_google_sheets_pdf_urls_v1';
  static const String _firestoreCollection = 'app_config';
  static const String _firestoreDoc = 'developer_pdf_settings';

  /// Developer can also hardcode one or more comma-separated URLs here or via --dart-define.
  static const String _envScriptUrls = String.fromEnvironment(
    'GOOGLE_SHEETS_PDF_URL',
    defaultValue: '',
  );

  static String? _cachedRawUrls;
  static DateTime? _lastFetchTime;
  static final math.Random _random = math.Random();

  static const String appsScriptSourceCode = r"""/**
 * ============================================================================
 * PROFESSIONAL SCHOOL MANAGEMENT — FREE GOOGLE SHEETS PDF CONVERTER (Apps Script)
 * ============================================================================
 * Converts populated Hajari Patrak & Result (.xlsx) workbooks into exact PDFs
 * using Google Drive & Google Sheets at ₹0 cost.
 * ============================================================================
 */

function _ensureOAuthScopes() {
  DriveApp.getRootFolder();
  SpreadsheetApp.getActive();
  UrlFetchApp.fetch('https://www.google.com');
}

function doGet(e) {
  var action = (e && e.parameter && e.parameter.action) ? String(e.parameter.action) : 'ping';
  return _jsonResponse({
    status: 'ok',
    action: action,
    message: 'PSM Google Sheets PDF Converter is active and ready.'
  });
}

function doPost(e) {
  var tempFileId = null;
  var keepSheet = false;
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return _jsonResponse({ status: 'error', message: 'Empty POST body.' });
    }

    var payload = JSON.parse(e.postData.contents);
    var action = String(payload.action || 'convertToPdf');

    if (action === 'ping') {
      return _jsonResponse({
        status: 'ok',
        message: 'PSM Google Sheets PDF Converter connected successfully!'
      });
    }

    var workbookBase64 = String(payload.workbookBase64 || '').trim();
    if (!workbookBase64) {
      return _jsonResponse({ status: 'error', message: 'Missing workbookBase64.' });
    }

    var baseName = String(payload.filename || 'PSM_Document').replace(/\.pdf$/i, '').replace(/\.xlsx$/i, '');
    var uniqueSuffix = new Date().getTime() + '_' + Math.floor(Math.random() * 1000000);
    var tempName = baseName + '_' + uniqueSuffix;
    var paperSize = String(payload.paperSize || 'a4').toLowerCase();
    var portrait = payload.portrait === true || String(payload.portrait) === 'true';
    keepSheet = payload.keepSheetInDrive === true || String(payload.keepSheetInDrive) === 'true';
    var onlyOpenSheet = payload.onlyOpenSheet === true || String(payload.onlyOpenSheet) === 'true';

    var token = ScriptApp.getOAuthToken();
    var metadata = {
      name: keepSheet ? baseName : tempName,
      mimeType: 'application/vnd.google-apps.spreadsheet'
    };
    var boundary = '-------psm_xlsx_boundary_' + uniqueSuffix;
    var delimiter = '\r\n--' + boundary + '\r\n';
    var closeDelim = '\r\n--' + boundary + '--';

    var multipartBody = Utilities.newBlob(
      delimiter +
      'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify(metadata) +
      delimiter +
      'Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n' +
      'Content-Transfer-Encoding: base64\r\n\r\n' +
      workbookBase64 +
      closeDelim
    ).getBytes();

    var uploadResp = UrlFetchApp.fetch(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink',
      {
        method: 'post',
        contentType: 'multipart/related; boundary=' + boundary,
        payload: multipartBody,
        headers: { Authorization: 'Bearer ' + token },
        muteHttpExceptions: true
      }
    );

    if (uploadResp.getResponseCode() < 200 || uploadResp.getResponseCode() >= 300) {
      return _jsonResponse({
        status: 'error',
        message: 'Drive XLSX-to-Sheet conversion failed (' + uploadResp.getResponseCode() + '): ' + uploadResp.getContentText()
      });
    }

    var uploadJson = JSON.parse(uploadResp.getContentText());
    tempFileId = uploadJson.id;
    var sheetUrl = uploadJson.webViewLink || ('https://docs.google.com/spreadsheets/d/' + tempFileId + '/edit');

    var logoBase64 = String(payload.logoBase64 || '').trim();
    if (logoBase64) {
      try {
        var ss = SpreadsheetApp.openById(tempFileId);
        var firstSheet = ss.getSheets()[0];
        if (firstSheet) {
          var logoBytes = Utilities.base64Decode(logoBase64);
          var logoBlob = Utilities.newBlob(logoBytes, 'image/png', 'school_logo.png');
          var targetRow = Number(payload.logoRow || 4);
          var targetCol = Number(payload.logoCol || 4);
          var offsetX = Number(payload.logoOffsetX || 12);
          var offsetY = Number(payload.logoOffsetY || 6);
          var img = firstSheet.insertImage(logoBlob, targetCol, targetRow, offsetX, offsetY);
          if (payload.logoWidthPx && payload.logoHeightPx) {
            img.setWidth(Number(payload.logoWidthPx));
            img.setHeight(Number(payload.logoHeightPx));
          }
          SpreadsheetApp.flush();
        }
      } catch (logoErr) {}
    }

    if (keepSheet) {
      try {
        DriveApp.getFileById(tempFileId).setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
      } catch (_) {}
    }

    if (onlyOpenSheet) {
      return _jsonResponse({
        status: 'ok',
        sheetId: tempFileId,
        sheetUrl: sheetUrl
      });
    }

    var sizeParam = (paperSize === 'legal') ? '5' : '7';
    var scaleParam = String(payload.scale || '4');
    var topMargin = String(payload.topMargin || '0.16');
    var bottomMargin = String(payload.bottomMargin || '0.16');
    var leftMargin = String(payload.leftMargin || '0.16');
    var rightMargin = String(payload.rightMargin || '0.16');

    var exportUrl = 'https://docs.google.com/spreadsheets/d/' + tempFileId + '/export'
      + '?format=pdf'
      + '&size=' + sizeParam
      + '&portrait=' + (portrait ? 'true' : 'false')
      + '&scale=' + scaleParam
      + '&top_margin=' + topMargin
      + '&bottom_margin=' + bottomMargin
      + '&left_margin=' + leftMargin
      + '&right_margin=' + rightMargin
      + '&gridlines=false'
      + '&printtitle=false'
      + '&sheetnames=false'
      + '&pagenum=UNDEFINED'
      + '&horizontal_alignment=CENTER'
      + '&vertical_alignment=TOP';

    var pdfResp = UrlFetchApp.fetch(exportUrl, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token },
      muteHttpExceptions: true
    });

    if (pdfResp.getResponseCode() !== 200) {
      return _jsonResponse({
        status: 'error',
        message: 'Google Sheets PDF export failed (' + pdfResp.getResponseCode() + '): ' + pdfResp.getContentText()
      });
    }

    var pdfBase64 = Utilities.base64Encode(pdfResp.getBlob().getBytes());

    return _jsonResponse({
      status: 'ok',
      filename: baseName + '.pdf',
      pdfBase64: pdfBase64,
      sheetId: keepSheet ? tempFileId : null,
      sheetUrl: keepSheet ? sheetUrl : null
    });

  } catch (err) {
    return _jsonResponse({
      status: 'error',
      message: String(err && err.stack ? err.stack : err)
    });
  } finally {
    if (tempFileId && !keepSheet) {
      try {
        DriveApp.getFileById(tempFileId).setTrashed(true);
      } catch (_) {}
    }
  }
}

function _jsonResponse(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
""";

  /// Returns all valid configured Apps Script Web App URLs (supports comma or newline separation).
  Future<List<String>> getConfiguredScriptUrls() async {
    final raw = await getRawConfiguredUrls();
    return _parseUrls(raw);
  }

  Future<String> getConfiguredScriptUrl() async {
    final urls = await getConfiguredScriptUrls();
    if (urls.isEmpty) return '';
    return urls[_random.nextInt(urls.length)];
  }

  Future<String> getRawConfiguredUrls() async {
    if (_envScriptUrls.trim().isNotEmpty) {
      return _envScriptUrls.trim();
    }
    final now = DateTime.now();
    if (_cachedRawUrls != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inMinutes < 10) {
      return _cachedRawUrls!;
    }

    // 1. Check global Developer setting in Firestore (`app_config/developer_pdf_settings`)
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .doc(_firestoreDoc)
          .get();
      if (snap.exists) {
        final data = snap.data();
        final remote = (data?['google_sheets_pdf_urls'] ??
                data?['google_sheets_pdf_url'] ??
                '')
            .toString()
            .trim();
        _cachedRawUrls = remote;
        _lastFetchTime = now;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, remote);
        return remote;
      }
    } catch (_) {}

    // 2. Fallback to local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = (prefs.getString(_prefsKey) ?? '').trim();
      _cachedRawUrls = local;
      _lastFetchTime = now;
      return local;
    } catch (_) {}

    return '';
  }

  /// Saves Developer's Google Sheets Web App URL(s) globally in Firestore for all schools & teachers.
  Future<void> saveDeveloperScriptUrls(String rawUrls) async {
    final trimmed = rawUrls.trim();
    _cachedRawUrls = trimmed;
    _lastFetchTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, trimmed);
    } catch (_) {}

    try {
      await FirebaseFirestore.instance
          .collection(_firestoreCollection)
          .doc(_firestoreDoc)
          .set(
        <String, dynamic>{
          'google_sheets_pdf_urls': trimmed,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  List<String> _parseUrls(String raw) {
    if (raw.trim().isEmpty) return const <String>[];
    return raw
        .split(RegExp(r'[\s,;]+'))
        .map((s) => s.trim())
        .where((s) => s.startsWith('https://script.google.com/'))
        .toList(growable: false);
  }

  Future<(bool, String)> testScriptUrls(String rawUrls) async {
    final urls = _parseUrls(rawUrls);
    if (urls.isEmpty) {
      return (
        false,
        'ઓછામાં ઓછો એક https://script.google.com/macros/s/.../exec URL દાખલ કરો (અથવા ખાલી રાખો જો માત્ર Browser Print વાપરવું હોય).'
      );
    }
    var okCount = 0;
    final errors = <String>[];
    for (var i = 0; i < urls.length; i++) {
      try {
        final resp = await http
            .post(
              Uri.parse(urls[i]),
              headers: const <String, String>{
                'Content-Type': 'text/plain; charset=utf-8',
              },
              body: jsonEncode(<String, dynamic>{'action': 'ping'}),
            )
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          if (decoded is Map && decoded['status'] == 'ok') {
            okCount++;
            continue;
          }
        }
        errors.add('URL #${i + 1}: HTTP ${resp.statusCode}');
      } catch (e) {
        errors.add('URL #${i + 1}: $e');
      }
    }
    if (okCount == urls.length) {
      return (
        true,
        '✅ બધા $okCount Google Sheets Apps Script URL સફળતાપૂર્વક કનેક્ટ થઈ ગયા! (~${okCount * 30} શિક્ષકો એકસાથે PDF બનાવી શકશે + બાકીના માટે ઓટોમેટિક Browser Print Fallback).'
      );
    }
    return (
      false,
      '$okCount / ${urls.length} URL ચાલુ છે. ભૂલ: ${errors.join(", ")}'
    );
  }

  /// Load-balances across all Developer-configured Apps Script URLs with automatic
  /// retry across backup URLs if one endpoint is busy (e.g., when 50 teachers print at once).
  Future<Uint8List> convertWorkbookToPdf({
    required Uint8List preparedWorkbookBytes,
    required String filename,
    required String paperSize,
    required bool portrait,
    Uint8List? schoolLogoBytes,
    int logoRow = 4,
    int logoCol = 4,
    int logoWidthPx = 125,
    int logoHeightPx = 115,
    bool keepSheetInDrive = false,
  }) async {
    final urls = await getConfiguredScriptUrls();
    if (urls.isEmpty) {
      throw StateError('No Developer Google Sheets Apps Script URL configured.');
    }

    // Shuffle URLs so 50 concurrent teachers distribute evenly across all configured URLs
    final shuffledUrls = List<String>.from(urls)..shuffle(_random);

    final payload = jsonEncode(<String, dynamic>{
      'action': 'convertToPdf',
      'workbookBase64': base64Encode(preparedWorkbookBytes),
      'filename': filename,
      'paperSize': paperSize,
      'portrait': portrait,
      'scale': '4',
      'keepSheetInDrive': keepSheetInDrive,
      'onlyOpenSheet': false,
      if (schoolLogoBytes != null && schoolLogoBytes.isNotEmpty) ...<String, dynamic>{
        'logoBase64': base64Encode(schoolLogoBytes),
        'logoRow': logoRow,
        'logoCol': logoCol,
        'logoWidthPx': logoWidthPx,
        'logoHeightPx': logoHeightPx,
      },
    });

    Object? lastError;
    for (var attempt = 0; attempt < shuffledUrls.length; attempt++) {
      final targetUrl = shuffledUrls[attempt];
      try {
        final response = await http
            .post(
              Uri.parse(targetUrl),
              headers: const <String, String>{
                'Content-Type': 'text/plain; charset=utf-8',
              },
              body: payload,
            )
            .timeout(const Duration(seconds: 90));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map && decoded['status'] == 'ok') {
            final pdfB64 = (decoded['pdfBase64'] ?? '').toString().trim();
            if (pdfB64.isNotEmpty) {
              return Uint8List.fromList(base64Decode(pdfB64));
            }
          }
          lastError = decoded is Map ? decoded['message'] : 'Invalid response';
        } else {
          lastError = 'HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = e;
      }
      // Small jittered backoff before trying the next URL in the pool
      if (attempt + 1 < shuffledUrls.length) {
        await Future<void>.delayed(
          Duration(milliseconds: 300 + _random.nextInt(400)),
        );
      }
    }

    throw StateError('Google Sheets PDF pool busy or unreachable: $lastError');
  }
}

/// Developer-Only Configuration Card to embed inside `lib/screens/developer_panel.dart`.
/// Never shown to School Admins or Teachers.
class GoogleSheetsDeveloperConfigCard extends StatefulWidget {
  const GoogleSheetsDeveloperConfigCard({super.key});

  @override
  State<GoogleSheetsDeveloperConfigCard> createState() =>
      _GoogleSheetsDeveloperConfigCardState();
}

class _GoogleSheetsDeveloperConfigCardState
    extends State<GoogleSheetsDeveloperConfigCard> {
  final TextEditingController _urlController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUrl() async {
    final raw = await const GoogleSheetsPdfService().getRawConfiguredUrls();
    if (!mounted) return;
    setState(() {
      _urlController.text = raw;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF15803D), width: 1.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.developer_mode_rounded, color: Color(0xFF15803D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📊 Developer Only: Google Sheets PDF Web App URL (Hajari Patrak & Result)',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF14532D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '• આ સેટિંગ માત્ર Developer Panel માં જ દેખાશે (School Admin કે Teacher સ્ક્રીનમાં ક્યાંય દેખાશે નહીં).\n'
              '• જો આ બોક્સ ખાલી રાખશો (હાલની જેમ), તો Hajari Patrak અને Result ના તમામ PDF મૂળ Excel ટેમ્પ્લેટ મુજબ જ સીધા Browser Print Engine થી ₹0 ખર્ચે બનશે (50 કે 500 શિક્ષકો એકસાથે પ્રિન્ટ કરે તો પણ કોઈ લિમિટ નથી).\n'
              '• જ્યારે તમારે Google Sheets Apps Script ચાલુ કરવું હોય, ત્યારે અહીં 1 અથવા વધુ Web App URL (કોમાથી અલગ પાડીને) સેવ કરી શકો છો. જો 50 શિક્ષકો એકસાથે ક્લિક કરે અને Google ની 30-request લિમિટ આવે, તો સિસ્ટમ આપોઆપ Browser Print પર fallback થઈ જશે.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(
                        text: GoogleSheetsPdfService.appsScriptSourceCode,
                      ),
                    );
                    if (!mounted) return;
                    setState(() {
                      _statusOk = true;
                      _statusMessage =
                          '✅ Apps Script (Code.gs) કોપી થઈ ગયો! script.google.com માં પેસ્ટ કરી Deploy કરો.';
                    });
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('📋 Apps Script કોડ કોપી કરો (Code.gs)'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse('https://script.google.com'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('script.google.com ખોલો'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else
              TextField(
                controller: _urlController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText:
                      'Google Apps Script Web App URL (/exec) — ખાલી રાખશો તો Local Template Browser Print વપરાશે',
                  hintText:
                      'https://script.google.com/macros/s/.../exec (એકથી વધુ URL માટે કોમા મૂકો)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await const GoogleSheetsPdfService()
                              .saveDeveloperScriptUrls(_urlController.text);
                          if (!mounted) return;
                          setState(() {
                            _saving = false;
                            _statusOk = true;
                            _statusMessage = _urlController.text.trim().isEmpty
                                ? '✅ સેવ થયું: હાલ Local Template Browser Print Mode સક્રિય છે.'
                                : '✅ Developer Google Sheets Web App URL તમામ શાળાઓ માટે સેવ થઈ ગયો!';
                          });
                        },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text(_saving ? 'સેવ થાય છે...' : '💾 Developer URL સેવ કરો'),
                ),
                OutlinedButton.icon(
                  onPressed: _testing
                      ? null
                      : () async {
                          setState(() {
                            _testing = true;
                            _statusMessage = 'કનેક્શન ચકાસાઈ રહ્યું છે...';
                          });
                          final (ok, msg) = await const GoogleSheetsPdfService()
                              .testScriptUrls(_urlController.text);
                          if (!mounted) return;
                          setState(() {
                            _testing = false;
                            _statusOk = ok;
                            _statusMessage = msg;
                          });
                        },
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text('🔍 URL ચકાસો (Test)'),
                ),
                if (_urlController.text.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            _urlController.clear();
                            await const GoogleSheetsPdfService()
                                .saveDeveloperScriptUrls('');
                            if (!mounted) return;
                            setState(() {
                              _statusOk = true;
                              _statusMessage =
                                  '✅ URL દૂર કર્યો — હવે સીધું Local Template Browser Print વપરાશે.';
                            });
                          },
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: const Text('URL ક્લિયર કરો (Browser Print Only)'),
                  ),
              ],
            ),
            if (_statusMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _statusOk
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _statusOk
                        ? const Color(0xFF166534)
                        : const Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
