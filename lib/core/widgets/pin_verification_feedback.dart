import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/app_strings.dart';
import '../theme/app_colors.dart';
import 'pin_pad.dart';

mixin PinVerificationShakeMixin<T extends StatefulWidget>
    on State<T>, TickerProvider {
  late final AnimationController pinShakeController;
  late final Animation<double> pinShakeAnimation;

  void initPinShakeAnimation() {
    pinShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    pinShakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: pinShakeController, curve: Curves.easeInOut),
    );
  }

  void disposePinShakeAnimation() {
    pinShakeController.dispose();
  }

  void triggerPinShake() {
    pinShakeController.forward(from: 0);
  }
}

class PinVerificationFeedback extends StatelessWidget {
  const PinVerificationFeedback({
    super.key,
    required this.shakeAnimation,
    required this.inputLength,
    required this.attempts,
    required this.isError,
    required this.isLoading,
    this.isSuccess = false,
    this.darkMode = false,
    this.showAttemptStatus = true,
    this.helperText,
    this.helperColor,
  });

  final Animation<double> shakeAnimation;
  final int inputLength;
  final int attempts;
  final bool isError;
  final bool isLoading;
  final bool isSuccess;
  final bool darkMode;
  final bool showAttemptStatus;
  final String? helperText;
  final Color? helperColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = AppConstants.maxPinAttempts - attempts;
    final showAttemptsWarning = showAttemptStatus && attempts > 0;
    final statusText = helperText ??
        (isError
            ? AppStrings.pinIncorrect
            : showAttemptsWarning
                ? '$remaining tentativa${remaining == 1 ? '' : 's'} restante${remaining == 1 ? '' : 's'}'
                : null);
    final statusColor = helperColor ??
        (remaining <= 1
            ? AppColors.error
            : darkMode
                ? AppColors.secondary.withValues(alpha: 0.85)
                : AppColors.amber);

    return Column(
      children: [
        AnimatedBuilder(
          animation: shakeAnimation,
          builder: (_, child) => Transform.translate(
            offset: Offset(shakeAnimation.value, 0),
            child: child,
          ),
          child: PinDots(
            length: AppConstants.pinLength,
            filled: inputLength,
            isError: isError,
            isSuccess: isSuccess,
            darkMode: darkMode,
          ),
        ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          opacity: statusText == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            height: 20,
            child: Center(
              child: statusText == null
                  ? const SizedBox.shrink()
                  : Text(
                      statusText,
                      style: (darkMode
                              ? const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                )
                              : theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600))
                          ?.copyWith(color: statusColor),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ),
        if (isLoading) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: darkMode ? Colors.white : AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}
