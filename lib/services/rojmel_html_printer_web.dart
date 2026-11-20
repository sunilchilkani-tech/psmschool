import 'dart:async';
import 'dart:html' as html;

/// Returns a lightweight token instead of opening an `about:blank` popup tab,
/// because in compiled Flutter Web `window.open` returns `_WindowCrossFrame`
/// (`WindowBase`), which cannot be cast to `html.Window`. Printing via a hidden
/// same-origin `IFrameElement` avoids `about:blank` tabs and popup blockers.
dynamic openRojmelPrintWindow() => 'iframe_print_handle';

/// Loads the complete print HTML into a hidden iframe using a Blob URL so the
/// document's onload/print script triggers the browser print dialog directly
/// without opening a blank tab.
void writeRojmelPrintDocument(dynamic windowHandle, String htmlDocument) {
  if (windowHandle is html.WindowBase) {
    try {
      windowHandle.close();
    } catch (_) {}
  }

  final existing = html.document.getElementById('psm-rojmel-print-iframe');
  existing?.remove();

  final blob = html.Blob(<Object>[htmlDocument], 'text/html;charset=utf-8');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);

  final iframe = html.IFrameElement()
    ..id = 'psm-rojmel-print-iframe'
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.border = '0'
    ..style.opacity = '0'
    ..src = objectUrl;

  html.document.body?.append(iframe);

  Timer(const Duration(minutes: 3), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
}

void closeRojmelPrintWindow(dynamic windowHandle) {
  if (windowHandle is html.WindowBase) {
    try {
      windowHandle.close();
    } catch (_) {}
  }
}
