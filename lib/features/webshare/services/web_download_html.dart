import 'dart:html' as html;
import 'dart:typed_data';

class WebDownload {
  static void saveBytes(
    String filename,
    List<int> bytes, {
    String? contentType,
  }) {
    print('[WebDownload] saveBytes called: filename=$filename, size=${bytes.length}, contentType=$contentType');
    
    try {
      final data = Uint8List.fromList(bytes);
      print('[WebDownload] Created Uint8List, creating blob...');
      
      final blob = html.Blob([data], contentType ?? 'application/octet-stream');
      print('[WebDownload] Blob created, size=${blob.size}');
      
      final url = html.Url.createObjectUrlFromBlob(blob);
      print('[WebDownload] Blob URL created: $url');
      
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..style.display = 'none';
      
      print('[WebDownload] Anchor element created, appending to body...');
      html.document.body?.append(anchor);
      
      print('[WebDownload] Triggering click...');
      anchor.click();
      
      print('[WebDownload] Download triggered successfully');
      
      // Clean up after a delay to ensure download starts
      Future.delayed(const Duration(milliseconds: 1000), () {
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        print('[WebDownload] Cleanup completed');
      });
    } catch (e, stackTrace) {
      print('[WebDownload] Error in saveBytes: $e');
      print('[WebDownload] Stack trace: $stackTrace');
    }
  }

  static void saveParts(
    String filename,
    List<Uint8List> parts, {
    String? contentType,
  }) {
    print('[WebDownload] saveParts called: filename=$filename, parts=${parts.length}, contentType=$contentType');
    
    try {
      // Convert List<Uint8List> to a single Uint8List by concatenating
      final totalLength = parts.fold<int>(0, (sum, part) => sum + part.length);
      print('[WebDownload] Total size: $totalLength bytes');
      
      final combined = Uint8List(totalLength);
      var offset = 0;
      for (final part in parts) {
        combined.setRange(offset, offset + part.length, part);
        offset += part.length;
      }
      
      print('[WebDownload] Combined into single Uint8List, creating blob...');
      final blob = html.Blob([combined], contentType ?? 'application/octet-stream');
      print('[WebDownload] Blob created, size=${blob.size}');
      
      final url = html.Url.createObjectUrlFromBlob(blob);
      print('[WebDownload] Blob URL created: $url');
      
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..style.display = 'none';
      
      print('[WebDownload] Anchor element created, appending to body...');
      html.document.body?.append(anchor);
      
      print('[WebDownload] Triggering click...');
      anchor.click();
      
      print('[WebDownload] Download triggered successfully');
      
      Future.delayed(const Duration(milliseconds: 1000), () {
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        print('[WebDownload] Cleanup completed');
      });
    } catch (e, stackTrace) {
      print('[WebDownload] Error in saveParts: $e');
      print('[WebDownload] Stack trace: $stackTrace');
    }
  }
}
