import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppShadows {
  static List<BoxShadow> get sm => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.10),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.24),
          blurRadius: 56,
          offset: const Offset(0, 16),
        ),
      ];
}
