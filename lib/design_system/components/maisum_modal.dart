import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_layout.dart';
import 'maisum_button.dart';
import 'maisum_surface.dart';

class MaisUmModal {
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    required String primaryLabel,
    required String secondaryLabel,
    IconData icon = Icons.help_outline_rounded,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: MaisUmSurface(
              radius: AppRadius.xl,
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: destructive
                          ? AppColors.errorLight
                          : AppColors.secondaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 30,
                      color: destructive
                          ? AppColors.error
                          : AppColors.primaryDarker,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.primaryDarker,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: MaisUmButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          label: secondaryLabel,
                          variant: MaisUmButtonVariant.outlined,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: MaisUmButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          label: primaryLabel,
                          variant: destructive
                              ? MaisUmButtonVariant.danger
                              : MaisUmButtonVariant.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
