import 'package:flutter/material.dart';

import '../../design_system/components/maisum_button.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.trailingIcon,
    this.height = 56,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final IconData? trailingIcon;
  final double height;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    return MaisUmButton(
      label: label,
      onPressed: onPressed,
      isLoading: loading,
      leadingIcon: icon,
      trailingIcon: trailingIcon,
      height: height,
      animationDuration: animationDuration,
    );
  }
}
