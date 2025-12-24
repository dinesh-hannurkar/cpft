import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/core/constants/app_strings.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        title: 'Privacy Policy',
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      'Privacy Policy',
                      'This Privacy Policy describes how ${AppStrings.appName} collects, uses, and discloses information. Our policy is simple: We prioritize your privacy by collecting virtually nothing.',
                    ),
                    _buildSection(
                      '1. Information We DO NOT Collect',
                      '''Due to the nature of our Service: direct, cross-platform file transfer, we operate with a strict policy of Non-Collection.
No Personal Information: We do not ask for, collect, or store personal identifiable information (PII) such as your name, email address, phone number, or location data. You are not required to create an account to use the Service.
No File or Content Storage: We do not store, view, or retain any files, content, or data that you transfer using our App. The file transfer occurs directly between your devices (peer-to-peer) and is not saved on our servers.
No Usage Tracking (Optional): We do not use third-party analytics or tracking tools that monitor your activity within the App. ''',
                    ),
                    _buildSection(
                      '2. How We Handle Data',
                      '''The App requires minimal technical data solely for establishing a connection between two devices to enable the file transfer.
Connection Data: When initiating a transfer, the App may generate a temporary, anonymous connection ID/code (e.g., a six-digit code) and utilize the network IP addresses of the two devices only for the duration of the transfer session. This temporary session data is not linked to any personal identity and is immediately discarded once the transfer is complete or the session times out.''',
                    ),
                    _buildSection(
                      '3. Data Security',
                      'While we do not store your content, we are committed to ensuring that the connection mechanism is secure. All transfers are facilitated using industry-standard encryption protocols (like TLS/SSL) to protect the data while it is in transit between your devices.',
                    ),
                    _buildSection(
                      '4. Children\'s Privacy',
                      'Our Service is not directed to anyone under the age of 13. We do not knowingly collect personal information from children under 13.',
                    ),
                    _buildSection(
                      '5. Changes to This Privacy Policy',
                      'We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page.',
                    ),
                    const SizedBox(height: AppSizes.lg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content, {bool isDate = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isDate ? 12 : 16,
              fontWeight: isDate ? FontWeight.normal : FontWeight.bold,
              color: isDate ? Colors.grey[600] : AppColors.darkPrimary,
            ),
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: AppSizes.xs),
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
