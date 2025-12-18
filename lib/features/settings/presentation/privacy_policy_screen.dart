import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';

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
                      'Last Updated: December 15, 2025',
                      '',
                      isDate: true,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    _buildSection(
                      'Introduction',
                      'CPFT (Cross-Platform File Transfer) is committed to protecting your privacy. This Privacy Policy explains how we handle your information when you use our application.',
                    ),
                    _buildSection(
                      '1. Information We Collect',
                      '''CPFT is designed with privacy in mind. We collect minimal information:

**Device Information**
• Device name (set by you)
• Operating system type and version
• App version number
• Network interface information (for local discovery)

**Technical Data**
• IP address (local network only, not stored)
• Connection logs (stored locally only)
• Error logs (stored locally for debugging)
• Performance metrics (local only)

**We DO NOT collect:**
• Personal identification information
• File contents or metadata
• Location data beyond network discovery
• Usage analytics or tracking data
• Any information from transferred files''',
                    ),
                    _buildSection(
                      '2. How We Use Information',
                      '''The limited information we collect is used solely for:

• Enabling device discovery on local networks
• Establishing peer-to-peer connections
• Displaying device names in the app interface
• Debugging connection issues (local logs only)
• Improving app stability and performance

We do not:
• Share your information with third parties
• Use your data for advertising
• Track your activities
• Store your data on external servers
• Analyze your file transfers''',
                    ),
                    _buildSection(
                      '3. File Transfers',
                      '''CPFT operates on these privacy principles:

**Direct Transfer**
• All files are transferred directly between devices
• No intermediate servers or cloud storage
• No file content inspection or analysis
• Transfers occur only on local network

**No Storage**
• We do not store transferred files
• No backup copies are made on our servers
• Files exist only on sender and receiver devices
• Transfer history is local only

**Encryption**
• Connections use secure protocols
• Data in transit is protected
• No man-in-the-middle access possible''',
                    ),
                    _buildSection(
                      '4. Permissions',
                      '''CPFT requires certain permissions to function:

**Android**
• Storage: Access files for transfer
• Location: Required for WiFi network discovery
• Local Network: Device discovery on local network
• Camera: QR code scanning (optional)

**iOS**
• Photos: Access media for transfer
• Local Network: Device discovery
• Camera: QR code scanning (optional)

**Web**
• Camera: QR code scanning (optional)
• File System: Select and download files

All permissions are used solely for stated purposes and never for data collection.''',
                    ),
                    _buildSection('5. Data Storage', '''**Local Storage Only**
• All app data is stored on your device
• Connection history stored locally
• Settings saved in device storage
• No cloud synchronization

**You Control:**
• All data remains on your device
• Clear app data to remove all information
• Uninstall removes all local data
• No remote data to delete'''),
                    _buildSection(
                      '6. Third-Party Services',
                      '''CPFT uses minimal third-party services:

• No analytics services
• No advertising networks
• No social media integration
• No tracking services

External links (app stores, support) have their own privacy policies.''',
                    ),
                    _buildSection(
                      '7. Children\'s Privacy',
                      'CPFT does not knowingly collect information from children under 13. The app does not require age verification as no personal data is collected.',
                    ),
                    _buildSection(
                      '8. Security',
                      '''We implement security measures:

• Secure connection protocols
• Local network isolation
• No external data transmission
• Regular security updates
• Open-source code (auditable)

However, no method is 100% secure. Use CPFT on trusted networks.''',
                    ),
                    _buildSection(
                      '9. International Users',
                      'CPFT operates entirely on local networks. No data crosses international borders through our services. All transfers remain within your local network.',
                    ),
                    _buildSection('10. Your Rights', '''You have the right to:

• Access your local data (stored on device)
• Delete your data (clear app data)
• Stop using the service at any time
• Request information about data handling
• Report privacy concerns

Since all data is local, you have complete control.'''),
                    _buildSection(
                      '11. Data Retention',
                      '''CPFT retains minimal data:

• Connection logs: Until manually cleared
• Settings: Until app uninstall
• Device name: Until changed by user
• Transfer history: Local only, user-controlled

No server-side data retention as we have no servers storing user data.''',
                    ),
                    _buildSection(
                      '12. Open Source',
                      'CPFT is open-source software. You can review our code to verify privacy claims. The source code is available for inspection and audit.',
                    ),
                    _buildSection(
                      '13. Changes to Privacy Policy',
                      'We may update this Privacy Policy occasionally. Changes will be posted in the app with the updated date. Continued use after changes constitutes acceptance.',
                    ),
                    _buildSection(
                      '14. California Privacy Rights',
                      'California residents: We do not sell personal information. We collect minimal data as described above, all stored locally on your device.',
                    ),
                    _buildSection(
                      '15. GDPR Compliance',
                      'For EU users: We comply with GDPR by design. No personal data is collected or processed on external servers. All data remains under your control on your device.',
                    ),
                    _buildSection(
                      '16. Contact Us',
                      'For privacy questions or concerns, contact us at:\n\nEmail: support@cpft.app\n\nWe will respond to privacy inquiries within 30 days.',
                    ),
                    const SizedBox(height: AppSizes.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(
                          AppSizes.cardRadiusSm,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: AppSizes.sm),
                              const Expanded(
                                child: Text(
                                  'Privacy-First Design',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.sm),
                          const Text(
                            'CPFT is built with privacy as a core principle. No clouds, no tracking, no external servers. Your files stay between your devices, always.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
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
