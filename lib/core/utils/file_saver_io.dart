import 'dart:io';
import 'dart:typed_data';

Future<String?> saveBytes(Uint8List bytes, String filename, String mime) async {
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> printBytes(Uint8List bytes, String filename, String mime) async {
  final path = await saveBytes(bytes, filename, mime);
  if (path == null) return;
  // Best-effort: hand the file to the OS default viewer (which offers print).
  // Failures are non-fatal — the document is already saved to disk.
  try {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['shell32.dll,ShellExec_RunDLL', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {
    /* viewer launch is best-effort */
  }
}
