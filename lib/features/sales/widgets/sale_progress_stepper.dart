import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../presentation/sale_controller.dart';

class SaleProgressStepper extends StatelessWidget {
  const SaleProgressStepper({
    super.key,
    required this.customerStatus,
    required this.amountStatus,
    required this.confirmStatus,
  });

  final StepStatus customerStatus;
  final StepStatus amountStatus;
  final StepStatus confirmStatus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StepItem(
            label: AppStrings.cliente,
            status: customerStatus,
            number: 1,
          ),
        ),
        _StepConnector(
          completed: customerStatus == StepStatus.completed,
          enabled: amountStatus != StepStatus.pending,
        ),
        Expanded(
          child: _StepItem(
            label: AppStrings.valorStep,
            status: amountStatus,
            number: 2,
          ),
        ),
        _StepConnector(
          completed: amountStatus == StepStatus.completed,
          enabled: confirmStatus != StepStatus.pending,
        ),
        Expanded(
          child: _StepItem(
            label: AppStrings.confirmar,
            status: confirmStatus,
            number: 3,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.completed, required this.enabled});

  final bool completed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.success
        : enabled
            ? AppColors.secondary.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.25);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: 22,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: color,
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.label,
    required this.status,
    required this.number,
  });

  final String label;
  final StepStatus status;
  final int number;

  @override
  Widget build(BuildContext context) {
    final textColor = status == StepStatus.pending
        ? Colors.white.withValues(alpha: 0.72)
        : Colors.white;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _backgroundColorFor(status),
            border: status == StepStatus.pending
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.7), width: 1.4)
                : null,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _StepIcon(
                key: ValueKey<StepStatus>(status),
                status: status,
                number: number,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _backgroundColorFor(StepStatus status) {
    switch (status) {
      case StepStatus.completed:
        return AppColors.success;
      case StepStatus.active:
        return AppColors.secondary;
      case StepStatus.pending:
        return Colors.white.withValues(alpha: 0.14);
    }
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({super.key, required this.status, required this.number});

  final StepStatus status;
  final int number;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case StepStatus.completed:
        return const Icon(Icons.check_rounded, color: Colors.white, size: 17);
      case StepStatus.active:
        return Text(
          number.toString(),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        );
      case StepStatus.pending:
        return Icon(
          Icons.circle_outlined,
          color: Colors.white.withValues(alpha: 0.72),
          size: 13,
        );
    }
  }
}
