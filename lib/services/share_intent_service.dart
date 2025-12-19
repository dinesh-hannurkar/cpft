import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';


class ShareIntentService {
  static final ShareIntentService _instance = ShareIntentService._internal();
  factory ShareIntentService() => _instance;
  ShareIntentService._internal();

  final StreamController<List<SharedMediaFile>> _sharedFilesController =
      StreamController<List<SharedMediaFile>>.broadcast();

  Stream<List<SharedMediaFile>> get sharedFilesStream =>
      _sharedFilesController.stream;

  List<SharedMediaFile> _currentSharedFiles = [];

  static const MethodChannel _events = MethodChannel('com.example.cpft/share-events');

  void initialize() {
    // Only use receive_sharing_intent on mobile platforms
    if (Platform.isAndroid || Platform.isIOS) {
      // Listen for share events to trigger immediate fetch
      _events.setMethodCallHandler((call) async {
        if (call.method == 'shareOpened') {
          // Trigger immediate check for shared content
          ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _handleSharedFiles(value);
              print('ShareIntentService: immediate shared media on open: ${value.length} items');
            }
          });
        }
      });

      // Get initial shared media when app is launched from share
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
          print('ShareIntentService: initial shared media: ${value.length} items');
        }
      });

      // Listen for shared media stream
      ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
          print('ShareIntentService: stream shared media: ${value.length} items');
        }
      });
    } else {
      // On desktop platforms, sharing is handled differently (e.g., drag-and-drop)
      print('ShareIntentService: Skipping mobile share intent setup on ${Platform.operatingSystem}');
    }

    print('ShareIntentService initialized');
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    _currentSharedFiles = List<SharedMediaFile>.from(files);
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.add(List<SharedMediaFile>.from(files));
    }

    // Log shared files for debugging
    for (var file in files) {
      print('Shared file: ${file.path}');
      print('File type: ${file.type}');
      print('File mime type: ${file.mimeType}');
    }
  }

  void _handleSharedText(String text) {
    print('Shared text: $text');
    // You can handle text sharing here if needed
    // For now, we'll focus on file sharing
  }

  List<SharedMediaFile> getCurrentSharedFiles() {
    return List<SharedMediaFile>.from(_currentSharedFiles);
  }

  Future<String> copySharedFileToAppDirectory(SharedMediaFile sharedFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = path.basename(sharedFile.path);
    final targetPath = path.join(appDir.path, 'shared_files', fileName);

    // Ensure the shared_files directory exists
    final sharedDir = Directory(path.dirname(targetPath));
    if (!await sharedDir.exists()) {
      await sharedDir.create(recursive: true);
    }

    // Copy the file
    final sourceFile = File(sharedFile.path);
    await sourceFile.copy(targetPath);

    return targetPath;
  }

  void clearSharedFiles() {
    _currentSharedFiles.clear();
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.add([]);
    }
  }

  void dispose() {
    _sharedFilesController.close();
  }
}