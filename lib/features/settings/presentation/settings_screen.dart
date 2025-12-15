import 'package:cpft/features/settings/presentation/widget/settings_tile.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/services/discovery_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cpft/main.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:cpft/shared/widgets/primary_text_field.dart';
import 'package:cpft/shared/widgets/primary_button.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:cpft/shared/showcase/showcase_helper.dart';
import 'package:cpft/services/sound_service.dart';
import 'package:cpft/features/settings/presentation/help_screen.dart';
import 'package:cpft/features/settings/presentation/terms_of_use_screen.dart';
import 'package:cpft/features/settings/presentation/privacy_policy_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cpft/features/settings/presentation/feedback_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String currentDeviceName;
  final DiscoveryService? discoveryService;

  const SettingsScreen({
    super.key,
    required this.currentDeviceName,
    this.discoveryService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _deviceName;
  String _appVersion = '';
  bool _isApplying = false;
  bool _soundsEnabled = true;

  @override
  void initState() {
    super.initState();
    _deviceName = widget.currentDeviceName;
    _loadVersion();
    _loadDeviceNameFromPrefs();
    _loadSoundsEnabled();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenShowcase = prefs.getBool('settings_showcase_seen') ?? false;

      if (!hasSeenShowcase && mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            try {
              ShowCaseWidget.of(
                context,
              ).startShowCase([ShowcaseHelper.settingsIconKey]);
              prefs.setBool('settings_showcase_seen', true);
            } catch (_) {}
          }
        });
      }
    });
  }

  Future<void> _loadDeviceNameFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = (prefs.getString('device_name') ?? '').trim();
      if (name.isNotEmpty && name != _deviceName && mounted) {
        setState(() => _deviceName = name);
      }
    } catch (_) {}
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  Future<void> _loadSoundsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() => _soundsEnabled = prefs.getBool('sounds_enabled') ?? true);
    } catch (_) {}
  }

  Future<void> _toggleSounds(bool value) async {
    setState(() => _soundsEnabled = value);
    await SoundService().setSoundsEnabled(value);
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  Future<void> _rateApp() async {
    const String appStoreUrl = 'https://play.google.com/store/apps/details?id=com.cpft.app';
    const String appStoreUrlIOS = 'https://apps.apple.com/app/cpft/id1234567890'; // Replace with actual App Store ID

    try {
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        await _launchUrl(appStoreUrlIOS);
      } else {
        await _launchUrl(appStoreUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open app store: $e')),
        );
      }
    }
  }

  Future<void> _shareApp() async {
    try {
      await Share.share(
        'Check out CPFT - Cross-Platform File Transfer! Transfer files between devices instantly over WiFi. '
        'Download now: https://cpft.app/download',
        subject: 'CPFT - Cross-Platform File Transfer',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share app: $e')),
        );
      }
    }
  }

  Future<void> _promptRename() async {
    final controller = TextEditingController(text: _deviceName);
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.lg,
                      vertical: AppSizes.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with close button (iOS sheet style)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rename Device',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkPrimary,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Choose a new name for your device',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.lg),
                        Form(
                          key: formKey,
                          child: PrimaryTextField(
                            controller: controller,
                            autofocus: true,
                            maxLength: 32,
                            hintText: 'Device name',
                            validator: (value) {
                              final v = value?.trim() ?? '';
                              if (v.isEmpty) return 'Please enter a name';
                              if (v.length < 2) return 'Name is too short';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: AppSizes.lg),
                        PrimaryButton(
                          text: 'Save Changes',
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final newName = controller.text.trim();
                            Navigator.pop(context);
                            if (newName != _deviceName) {
                              await _applyNewName(newName);
                            }
                          },
                        ),
                        const SizedBox(height: AppSizes.md),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyNewName(String newName) async {
    setState(() => _isApplying = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', newName);
      await widget.discoveryService?.dispose();

      globalDeviceName = newName;
      globalDiscoveryService = null;

      if (!mounted) return;
      if (kIsWeb) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/webshare', (route) => false);
      } else {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to apply name: $e')));
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _deviceName.isNotEmpty
        ? _deviceName.trim()[0].toUpperCase()
        : 'D';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        title: 'Settings',
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
          child: AbsorbPointer(
            absorbing: _isApplying,
            child: Stack(
              children: [
                ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSizes.xl,
                        bottom: AppSizes.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.white,
                                width: 5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 48,
                              backgroundColor: AppColors.secondary,
                              child: Text(
                                initial,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppSizes.fontSizeLg * 2.5,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          Text(
                            _deviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _promptRename,
                            child: const Text(
                              'rename',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(
                      height: 1,
                      child: Divider(
                        color: AppColors.skyBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    // General section
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSizes.xs,
                        horizontal: AppSizes.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SettingsTile(
                            icon: Icons.volume_up_rounded,
                            title: 'Sounds',
                            subtitle: 'Enable or disable sound effects',
                            trailing: Switch(
                              value: _soundsEnabled,
                              onChanged: _toggleSounds,
                              activeColor: AppColors.primary,
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.info_outline_rounded,
                            title: 'Version',
                            subtitle: 'Installed app version',
                            trailing: Text(
                              _appVersion.isEmpty ? '-' : _appVersion,
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.help_outline_rounded,
                            title: 'Help & Support',
                            subtitle: 'Get help, FAQs, and contact support',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HelpScreen(),
                              ),
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.description_outlined,
                            title: 'Terms of Use',
                            subtitle: 'Read the terms and conditions',
                            onTap: () {
                              if (kIsWeb) {
                                Navigator.pushNamed(context, '/termsofuse');
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TermsOfUseScreen(),
                                  ),
                                );
                              }
                            },
                          ),
                          SettingsTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            subtitle: 'Learn how your data is used',
                            onTap: () {
                              if (kIsWeb) {
                                Navigator.pushNamed(context, '/privacy');
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PrivacyPolicyScreen(),
                                  ),
                                );
                              }
                            },
                          ),
                          SettingsTile(
                            icon: Icons.feedback_outlined,
                            title: 'Send Feedback',
                            subtitle: 'Report a bug or suggest a feature',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FeedbackScreen(),
                              ),
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.star_rate_outlined,
                            title: 'Rate Us',
                            subtitle: 'Leave a rating in the store',
                            onTap: _rateApp,
                          ),
                          SettingsTile(
                            icon: Icons.share_outlined,
                            title: 'Share App',
                            subtitle: 'Share CPFT with friends',
                            onTap: _shareApp,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_isApplying)
                  Container(
                    color: Colors.white.withValues(alpha: 0.6),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
