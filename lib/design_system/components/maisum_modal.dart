import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class MaisUmModal {
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    required String primaryLabel,
    required String secondaryLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(secondaryLabel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(primaryLabel),
            ),
          ],
        );
      },
    );
  }
}
