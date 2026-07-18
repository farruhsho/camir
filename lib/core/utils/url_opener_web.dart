import 'package:web/web.dart' as web;

bool openInNewTab(String url) {
  web.window.open(url, '_blank');
  return true;
}
