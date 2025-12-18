import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';

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
                      'Last Updated: December 15, 2025',
                      '',
                      isDate: true,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    _buildSection(
                      '1. Acceptance of Terms',
                      'By downloading, installing, or using CPFT (Cross-Platform File Transfer), you agree to be bound by these Terms of Use. If you do not agree to these terms, please do not use the application.',
                    ),
                    _buildSection(
                      '2. Description of Service',
                      'CPFT is a peer-to-peer file transfer application that allows users to share files directly between devices on the same local network. The service operates without cloud storage or external servers.',
                    ),
                    _buildSection('3. User Responsibilities', '''You agree to:
• Use CPFT only for lawful purposes
• Not transmit any harmful, illegal, or offensive content
• Respect intellectual property rights of others
• Not attempt to breach security or authentication measures
• Not use the service to distribute malware or viruses
• Ensure you have proper permissions for all shared files'''),
                    _buildSection(
                      '4. Privacy and Data',
                      '''CPFT operates on these principles:
• All file transfers occur directly between devices
• No files are stored on external servers
• No user data is collected or transmitted to third parties
• Network discovery uses local multicast protocols
• Connection logs are stored locally only''',
                    ),
                    _buildSection('5. Network Usage', '''When using CPFT:
• You must have permission to use the network
• File transfers may consume bandwidth
• Corporate or public networks may have restrictions
• You are responsible for compliance with network policies
• Some features may not work on restricted networks'''),
                    _buildSection(
                      '6. Disclaimer of Warranties',
                      'CPFT is provided "as is" without warranties of any kind, either express or implied. We do not guarantee that the service will be uninterrupted, secure, or error-free.',
                    ),
                    _buildSection(
                      '7. Limitation of Liability',
                      'To the maximum extent permitted by law, we shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use or inability to use CPFT.',
                    ),
                    _buildSection(
                      '8. File Transfer Responsibility',
                      '''You acknowledge that:
• You are responsible for the content of files you transfer
• We do not monitor or control file transfers
• We are not liable for any data loss or corruption
• You should maintain backups of important files
• File integrity is dependent on network conditions''',
                    ),
                    _buildSection(
                      '9. Third-Party Content',
                      'CPFT may contain links to third-party websites or services. We are not responsible for the content, privacy policies, or practices of any third-party sites or services.',
                    ),
                    _buildSection(
                      '10. Intellectual Property',
                      'CPFT and its original content, features, and functionality are owned by the developers and are protected by international copyright, trademark, and other intellectual property laws.',
                    ),
                    _buildSection(
                      '11. Termination',
                      'We reserve the right to terminate or suspend your access to CPFT at any time, without prior notice, for conduct that we believe violates these Terms of Use or is harmful to other users.',
                    ),
                    _buildSection(
                      '12. Changes to Terms',
                      'We reserve the right to modify or replace these Terms of Use at any time. Changes will be effective immediately upon posting. Continued use of CPFT after changes constitutes acceptance of the modified terms.',
                    ),
                    _buildSection(
                      '13. Open Source',
                      'CPFT is open-source software. The source code is available under the specified license terms. Contributors must comply with the license terms and these Terms of Use.',
                    ),
                    _buildSection(
                      '14. Platform-Specific Terms',
                      '''Additional platform requirements:
• Android: Minimum Android 8.0 required
• iOS: Minimum iOS 12.0 required
• Web: Modern browser with WebRTC support required
• Permissions must be granted for full functionality
• Platform limitations may affect certain features''',
                    ),
                    _buildSection(
                      '15. Governing Law',
                      'These Terms of Use shall be governed by and construed in accordance with applicable laws, without regard to conflict of law provisions.',
                    ),
                    _buildSection(
                      '16. Contact Information',
                      'For questions about these Terms of Use, please contact us at:\n\nEmail: support@cpft.app',
                    ),
                    const SizedBox(height: AppSizes.lg),
                    Center(
                      child: Text(
                        '© 2025 CPFT. All rights reserved.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
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
