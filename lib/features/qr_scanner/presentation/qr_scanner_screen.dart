import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/services/wifi_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _hasPermission = false;
  bool _isCheckingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    setState(() {
      _isCheckingPermission = true;
    });

    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
    } else if (status.isDenied || status.isPermanentlyDenied) {
      final result = await Permission.camera.request();
      setState(() {
        _hasPermission = result.isGranted;
        _isCheckingPermission = false;
      });

      if (!result.isGranted) {
        if (result.isPermanentlyDenied) {
          // Show dialog to open settings
          _showPermissionDialog();
        } else {
          // Permission denied, go back
          Navigator.of(context).pop();
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
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on, color: Colors.white),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleScannedCode(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          // Overlay with scan area
          Container(
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
                            top: BorderSide(color: AppColors.primary, width: 4),
                            left: BorderSide(color: AppColors.primary, width: 4),
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
                            top: BorderSide(color: AppColors.primary, width: 4),
                            right: BorderSide(color: AppColors.primary, width: 4),
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
                            bottom: BorderSide(color: AppColors.primary, width: 4),
                            left: BorderSide(color: AppColors.primary, width: 4),
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
                            bottom: BorderSide(color: AppColors.primary, width: 4),
                            right: BorderSide(color: AppColors.primary, width: 4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSizes.lg),
              margin: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppSizes.md),
              ),
              child: const Text(
                'Position the QR code within the frame to scan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleScannedCode(String code) {
    // Stop scanning
    controller.stop();

    // Parse WiFi QR code format: WIFI:S:<SSID>;T:<WPA|WEP|WPA2|nopass>;P:<password>;;
    if (code.startsWith('WIFI:')) {
      final wifiData = _parseWifiQrCode(code);
      if (wifiData != null) {
        // Auto-connect on both platforms without custom dialog
        if (Theme.of(context).platform == TargetPlatform.iOS) {
          _autoConnectOnIOS(wifiData);
        } else {
          _autoConnectOnAndroid(wifiData);
        }
      } else {
        _showErrorDialog('Invalid WiFi QR code format');
      }
    } else {
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
      Navigator.of(context).pop(); // Close scanner after requesting join
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showErrorDialog('Failed to connect: $e');
    }
  }

  Future<void> _autoConnectOnAndroid(Map<String, String> wifiData) async {
    final ssid = wifiData['ssid']!;
    final password = wifiData['password'];
    final security = (wifiData['security'] ?? 'WPA2');

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to $ssid...'), duration: const Duration(seconds: 3)),
      );

      await WifiService.connectToWifi(
        ssid: ssid,
        password: password?.isNotEmpty == true ? password : null,
        security: security,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection requested for $ssid'), duration: const Duration(seconds: 2)),
      );
      Navigator.of(context).pop(); // Close scanner
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showErrorDialog('Failed to connect: $e');
    }
  }

  Map<String, String>? _parseWifiQrCode(String code) {
    try {
      print('Parsing WiFi QR code: $code');

      // Remove WIFI: prefix and ;; suffix
      final content = code.substring(5).replaceAll(';;', '');
      print('Content after removing WIFI: and ;; : $content');

      final parts = content.split(';');
      print('Split parts: $parts');

      String? ssid, security, password;

      for (final part in parts) {
        print('Processing part: $part');
        if (part.startsWith('S:')) {
          ssid = part.substring(2);
          print('Found SSID: "$ssid"');
        } else if (part.startsWith('T:')) {
          security = part.substring(2);
          print('Found security: "$security"');
        } else if (part.startsWith('P:')) {
          password = part.substring(2);
          print('Found password: "$password"');
        }
      }

      if (ssid != null) {
        final result = {
          'ssid': ssid,
          'security': security ?? 'nopass',
          'password': password ?? '',
        };
        print('Parsed WiFi data: $result');
        return result;
      }
    } catch (e) {
      debugPrint('Error parsing WiFi QR code: $e');
    }
    return null;
  }

  // Dialog-based connection flow removed; auto-connect is used instead.

  // Removed legacy dialog/manual connection helpers in favor of auto-connect.

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
              controller.start(); // Resume scanning
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}