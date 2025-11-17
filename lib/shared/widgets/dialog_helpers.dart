import 'package:flutter/material.dart';

/// Shows a dialog with consistent barrier and navigator behavior.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  final theme = Theme.of(context);
  // Slightly stronger barrier in dark mode
  final barrier = theme.brightness == Brightness.dark
      ? Colors.black87
      : Colors.black54;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrier,
    useRootNavigator: true,
    builder: builder,
  );
}
