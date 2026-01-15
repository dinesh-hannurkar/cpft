import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fylooo/utils/permissions.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/services/wifi_service.dart';
import 'package:flutter/foundation.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';

import 'package:fylooo/services/discovery_service.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';

class QrScannerScreen extends StatefulWidget {
  final DiscoveryService? discoveryService;
  final String? myDeviceName;

  const QrScannerScreen({super.key, this.discoveryService, this.myDeviceName});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? controller;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final platformStr = kIsWeb ? 'web' : defaultTargetPlatform.name;
    debugPrint('QR Scanner: initState called, platform: $platformStr');
    _initializeScanner();
  }

  Future<void> _initializeScanner() async {
    try {
      await _checkCameraPermission();

      if (_hasPermission && mounted) {
        setState(() {
          controller = MobileScannerController(
            detectionSpeed: DetectionSpeed.noDuplicates,
            facing: CameraFacing.back,
          );
        });
      } else {
        debugPrint('QR Scanner: Permission not granted or widget unmounted');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    setState(() {
      _isCheckingPermission = true;
    });

    if (kIsWeb) {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
      return;
    }

    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
    } else if (status.isDenied || status.isPermanentlyDenied) {
      final result = await AppPermissions.runGuarded(
        () => Permission.camera.request(),
      );
      setState(() {
        _hasPermission = result.isGranted;
        _isCheckingPermission = false;
      });

      if (!result.isGranted) {
        if (result.isPermanentlyDenied) {
          _showPermissionDialog();
        } else {
          if (mounted) Navigator.of(context).pop();
        }
      }
    } else {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera permission is required to scan QR codes. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to previous screen
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            'Scan QR Code',
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            'Scan QR Code',
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Text(
            'Camera permission is required to scan QR codes.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.blackDark,
      appBar: AppBar(
        backgroundColor: AppColors.blackDark,
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: AppColors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (controller != null) ...[
            IconButton(
              icon: const Icon(Icons.flashlight_on, color: AppColors.white),
              onPressed: () => controller!.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch, color: AppColors.white),
              onPressed: () => controller!.switchCamera(),
            ),
          ],
        ],
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.red,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          controller = null;
                        });
                        _initializeScanner();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : controller == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.white),
                  const SizedBox(height: 16),
                  Text(
                    _isCheckingPermission
                        ? 'Checking camera permission...'
                        : 'Initializing camera...',
                    style: const TextStyle(color: AppColors.white),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                MobileScanner(
                  controller: controller!,
                  onDetect: (capture) {
                    if (_isProcessing) {
                      debugPrint(
                        'QR Scanner: Already processing, ignoring detection',
                      );
                      return;
                    }

                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null &&
                          barcode.rawValue!.isNotEmpty) {
                        setState(() => _isProcessing = true);
                        _handleScannedCode(barcode.rawValue!);
                        break;
                      }
                    }
                  },
                ),

                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            // Corner brackets
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                    left: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                    right: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                    left: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                    right: BorderSide(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Instructions
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSizes.lg),
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSizes.lg,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(AppSizes.md),
                        ),
                        child: const Text(
                          'Position the QR code within the frame to scan',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Camera Active - Point at QR Code',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _handleScannedCode(String code) {
    if (code.startsWith('WIFI:')) {
      debugPrint('QR Scanner: WiFi QR code detected');
      final wifiData = _parseWifiQrCode(code);
      if (wifiData != null) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          _autoConnectOnIOS(wifiData);
        } else {
          _autoConnectOnAndroid(wifiData);
        }
      } else {
        _isProcessing = false;
        _showErrorDialog('Invalid WiFi QR code format');
      }
    } else {
      debugPrint(
        'QR Scanner: Not a WiFi QR code: ${code.substring(0, code.length > 50 ? 50 : code.length)}',
      );
      _isProcessing = false;
      _showErrorDialog('Not a WiFi QR code. Scanned: $code');
    }
  }

  Future<void> _autoConnectOnIOS(Map<String, String> wifiData) async {
    final ssid = wifiData['ssid']!;
    final password = wifiData['password'];
    final security = (wifiData['security'] ?? 'WPA2');

    try {
      await WifiService.connectToWifi(
        ssid: ssid,
        password: password?.isNotEmpty == true ? password : null,
        security: security,
      );

      if (!mounted) return;

      // Notify user
      AppSnackbar.showSuccess(
        context,
        'Connected to WiFi! Searching for host...',
      );

      // Trigger discovery and navigation (same as Android)
      if (widget.discoveryService != null && widget.myDeviceName != null) {
        // Enable auto-accept for incoming connections from the host
        widget.discoveryService!.connectionManager?.setAutoAccept(true);

        // Define the expected IP for WiFi Direct Group Owner (standard gateway)
        const groupOwnerIp = '192.168.49.1';
        bool found = false;

        void navigateToChat(String name, int port) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                deviceName: name,
                ipAddress: groupOwnerIp,
                port: port,
                myDeviceName: widget.myDeviceName!,
                connectionManager: widget.discoveryService!.connectionManager!,
              ),
            ),
          );
        }

        // Check current devices
        final devices = widget.discoveryService!.discoveredDevices;
        for (final DeviceInfo device in devices.values) {
          if (device.ip == groupOwnerIp) {
            navigateToChat(device.name, device.port);
            found = true;
            break;
          }
        }

        if (!found) {
          void onDiscovered(String name, String ip, int port) {
            if (ip == groupOwnerIp) {
              widget.discoveryService!.removeDiscoveryListener(onDiscovered);
              navigateToChat(name, port);
            }
          }

          widget.discoveryService!.addDiscoveryListener(onDiscovered);

          // Force announcements to speed up discovery
          widget.discoveryService!.announce();

          Future.delayed(const Duration(seconds: 10), () {
            if (mounted) {
              widget.discoveryService!.removeDiscoveryListener(onDiscovered);
              // Fallback navigation
              if (!found) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      deviceName: 'P2P Host',
                      ipAddress: groupOwnerIp,
                      port: 53317,
                      myDeviceName: widget.myDeviceName!,
                      connectionManager:
                          widget.discoveryService!.connectionManager!,
                    ),
                  ),
                );
              }
            }
          });
        }
      } else {
        // Fallback if no services
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showErrorDialog('Failed to connect: $e');
    }
  }

  Future<void> _autoConnectOnAndroid(Map<String, String> wifiData) async {
    final ssid = wifiData['ssid']!;
    final password = wifiData['password'];

    try {
      if (!mounted) return;

      // Import WiFiDirectService at the top of the file
      final wifiDirectService = WiFiDirectService();
      await wifiDirectService.initialize();

      // Show connecting message using AppSnackbar
      AppSnackbar.showInfo(context, 'Connecting to $ssid via WiFi Direct...');

      // Enable auto-accept for incoming connections from the host
      widget.discoveryService?.connectionManager?.setAutoAccept(true);

      final success = await wifiDirectService.connectToGroup(
        ssid,
        password ?? '',
      );

      if (!mounted) return;

      if (success) {
        AppSnackbar.showSuccess(
          context,
          'Connected! Waiting for device discovery...',
        );

        // Wait for mDNS to discover the device if we have the service
        if (widget.discoveryService != null && widget.myDeviceName != null) {
          // Define the expected IP for WiFi Direct Group Owner
          const groupOwnerIp = '192.168.49.1';

          // Check if already discovered
          bool found = false;

          // Helper to navigate
          void navigateToChat(String name, int port) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  deviceName: name,
                  ipAddress: groupOwnerIp,
                  port: port,
                  myDeviceName: widget.myDeviceName!,
                  connectionManager:
                      widget.discoveryService!.connectionManager!,
                ),
              ),
            );
          }

          // Check current devices first
          final devices = widget.discoveryService!.discoveredDevices;
          for (final DeviceInfo device in devices.values) {
            if (device.ip == groupOwnerIp) {
              navigateToChat(device.name, device.port);
              found = true;
              break;
            }
          }

          if (!found) {
            // Listen for new devices
            void onDiscovered(String name, String ip, int port) {
              if (ip == groupOwnerIp) {
                widget.discoveryService!.removeDiscoveryListener(onDiscovered);
                navigateToChat(name, port);
              }
            }

            widget.discoveryService!.addDiscoveryListener(onDiscovered);

            // Timeout after 10 seconds (mDNS can be slow)
            Future.delayed(const Duration(seconds: 10), () {
              if (mounted) {
                widget.discoveryService!.removeDiscoveryListener(onDiscovered);
                // Fallback if not discovered: Just go back or try to connect assuming defaults
                // But without port/name it's hard.
                // We can try default port 53317 and generic name.
                if (!found) {
                  // Don't navigate if already found
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        deviceName: 'P2P Host',
                        ipAddress: groupOwnerIp,
                        port: 53317,
                        myDeviceName: widget.myDeviceName!,
                        connectionManager:
                            widget.discoveryService!.connectionManager!,
                      ),
                    ),
                  );
                }
              }
            });
          }
        } else {
          // Fallback if service not provided
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop(); // Close scanner
          }
        }
      } else {
        _isProcessing = false;
        AppSnackbar.showError(
          context,
          'Failed to connect to WiFi Direct group',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _isProcessing = false;
      AppSnackbar.showError(context, 'Connection failed: $e');
    }
  }

  Map<String, String>? _parseWifiQrCode(String code) {
    try {
      final content = code.substring(5).replaceAll(';;', '');
      final parts = content.split(';');
      String? ssid, security, password;

      for (final part in parts) {
        if (part.startsWith('S:')) {
          ssid = part.substring(2);
        } else if (part.startsWith('T:')) {
          security = part.substring(2);
        } else if (part.startsWith('P:')) {
          password = part.substring(2);
        }
      }

      if (ssid != null) {
        final result = {
          'ssid': ssid,
          'security': security ?? 'nopass',
          'password': password ?? '',
        };
        return result;
      }
    } catch (e) {
      debugPrint('Error parsing WiFi QR code: $e');
    }
    return null;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isProcessing = false);
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
