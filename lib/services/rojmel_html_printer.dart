import 'rojmel_html_printer_stub.dart'
    if (dart.library.html) 'rojmel_html_printer_web.dart' as implementation;

/// Opens a browser print window and writes a complete HTML document into it.
/// The document itself calls window.print() after it is loaded.
dynamic openRojmelPrintWindow() => implementation.openRojmelPrintWindow();

void writeRojmelPrintDocument(dynamic windowHandle, String htmlDocument) =>
    implementation.writeRojmelPrintDocument(windowHandle, htmlDocument);

void closeRojmelPrintWindow(dynamic windowHandle) =>
    implementation.closeRojmelPrintWindow(windowHandle);
