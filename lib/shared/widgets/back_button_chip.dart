import 'package:cpft/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:flutter/material.dart';

class BackButtonChip extends StatelessWidget {
  final VoidCallback onPressed;
  const BackButtonChip({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppIconButton(onPressed: onPressed, icon: Icons.arrow_back);
  }
}
