import 'url_opener_io.dart' if (dart.library.js_interop) 'url_opener_web.dart' as impl;

/// Opens [url] in a new browser tab. Returns true if the platform could open
/// it (web); on desktop/mobile returns false — the caller shows the URL to copy.
bool openInNewTab(String url) => impl.openInNewTab(url);
