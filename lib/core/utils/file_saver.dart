import 'dart:typed_data';

import 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Saves [bytes] as a downloadable file.
///
/// On web triggers a browser download and returns null; elsewhere writes to the
/// system temp directory and returns the absolute path.
Future<String?> saveBytes(Uint8List bytes, String filename, String mime) =>
    impl.saveBytes(bytes, filename, mime);

/// Opens [bytes] for printing.
///
/// On web loads the document in a hidden iframe and fires the browser print
/// dialog; on desktop it writes to temp and best-effort opens it with the OS
/// default viewer. Used to auto-print the чек + талон right after payment.
Future<void> printBytes(Uint8List bytes, String filename, String mime) =>
    impl.printBytes(bytes, filename, mime);
