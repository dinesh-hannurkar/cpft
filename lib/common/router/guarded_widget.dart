import 'package:flutter/material.dart';

class GuardedRoute extends StatelessWidget {
  final bool Function() guardCondition;
  final WidgetBuilder builder;
  final String redirectRouteName;

  const GuardedRoute({
    super.key,
    required this.guardCondition,
    required this.builder,
    required this.redirectRouteName,
  });

  @override
  Widget build(BuildContext context) {
    if (guardCondition()) {
      return builder(context);
    } else {
      // Use WidgetsBinding to pushNamed after build phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, redirectRouteName);
      });

      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
  }
}
