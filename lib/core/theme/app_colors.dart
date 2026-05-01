import 'package:flutter/material.dart';

class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  // Converted from design system oklch tokens
  static const Color primary = Color(0xFF1C2E50); // --navy  oklch(20% .055 258)
  static const Color primaryDark =
      Color(0xFF162440); // --navy2 oklch(17% .05  258)
  static const Color primaryDarker =
      Color(0xFF101C32); // --navy3 oklch(14% .04  258)
  static const Color secondary =
      Color(0xFFE8B84B); // --gold  oklch(82% .18  82)
  static const Color secondaryDark = Color(0xFFD4A030); // --goldDk
  static const Color secondaryLight = Color(0xFFFBF7E8); // --goldLt

  // ── Surface ───────────────────────────────────────────────────────────────
  static const Color white = Color(0xFFFEFDF9);
  static const Color offWhite = Color(0xFFFAF9F5); // --off

  // ── Neutral scale ─────────────────────────────────────────────────────────
  static const Color g100 = Color(0xFFEEF0F5);
  static const Color g300 = Color(0xFFCDD1DC);
  static const Color g500 = Color(0xFF7C8499);
  static const Color g800 = Color(0xFF2E3347);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color green = Color(0xFF27A26A);
  static const Color greenLight = Color(0xFFE6F7F0);
  static const Color red = Color(0xFFCB3311);
  static const Color redLight = Color(0xFFFCEAE6);
  static const Color amber = Color(0xFFD9A020);
  static const Color amberLight = Color(0xFFFCF3E0);

  // ── Material 3 semantic aliases ───────────────────────────────────────────
  static const Color onPrimary = white;
  static const Color onSecondary = primary;
  static const Color surface = offWhite;
  static const Color background = white;
  static const Color card = white;
  static const Color divider = g100;
  static const Color onSurface = g800;
  static const Color onSurfaceVariant = g500;
  static const Color mediumGray = g300;
  static const Color outlineVariant = g300;
  static const Color surfaceContainerLowest = white;
  static const Color surfaceContainerLow = Color(0xFFF5F6FA);
  static const Color surfaceContainerHigh = Color(0xFFE4E7EF);
  static const Color surfaceContainerHighest = g100;
  static const Color error = red;
  static const Color errorLight = redLight;
  static const Color errorContainer = redLight;
  static const Color onError = white;

  // ── Legacy compat (used by existing widgets/screens) ─────────────────────
  static const Color primaryLight = Color(0xFF2E4A7A); // lighter navy shade
  static const Color rewards = secondary;
  static const Color rewardsLight = secondaryLight;
  static const Color success = green;
  static const Color successLight = greenLight;
  static const Color warning = amber;
  static const Color warningLight = amberLight;
  static const Color textPrimary = g800;
  static const Color textSecondary = g500;
  static const Color textHint = g300;
  static const Color offline = g500;
  static const Color offlineBg = g100;
  static const Color syncPending = amber;
  static const Color syncDone = green;
}
