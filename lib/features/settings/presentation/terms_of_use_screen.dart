import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/core/constants/app_strings.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        title: 'Terms of Use',
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
                      'Terms of Use',
                      'These Terms of Use ("Terms") govern your use of the ${AppStrings.appName} mobile and desktop applications and related services (collectively, the "Service").',
                    ),
                    _buildSection(
                      '1. Acceptance of Terms',
                      'By accessing or using the Service, you agree to be bound by these Terms. If you disagree with any part of the terms, you may not access the Service.',
                    ),
                    _buildSection(
                      '2. The Service',
                      'The Service provides a tool for the direct transfer of files between different devices and operating systems. The Service acts only as an intermediary to facilitate this direct connection.',
                    ),
                    _buildSection(
                      '3. User Responsibilities and Acceptable Use',
                      'You agree to use the Service only for lawful purposes and in accordance with these Terms. You agree not to:\n'
                          'Transmit any illegal, harmful, threatening, defamatory, obscene, or otherwise objectionable material.\n'
                          'Transfer files that you do not have the legal right to share.\n'
                          'Attempt to interfere with or disrupt the integrity or performance of the Service.\n'
                          'Use the Service to transmit viruses, malware, or any other destructive or disabling code.',
                    ),
                    _buildSection(
                      '4. Disclaimer of Stored Data',
                      'We do not store, retain, or back up any files, content, or data transferred through the Service. All transfers are peer-to-peer and are deleted from our systems (if any temporary intermediary connection data is used) immediately upon successful transfer or connection timeout.\n'
                          'You are solely responsible for backing up your own data. We shall not be liable for any loss of files, content, or data.',
                    ),
                    _buildSection(
                      '5. Intellectual Property',
                      'The Service itself (excluding the files you transfer) is and will remain the exclusive property of Omnity Digital Private Limited and its licensors.',
                    ),
                    _buildSection(
                      '6. Termination',
                      'We may terminate or suspend your access immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.',
                    ),
                    _buildSection(
                      '7. Limitation of Liability',
                      'In no event shall Omnity Digital Private Limited, nor its directors, employees, partners, agents, suppliers, or affiliates, be liable for any indirect, incidental, special, consequential or punitive damages, including without limitation, loss of profits, data, use, goodwill, or other intangible losses, resulting from: (i) your access to or use of or inability to access or use the Service; (ii) any content obtained from the Service; and (iii) unauthorized access, use or alteration of your transmissions or content, especially related to the files you choose to transfer.',
                    ),
                    _buildSection(
                      '8. Governing Law',
                      'These Terms shall be governed and construed in accordance with the laws of INDIA, without regard to its conflict of law provisions.',
                    ),
                    _buildSection(
                      '9. Changes to Terms',
                      'We reserve the right, at our sole discretion, to modify or replace these Terms at any time. We will try to provide at least 30 days\' notice before any new terms take effect.',
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

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Column(
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
