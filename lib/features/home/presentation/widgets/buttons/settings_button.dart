import 'package:fylooo/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  const AppIconButton({super.key, required this.onPressed, required this.icon});
  final IconData icon;

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
            BoxShadow(
              color: AppColors.secondary,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(child: Icon(icon, color: AppColors.primary, size: 20)),
      ),
    );
  }
}
