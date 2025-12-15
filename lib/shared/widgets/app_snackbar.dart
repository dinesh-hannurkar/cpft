import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';

/// Enum for different snackbar types
enum SnackbarType {
  success,
  error,
  warning,
  info,
}

/// A reusable snackbar widget with consistent styling and theming
class AppSnackbar {
  /// Shows a success snackbar
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      type: SnackbarType.success,
      duration: duration,
      action: action,
    );
  }

  /// Shows an error snackbar
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      type: SnackbarType.error,
      duration: duration,
      action: action,
    );
  }

  /// Shows a warning snackbar
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      type: SnackbarType.warning,
      duration: duration,
      action: action,
    );
  }

  /// Shows an info snackbar
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      type: SnackbarType.info,
      duration: duration,
      action: action,
    );
  }

  /// Shows a custom snackbar with specified type
  static void show(
    BuildContext context,
    String message, {
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(
      context,
      message,
      type: type,
      duration: duration,
      action: action,
    );
  }

  /// Internal method to show the snackbar
  static void _show(
    BuildContext context,
    String message, {
    required SnackbarType type,
    required Duration duration,
    SnackBarAction? action,
  }) {
    // Get colors based on type
    final colors = _getColors(type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _getIcon(type),
              color: colors.textColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colors.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: colors.backgroundColor,
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  /// Get colors for the snackbar type
  static _SnackbarColors _getColors(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return _SnackbarColors(
          backgroundColor: AppColors.green,
          textColor: AppColors.white,
        );
      case SnackbarType.error:
        return _SnackbarColors(
          backgroundColor: AppColors.red,
          textColor: AppColors.white,
        );
      case SnackbarType.warning:
        return _SnackbarColors(
          backgroundColor: Colors.orange,
          textColor: AppColors.white,
        );
      case SnackbarType.info:
      default:
        return _SnackbarColors(
          backgroundColor: AppColors.primary,
          textColor: AppColors.white,
        );
    }
  }

  /// Get icon for the snackbar type
  static IconData _getIcon(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return Icons.check_circle_outline;
      case SnackbarType.error:
        return Icons.error_outline;
      case SnackbarType.warning:
        return Icons.warning_amber_outlined;
      case SnackbarType.info:
      default:
        return Icons.info_outline;
    }
  }
}

/// Helper class for snackbar colors
class _SnackbarColors {
  const _SnackbarColors({
    required this.backgroundColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color textColor;
}