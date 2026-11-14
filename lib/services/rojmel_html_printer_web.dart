import 'dart:async';
import 'dart:html' as html;

/// Opens a same-origin blank window synchronously during the user's click so
/// that popup blockers are less likely to block the print workflow.
dynamic openRojmelPrintWindow() => html.window.open('about:blank', '_blank');

/// Loads the complete print HTML into the popup using a Blob URL.
///
/// Navigating the popup to a text/html Blob URL avoids the legacy
/// Document.open/write/close APIs. The supplied HTML page is responsible for
/// calling window.print() after the document loads.
void writeRojmelPrintDocument(dynamic windowHandle, String htmlDocument) {
  final popupBase = windowHandle as html.WindowBase?;
  if (popupBase == null) {
    throw StateError('The browser blocked the print window.');
  }

  final popup = popupBase as html.Window?;
  if (popup == null) {
    throw StateError('The browser did not return a navigable print window.');
  }

  final blob = html.Blob(<Object>[htmlDocument], 'text/html;charset=utf-8');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  try {
    popup.location.href = objectUrl;
    // `Window.setTimeout` is not exposed by the Dart HTML binding used by this
    // project. Use dart:async Timer to revoke the temporary URL after printing
    // has had time to load the document.
    Timer(const Duration(minutes: 2), () {
      html.Url.revokeObjectUrl(objectUrl);
    });
  } catch (_) {
    html.Url.revokeObjectUrl(objectUrl);
    rethrow;
  }
}

void closeRojmelPrintWindow(dynamic windowHandle) {
  try {
    (windowHandle as html.WindowBase?)?.close();
  } catch (_) {
    // Nothing further is needed if the browser already closed the window.
  }
}
