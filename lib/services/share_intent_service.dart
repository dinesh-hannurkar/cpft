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
  bool _hasReceivedDirectData = false;

  static const MethodChannel _events = MethodChannel('com.example.cpft/share-events');

  void initialize() {
    // Reset state
    _hasReceivedDirectData = false;
    _currentSharedFiles.clear();
    // Only use receive_sharing_intent on mobile platforms
    if (Platform.isAndroid || Platform.isIOS) {
      print('ShareIntentService: Initializing on ${Platform.operatingSystem}');
      
      // Listen for share events to trigger immediate fetch
      _events.setMethodCallHandler((call) async {
        print('ShareIntentService: Received method call: ${call.method}');
        if (call.method == 'shareOpened') {
          print('ShareIntentService: shareOpened callback received, hasReceivedDirectData: $_hasReceivedDirectData');
          // Wait a short time to allow sharedDataReceived to process first
          Future.delayed(const Duration(milliseconds: 100), () {
            print('ShareIntentService: Checking for direct data after delay, hasReceivedDirectData: $_hasReceivedDirectData');
            // Only fetch from plugin if we haven't received data directly
            if (!_hasReceivedDirectData) {
              print('ShareIntentService: shareOpened callback received, fetching initial media...');
              // Trigger immediate check for shared content
              ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
                print('ShareIntentService: getInitialMedia returned ${value.length} items after shareOpened');
                if (value.isNotEmpty) {
                  _handleSharedFiles(value);
                  print('ShareIntentService: immediate shared media on open: ${value.length} items');
                } else {
                  print('ShareIntentService: No shared media found after shareOpened callback');
                }
              }).catchError((error) {
                print('ShareIntentService: Error getting initial media after shareOpened: $error');
              });
            } else {
              print('ShareIntentService: Skipping getInitialMedia because direct data was already received');
            }
          });
        } else if (call.method == 'sharedDataReceived') {
          print('ShareIntentService: sharedDataReceived callback received');
          // Handle data sent directly from iOS AppDelegate
          if (call.arguments is List) {
            final List<dynamic> data = call.arguments as List<dynamic>;
            print('ShareIntentService: Received ${data.length} raw items from iOS');
            print('ShareIntentService: Raw data: $data');
            final List<SharedMediaFile> files = data.map((item) {
              print('ShareIntentService: Processing raw item: $item');
              try {
                // Handle dynamic typing from platform channel
                if (item is Map) {
                  final map = Map<String, dynamic>.from(item as Map);
                  final path = map['path']?.toString() ?? '';
                  final type = map['type']?.toString() ?? '';
                  
                  if (path.isEmpty) {
                    print('ShareIntentService: Skipping item with empty path');
                    return null;
                  }
                  
                  print('ShareIntentService: Processing item: $type - $path');
                  return SharedMediaFile(
                    path: path,
                    mimeType: map['mimeType']?.toString(),
                    thumbnail: map['thumbnail']?.toString(),
                    duration: map['duration'] is num ? (map['duration'] as num).toInt() : null,
                    message: map['message']?.toString(),
                    type: _parseMediaType(type),
                  );
                } else {
                  print('ShareIntentService: Item is not a Map: $item');
                  return null;
                }
              } catch (e) {
                print('ShareIntentService: Error parsing item $item: $e');
                return null;
              }
            }).where((file) => file != null).cast<SharedMediaFile>().toList();
            
            print('ShareIntentService: Parsed ${files.length} files from iOS data');
            if (files.isNotEmpty) {
              print('ShareIntentService: Received ${files.length} files directly from iOS');
              _hasReceivedDirectData = true;
              _handleSharedFiles(files);
            } else {
              print('ShareIntentService: No files parsed from iOS data');
            }
          } else {
            print('ShareIntentService: sharedDataReceived arguments is not a List: ${call.arguments}');
          }
        }
      });

      // Get initial shared media when app is launched from share
      print('ShareIntentService: Calling getInitialMedia on initialization...');
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        print('ShareIntentService: getInitialMedia returned ${value.length} items on init');
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
          print('ShareIntentService: initial shared media: ${value.length} items');
        } else {
          print('ShareIntentService: No initial shared media found on init');
        }
      }).catchError((error) {
        print('ShareIntentService: Error getting initial media on init: $error');
      });

      // Listen for shared media stream
      ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
        print('ShareIntentService: Media stream received ${value.length} items');
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
    print('ShareIntentService: _handleSharedFiles called with ${files.length} files');
    _currentSharedFiles = List<SharedMediaFile>.from(files);
    print('ShareIntentService: Updated _currentSharedFiles to ${files.length} files');
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.add(List<SharedMediaFile>.from(files));
      print('ShareIntentService: Added ${files.length} files to stream');
    } else {
      print('ShareIntentService: Stream controller is closed, cannot add files');
    }

    // Log shared files for debugging
    for (var file in files) {
      print('Shared file: ${file.path}');
      print('File type: ${file.type}');
      print('File mime type: ${file.mimeType}');
    }
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
    _hasReceivedDirectData = false;
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.add([]);
    }
  }

  void dispose() {
    _sharedFilesController.close();
  }
  
  SharedMediaType _parseMediaType(String typeString) {
    switch (typeString) {
      case 'image':
        return SharedMediaType.image;
      case 'video':
        return SharedMediaType.video;
      case 'text':
        return SharedMediaType.text;
      case 'file':
        return SharedMediaType.file;
      case 'url':
        return SharedMediaType.url;
      default:
        return SharedMediaType.file; // Default fallback
    }
  }
}