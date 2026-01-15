import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:permission_handler/permission_handler.dart';

class WiFiDirectScreen extends StatefulWidget {
  const WiFiDirectScreen({super.key});

  @override
  State<WiFiDirectScreen> createState() => _WiFiDirectScreenState();
}

class _WiFiDirectScreenState extends State<WiFiDirectScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = WiFiDirectService();
  StreamSubscription? _connectionSub;

  // Host State
  bool _isCreatingGroup = false;
  String? _groupSsid;
  String? _groupPass;

  // Guest State
  MobileScannerController? _scannerController;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _startScanner();
      } else {
        _stopScanner();
      }
    });

    _connectionSub = _service.connectionStream.listen((event) {
      if (event.isLost) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('P2P Connection Lost')));
          setState(() {
            _groupSsid = null;
            _groupPass = null;
            _isCreatingGroup = false;
            _isConnecting = false;
          });
        }
      } else {
        if (event.isGroupOwner && event.ssid != null) {
          if (mounted) {
            setState(() {
              _isCreatingGroup = false;
              _groupSsid = event.ssid;
              _groupPass = event.password;
            });
          }
        } else if (!event.isGroupOwner && event.ipAddress != null) {
          // Connected as guest
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Connected! Waiting for device discovery...'),
                duration: Duration(seconds: 3),
              ),
            );
            // Wait a moment for mDNS discovery to find the other device
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
        }
      }
    });
  }

  void _startScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    if (mounted) setState(() {});
  }

  void _stopScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connectionSub?.cancel();
    _scannerController?.dispose();
    _service.stopDiscovery(); // Cleanup on exit
    super.dispose();
  }

  Future<void> _createGroup() async {
    setState(() => _isCreatingGroup = true);
    final success = await _service.createGroup();
    if (!success) {
      if (mounted) {
        setState(() => _isCreatingGroup = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create group. WiFi must be ON.'),
          ),
        );
      }
    }
  }

  void _handleScannedCode(String code) {
    if (_isConnecting) return;

    // Parse WIFI:S:ssid;P:password;;
    // Typical format: WIFI:S:DIRECT-xy;T:WPA;P:pass;;
    if (!code.startsWith('WIFI:')) return;

    String? ssid, pass;
    final content = code.substring(5).replaceAll(';;', '');
    final parts = content.split(';');
    for (final part in parts) {
      if (part.startsWith('S:')) ssid = part.substring(2);
      if (part.startsWith('P:')) pass = part.substring(2);
    }

    if (ssid != null && pass != null) {
      _connectToGroup(ssid, pass);
    }
  }

  Future<void> _connectToGroup(String ssid, String pass) async {
    setState(() => _isConnecting = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Connecting to $ssid...')));

    final success = await _service.connectToGroup(ssid, pass);
    if (!success) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect to group')),
        );
      }
    }
    // If success, we wait for stream event
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline P2P Mode'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Send (Host)'),
            Tab(text: 'Receive (Join)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildHostTab(), _buildGuestTab()],
      ),
    );
  }

  Widget _buildHostTab() {
    if (_groupSsid != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Scan to Connect',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            QrImageView(
              data: 'WIFI:S:$_groupSsid;T:WPA;P:$_groupPass;;',
              version: QrVersions.auto,
              size: 250,
            ),
            const SizedBox(height: 20),
            Text('SSID: $_groupSsid'),
            Text('Password: $_groupPass'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                _service.disconnect();
                setState(() {
                  _groupSsid = null;
                  _groupPass = null;
                });
              },
              child: const Text('Cancel Group'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: _isCreatingGroup
          ? const CircularProgressIndicator()
          : ElevatedButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Create Offline Group'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
    );
  }

  Widget _buildGuestTab() {
    if (_scannerController == null) {
      return const Center(child: Text('Initializing Camera...'));
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController!,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                _handleScannedCode(barcode.rawValue!);
              }
            }
          },
        ),
        if (_isConnecting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Connecting...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
