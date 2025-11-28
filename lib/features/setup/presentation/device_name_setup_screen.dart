import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/primary_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class DeviceNameSetupScreen extends StatefulWidget {
  const DeviceNameSetupScreen({super.key});

  @override
  State<DeviceNameSetupScreen> createState() => _DeviceNameSetupScreenState();
}

class _DeviceNameSetupScreenState extends State<DeviceNameSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', name);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save device name', style: TextStyle(color: Colors.white))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useGeneratedName() async {
    setState(() => _isLoading = true);

    try {
      final generatedName = _generateUniqueDeviceName();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', generatedName);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate device name', style: TextStyle(color: Colors.white))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _generateUniqueDeviceName() {
    // Simple device name generation - you can make this more sophisticated
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    return 'Device-$timestamp';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.devices,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Welcome to CPFT',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Set up your device name to start discovering other devices on your network',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.greyDark,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  // Input field
                  PrimaryTextField(
                    controller: _nameController,
                    enabled: !_isLoading,
                    hintText: 'Enter device name...',
                    prefixIcon: Icons.person,
                    autofocus: true,
                  ),
                  const SizedBox(height: 32),
                  // Buttons
                  PrimaryButton(
                    text: 'Continue',
                    onPressed: _saveDeviceName,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 16),
                  // TextButton(
                  //   onPressed: _isLoading ? null : _useGeneratedName,
                  //   style: TextButton.styleFrom(
                  //     foregroundColor: AppColors.greyDark,
                  //     textStyle: const TextStyle(
                  //       fontSize: 16,
                  //       fontWeight: FontWeight.w500,
                  //     ),
                  //   ),
                  //   child: const Text('Use auto-generated name'),
                  // ),
                  // const SizedBox(height: 24), // Extra space at bottom for keyboard
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
