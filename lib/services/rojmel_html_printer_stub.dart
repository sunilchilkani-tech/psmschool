/// Non-web fallback. Exact HTML/CSS printing is currently implemented for
/// Flutter Web. Native platforms must use a proper HTML-to-PDF renderer rather
/// than silently generating a different layout.
dynamic openRojmelPrintWindow() => null;

void writeRojmelPrintDocument(dynamic windowHandle, String htmlDocument) {
  throw UnsupportedError('Exact Rojmel HTML printing is only available in Flutter Web.');
}

void closeRojmelPrintWindow(dynamic windowHandle) {}
