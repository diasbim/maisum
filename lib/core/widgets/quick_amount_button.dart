import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class QuickAmountButton extends StatelessWidget {
  const QuickAmountButton({
    super.key,
    required this.amount,
    required this.onTap,
    this.selected = false,
    this.label,
  });

  final int amount;
  final VoidCallback onTap;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 86,
        height: 78,
        decoration: BoxDecoration(
          color: selected ? AppColors.secondaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.secondary : AppColors.g100,
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$amount',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      label!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.secondaryDark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
