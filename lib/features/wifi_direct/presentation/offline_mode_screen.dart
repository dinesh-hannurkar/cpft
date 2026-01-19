import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:fylooo/services/wifi_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fylooo/features/qr_scanner/presentation/qr_scanner_screen.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';

class OfflineModeScreen extends StatefulWidget {
  const OfflineModeScreen({super.key});

  @override
  State<OfflineModeScreen> createState() => _OfflineModeScreenState();
}

class _OfflineModeScreenState extends State<OfflineModeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  P2PCredentials? _credentials;
  bool _isCreatingGroup = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Clean up connections when leaving this screen
    // This ensures we unbind from the network so normal internet works again
    WiFiDirectService().removeGroup();
    super.dispose();
  }

  Future<void> _createGroup() async {
    setState(() {
      _isCreatingGroup = true;
      _errorMessage = null;
    });

    try {
      final creds = await WiFiDirectService().createGroup();
      if (mounted) {
        setState(() {
          _credentials = creds;
          _isCreatingGroup = false;
        });
        if (creds == null) {
          setState(() {
            _errorMessage = 'Failed to create group. WiFi Direct might not be supported or enabled.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingGroup = false;
          _errorMessage = 'Error creating group: $e';
        });
      }
    }
  }

  Future<void> _handleQrScan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrScannerScreen(returnResult: true),
      ),
    );

    if (result != null && mounted) {
      _connectToGroup(result);
    }
  }

  Future<void> _connectToGroup(String qrData) async {
    final Map<String, String>? wifiData = _parseWifiQrCode(qrData);
    if (wifiData == null) {
      if (mounted) {
        AppSnackbar.showError(context, 'Invalid QR code');
      }
      return;
    }

    final ssid = wifiData['ssid'];
    final password = wifiData['password'];

    if (ssid == null || password == null) {
       if (mounted) {
         AppSnackbar.showError(context, 'Invalid WiFi QR data');
       }
       return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecting to group...')),
      );
    }

    final success = await WiFiDirectService().connectToGroup(
      ssid: ssid,
      password: password,
    );

    if (mounted) {
      if (success) {
        AppSnackbar.showSuccess(context, 'Connected to $ssid');
      } else {
        AppSnackbar.showError(context, 'Failed to connect to group');
      }
    }
  }

  Map<String, String>? _parseWifiQrCode(String code) {
    try {
      if (!code.startsWith('WIFI:')) return null;
      final content = code.substring(5).replaceAll(';;', '');
      final parts = content.split(';');
      String? ssid, password;

      for (final part in parts) {
        if (part.startsWith('S:')) {
          ssid = part.substring(2);
        } else if (part.startsWith('P:')) {
          password = part.substring(2);
        }
      }

      if (ssid != null) {
        return {
          'ssid': ssid,
          'password': password ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error parsing WiFi QR code: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Mode'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Receive (Host)', icon: Icon(Icons.wifi_tethering)),
            Tab(text: 'Send (Join)', icon: Icon(Icons.wifi_find)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHostTab(),
          _buildJoinTab(),
        ],
      ),
    );
  }

  Widget _buildHostTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_tethering, size: 80, color: AppColors.primary),
          const SizedBox(height: AppSizes.lg),
          const Text(
            'Host a high-speed offline group',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Creates a WiFi Direct group for others to join directly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: AppSizes.xl),
          if (_isCreatingGroup)
            const CircularProgressIndicator()
          else if (_credentials != null)
            _buildQrCode(_credentials!)
          else
            ElevatedButton(
              onPressed: _createGroup,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Create Group'),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQrCode(P2PCredentials creds) {
    final wifiString = 'WIFI:S:${creds.ssid};T:WPA;P:${creds.password};;';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: QrImageView(
            data: wifiString,
            version: QrVersions.auto,
            size: 220,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SSID: ${creds.ssid}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Scan this with the "Send" tab on the other device.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildJoinTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 80, color: AppColors.primary),
          const SizedBox(height: AppSizes.lg),
          const Text(
            'Join an offline group',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Scan the QR code from the Host device to connect instantly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: AppSizes.xl),
          ElevatedButton.icon(
            onPressed: _handleQrScan,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan QR Code'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
