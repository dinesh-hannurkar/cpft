import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:cpft/shared/widgets/primary_text_field.dart';
import 'package:cpft/shared/widgets/primary_button.dart';
import 'package:cpft/shared/widgets/app_snackbar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;
import 'package:cpft/services/feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  FeedbackType _selectedType = FeedbackType.bug;
  String _description = '';
  String _expectedBehavior = '';
  String _stepsToReproduce = '';
  bool _includeDeviceInfo = true;
  bool _isSubmitting = false;

  String _appVersion = '';
  String _deviceInfo = '';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _loadDeviceInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = info.version);
    } catch (e) {
      debugPrint('Error loading app info: $e');
    }
  }

  void _loadDeviceInfo() {
    final deviceInfo = StringBuffer();

    // Platform info
    deviceInfo.writeln('Platform: ${Platform.operatingSystem}');
    deviceInfo.writeln('OS Version: ${Platform.operatingSystemVersion}');

    // App info
    deviceInfo.writeln('App Version: $_appVersion');

    // Additional device details
    try {
      deviceInfo.writeln('Locale: ${Platform.localeName}');
    } catch (e) {
      // Ignore locale errors
    }

    setState(() => _deviceInfo = deviceInfo.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        title: 'Send Feedback',
        centerTitle: true,
      ),
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
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSizes.md),
              children: [
                // Feedback Type Selection
                _buildSection(
                  'Feedback Type',
                  Column(
                    children: FeedbackType.values.map((type) {
                      return RadioListTile<FeedbackType>(
                        title: Text(_getFeedbackTypeTitle(type)),
                        subtitle: Text(_getFeedbackTypeDescription(type)),
                        value: type,
                        groupValue: _selectedType,
                        onChanged: (value) {
                          setState(() => _selectedType = value!);
                        },
                        activeColor: AppColors.primary,
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: AppSizes.lg),

                // Description
                _buildSection(
                  'Description',
                  PrimaryTextField(
                    hintText: _getDescriptionHint(),
                    maxLines: 4,
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Please provide a description';
                      }
                      return null;
                    },
                    onChanged: (value) => _description = value,
                  ),
                ),

                const SizedBox(height: AppSizes.lg),

                // Bug-specific fields
                if (_selectedType == FeedbackType.bug) ...[
                  _buildSection(
                    'Steps to Reproduce',
                    PrimaryTextField(
                      hintText: '1. Open the app\n2. Go to...\n3. Click...',
                      maxLines: 3,
                      onChanged: (value) => _stepsToReproduce = value,
                    ),
                  ),

                  const SizedBox(height: AppSizes.lg),

                  _buildSection(
                    'Expected Behavior',
                    PrimaryTextField(
                      hintText: 'What should happen instead?',
                      maxLines: 2,
                      onChanged: (value) => _expectedBehavior = value,
                    ),
                  ),

                  const SizedBox(height: AppSizes.lg),
                ],

                // Device Info Toggle
                _buildSection(
                  'Additional Information',
                  Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Include device information'),
                        subtitle: const Text('Help us debug issues faster'),
                        value: _includeDeviceInfo,
                        onChanged: (value) => setState(() => _includeDeviceInfo = value),
                        activeThumbColor: AppColors.primary,
                      ),
                      if (_includeDeviceInfo)
                        Container(
                          padding: const EdgeInsets.all(AppSizes.sm),
                          margin: const EdgeInsets.only(top: AppSizes.sm),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(AppSizes.cardRadiusSm),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _deviceInfo,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Colors.grey,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSizes.xl),

                // Submit Button
                PrimaryButton(
                  text: _isSubmitting ? 'Sending...' : 'Send Feedback',
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  isLoading: _isSubmitting,
                ),

                const SizedBox(height: AppSizes.md),

                // Alternative contact
                Center(
                  child: TextButton(
                    onPressed: _sendViaEmail,
                    child: const Text('Prefer to send via email instead?'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.darkPrimary,
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        content,
      ],
    );
  }

  String _getFeedbackTypeTitle(FeedbackType type) {
    switch (type) {
      case FeedbackType.bug:
        return 'Bug Report';
      case FeedbackType.feature:
        return 'Feature Request';
      case FeedbackType.general:
        return 'General Feedback';
      case FeedbackType.other:
        return 'Other';
    }
  }

  String _getFeedbackTypeDescription(FeedbackType type) {
    switch (type) {
      case FeedbackType.bug:
        return 'Report crashes, errors, or unexpected behavior';
      case FeedbackType.feature:
        return 'Suggest new features or improvements';
      case FeedbackType.general:
        return 'Share your overall experience with CPFT';
      case FeedbackType.other:
        return 'Any other feedback or questions';
    }
  }

  String _getDescriptionHint() {
    switch (_selectedType) {
      case FeedbackType.bug:
        return 'Describe the problem you encountered...';
      case FeedbackType.feature:
        return 'Describe the feature you would like to see...';
      case FeedbackType.general:
        return 'Share your thoughts about CPFT...';
      case FeedbackType.other:
        return 'Tell us what\'s on your mind...';
    }
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final success = await FeedbackService().submitFeedback(
        type: _selectedType,
        description: _description,
        stepsToReproduce: _stepsToReproduce.isNotEmpty ? _stepsToReproduce : null,
        expectedBehavior: _expectedBehavior.isNotEmpty ? _expectedBehavior : null,
        includeDeviceInfo: _includeDeviceInfo,
      );

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, 'Thank you for your feedback!');
          Navigator.pop(context);
        } else {
          AppSnackbar.showError(context, 'Failed to send feedback. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to send feedback: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendViaEmail() async {
    // This now uses the Firebase service with email fallback
    await _submitFeedback();
  }
}