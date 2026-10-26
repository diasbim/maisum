import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_layout.dart';

/// A small pill-shaped label used to introduce a section on a hero/brand
/// surface (e.g. "ESCOLHA O SEU PERFIL", "Feito para pequenos negócios").
///
/// Centralizes the badge's shape, background and border so every screen
/// reuses the same shell instead of re-declaring an almost-identical
/// `Container` + `BoxDecoration` per hero.
class EyebrowBadge extends StatelessWidget {
  const EyebrowBadge({
    super.key,
    required this.label,
    this.icon,
    this.textColor = AppColors.white,
  });

  final String label;
  final IconData? icon;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.secondary, size: 16),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
