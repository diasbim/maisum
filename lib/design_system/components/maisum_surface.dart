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
    final effectiveBackground = backgroundColor ?? style.background;
    final isDark = _isDarkSurface(effectiveBackground, backgroundGradient);
    final foreground = isDark ? AppColors.white : AppColors.onSurface;
    final secondaryForeground = isDark
        ? AppColors.white.withValues(alpha: 0.78)
        : AppColors.onSurfaceVariant;
    final actionColor =
        isDark ? AppColors.secondary : AppColors.secondaryForeground;
    final inheritedTheme = Theme.of(context);
    final contentTheme = inheritedTheme.copyWith(
      colorScheme: inheritedTheme.colorScheme.copyWith(
        primary: actionColor,
        onPrimary: isDark ? AppColors.primaryDarker : AppColors.white,
        surface: effectiveBackground,
        onSurface: foreground,
        onSurfaceVariant: secondaryForeground,
        error: AppColors.error,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.error,
      ),
      textTheme: _surfaceTextTheme(
        inheritedTheme.textTheme,
        foreground: foreground,
        secondaryForeground: secondaryForeground,
      ),
      iconTheme: inheritedTheme.iconTheme.copyWith(color: foreground),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: actionColor),
      ),
      focusColor: actionColor.withValues(alpha: 0.18),
      hoverColor: actionColor.withValues(alpha: 0.08),
      splashColor: actionColor.withValues(alpha: 0.12),
      highlightColor: actionColor.withValues(alpha: 0.08),
    );
    final effectiveAnimationDuration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : animationDuration;
    final surface = AnimatedContainer(
      duration: effectiveAnimationDuration,
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null ? effectiveBackground : null,
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

    final semanticContent = semanticLabel == null && !semanticButton
        ? content
        : Semantics(
            label: semanticLabel,
            button: semanticButton || onTap != null,
            selected: selected,
            child: content,
          );

    return Theme(
      data: contentTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: semanticContent,
        ),
      ),
    );
  }

  bool _isDarkSurface(Color background, Gradient? gradient) {
    final colors = gradient?.colors ?? [background];
    final darkColors = colors.where(
      (color) => ThemeData.estimateBrightnessForColor(color) == Brightness.dark,
    );
    return darkColors.length > colors.length / 2;
  }

  TextTheme _surfaceTextTheme(
    TextTheme source, {
    required Color foreground,
    required Color secondaryForeground,
  }) {
    TextStyle? primary(TextStyle? style) => style?.copyWith(color: foreground);
    TextStyle? secondary(TextStyle? style) =>
        style?.copyWith(color: secondaryForeground);

    return source.copyWith(
      displayLarge: primary(source.displayLarge),
      displayMedium: primary(source.displayMedium),
      displaySmall: primary(source.displaySmall),
      headlineLarge: primary(source.headlineLarge),
      headlineMedium: primary(source.headlineMedium),
      headlineSmall: primary(source.headlineSmall),
      titleLarge: primary(source.titleLarge),
      titleMedium: primary(source.titleMedium),
      titleSmall: secondary(source.titleSmall),
      bodyLarge: primary(source.bodyLarge),
      bodyMedium: primary(source.bodyMedium),
      bodySmall: secondary(source.bodySmall),
      labelLarge: primary(source.labelLarge),
      labelMedium: secondary(source.labelMedium),
      labelSmall: secondary(source.labelSmall),
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
          borderWidth: 1,
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
