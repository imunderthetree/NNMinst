import 'link_launcher_stub.dart'
    if (dart.library.html) 'link_launcher_web.dart';

Future<bool> openExternalLink(String url, {bool newTab = false}) {
  return openExternalLinkImpl(url, newTab: newTab);
}
