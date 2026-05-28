import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalLinkImpl(String url, {bool newTab = false}) async {
  final uri = Uri.parse(url);
  return launchUrl(uri, mode: LaunchMode.platformDefault);
}
