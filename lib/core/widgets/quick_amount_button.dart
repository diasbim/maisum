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
        width: 88,
        height: 72,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$amount',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              label ?? 'MZN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
