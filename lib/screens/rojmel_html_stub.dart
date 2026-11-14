// ============================================================================
// Cross-platform stub for `dart:html` when compiling/analyzing on non-web targets
// File: lib/screens/rojmel_html_stub.dart
// ============================================================================

import 'dart:async';

class Blob {
  final List<Object?> parts;
  final String? type;
  Blob(this.parts, [this.type]);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class HtmlStyle {
  String? display;
  String? position;
  String? left;
  String? top;
  String? width;
  String? height;
  String? border;
  String? opacity;
  String? pointerEvents;
}

class AnchorElement {
  String? href;
  String? download;
  String? target;
  final HtmlStyle style = HtmlStyle();

  AnchorElement({this.href});

  void setAttribute(String name, String value) {
    if (name == 'download') download = value;
    if (name == 'href') href = value;
    if (name == 'target') target = value;
  }

  void click() {}
  void remove() {}
}

class IFrameElement {
  final HtmlStyle style = HtmlStyle();
  String? src;
  String? srcdoc;
  void remove() {}
}

class MessageEvent {
  final Object? data;
  const MessageEvent([this.data]);
}

class _DocumentBody {
  void append(Object element) {}
}

class Document {
  _DocumentBody? body = _DocumentBody();
}

final Document document = Document();

class FileUploadInputElement {
  String? accept;
  bool multiple = false;
  List<dynamic>? files;
  Stream<dynamic> get onChange => const Stream<dynamic>.empty();
  void click() {}
}

class FileReader {
  dynamic result;
  Stream<dynamic> get onLoadEnd => const Stream<dynamic>.empty();
  void readAsArrayBuffer(dynamic file) {}
  void readAsText(dynamic file) {}
}

class BrowserWindow {
  final Map<String, String> localStorage = <String, String>{};
  Stream<MessageEvent> get onMessage => const Stream<MessageEvent>.empty();
  void open(String url, [String? target, String? options]) {}
  void print() {}
}

final BrowserWindow window = BrowserWindow();