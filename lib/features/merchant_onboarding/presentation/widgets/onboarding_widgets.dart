import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/design_system.dart';
import '../../domain/merchant_onboarding_models.dart';

class ProgressHeader extends StatelessWidget {
  const ProgressHeader({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    this.onBack,
  });

  final MerchantOnboardingStep step;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final progress = step.number / step.total;
    final theme = Theme.of(context);

    return Semantics(
      label: 'Passo ${step.number} de ${step.total}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: AppControlSize.iconButton,
                height: AppControlSize.iconButton,
                child: IconButton(
                  onPressed: onBack ??
                      () {
                        if (context.canPop()) {
                          context.pop();
                          return;
                        }
                        context.go('/onboarding-entry');
                      },
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.primary,
                  tooltip: 'Voltar',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 220),
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: AppColors.g100,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${step.number} de ${step.total}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            title,
            style: theme.textTheme.displaySmall?.copyWith(
              color: AppColors.primaryDarker,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OnboardingStatusScaffold extends StatelessWidget {
  const OnboardingStatusScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.onBack,
    this.errorMessage,
    this.onRetry,
  });

  final MerchantOnboardingStep step;
  final String title;
  final VoidCallback onBack;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.lg,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgressHeader(
                  step: step,
                  title: title,
                  onBack: onBack,
                ),
                Expanded(
                  child: Center(
                    child: errorMessage == null
                        ? const CircularProgressIndicator(
                            color: AppColors.secondary,
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ErrorCard(message: errorMessage!),
                              if (onRetry != null) ...[
                                const SizedBox(height: AppSpacing.lg),
                                MaisUmButton(
                                  label: 'Tentar novamente',
                                  leadingIcon: Icons.refresh_rounded,
                                  variant: MaisUmButtonVariant.outlined,
                                  onPressed: onRetry,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.children,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.primaryEnabled = true,
    this.isLoading = false,
    this.errorMessage,
    this.onBack,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final MerchantOnboardingStep step;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final bool primaryEnabled;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onBack;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final bottomContentPadding =
        secondaryLabel == null ? 120.0 : AppSpacing.xxxxxxl * 3;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          (onBack ?? () => context.go(step.previousRoute))();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= AppBreakpoints.tablet
                  ? AppLayout.formMaxWidth
                  : constraints.maxWidth;

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: maxWidth,
                  height: constraints.maxHeight,
                  child: Stack(
                    children: [
                      ListView(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          AppSpacing.lg,
                          AppSpacing.xxl,
                          bottomContentPadding,
                        ),
                        children: [
                          ProgressHeader(
                            step: step,
                            title: title,
                            subtitle: subtitle,
                            onBack: onBack,
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: errorMessage == null
                                ? const SizedBox.shrink()
                                : ErrorCard(message: errorMessage!),
                          ),
                          if (errorMessage != null)
                            const SizedBox(height: AppSpacing.lg),
                          ...children,
                        ],
                      ),
                      Positioned(
                        left: AppSpacing.xxl,
                        right: AppSpacing.xxl,
                        bottom: AppSpacing.lg,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MaisUmButton(
                              label: primaryLabel,
                              isLoading: isLoading,
                              enabled: primaryEnabled,
                              onPressed: onPrimaryPressed,
                              height: AppControlSize.buttonLarge,
                              trailingIcon: Icons.arrow_forward_rounded,
                              iconColor: AppColors.secondary,
                            ),
                            if (secondaryLabel != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              MaisUmButton(
                                label: secondaryLabel!,
                                enabled: !isLoading,
                                onPressed: onSecondaryPressed,
                                variant: MaisUmButtonVariant.ghost,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isLoading) const LoadingOverlay(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedScale(
        scale: selected ? 1.03 : 1,
        duration: const Duration(milliseconds: 180),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 155;
            return MaisUmSurface(
              onTap: onTap,
              selected: selected,
              padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color:
                          selected ? AppColors.secondary : Colors.transparent,
                      size: compact ? 18 : 26,
                    ),
                  ),
                  Icon(
                    icon,
                    size: compact ? 30 : 44,
                    color: selected
                        ? AppColors.secondary
                        : AppColors.primaryDarker,
                  ),
                  SizedBox(height: compact ? 4 : AppSpacing.md),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color:
                          selected ? AppColors.white : AppColors.primaryDarker,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.onEdit,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaisUmSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.secondaryLight,
                foregroundColor: AppColors.primaryDarker,
                child: Icon(icon),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(onPressed: onEdit, child: const Text('Editar')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.primaryDarker,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaisUmSurface(
      width: double.infinity,
      variant: MaisUmSurfaceVariant.error,
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.primaryDarker.withValues(alpha: 0.24),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
      ),
    );
  }
}
