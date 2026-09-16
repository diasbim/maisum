import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/errors/app_error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../core/utils/moz_phone_utils.dart';
import '../../../../design_system/design_system.dart';

/// The three things every affiliate screen has to say while it waits.
///
/// Loading keeps the final layout so the page does not jump when the answer
/// arrives; an error says what a shop owner can do about it and offers the
/// retry; empty explains what the screen is for and offers the one action that
/// fills it. They live here because six screens answering the same three
/// questions differently is how an app starts feeling unreliable.
class AffiliateAsyncView<T> extends StatelessWidget {
  const AffiliateAsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.skeletonLines = 3,
    this.loadingLabel = 'A carregar',
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T data) builder;
  final int skeletonLines;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => builder(context, data),
      loading: () => AffiliateSkeleton(
        lines: skeletonLines,
        label: loadingLabel,
      ),
      error: (error, _) => AffiliateErrorState(error: error, onRetry: onRetry),
    );
  }
}

/// Placeholder cards the same shape as the real ones.
class AffiliateSkeleton extends StatelessWidget {
  const AffiliateSkeleton({
    super.key,
    this.lines = 3,
    this.label = 'A carregar',
  });

  final int lines;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label…',
      liveRegion: true,
      child: Column(
        key: const Key('affiliate-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < lines; index += 1)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: MaisUmSurface(
                variant: MaisUmSurfaceVariant.muted,
                radius: AppRadius.lg,
                padding: EdgeInsets.all(AppSpacing.lg),
                animationDuration: Duration.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(widthFactor: 0.55),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonBar(widthFactor: 0.8),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonBar(widthFactor: 0.35),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.g100,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

/// A failure the owner can act on, with the retry attached.
class AffiliateErrorState extends StatelessWidget {
  const AffiliateErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final info = AppErrorMapper.describe(error);
    return MaisUmSurface(
      key: const Key('affiliate-error-state'),
      width: double.infinity,
      variant: MaisUmSurfaceVariant.error,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  info.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            info.message,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          MaisUmButton(
            label: 'Tentar novamente',
            leadingIcon: Icons.refresh_rounded,
            variant: MaisUmButtonVariant.outlined,
            foregroundColor: AppColors.primary,
            onPressed: onRetry,
            animationDuration: Duration.zero,
          ),
        ],
      ),
    );
  }
}

/// Says the list is a floor, not a total.
///
/// The server stops scanning at a cap and flags it. Showing the rows without
/// this line would let an owner conclude they have twelve affiliates when the
/// twelve are only the ones that fit.
class AffiliateTruncatedBanner extends StatelessWidget {
  const AffiliateTruncatedBanner({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return MaisUmSurface(
      key: const Key('affiliate-truncated-banner'),
      width: double.infinity,
      variant: MaisUmSurfaceVariant.warning,
      radius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.md),
      animationDuration: Duration.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              detail ??
                  'Mostramos apenas parte dos dados. Os números podem estar '
                      'incompletos.',
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What cannot be done right now, and why.
class AffiliateOfflineNotice extends StatelessWidget {
  const AffiliateOfflineNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaisUmSurface(
      key: const Key('affiliate-offline-notice'),
      width: double.infinity,
      variant: MaisUmSurfaceVariant.muted,
      radius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.md),
      animationDuration: Duration.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 18, color: AppColors.offline),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A status the eye reads by shape and the screen reader reads by name.
///
/// The icon is not decoration: colour alone would leave the state invisible to
/// anyone who cannot separate the green from the grey, and both are legitimate
/// states rather than success and failure.
class AffiliateStatusChip extends StatelessWidget {
  const AffiliateStatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Estado: $label',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled number, sized so it survives a 200% text scale.
class AffiliateMetricTile extends StatelessWidget {
  const AffiliateMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value${hint == null ? '' : '. $hint'}',
      excludeSemantics: true,
      child: MaisUmSurface(
        width: double.infinity,
        radius: AppRadius.lg,
        padding: const EdgeInsets.all(AppSpacing.lg),
        animationDuration: Duration.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.secondaryForeground),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint!,
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The affiliate's number, as much of it as this user may see.
///
/// An owner manages the relationship and needs to be able to call the person;
/// anyone else gets the masked form, which is the same rule the rest of the app
/// already applies to a customer's number.
String affiliatePhoneForRole({
  required bool isOwner,
  String? phone,
  String? phoneLast4,
}) {
  final value = phone?.trim();
  if (value == null || value.isEmpty) {
    final last4 = phoneLast4?.trim();
    if (last4 == null || last4.isEmpty) return 'Sem número';
    return '*** *** $last4';
  }
  return isOwner ? value : MozPhoneUtils.maskForDisplay(value);
}
