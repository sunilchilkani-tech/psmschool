/// Non-web fallback for the browser-native Daily DATEWISE print renderer.
Object? openDailyReportPrintWindow() => null;

Future<void> printDailyReportHtml(Object? target, String html) async {
  throw UnsupportedError('The merged Gujarati Daily DATEWISE print layout is available in Flutter Web.');
}
