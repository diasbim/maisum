import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.darkMode = false,
  });

  final void Function(String digit) onDigit;
  final VoidCallback onDelete;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(['1', '2', '3']),
          const SizedBox(height: 12),
          _row(['4', '5', '6']),
          const SizedBox(height: 12),
          _row(['7', '8', '9']),
          const SizedBox(height: 12),
          _bottomRow(),
        ],
      ),
    );
  }

  Widget _row(List<String> digits) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: digits.map(_digitButton).toList(),
      );

  Widget _bottomRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 80, height: 80),
          _digitButton('0'),
          _PadButton(
            onTap: () {
              HapticFeedback.lightImpact();
              onDelete();
            },
            darkMode: darkMode,
            child: Icon(
              Icons.backspace_outlined,
              size: 24,
              color: darkMode ? Colors.white : AppColors.onSurface,
            ),
          ),
        ],
      );

  Widget _digitButton(String digit) => _PadButton(
        onTap: () {
          HapticFeedback.lightImpact();
          onDigit(digit);
        },
        darkMode: darkMode,
        child: Text(
          digit,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: darkMode ? Colors.white : AppColors.onSurface,
          ),
        ),
      );
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.onTap,
    required this.child,
    this.darkMode = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Material(
        color: darkMode
            ? Colors.white.withValues(alpha: 0.10)
            : AppColors.surfaceContainerLow,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          splashColor: darkMode
              ? Colors.white.withValues(alpha: 0.15)
              : AppColors.secondary.withValues(alpha: 0.12),
          highlightColor: darkMode
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.secondary.withValues(alpha: 0.06),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.isError = false,
    this.isSuccess = false,
    this.darkMode = false,
  });

  final int length;
  final int filled;
  final bool isError;
  final bool isSuccess;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        final Color color;
        if (isError) {
          color = AppColors.error;
        } else if (isSuccess) {
          color = AppColors.success;
        } else if (isFilled) {
          color = AppColors.secondary;
        } else {
          color = Colors.transparent;
        }

        final emptyBorderColor = darkMode
            ? Colors.white.withValues(alpha: 0.35)
            : AppColors.g300;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: isFilled ? 18 : 14,
          height: isFilled ? 18 : 14,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: isFilled
                ? null
                : Border.all(color: emptyBorderColor, width: 2),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
