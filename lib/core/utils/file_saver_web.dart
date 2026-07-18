import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> saveBytes(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return null;
}

Future<void> printBytes(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  // A hidden iframe whose content is the PDF; once loaded we focus it and call
  // print(). The iframe + object URL are intentionally kept alive (not revoked)
  // so the print session has a live document.
  final iframe = web.HTMLIFrameElement()
    ..style.display = 'none'
    ..src = url;
  iframe.addEventListener(
    'load',
    (web.Event _) {
      final win = iframe.contentWindow;
      win?.focus();
      win?.print();
    }.toJS,
  );
  web.document.body!.appendChild(iframe);
}
