import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_layout.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.assetPath,
    this.assetHeight,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? assetPath;
  final double? assetHeight;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.g100),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (assetPath != null)
                      Image.asset(
                        assetPath!,
                        height: assetHeight ?? 160,
                        fit: BoxFit.contain,
                      )
                    else
                      Container(
                        width: assetHeight ?? 112,
                        height: assetHeight ?? 112,
                        decoration: const BoxDecoration(
                          color: AppColors.secondaryLight,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.inbox_rounded,
                          size: 52,
                          color: AppColors.secondaryDark,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
