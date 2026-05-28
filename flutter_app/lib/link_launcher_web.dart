// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openExternalLinkImpl(String url, {bool newTab = false}) async {
  if (newTab) {
    final opened = html.window.open(url, '_blank');
    if (opened == null) {
      html.window.location.assign(url);
    }
    return true;
  }

  html.window.location.assign(url);
  return true;
}
