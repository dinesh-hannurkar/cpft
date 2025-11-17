
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';

class AppTextStyles {
  // Headings
  static const TextStyle heading1 = TextStyle(
    fontSize: AppSizes.fontSizeLg + 6, // 24.0
    fontWeight: FontWeight.bold,
    color: AppColors.blackDark,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: AppSizes.fontSizeLg + 2, // 20.0
    fontWeight: FontWeight.w600,
    color: AppColors.blackDark,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: AppSizes.fontSizeLg, // 18.0
    fontWeight: FontWeight.w500,
    color: AppColors.blackDark,
  );

  // Body text
  static const TextStyle bodyLarge = TextStyle(
    fontSize: AppSizes.fontSizeLg, // 16.0
    fontWeight: FontWeight.normal,
    color: AppColors.white,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: AppSizes.fontSizeMd, // 16.0
    fontWeight: FontWeight.normal,
    color: AppColors.white,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: AppSizes.fontSizeSm, // 14.0
    fontWeight: FontWeight.normal,
    color: AppColors.greyDark,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontSize: AppSizes.fontSizeMd, // 16.0
    fontWeight: FontWeight.w600,
    color: AppColors.white,
  );

  // Caption / hint text
  static const TextStyle caption = TextStyle(
    fontSize: AppSizes.fontSizeSm * 0.8,
    fontWeight: FontWeight.w400,
    color: AppColors.greyDark,
  );

  // Label (e.g., form field labels)
  static const TextStyle label = TextStyle(
    fontSize: AppSizes.fontSizeSm, // 14.0
    fontWeight: FontWeight.w500,
    color: AppColors.blackDark,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: AppSizes.fontSizeLg - 2,
    fontWeight: FontWeight.w500,
    color: AppColors.blackDark,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: AppSizes.fontSizeSm,
    fontWeight: FontWeight.w500,
    color: AppColors.blackDark,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: AppSizes.fontSizeLg + 10,
    fontWeight: FontWeight.w600,
    color: AppColors.blackDark,
  );
}
