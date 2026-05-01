import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // ── Gradients ─────────────────────────────────────────────────────────────
  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get goldGradient => const LinearGradient(
        colors: [AppColors.secondary, AppColors.secondaryDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Shadows ───────────────────────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.10),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.24),
          blurRadius: 56,
          offset: const Offset(0, 16),
        ),
      ];

  // ── Text theme ────────────────────────────────────────────────────────────
  static TextTheme get _textTheme {
    return TextTheme(
      // Bricolage Grotesque — display & headline
      displayLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 40, fontWeight: FontWeight.w800,
        color: AppColors.onSurface, letterSpacing: -0.5, height: 1.1,
      ),
      displayMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 32, fontWeight: FontWeight.w800,
        color: AppColors.onSurface, letterSpacing: -0.3, height: 1.1,
      ),
      displaySmall: GoogleFonts.bricolageGrotesque(
        fontSize: 26, fontWeight: FontWeight.w800,
        color: AppColors.onSurface, height: 1.2,
      ),
      headlineLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 24, fontWeight: FontWeight.w700,
        color: AppColors.onSurface, height: 1.2,
      ),
      headlineMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: AppColors.onSurface, height: 1.3,
      ),
      headlineSmall: GoogleFonts.bricolageGrotesque(
        fontSize: 18, fontWeight: FontWeight.w700,
        color: AppColors.onSurface, height: 1.3,
      ),
      // Outfit — titles, body, labels
      titleLarge: GoogleFonts.outfit(
        fontSize: 18, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleSmall: GoogleFonts.outfit(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
      ),
      bodyLarge: GoogleFonts.outfit(
        fontSize: 16, fontWeight: FontWeight.w400,
        color: AppColors.onSurface, height: 1.6,
      ),
      bodyMedium: GoogleFonts.outfit(
        fontSize: 15, fontWeight: FontWeight.w400,
        color: AppColors.onSurface, height: 1.6,
      ),
      bodySmall: GoogleFonts.outfit(
        fontSize: 13, fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant, height: 1.5,
      ),
      labelLarge: GoogleFonts.outfit(
        fontSize: 15, fontWeight: FontWeight.w600,
        color: AppColors.onSurface, letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.outfit(
        fontSize: 13, fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.outfit(
        fontSize: 11, fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant, letterSpacing: 0.4,
      ),
    );
  }

  // ── Light Theme ───────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.g100,
          secondary: AppColors.secondary,
          onSecondary: AppColors.onSecondary,
          secondaryContainer: AppColors.secondaryLight,
          error: AppColors.error,
          onError: AppColors.onError,
          errorContainer: AppColors.errorContainer,
          surface: AppColors.offWhite,
          onSurface: AppColors.onSurface,
          onSurfaceVariant: AppColors.onSurfaceVariant,
          outline: AppColors.g300,
          outlineVariant: AppColors.g100,
          surfaceContainerLowest: AppColors.white,
          surfaceContainerLow: AppColors.surfaceContainerLow,
          surfaceContainer: AppColors.offWhite,
          surfaceContainerHigh: AppColors.surfaceContainerHigh,
          surfaceContainerHighest: AppColors.surfaceContainerHighest,
        ),
        scaffoldBackgroundColor: AppColors.offWhite,
        textTheme: _textTheme,

        // ── AppBar ──────────────────────────────────────────────────────────
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.bricolageGrotesque(
            color: AppColors.onPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: AppColors.onPrimary),
        ),

        // ── Elevated Button ─────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.outfit(
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2,
            ),
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
        ),

        // ── Outlined Button ─────────────────────────────────────────────────
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(56),
            side: const BorderSide(color: AppColors.g300, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: GoogleFonts.outfit(
              fontSize: 15, fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // ── Text Button ─────────────────────────────────────────────────────
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: GoogleFonts.outfit(
              fontSize: 14, fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // ── Input Decoration ────────────────────────────────────────────────
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.g300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.g300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.secondary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          hintStyle: GoogleFonts.outfit(
            color: AppColors.g300, fontSize: 15, fontWeight: FontWeight.w400,
          ),
          labelStyle: GoogleFonts.outfit(
            color: AppColors.g500, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.8,
          ),
          errorStyle: GoogleFonts.outfit(color: AppColors.error, fontSize: 12),
        ),

        // ── Card ────────────────────────────────────────────────────────────
        cardTheme: CardThemeData(
          color: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.g100, width: 1.5),
          ),
          margin: EdgeInsets.zero,
        ),

        // ── List Tile ───────────────────────────────────────────────────────
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          minVerticalPadding: 8,
        ),

        // ── Divider ─────────────────────────────────────────────────────────
        dividerTheme: const DividerThemeData(
          color: AppColors.g100,
          thickness: 1,
          space: 1,
        ),

        // ── Chip ────────────────────────────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.g100,
          selectedColor: AppColors.secondaryLight,
          labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),

        // ── SnackBar ────────────────────────────────────────────────────────
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.g800,
          contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),

        // ── FAB ─────────────────────────────────────────────────────────────
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          elevation: 0,
          shape: CircleBorder(),
        ),

        // ── Bottom Sheet ────────────────────────────────────────────────────
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          elevation: 0,
        ),

        // ── Progress Indicator ──────────────────────────────────────────────
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.secondary,
          linearTrackColor: AppColors.g100,
        ),

        // ── Dialog ──────────────────────────────────────────────────────────
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          titleTextStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface,
          ),
        ),
      );
}
