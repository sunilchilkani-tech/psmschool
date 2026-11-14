import 'package:universal_html/html.dart' as html;

/// Must be called synchronously from the PDF button gesture to avoid popup blocking.
Object? openDailyReportPrintWindow() =>
    html.window.open('about:blank', 'psm_daily_datewise_print');

/// Navigate the pre-opened tab to a Blob URL. Do not access the cross-window
/// document or call focus() on WindowBase; the HTML page focuses and prints itself.
Future<void> printDailyReportHtml(Object? target, String content) async {
  final html.WindowBase? printWindow =
      target is html.WindowBase ? target : null;
  if (printWindow == null || printWindow.closed == true) {
    throw StateError(
      'Chrome blocked the report print window. Allow pop-ups for this site and try again.',
    );
  }

  const printScript = '''<script>
window.addEventListener('load', function () {
  window.setTimeout(function () {
    window.focus();
    window.print();
    window.setTimeout(function () {
      try { URL.revokeObjectURL(window.location.href); } catch (_) {}
    }, 1000);
  }, 250);
});
</script>''';

  final bodyEnd = RegExp(r'</body\s*>', caseSensitive: false);
  final printableHtml = bodyEnd.hasMatch(content)
      ? content.replaceFirst(bodyEnd, '$printScript</body>')
      : '$content$printScript';
  final blob = html.Blob(<Object>[printableHtml], 'text/html;charset=utf-8');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);

  try {
    printWindow.location.href = objectUrl;
  } catch (error) {
    html.Url.revokeObjectUrl(objectUrl);
    throw StateError('Could not prepare the Daily DATEWISE print page: $error');
  }
}