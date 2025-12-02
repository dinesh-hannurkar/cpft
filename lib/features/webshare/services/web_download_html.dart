// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

class WebDownload {
  static void saveBytes(String filename, List<int> bytes, {String? contentType}) {
    final data = Uint8List.fromList(bytes);
    final blob = html.Blob([data], contentType ?? 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    // Some browsers require the element to be attached before clicking
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  static void saveParts(String filename, List<Uint8List> parts, {String? contentType}) {
    final blob = html.Blob(parts, contentType ?? 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)..download = filename;
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
