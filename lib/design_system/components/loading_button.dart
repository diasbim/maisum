import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'maisum_button.dart';

class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    this.loadingLabel,
    required this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.height = 56,
    this.radius = 18,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = Colors.white,
  });

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;
  final double height;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return MaisUmButton(
      label: label,
      loadingLabel: loadingLabel,
      onPressed: onPressed,
      isLoading: isLoading,
      enabled: enabled,
      height: height,
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }
}
