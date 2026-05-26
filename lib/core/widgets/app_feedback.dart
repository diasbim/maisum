import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../theme/app_layout.dart';

class AppFeedback {
  static void showMessage(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            96,
          ),
          showCloseIcon: true,
        ),
      );
  }

  static void showRetryableError(
    BuildContext context, {
    required String message,
    required VoidCallback onRetry,
  }) {
    showMessage(
      context,
      message: message,
      isError: true,
      action: SnackBarAction(
        label: AppStrings.tentar,
        onPressed: onRetry,
      ),
    );
  }
}
