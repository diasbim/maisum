import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../errors/app_error_mapper.dart';
import 'empty_state.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.title,
    this.subtitle,
  });

  final Object error;
  final VoidCallback? onRetry;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final info = AppErrorMapper.describe(error);
    return EmptyState(
      title: title ?? info.title,
      subtitle: subtitle ?? info.message,
      actionLabel: onRetry == null ? null : AppStrings.tentar,
      onAction: onRetry,
    );
  }
}
