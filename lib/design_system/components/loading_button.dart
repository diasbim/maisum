import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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
    final effectiveEnabled = enabled && !isLoading && onPressed != null;
    final effectiveLabel = isLoading
        ? (loadingLabel == null || loadingLabel!.trim().isEmpty
            ? label
            : loadingLabel!)
        : label;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: effectiveEnabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
          disabledForegroundColor: AppColors.onSurfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? Row(
                  key: const ValueKey('loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        effectiveLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              : Text(
                  effectiveLabel,
                  key: const ValueKey('label'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
