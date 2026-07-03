import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_layout.dart';
import '../../core/theme/app_shadows.dart';

enum MaisUmSurfaceVariant {
  standard,
  muted,
  selected,
  error,
  warning,
  success,
}

class MaisUmSurface extends StatelessWidget {
  const MaisUmSurface({
    super.key,
    required this.child,
    this.variant = MaisUmSurfaceVariant.standard,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.radius = AppRadius.lg,
    this.width,
    this.height,
    this.onTap,
    this.selected = false,
    this.semanticLabel,
    this.semanticButton = false,
    this.backgroundColor,
    this.backgroundGradient,
    this.borderColor,
    this.borderWidth,
    this.shadows,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final MaisUmSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticLabel;
  final bool semanticButton;
  final Color? backgroundColor;
  final Gradient? backgroundGradient;
  final Color? borderColor;
  final double? borderWidth;
  final List<BoxShadow>? shadows;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final style = _SurfaceStyle.resolve(variant, selected: selected);
    final borderRadius = BorderRadius.circular(radius);
    final surface = AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null
            ? backgroundColor ?? style.background
            : null,
        gradient: backgroundGradient,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? style.border,
          width: borderWidth ?? style.borderWidth,
        ),
        boxShadow: shadows ?? style.shadows,
      ),
      child: child,
    );

    final content = onTap == null
        ? surface
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: surface,
            ),
          );

    if (semanticLabel == null && !semanticButton) {
      return content;
    }

    return Semantics(
      label: semanticLabel,
      button: semanticButton || onTap != null,
      selected: selected,
      child: content,
    );
  }
}

class _SurfaceStyle {
  const _SurfaceStyle({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.shadows,
  });

  final Color background;
  final Color border;
  final double borderWidth;
  final List<BoxShadow>? shadows;

  static _SurfaceStyle resolve(
    MaisUmSurfaceVariant variant, {
    required bool selected,
  }) {
    if (selected) {
      return _SurfaceStyle(
        background: AppColors.primaryDarker,
        border: AppColors.secondary,
        borderWidth: 2,
        shadows: AppShadows.md,
      );
    }

    return switch (variant) {
      MaisUmSurfaceVariant.standard => _SurfaceStyle(
          background: AppColors.white,
          border: AppColors.g100,
          borderWidth: 1.5,
          shadows: AppShadows.sm,
        ),
      MaisUmSurfaceVariant.muted => _SurfaceStyle(
          background: AppColors.surfaceContainerLow,
          border: AppColors.surfaceContainerLow,
          borderWidth: 1,
          shadows: AppShadows.sm,
        ),
      MaisUmSurfaceVariant.selected => _SurfaceStyle(
          background: AppColors.primaryDarker,
          border: AppColors.secondary,
          borderWidth: 2,
          shadows: AppShadows.md,
        ),
      MaisUmSurfaceVariant.error => const _SurfaceStyle(
          background: AppColors.errorLight,
          border: AppColors.errorLight,
          borderWidth: 1,
          shadows: null,
        ),
      MaisUmSurfaceVariant.warning => const _SurfaceStyle(
          background: AppColors.warningLight,
          border: AppColors.warningLight,
          borderWidth: 1,
          shadows: null,
        ),
      MaisUmSurfaceVariant.success => const _SurfaceStyle(
          background: AppColors.successLight,
          border: AppColors.successLight,
          borderWidth: 1,
          shadows: null,
        ),
    };
  }
}
