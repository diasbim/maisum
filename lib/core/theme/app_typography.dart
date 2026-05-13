import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  static const TextTheme textTheme = TextTheme(
    // Display & headline
    displayLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      color: AppColors.onSurface,
      letterSpacing: -0.5,
      height: 1.1,
    ),
    displayMedium: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: AppColors.onSurface,
      letterSpacing: -0.3,
      height: 1.1,
    ),
    displaySmall: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: AppColors.onSurface,
      height: 1.2,
    ),
    headlineLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.3,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.3,
    ),
    // Titles, body, labels
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariant,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
      height: 1.6,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
      height: 1.6,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurfaceVariant,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariant,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariant,
      letterSpacing: 0.4,
    ),
  );
}
