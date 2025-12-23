import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/primary_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class DeviceNameSetupScreen extends StatefulWidget {
  const DeviceNameSetupScreen({super.key});

  @override
  State<DeviceNameSetupScreen> createState() => _DeviceNameSetupScreenState();
}

class _DeviceNameSetupScreenState extends State<DeviceNameSetupScreen>
    with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppSnackbar.showError(context, AppStrings.pleaseEnterDeviceName);
      return;
    }
    if (name.length < 2) {
      AppSnackbar.showError(context, AppStrings.deviceNameTooShort);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', name);

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacementNamed(kIsWeb ? '/webshare' : '/home');
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        AppSnackbar.showError(context, AppStrings.failedToSaveDeviceName);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE2F6FB), // Light blue gradient start
              Color(0xFFF0F6F7), // Light secondary
              Colors.white, // Pure white at bottom
            ],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSizes.md,
                        vertical: isSmallScreen ? AppSizes.md : AppSizes.md,
                      ),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: isSmallScreen ? AppSizes.lg : AppSizes.xl,
                            ),

                            // Animated Logo Container
                            ScaleTransition(
                              scale: _scaleAnimation,
                              child: Container(
                                padding: EdgeInsets.all(AppSizes.md),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primary.withValues(alpha: 0.1),
                                      AppColors.secondary.withValues(
                                        alpha: 0.8,
                                      ),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 30,
                                      offset: const Offset(0, 12),
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, -8),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  width: isSmallScreen ? 80 : 100,
                                  height: isSmallScreen ? 80 : 100,
                                  padding: const EdgeInsets.all(AppSizes.md),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Image.asset(
                                    'assets/images/app-logo.jpg',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(
                              height: isSmallScreen
                                  ? AppSizes.md
                                  : AppSizes.lg * 1.5,
                            ),

                            // Enhanced Title with gradient text effect
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [AppColors.primary, AppColors.skyBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: Text(
                                AppStrings.welcomeMessage,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 26 : 34,
                                  fontWeight: FontWeight.bold,
                                  color: Colors
                                      .white, // Will be overridden by shader
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            SizedBox(
                              height: isSmallScreen ? AppSizes.sm : AppSizes.md,
                            ),

                            // Enhanced Subtitle
                            Text(
                              'Set up your device name to start discovering other devices on your network.',
                              style: TextStyle(
                                fontSize: isSmallScreen
                                    ? AppSizes.fontSizeSm
                                    : AppSizes.fontSizeMd,
                                color: AppColors.greyDark.withValues(
                                  alpha: 0.8,
                                ),
                                height: 1.6,
                                fontWeight: FontWeight.w400,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            SizedBox(height: AppSizes.xl),

                            // Enhanced Input Field with subtle animation
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen
                                    ? AppSizes.sm
                                    : AppSizes.md,
                              ),
                              child: PrimaryTextField(
                                controller: _nameController,
                                enabled: !_isLoading,
                                hintText: 'Device name',
                                prefixIcon: Icons.person,
                                autofocus: true,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _saveDeviceName(),
                              ),
                            ),

                            // Enhanced Continue Button
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen
                                    ? AppSizes.sm
                                    : AppSizes.md,
                                vertical: AppSizes.md,
                              ),
                              child: PrimaryButton(
                                text: AppStrings.continueText,
                                onPressed: _saveDeviceName,
                                isLoading: _isLoading,
                                height: isSmallScreen ? 56 : 60,
                                elevation: 8,
                              ),
                            ),

                            SizedBox(
                              height: isSmallScreen ? AppSizes.lg : AppSizes.xl,
                            ),

                            // Add flexible space at bottom for better centering on larger screens
                            if (!isSmallScreen) const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
