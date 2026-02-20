import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fylooo/core/constants/app_sizes.dart';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fylooo/utils/permissions.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/services/wifi_service.dart';
import 'package:flutter/foundation.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';

import 'package:fylooo/services/discovery_service.dart';

import 'package:fylooo/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';

class QrScannerScreen extends StatefulWidget {
  final DiscoveryService? discoveryService;
  final String? myDeviceName;

  const QrScannerScreen({super.key, this.discoveryService, this.myDeviceName});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

enum ScannerState { scanning, detected, connecting, connected }

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? controller;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  bool _isProcessing = false;
  String? _errorMessage;
  ScannerState _scannerState = ScannerState.scanning;
  String _connectionStatus = '';
  late AnimationController _animationController;
  int _currentStep = 0; // 0: Wifi, 1: Discovery, 2: Handshake

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
    _animationController.dispose();
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
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              _errorMessage != null
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
                          const CircularProgressIndicator(
                            color: AppColors.white,
                          ),
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
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_scannerState == ScannerState.scanning)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 32.0,
                              left: 24,
                              right: 24,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Scan to Connect',
                                  style: TextStyle(
                                    color: AppColors.darkPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Point your camera at the QR code\nshown on the other device',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.blueGrey.shade600,
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Center(
                          child: Container(
                            width: 300,
                            height: 300,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
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

                                      final List<Barcode> barcodes =
                                          capture.barcodes;
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

                                  // Premium Scanner Overlay
                                  CustomPaint(
                                    painter: ScannerOverlayPainter(
                                      animation: _animationController,
                                      borderColor: AppColors.skyBlue,
                                      borderRadius: 24,
                                      borderLength: 40,
                                      cutOutWidth:
                                          260, // Slightly smaller than container
                                      cutOutHeight: 260,
                                    ),
                                    child: Container(),
                                  ),

                                  // Connection Progress Overlay
                                  if (_scannerState != ScannerState.scanning)
                                    _buildConnectionOverlay(),
                                  // Close Button
                                  Positioned(
                                    top: AppSizes.sm,
                                    // left: 0,
                                    right: AppSizes.lg,
                                    child: Center(
                                      child: AppIconButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: Icons.close_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleScannedCode(String code) async {
    // Stop camera immediately
    await controller?.stop();

    setState(() {
      _scannerState = ScannerState.detected;
      _connectionStatus = 'QR Code Detected';
    });

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _scannerState = ScannerState.connecting;
      _currentStep = 0;
    });

    if (code.startsWith('WIFI:')) {
      debugPrint('QR Scanner: WiFi QR code detected');
      final wifiData = _parseWifiQrCode(code);
      if (wifiData != null) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          _autoConnectOnAndroid(wifiData);
        } else {
          // iOS, MacOS, Windows, etc. treat this as a standard WiFi connection
          _connectToStandardWifi(wifiData);
        }
      } else {
        setState(() {
          _errorMessage = 'Invalid WiFi QR code format';
          _isProcessing = false;
          _scannerState = ScannerState.scanning;
        });
        controller?.start();
      }
    } else {
      debugPrint(
        'QR Scanner: Not a WiFi QR code: ${code.substring(0, code.length > 50 ? 50 : code.length)}',
      );
      _isProcessing = false;
      _showErrorDialog('Not a WiFi QR code. Scanned: $code');
    }
  }

  Future<void> _connectToStandardWifi(Map<String, String> wifiData) async {
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

      setState(() {
        _currentStep = 1;
      });

      // Trigger discovery and navigation (same as Android)
      if (widget.discoveryService != null && widget.myDeviceName != null) {
        // Enable auto-accept for incoming connections from the host
        widget.discoveryService!.connectionManager?.setAutoAccept(true);

        // Define the expected IP for WiFi Direct Group Owner (standard gateway)
        const groupOwnerIp = '192.168.49.1';
        bool found = false;
        int attempts = 0;

        void navigateToChat(String name, int port) {
          if (!mounted) return;
          setState(() => _currentStep = 2);
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
              found = true;
            }
          }

          widget.discoveryService!.addDiscoveryListener(onDiscovered);

          // Force announcements to speed up discovery
          widget.discoveryService!.announce();

          // Poll/Announce cycle
          Timer.periodic(const Duration(seconds: 2), (timer) {
            if (!mounted || found || attempts > 5) {
              timer.cancel();
              if (!found && mounted) {
                widget.discoveryService!.removeDiscoveryListener(onDiscovered);
                _resetScanner('Discovery timed out. Please try again.');
              }
              return;
            }
            attempts++;
            widget.discoveryService!.announce();
          });
        }
      } else {
        // Fallback if no services
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      _resetScanner('Failed to connect: $e');
    }
  }

  void _resetScanner([String? error]) {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _scannerState = ScannerState.scanning;
      _connectionStatus = '';
      if (error != null) {
        AppSnackbar.showError(context, error);
      }
    });
    controller?.start();
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

        setState(() {
          _currentStep = 1;
        });

        // Wait for mDNS to discover the device if we have the service
        if (widget.discoveryService != null && widget.myDeviceName != null) {
          // Define the expected IP for WiFi Direct Group Owner
          const groupOwnerIp = '192.168.49.1';

          // Check if already discovered
          bool found = false;
          int attempts = 0;

          // Helper to navigate
          void navigateToChat(String name, int port) {
            if (!mounted) return;
            setState(() => _currentStep = 2);
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
                found = true;
              }
            }

            widget.discoveryService!.addDiscoveryListener(onDiscovered);
            widget.discoveryService!.announce();

            setState(() {
              _currentStep = 1;
            });
            widget.discoveryService!.announce();

            // Active discovery loop
            Timer.periodic(const Duration(seconds: 2), (timer) {
              if (!mounted || found || attempts > 5) {
                timer.cancel();
                if (!found && mounted) {
                  widget.discoveryService!.removeDiscoveryListener(
                    onDiscovered,
                  );
                  _resetScanner('Discovery timed out. Please try again.');
                }
                return;
              }
              attempts++;
              widget.discoveryService!.announce();
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
        _resetScanner('Failed to connect to WiFi Direct group');
      }
    } catch (e) {
      if (!mounted) return;
      _resetScanner('Connection failed: $e');
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

  Widget _buildCompactConnectionSteps() {
    return Column(
      children: [
        _buildStep('Connecting to WiFi Network', _currentStep >= 0),
        const SizedBox(height: 12),
        _buildStep('Discovering Device', _currentStep >= 1),
        const SizedBox(height: 12),
        _buildStep('Finalizing Connection', _currentStep >= 2),
      ],
    );
  }

  Widget _buildStep(String label, bool isActive) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.grey[100],
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? AppColors.primary : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: isActive
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? AppColors.darkPrimary : Colors.grey[500],
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              spreadRadius: 4,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                if (_scannerState == ScannerState.detected) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.green,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'QR Code Detected',
                            style: TextStyle(
                              color: AppColors.darkPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Establishing connection...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else if (_scannerState == ScannerState.connecting) ...[
                  // Connecting State Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Connecting...',
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // Centered compact steps
                  Center(child: _buildCompactConnectionSteps()),
                  const SizedBox(height: 24),
                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        _resetScanner('Connection cancelled by user');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        foregroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel Connection',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Animation<double> animation;
  final Color borderColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutWidth;
  final double cutOutHeight;

  ScannerOverlayPainter({
    required this.animation,
    this.borderColor = Colors.white,
    this.borderRadius = 12,
    this.borderLength = 20,
    this.cutOutWidth = 250,
    this.cutOutHeight = 250,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutOutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutOutWidth,
      height: cutOutHeight,
    );

    final cutOutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
      );

    final backgroundPaint = Paint()
      ..color = Colors.black
          .withOpacity(0.7) // Darker, more premium background
      ..style = PaintingStyle.fill;

    // Draw background with cutout
    canvas.drawPath(
      Path.combine(PathOperation.difference, backgroundPath, cutOutPath),
      backgroundPaint,
    );

    // Draw Corners with Gradient
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [borderColor, borderColor.withOpacity(0.5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(cutOutRect);

    final cornerPath = Path();

    // Top Left
    cornerPath.moveTo(cutOutRect.left, cutOutRect.top + borderLength);
    cornerPath.lineTo(cutOutRect.left, cutOutRect.top + borderRadius);
    cornerPath.arcToPoint(
      Offset(cutOutRect.left + borderRadius, cutOutRect.top),
      radius: Radius.circular(borderRadius),
    );
    cornerPath.lineTo(cutOutRect.left + borderLength, cutOutRect.top);

    // Top Right
    cornerPath.moveTo(cutOutRect.right - borderLength, cutOutRect.top);
    cornerPath.lineTo(cutOutRect.right - borderRadius, cutOutRect.top);
    cornerPath.arcToPoint(
      Offset(cutOutRect.right, cutOutRect.top + borderRadius),
      radius: Radius.circular(borderRadius),
    );
    cornerPath.lineTo(cutOutRect.right, cutOutRect.top + borderLength);

    // Bottom Right
    cornerPath.moveTo(cutOutRect.right, cutOutRect.bottom - borderLength);
    cornerPath.lineTo(cutOutRect.right, cutOutRect.bottom - borderRadius);
    cornerPath.arcToPoint(
      Offset(cutOutRect.right - borderRadius, cutOutRect.bottom),
      radius: Radius.circular(borderRadius),
    );
    cornerPath.lineTo(cutOutRect.right - borderLength, cutOutRect.bottom);

    // Bottom Left
    cornerPath.moveTo(cutOutRect.left + borderLength, cutOutRect.bottom);
    cornerPath.lineTo(cutOutRect.left + borderRadius, cutOutRect.bottom);
    cornerPath.arcToPoint(
      Offset(cutOutRect.left, cutOutRect.bottom - borderRadius),
      radius: Radius.circular(borderRadius),
    );
    cornerPath.lineTo(cutOutRect.left, cutOutRect.bottom - borderLength);

    canvas.drawPath(cornerPath, paint);

    // Draw Scan Line
    final scanLineY = cutOutRect.top + (cutOutRect.height * animation.value);

    // Gradient for the scan line (fading at edges)
    final scanLinePaint = Paint()
      ..shader =
          LinearGradient(
            colors: [Colors.transparent, borderColor, Colors.transparent],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(
            Rect.fromLTWH(cutOutRect.left, scanLineY, cutOutRect.width, 2),
          );

    canvas.drawRect(
      Rect.fromLTWH(cutOutRect.left, scanLineY, cutOutRect.width, 2),
      scanLinePaint,
    );

    // Optional: Add a subtle glow below the scan line
    final glowPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [borderColor.withOpacity(0.3), Colors.transparent],
          ).createShader(
            Rect.fromLTWH(cutOutRect.left, scanLineY, cutOutRect.width, 40),
          );

    canvas.drawRect(
      Rect.fromLTWH(cutOutRect.left, scanLineY, cutOutRect.width, 40),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return animation.value != oldDelegate.animation.value;
  }
}
