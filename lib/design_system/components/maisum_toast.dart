import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum MaisUmToastType { success, warning, error, info }

class MaisUmToast {
  static void show(
    BuildContext context, {
    required String message,
    MaisUmToastType type = MaisUmToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: _background(type),
          content: Row(
            children: [
              Icon(_icon(type), color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  static Color _background(MaisUmToastType type) {
    switch (type) {
      case MaisUmToastType.success:
        return AppColors.success;
      case MaisUmToastType.warning:
        return AppColors.warning;
      case MaisUmToastType.error:
        return AppColors.error;
      case MaisUmToastType.info:
        return AppColors.primary;
    }
  }

  static IconData _icon(MaisUmToastType type) {
    switch (type) {
      case MaisUmToastType.success:
        return Icons.check_circle_rounded;
      case MaisUmToastType.warning:
        return Icons.warning_amber_rounded;
      case MaisUmToastType.error:
        return Icons.error_outline_rounded;
      case MaisUmToastType.info:
        return Icons.info_outline_rounded;
    }
  }
}
