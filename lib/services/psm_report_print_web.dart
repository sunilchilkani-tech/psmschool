import 'package:universal_html/html.dart' as html;

dynamic openReportPrintWindow() => html.window.open('about:blank', '_blank');

Future<void> printReportHtml(dynamic target, String htmlDocument) async {
  if (target == null) {
    throw StateError('Chrome blocked the report print window. Allow pop-ups for this app and click Print / Save PDF again.');
  }
  final dynamic document = target.document;
  document.open();
  document.write(htmlDocument);
  document.close();
  await Future<void>.delayed(const Duration(milliseconds: 700));
  target.focus();
  target.print();
}
