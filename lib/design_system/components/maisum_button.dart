import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_layout.dart';

enum MaisUmButtonVariant {
  primary,
  secondary,
  outlined,
  ghost,
  danger,
}

class MaisUmButton extends StatelessWidget {
  const MaisUmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loadingLabel,
    this.isLoading = false,
    this.enabled = true,
    this.variant = MaisUmButtonVariant.primary,
    this.leadingIcon,
    this.trailingIcon,
    this.iconColor,
    this.height = AppControlSize.button,
    this.radius = AppRadius.lg,
    this.fullWidth = true,
    this.backgroundColor,
    this.foregroundColor,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;
  final MaisUmButtonVariant variant;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final Color? iconColor;
  final double height;
  final double radius;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && !isLoading && onPressed != null;
    final effectiveAnimationDuration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : animationDuration;
    final colors = _ButtonColors.resolve(
      variant: variant,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
    final child = AnimatedSwitcher(
      duration: effectiveAnimationDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isLoading
          ? _ButtonLoadingContent(
              key: const ValueKey('loading'),
              label: loadingLabel == null || loadingLabel!.trim().isEmpty
                  ? label
                  : loadingLabel!,
              color: colors.foreground,
            )
          : _ButtonLabel(
              key: const ValueKey('label'),
              label: label,
              leadingIcon: leadingIcon,
              trailingIcon: trailingIcon,
              iconColor: iconColor,
            ),
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height < AppControlSize.iconButton
          ? AppControlSize.iconButton
          : height,
      child: switch (variant) {
        MaisUmButtonVariant.outlined => OutlinedButton(
            onPressed: effectiveEnabled ? onPressed : null,
            style: _outlinedStyle(colors),
            child: child,
          ),
        MaisUmButtonVariant.ghost => TextButton(
            onPressed: effectiveEnabled ? onPressed : null,
            style: _ghostStyle(colors),
            child: child,
          ),
        _ => ElevatedButton(
            onPressed: effectiveEnabled ? onPressed : null,
            style: _filledStyle(colors),
            child: child,
          ),
      },
    );
  }

  ButtonStyle _filledStyle(_ButtonColors colors) {
    return ElevatedButton.styleFrom(
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      disabledBackgroundColor: AppColors.surfaceContainerHigh,
      disabledForegroundColor: AppColors.onSurfaceVariant,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }

  ButtonStyle _outlinedStyle(_ButtonColors colors) {
    return OutlinedButton.styleFrom(
      foregroundColor: colors.foreground,
      disabledForegroundColor: AppColors.onSurfaceVariant,
      side: BorderSide(color: colors.border, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }

  ButtonStyle _ghostStyle(_ButtonColors colors) {
    return TextButton.styleFrom(
      foregroundColor: colors.foreground,
      disabledForegroundColor: AppColors.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({
    super.key,
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.iconColor,
  });

  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 20, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(trailingIcon, size: 20, color: iconColor),
        ],
      ],
    );
  }
}

class _ButtonLoadingContent extends StatelessWidget {
  const _ButtonLoadingContent({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  static _ButtonColors resolve({
    required MaisUmButtonVariant variant,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final defaults = switch (variant) {
      MaisUmButtonVariant.primary => const _ButtonColors(
          background: AppColors.primaryDarker,
          foreground: AppColors.white,
          border: AppColors.primaryDarker,
        ),
      MaisUmButtonVariant.secondary => const _ButtonColors(
          background: AppColors.secondaryLight,
          foreground: AppColors.primaryDarker,
          border: AppColors.secondaryLight,
        ),
      MaisUmButtonVariant.outlined => const _ButtonColors(
          background: Colors.transparent,
          foreground: AppColors.primary,
          border: AppColors.g300,
        ),
      MaisUmButtonVariant.ghost => const _ButtonColors(
          background: Colors.transparent,
          foreground: AppColors.primary,
          border: Colors.transparent,
        ),
      MaisUmButtonVariant.danger => const _ButtonColors(
          background: AppColors.error,
          foreground: AppColors.white,
          border: AppColors.error,
        ),
    };

    return _ButtonColors(
      background: backgroundColor ?? defaults.background,
      foreground: foregroundColor ?? defaults.foreground,
      border: defaults.border,
    );
  }
}
