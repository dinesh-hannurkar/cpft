import 'package:flutter/material.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  final theme = Theme.of(context);
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
