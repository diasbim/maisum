import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class CustomerExperienceTheme extends StatelessWidget {
  const CustomerExperienceTheme({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.manrope(
        fontSize: 44,
        height: 1.05,
        letterSpacing: -1.4,
        fontWeight: FontWeight.w900,
        color: AppColors.onSurface,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 20,
        height: 1.2,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
      ),
    );
    return Theme(
      data: base.copyWith(
        textTheme: textTheme,
        scaffoldBackgroundColor: AppColors.offWhite,
        dividerTheme: const DividerThemeData(
          color: AppColors.g100,
          thickness: 1,
          space: 1,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.square(48)),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: AppColors.white,
          selectedColor: AppColors.secondaryLight,
          side: const BorderSide(color: AppColors.g100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          labelStyle: textTheme.labelMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: textTheme.labelMedium?.copyWith(
            color: AppColors.primaryDarker,
            fontWeight: FontWeight.w800,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.secondaryDark,
          linearTrackColor: AppColors.g100,
        ),
        navigationBarTheme: base.navigationBarTheme.copyWith(
          backgroundColor: AppColors.white,
          indicatorColor: AppColors.secondaryLight,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return textTheme.labelSmall?.copyWith(
              color: selected
                  ? AppColors.primaryDarker
                  : AppColors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected
                  ? AppColors.primaryDarker
                  : AppColors.onSurfaceVariant,
              size: selected ? 23 : 22,
            );
          }),
        ),
      ),
      child: child,
    );
  }
}
