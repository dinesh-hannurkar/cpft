import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:cpft/core/logging/app_logger.dart';
import 'package:cpft/services/notification_service.dart';
import 'package:cpft/utils/network_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart';
import 'package:path/path.dart' as p;
import 'web_server.dart';
import 'mdns_srv_resolver.dart';

/// Service to manage web share functionality
class WebShareService {
  WebServer? _webServer;
  final String deviceName;
  final String? customServiceName;
  bool _externalServerRunning = false;

  // mDNS advertising
  static const MethodChannel _hostnameChannel = MethodChannel(
    'com.example.cpft/hostname',
  );
  Registration? _nsdRegistration;
  bool _isAdvertising = false;
  String? _actualHostname; // The actual .local hostname from NSD
  String? _localIP; // Local IP address for Android QR codes

  // State notifiers
  final ValueNotifier<int> connectedClients = ValueNotifier<int>(0);
  final ValueNotifier<List<SharedFile>> sharedFiles =
      ValueNotifier<List<SharedFile>>([]);
  final ValueNotifier<List<ReceivedFile>> receivedFiles =
      ValueNotifier<List<ReceivedFile>>([]);
  final ValueNotifier<String?> actualHostnameNotifier = ValueNotifier<String?>(
    null,
  );

  // Callbacks for integration with app
  final Function(String filename, int bytesReceived, int totalBytes)?
  onFileUploadProgress;
  final Function(String filename, String savedPath)? onFileUploadComplete;

  WebShareService({
    required this.deviceName,
    this.customServiceName,
    this.onFileUploadProgress,
    this.onFileUploadComplete,
  });

  bool get isRunning =>
      _webServer?.isRunning ?? false || _externalServerRunning;
  int get port => _webServer?.port ?? 80;
  bool get isAdvertising => _isAdvertising;
  String? get actualHostname => actualHostnameNotifier.value;
  String? get localIP => _localIP;

  /// Mark that an external web server is running
  void setExternalServerRunning() {
    _externalServerRunning = true;
  }

  /// Start the web server
  Future<bool> startWebServer({int port = 80}) async {
    debugPrint(
      '[WebShareService] Starting web server (trying ports 80, 8080, 8000)',
    );
    if (_webServer != null && _webServer!.isRunning) {
      debugPrint('[WebShareService] Web server already running');
      return true;
    }

    // Try common ports: 80 preferred for captive detection, then 8080, then 8000
    final portsToTry = [80, 8080, 8000];
    int? successfulPort;

    for (final tryPort in portsToTry) {
      debugPrint(
        '[WebShareService] Attempting to start web server on port $tryPort...',
      );

      _webServer = WebServer(
        deviceName: deviceName,
        onFileUploadProgress: (filename, received, total) {
          debugPrint(
            '[WebShareService] Upload progress: $filename - $received/$total bytes',
          );
          onFileUploadProgress?.call(filename, received, total);
        },
        onFileUploadComplete: (filename, savedPath) async {
          debugPrint(
            '[WebShareService] ✅ File upload complete: $filename -> $savedPath',
          );
          onFileUploadComplete?.call(filename, savedPath);

          // Show notification for completed file upload
          NotificationService().showNotification(
            type: NotificationType.fileTransferCompleted,
            title: 'File Uploaded',
            body: 'Successfully received $filename via web share',
          );

          // Small delay to ensure file is fully written to disk
          await Future.delayed(const Duration(milliseconds: 100));

          // Note: Do not auto-share back uploads to the browser.
          // This prevents sent files from appearing in the Receive tab.
          // If needed later, gate with a setting to re-enable.
          final file = File(savedPath);
          if (await file.exists()) {
            // intentionally not adding to _availableFiles
            await _refreshSharedFiles();
          }

          // Track received file
          receivedFiles.value = [
            ReceivedFile(
              filename: filename,
              path: savedPath,
              sizeBytes: File(savedPath).lengthSync(),
              receivedAt: DateTime.now(),
            ),
            ...receivedFiles.value,
          ];
        },
        onClientConnected: (_) {
          connectedClients.value = _webServer!.connectedClientsCount;
          // Show notification for new client connection
          NotificationService().showNotification(
            type: NotificationType.webShareClientConnected,
            title: 'Web Client Connected',
            body: 'A browser has connected to your web share',
          );
        },
        onClientDisconnected: (_) {
          connectedClients.value = _webServer!.connectedClientsCount;

          // Show notification for client disconnection
          NotificationService().showNotification(
            type: NotificationType.webShareClientDisconnected,
            title: 'Web Client Disconnected',
            body: 'A browser has disconnected from your web share',
          );
        },
      );

      debugPrint(
        '[WebShareService] Created WebServer instance, calling start()...',
      );
      final success = await _webServer!.start(port: tryPort);
      debugPrint('[WebShareService] WebServer.start() returned: $success');

      if (success) {
        successfulPort = tryPort;
        debugPrint('[WebShareService] ✅ Web server started on port $tryPort');
        break;
      } else {
        debugPrint(
          '[WebShareService] ❌ Failed to start on port $tryPort, trying next port...',
        );
        _webServer = null; // Clean up failed instance
      }
    }

    if (successfulPort == null) {
      debugPrint('[WebShareService] ❌ Failed to start web server on any port');
      return false;
    }

    await _refreshSharedFiles();
    connectedClients.value = _webServer!.connectedClientsCount;

    // Start mDNS advertising
    final serviceName = customServiceName ?? deviceName;
    final sanitizedName = serviceName
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
        .toLowerCase();
    debugPrint('[WebShareService] 📱 Device name: "$deviceName"');
    debugPrint(
      '[WebShareService] 🎯 Custom service name: "$customServiceName"',
    );
    debugPrint('[WebShareService] 🔄 Service name used: "$serviceName"');
    debugPrint('[WebShareService] ✨ Sanitized name: "$sanitizedName"');
    debugPrint(
      '[WebShareService] About to start mDNS advertising as $sanitizedName._http._tcp.local',
    );
    AppLogger.i(
      '[WebShareService] Starting mDNS advertising as $sanitizedName._http._tcp.local',
      tag: 'WebShareService',
    );
    await startAdvertisingService(sanitizedName, successfulPort);

    return true;
  }

  /// Stop the web server
  Future<void> stopWebServer() async {
    debugPrint('[WebShareService] Stopping web server...');
    if (_webServer != null) {
      await _webServer!.stop();
      _webServer = null;
      debugPrint('[WebShareService] Web server stopped');
    }
    // Reset external server flag
    _externalServerRunning = false;

    // Stop mDNS advertising
    await stopAdvertisingService();

    // Clear all state
    sharedFiles.value = [];
    receivedFiles.value = [];
    connectedClients.value = 0;
    debugPrint('[WebShareService] All state cleared');
  }

  /// Get server URL for sharing
  Future<String?> getServerUrl() async {
    if (!isRunning) return null;

    // Get the network IP address that other devices can access
    final networkIp = await NetworkUtils.getLanIPv4();

    String ip;
    if (networkIp != null) {
      ip = networkIp;
      debugPrint(
        '[WebShareService] 🌐 Web share URL: http://$ip:$port (network IP detected)',
      );
    } else {
      // No network connection - use localhost for local access only
      ip = 'localhost';
      debugPrint(
        '[WebShareService] 🌐 Web share URL: http://$ip:$port (localhost - no network connection)',
      );
      debugPrint(
        '[WebShareService] 💡 Connect to WiFi network for other devices to access this service',
      );
    }

    return 'http://$ip:$port';
  }

  /// Get hostname URL for sharing
  /// Returns the actual mDNS hostname that will be resolved by other devices
  Future<String?> getHostnameUrl() async {
    if (!isRunning) return null;

    // Check if we have network connectivity
    final networkIp = await NetworkUtils.getLanIPv4();
    if (networkIp == null) {
      debugPrint(
        '[WebShareService] ⚠️ No network connection - hostname URL not available',
      );
      return null; // Don't show hostname URL when offline
    }

    // Use the actual system hostname (Platform.localHostname)
    // This is where the service is ACTUALLY reachable (e.g., iPhone.local)
    final platformHost = Platform.localHostname.toLowerCase();
    String hostnameForUrl;

    if (platformHost == 'localhost' || platformHost.isEmpty) {
      // Fallback to sanitized device name if Platform.localHostname fails
      hostnameForUrl = deviceName
          .replaceAll(' ', '-')
          .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
          .toLowerCase();
      debugPrint(
        '[WebShareService] Platform.localHostname unavailable, using deviceName: $hostnameForUrl',
      );
    } else {
      // Use the actual system hostname
      hostnameForUrl = platformHost;
      debugPrint(
        '[WebShareService] Using actual system hostname: $hostnameForUrl',
      );
    }

    final hostnameUrl = 'http://$hostnameForUrl.local:$port';

    debugPrint('[WebShareService] 🌐 Hostname URL generation:');
    debugPrint('[WebShareService]   📱 deviceName: "$deviceName"');
    debugPrint(
      '[WebShareService]   🎯 customServiceName: "$customServiceName"',
    );
    debugPrint(
      '[WebShareService]   🔄 Platform.localHostname: "$platformHost"',
    );
    debugPrint('[WebShareService]   🌐 Accessible URL: $hostnameUrl');
    debugPrint(
      '[WebShareService]   💡 This matches where the service is actually reachable',
    );
    return hostnameUrl;
  }

  /// Share a local file (register for browser download)
  Future<String?> shareFile(File file) async {
    if (!isRunning) return null;
    if (!file.existsSync()) return null;
    final id = _webServer!.addFileForDownload(file.path, p.basename(file.path));
    await _refreshSharedFiles();
    return id;
  }

  /// Remove a shared file by id
  Future<void> removeSharedFile(String id) async {
    if (!isRunning) return;
    _webServer!.removeFileFromDownload(id);
    await _refreshSharedFiles();
  }

  Future<void> _refreshSharedFiles() async {
    if (!isRunning) {
      sharedFiles.value = [];
      return;
    }
    final list = _webServer!.getSharedFiles();
    sharedFiles.value = list
        .map(
          (m) => SharedFile(
            id: m['id'] as String,
            filename: m['filename'] as String,
            sizeBytes: m['size'] as int,
            sharedAt:
                DateTime.tryParse(m['sharedAt'] as String? ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
  }

  /// Dispose the service
  void dispose() {
    stopWebServer();
  }

  /// Start advertising the service via mDNS
  Future<void> startAdvertisingService(String instanceName, int port) async {
    if (_isAdvertising) {
      debugPrint('[WebShareService] Advertising already active, skipping');
      return;
    }

    debugPrint(
      '[WebShareService] Starting advertising service with instanceName: $instanceName, port: $port',
    );

    try {
      // Get local IP address
      final localIP = await NetworkUtils.getLanIPv4();

      if (localIP == null) {
        debugPrint(
          '[WebShareService] ⚠️ No network IP found - advertising will be skipped but web server will still run',
        );
        debugPrint(
          '[WebShareService] 💡 Connect to WiFi network for other devices to discover this service',
        );
        // Set fallback hostname even without network IP
        final fallbackHostname = deviceName
            .replaceAll(' ', '-')
            .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
            .toLowerCase();
        _actualHostname = fallbackHostname;
        actualHostnameNotifier.value = fallbackHostname;
        debugPrint(
          '[WebShareService] Set fallback hostname: $fallbackHostname',
        );
        // Don't return - allow web server to run even without advertising
        return;
      }

      debugPrint('[WebShareService] ✅ Got local IP: $localIP');

      // Store local IP for QR code (needed for Android)
      _localIP = localIP;

      // Create hostname from service name (without .local - domain adds it)
      final hostname = instanceName
          .replaceAll(' ', '-')
          .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
          .toLowerCase();
      debugPrint('[WebShareService] Created hostname: $hostname');

      // Use NSD package on both platforms for consistent behavior
      if (Platform.isAndroid) {
        // On Android, use NSD (native NSD API wrapper)
        debugPrint('[WebShareService] Using NSD for Android advertising');
      } else {
        // On iOS/macOS, use NSD (wraps Bonjour/NetService API)
        debugPrint('[WebShareService] Using NSD for iOS/macOS advertising');
      }

      // Use NSD package for advertising on both platforms
      try {
        // The actual hostname where the service can be reached is determined by
        // the system's mDNS hostname (e.g., iPhone.local, Android_XXXX.local)
        // We can't control this - it's set by the OS
        // So we'll try to detect it and store it in TXT records
        String actualHostname;

        if (Platform.isAndroid) {
          // On Android, get the actual hostname from native code
          // because Platform.localHostname and NSD don't provide the .local hostname
          try {
            final androidHostname = await _hostnameChannel.invokeMethod<String>(
              'getActualHostname',
            );
            if (androidHostname != null && androidHostname.isNotEmpty) {
              actualHostname = androidHostname;
              debugPrint(
                '[WebShareService] ✅ Got actual Android hostname: $actualHostname',
              );
            } else {
              throw Exception('Android hostname is null or empty');
            }
          } catch (e) {
            debugPrint(
              '[WebShareService] ⚠️ Failed to get Android hostname: $e',
            );
            // Fallback to sanitized device name
            actualHostname = deviceName
                .replaceAll(' ', '-')
                .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
                .toLowerCase();
            debugPrint(
              '[WebShareService] Using fallback deviceName: $actualHostname',
            );
          }
        } else {
          // On iOS/macOS, Platform.localHostname works correctly
          final platformHost = Platform.localHostname.toLowerCase();

          if (platformHost == 'localhost' || platformHost.isEmpty) {
            // Platform.localHostname failed, fallback to sanitized device name
            actualHostname = deviceName
                .replaceAll(' ', '-')
                .replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '')
                .toLowerCase();
            debugPrint(
              '[WebShareService] Platform.localHostname returned "$platformHost", using deviceName: $actualHostname',
            );
          } else {
            // Use the actual platform hostname
            actualHostname = platformHost;
            debugPrint(
              '[WebShareService] Using Platform.localHostname: $actualHostname',
            );
          }
        }

        // Store for QR code and external access
        _actualHostname = actualHostname;
        actualHostnameNotifier.value = actualHostname;

        debugPrint('[WebShareService] Creating NSD registration...');
        _nsdRegistration = await register(
          Service(
            name: instanceName,
            type: '_http._tcp',
            port: port,
            txt: {
              'ip': Uint8List.fromList(utf8.encode(localIP)),
              'host': Uint8List.fromList(
                utf8.encode('$actualHostname.local'),
              ), // Store actual system hostname
            },
          ),
        );

        debugPrint('[WebShareService] ✅ NSD advertising started');

        // Wait a bit to ensure registration completes
        await Future.delayed(Duration(seconds: 1));

        // Get the actual hostname using different methods per platform
        if (Platform.isAndroid) {
          // Android: Use multicast_dns SRV resolution
          // NSD on Android returns IP instead of hostname
          debugPrint(
            '[WebShareService] 🔍 Attempting to resolve actual hostname via SRV record...',
          );
          try {
            final srvHostname =
                await MdnsSrvResolver.getOwnHostname(
                  serviceName: instanceName,
                  serviceType: '_http._tcp',
                ).timeout(
                  Duration(seconds: 3),
                  onTimeout: () {
                    debugPrint(
                      '[WebShareService] ⏱️ SRV resolution timed out after 3s',
                    );
                    return null;
                  },
                );

            if (srvHostname != null && srvHostname.isNotEmpty) {
              _actualHostname = srvHostname;
              actualHostnameNotifier.value = srvHostname;
              debugPrint(
                '[WebShareService] ✅ SRV hostname resolved: $_actualHostname.local',
              );
              debugPrint(
                '[WebShareService] 🎯 This is the ACTUAL reachable hostname!',
              );
            } else {
              debugPrint(
                '[WebShareService] ⚠️ Could not resolve SRV hostname, using fallback',
              );
            }
          } catch (e) {
            debugPrint('[WebShareService] ⚠️ SRV resolution failed: $e');
            debugPrint(
              '[WebShareService] Using previously determined hostname: $_actualHostname',
            );
          }
        } else {
          // iOS: Use NSD discovery to get the actual hostname
          // NSD on iOS correctly returns the .local hostname
          debugPrint(
            '[WebShareService] 🔍 Using NSD discovery to get actual hostname...',
          );
          try {
            final discovery = await startDiscovery('_http._tcp');
            bool hostnameFound = false;

            // Listen for our own service
            discovery.addServiceListener((nsdService, status) {
              if (status == ServiceStatus.found &&
                  nsdService.name == instanceName &&
                  nsdService.host != null &&
                  nsdService.host!.isNotEmpty) {
                debugPrint(
                  '[WebShareService] 📡 Found our service via discovery: ${nsdService.name}',
                );
                debugPrint(
                  '[WebShareService]   - hostname: ${nsdService.host}',
                );

                // Extract hostname without trailing dot and .local suffix
                String hostname = nsdService.host!;
                if (hostname.endsWith('.')) {
                  hostname = hostname.substring(0, hostname.length - 1);
                }
                if (hostname.endsWith('.local')) {
                  hostname = hostname.substring(0, hostname.length - 6);
                }

                if (_actualHostname != hostname) {
                  _actualHostname = hostname;
                  actualHostnameNotifier.value = hostname;
                  debugPrint(
                    '[WebShareService] ✅ Updated hostname from NSD: $_actualHostname',
                  );
                  hostnameFound = true;
                }
              }
            });

            // Wait up to 2 seconds for discovery
            await Future.delayed(Duration(seconds: 2));

            // Stop discovery
            await stopDiscovery(discovery);

            if (hostnameFound) {
              debugPrint(
                '[WebShareService] ✅ iOS hostname resolved via NSD discovery',
              );
            } else {
              debugPrint(
                '[WebShareService] ℹ️ Using Platform.localHostname as fallback',
              );
            }
          } catch (e) {
            debugPrint('[WebShareService] ⚠️ NSD discovery failed: $e');
            debugPrint(
              '[WebShareService] Using previously determined hostname: $_actualHostname',
            );
          }
        }

        debugPrint(
          '[WebShareService] 🎯 NSD setup complete - hostname access should now work',
        );
      } catch (e) {
        debugPrint('[WebShareService] ⚠️ NSD advertising failed: $e');
        if (Platform.isIOS) {
          debugPrint(
            '[WebShareService] 💡 SOLUTION: Add multicast entitlement to iOS project',
          );
        }
        debugPrint(
          '[WebShareService] 💡 IP access still works: http://$localIP:$port',
        );
        // Don't rethrow - allow web server to continue without advertising
        _nsdRegistration = null;
      }

      _isAdvertising = true;
      final deviceHostname = Platform.localHostname.toLowerCase();
      debugPrint(Platform.localHostname);
      debugPrint(
        '[WebShareService] ✅ Started advertising mDNS service: $instanceName._http._tcp.local',
      );
      debugPrint(
        '[WebShareService] Service details: instance=$instanceName, hostname=$deviceHostname.local, ip=$localIP, port=$port',
      );
      debugPrint(
        '[WebShareService] 🔍 TEST: Try accessing http://$deviceHostname.local from another device',
      );
      debugPrint(
        '[WebShareService] 🔍 TEST: Or try: ping $deviceHostname.local',
      );
      debugPrint(
        '[WebShareService] 🔍 TEST: Or try: nslookup $deviceHostname.local',
      );
      debugPrint(
        '[WebShareService] 💡 If hostname doesn\'t work, use IP: http://$localIP:$port',
      );
    } catch (e) {
      debugPrint('[WebShareService] ❌ Failed to start advertising: $e');
      debugPrint('[WebShareService] Error details: ${e.toString()}');
      // Reset state on failure
      _isAdvertising = false;
      _nsdRegistration = null;
    }
  }

  /// Stop advertising the service
  Future<void> stopAdvertisingService() async {
    if (!_isAdvertising) return;

    try {
      if (_nsdRegistration != null) {
        debugPrint('[WebShareService] Stopping NSD registration...');
        await unregister(_nsdRegistration!);
        debugPrint('[WebShareService] ✅ NSD registration stopped');
        _nsdRegistration = null;
      }

      _isAdvertising = false;
      debugPrint('[WebShareService] Stopped advertising mDNS service');
    } catch (e) {
      debugPrint('[WebShareService] Failed to stop advertising: $e');
    }
  }

  /// Discover HTTP services on the local network via mDNS
  Future<List<Map<String, dynamic>>> discoverHttpServices() async {
    debugPrint('[WebShareService] Starting HTTP service discovery...');

    List<Map<String, dynamic>> services = [];

    try {
      // Use NSD for discovery on all platforms
      debugPrint('[WebShareService] Starting NSD discovery...');
      final discovery = await startDiscovery('_http._tcp');

      // Set up service listener
      discovery.addServiceListener((nsdService, status) async {
        print(nsdService);
        if (status == ServiceStatus.found) {
          debugPrint(
            '[WebShareService] ========== DISCOVERED SERVICE ==========',
          );
          debugPrint('[WebShareService] Found service: ${nsdService.name}');
          debugPrint('[WebShareService]   - host: ${nsdService.host}');
          debugPrint('[WebShareService]   - port: ${nsdService.port}');
          debugPrint(
            '[WebShareService]   - addresses: ${nsdService.addresses}',
          );
          debugPrint('[WebShareService]   - txt: ${nsdService.txt}');

          // Get hostname from NSD service - this is the actual .local hostname
          String? resolvedHost = nsdService.host;
          String? ip;

          // If this is our own service, update the actual hostname for QR code
          if (nsdService.host != null && nsdService.host!.isNotEmpty) {
            // On Android, nsdService.host returns IP - canonicalHostName doesn't resolve .local
            // This is a known Android limitation - mDNS hostnames aren't accessible via standard APIs
            if (Platform.isAndroid) {
              debugPrint(
                '[WebShareService]   ℹ️ Using IP address (Android limitation): ${nsdService.host}',
              );
              ip = nsdService.host;
              _localIP = ip;
              resolvedHost = ip;
            } else {
              // iOS or already has .local hostname
              final hostWithoutSuffix = nsdService.host!.endsWith('.local')
                  ? nsdService.host!.substring(0, nsdService.host!.length - 6)
                  : nsdService.host;

              if (_actualHostname != hostWithoutSuffix) {
                _actualHostname = hostWithoutSuffix;
                actualHostnameNotifier.value = hostWithoutSuffix;
                debugPrint(
                  '[WebShareService] 🎯 Updated actual hostname for QR code: $_actualHostname',
                );
              }
            }
          }

          // Get IP from addresses
          if (nsdService.addresses != null &&
              nsdService.addresses!.isNotEmpty) {
            ip = nsdService.addresses!.first.address;
            debugPrint('[WebShareService]   ✅ Using NSD IP: $ip');
          }

          // Read TXT record data as fallback
          if (nsdService.txt != null) {
            try {
              final txtHost = nsdService.txt!['host'];
              final txtIp = nsdService.txt!['ip'];

              if (txtHost != null) {
                final hostStr = utf8.decode(txtHost);
                debugPrint('[WebShareService]   - TXT host: $hostStr');

                // Use TXT host if NSD host is not available
                if (resolvedHost == null || resolvedHost.isEmpty) {
                  resolvedHost = hostStr;
                  debugPrint(
                    '[WebShareService]   ℹ️ Falling back to TXT host: $resolvedHost',
                  );
                }
              }

              if (txtIp != null && ip == null) {
                ip = utf8.decode(txtIp);
                debugPrint('[WebShareService]   - TXT ip: $ip');
              }
            } catch (e) {
              debugPrint('[WebShareService]   - Error reading TXT records: $e');
            }
          }

          // Validate we have both hostname and IP
          if (resolvedHost != null && ip != null) {
            // Use the resolved hostname (should be like Android_M874CMBN.local or iPhone.local)
            final hostname = resolvedHost;

            services.add({
              'instance': '${nsdService.name}._http._tcp.local',
              'target': resolvedHost,
              'ip': ip,
              'port': nsdService.port,
              'url': 'http://$hostname:${nsdService.port}/',
              'ipUrl': 'http://$ip:${nsdService.port}/',
            });
            debugPrint(
              '[WebShareService] ✅ Added service: ${nsdService.name} -> $hostname:${nsdService.port} ($ip)',
            );
          } else {
            debugPrint(
              '[WebShareService]   ⚠️ Missing hostname or IP, skipping service',
            );
          }
        }
      });

      // Stop discovery after 10 seconds
      await Future.delayed(Duration(seconds: 10));

      try {
        await stopDiscovery(discovery);
        debugPrint('[WebShareService] Discovery stopped');
      } catch (e) {
        debugPrint('[WebShareService] Error stopping discovery: $e');
      }
    } catch (e) {
      debugPrint('[WebShareService] Error discovering services: $e');
    }

    return services;
  }

  /// Add a file received via WebRTC to the received files list
  void addWebRTCReceivedFile(String filename, String path, int sizeBytes) {
    debugPrint('[WebShareService] Adding WebRTC received file: $filename');
    receivedFiles.value = [
      ReceivedFile(
        filename: filename,
        path: path,
        sizeBytes: sizeBytes,
        receivedAt: DateTime.now(),
      ),
      ...receivedFiles.value,
    ];
  }

  /// Add a file sent via WebRTC to the shared files list
  void addWebRTCSharedFile(String id, String filename, int sizeBytes) {
    debugPrint('[WebShareService] Adding WebRTC shared file: $filename');
    sharedFiles.value = [
      SharedFile(
        id: id,
        filename: filename,
        sizeBytes: sizeBytes,
        sharedAt: DateTime.now(),
      ),
      ...sharedFiles.value,
    ];
  }
}

class SharedFile {
  final String id;
  final String filename;
  final int sizeBytes;
  final DateTime sharedAt;
  SharedFile({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.sharedAt,
  });

  String get humanSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = sizeBytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed((i == 0) ? 0 : 1)} ${units[i]}';
  }
}

class ReceivedFile {
  final String filename;
  final String path;
  final int sizeBytes;
  final DateTime receivedAt;
  ReceivedFile({
    required this.filename,
    required this.path,
    required this.sizeBytes,
    required this.receivedAt,
  });

  String get humanSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = sizeBytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed((i == 0) ? 0 : 1)} ${units[i]}';
  }
}
