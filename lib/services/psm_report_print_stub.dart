dynamic openReportPrintWindow() => null;

Future<void> printReportHtml(dynamic target, String htmlDocument) async {
  throw UnsupportedError('Browser print-to-PDF is available only in the Flutter Web build.');
}
