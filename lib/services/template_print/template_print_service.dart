import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import 'html_renderer.dart';
import 'print_page.dart';

/// Prints Hajari Patrak / Result / Vyaktitva Vikas pages without any paid
/// server:
///  * Browser print (web) — the template is drawn as HTML with the app's own
///    Gujarati font embedded, then the browser's print preview opens.
///  * PDF via Google Apps Script — the developer adds one or more free web
///    app URLs; the app sends the workbook + page plan and gets a PDF back.
class TemplatePrintService {
  TemplatePrintService._();

  static const String configCollection = 'platform_config';
  static const String configDoc = 'print_service';

  static List<String>? _urlCache;
  static DateTime? _urlCacheAt;
  static String? _fontRegular;
  static String? _fontBold;
  static int _rotation = math.Random().nextInt(1000);

  // ------------------------------------------------------------ settings
  static List<String> parseUrls(String raw) => raw
      .split(RegExp(r'[\s,;]+'))
      .map((u) => u.trim())
      .where((u) => u.startsWith('https://script.google.com/') || u.startsWith('https://script.googleusercontent.com/'))
      .toSet()
      .toList();

  static Future<List<String>> appsScriptUrls({bool refresh = false}) async {
    final fresh = _urlCacheAt != null && DateTime.now().difference(_urlCacheAt!) < const Duration(minutes: 10);
    if (!refresh && fresh && _urlCache != null) return _urlCache!;
    try {
      final snap = await fs.FirebaseFirestore.instance.collection(configCollection).doc(configDoc).get();
      final raw = snap.data()?['apps_script_urls'];
      final list = raw is List ? raw.map((e) => '$e').toList() : parseUrls('${raw ?? ''}');
      _urlCache = parseUrls(list.join(','));
      _urlCacheAt = DateTime.now();
    } catch (_) {
      _urlCache ??= const <String>[];
    }
    return _urlCache!;
  }

  static Future<void> saveAppsScriptUrls(List<String> urls) async {
    await fs.FirebaseFirestore.instance.collection(configCollection).doc(configDoc).set(<String, dynamic>{
      'apps_script_urls': urls,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, fs.SetOptions(merge: true));
    _urlCache = urls;
    _urlCacheAt = DateTime.now();
  }

  /// Checks that a URL answers like the PSM PDF script.
  static Future<bool> testUrl(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      final body = jsonDecode(res.body);
      return body is Map && body['ok'] == true && body['service'] == 'psm-pdf';
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ printing
  /// Prints [job]. On the web the teacher can choose browser print (default)
  /// or a Google PDF; in the mobile app the Google PDF is used.
  static Future<void> printJob(BuildContext context, PrintJob job) => printJobs(context, <PrintJob>[job]);

  /// Prints several jobs together (one browser print, or one Google PDF per
  /// job — Google exports one paper size per PDF).
  static Future<void> printJobs(BuildContext context, List<PrintJob> jobs) async {
    if (jobs.isEmpty) return;
    final job = jobs.length == 1
        ? jobs.first
        : PrintJob(
            title: jobs.first.title,
            pages: [for (final j in jobs) ...j.pages],
            edits: jobs.first.edits,
            workbookBytes: jobs.first.workbookBytes,
          );
    final urls = await appsScriptUrls();
    if (!context.mounted) return;
    if (kIsWeb) {
      var choice = 'browser';
      if (urls.isNotEmpty) {
        final picked = await _chooseMode(context);
        if (picked == null) return;
        choice = picked;
      }
      if (choice == 'browser') {
        await browserPrint(job);
        return;
      }
    } else if (urls.isEmpty) {
      throw StateError('PDF service is not set. Please print from the website (browser print), or ask the developer to add the Google Apps Script URL.');
    }
    for (final j in jobs) {
      final pdf = await googlePdf(j, urls);
      await Printing.layoutPdf(name: '${j.title}.pdf', onLayout: (_) async => pdf);
    }
  }

  static Future<String?> _chooseMode(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('પ્રિન્ટ કેવી રીતે કરવી છે?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'browser'),
              child: const ListTile(
                leading: Icon(Icons.print_rounded, color: Color(0xFF087F5B)),
                title: Text('Browser Print (ઝડપી)'),
                subtitle: Text('તરત print preview ખુલશે. "Save as PDF" પણ પસંદ કરી શકાય.'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'google'),
              child: const ListTile(
                leading: Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFC92A2A)),
                title: Text('PDF (Google Sheets)'),
                subtitle: Text('Google દ્વારા PDF બને છે (થોડી સેકન્ડ લાગે).'),
              ),
            ),
          ],
        ),
      );

  static Future<void> _loadFonts() async {
    if (_fontRegular != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf');
      _fontRegular = base64Encode(r.buffer.asUint8List(r.offsetInBytes, r.lengthInBytes));
      _fontBold = base64Encode(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes));
    } catch (_) {}
  }

  static Future<String> buildHtml(PrintJob job, {bool autoPrint = true}) async {
    await _loadFonts();
    return TemplateHtmlRenderer(fontRegularBase64: _fontRegular, fontBoldBase64: _fontBold)
        .render(job.pages, title: job.title, autoPrint: autoPrint);
  }

  /// Opens the browser's print preview for [job] (web only).
  static Future<void> browserPrint(PrintJob job) async {
    if (!kIsWeb) throw UnsupportedError('Browser print is available on the website.');
    final doc = await buildHtml(job);
    // A hidden frame is never blocked as a pop-up and prints only itself.
    final old = html.document.getElementById('psm-template-print');
    old?.remove();
    final frame = html.IFrameElement()
      ..id = 'psm-template-print'
      ..style.position = 'fixed'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '1px'
      ..style.height = '1px'
      ..style.border = '0'
      ..style.opacity = '0';
    final blob = html.Blob(<Object>[doc], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    frame.src = url;
    html.document.body?.append(frame);
    Timer(const Duration(minutes: 10), () {
      html.Url.revokeObjectUrl(url);
      frame.remove();
    });
  }

  /// Gets the PDF from one of the Google Apps Script URLs (spreads load and
  /// falls back to the next URL when one is busy or fails).
  static Future<Uint8List> googlePdf(PrintJob job, List<String> urls) async {
    if (urls.isEmpty) throw StateError('No Google Apps Script URL is set.');
    final payload = jsonEncode(<String, dynamic>{
      'xlsx': base64Encode(job.workbookBytes),
      'plan': job.toPlanJson(),
    });
    final start = _rotation++ % urls.length;
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[(start + i) % urls.length];
      try {
        final res = await _post(url, payload).timeout(const Duration(minutes: 5));
        final body = jsonDecode(res);
        if (body is Map && body['ok'] == true && body['pdf'] is String) {
          return base64Decode(body['pdf'] as String);
        }
        lastError = body is Map ? body['error'] : 'Unexpected reply';
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Google PDF તૈયાર થઈ શકી નથી: $lastError');
  }

  static Future<String> _post(String url, String payload) async {
    // text/plain avoids a CORS pre-flight; Apps Script answers through a
    // redirect to googleusercontent.com.
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(url))
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = payload
        ..followRedirects = kIsWeb;
      final streamed = await client.send(req);
      if (!kIsWeb && (streamed.statusCode == 302 || streamed.statusCode == 303 || streamed.statusCode == 301)) {
        final location = streamed.headers['location'];
        await streamed.stream.drain<void>();
        if (location == null) throw StateError('Redirect without location');
        final res = await client.get(Uri.parse(location));
        return utf8.decode(res.bodyBytes);
      }
      return utf8.decode(await streamed.stream.toBytes());
    } finally {
      client.close();
    }
  }
}
