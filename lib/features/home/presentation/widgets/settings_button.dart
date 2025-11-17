import 'package:cpft/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class SettingsButton extends StatelessWidget {
  final VoidCallback onPressed;
  const SettingsButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.secondary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.white, width: 5),
          boxShadow: const [
            BoxShadow(color: AppColors.secondary, blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        child: Center(
          child: Icon(Icons.settings_outlined, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }
}
