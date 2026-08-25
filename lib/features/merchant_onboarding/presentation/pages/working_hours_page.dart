import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../design_system/components/maisum_button.dart';
import '../../domain/merchant_onboarding_models.dart';
import '../controllers/merchant_onboarding_controller.dart';
import '../widgets/onboarding_widgets.dart';

class WorkingHoursPage extends ConsumerWidget {
  const WorkingHoursPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(merchantOnboardingControllerProvider);
    return asyncState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: ErrorCard(message: 'Não foi possível carregar os horários.')),
      data: (state) {
        final hours = state.draft.workingHours.isEmpty
            ? state.config.defaultWorkingHours
            : state.draft.workingHours;
        final sortedDays = hours.keys.toList()..sort();
        final hasConfig = sortedDays.isNotEmpty;

        return OnboardingScaffold(
          step: MerchantOnboardingStep.workingHours,
          title: 'Horário de funcionamento',
          subtitle: 'Escolha os dias em que atende clientes.',
          errorMessage: state.errorMessage,
          primaryLabel: 'Continuar',
          primaryEnabled: hasConfig,
          onPrimaryPressed: () async {
            final moved = await ref
                .read(merchantOnboardingControllerProvider.notifier)
                .continueFromStep(MerchantOnboardingStep.workingHours);
            if (moved && context.mounted) {
              context.go(MerchantOnboardingStep.services.route);
            }
          },
          children: [
            if (!hasConfig)
              const ErrorCard(
                message:
                    'Os horários padrão ainda não foram configurados no Firestore.',
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: MaisUmButton(
                      label: 'Copiar primeiro dia',
                      leadingIcon: Icons.copy_rounded,
                      variant: MaisUmButtonVariant.outlined,
                      onPressed: () {
                        final template = hours[sortedDays.first]!;
                        ref
                            .read(merchantOnboardingControllerProvider.notifier)
                            .updateWorkingHours({
                          for (final day in sortedDays)
                            day: template.copyWith(weekday: day),
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: MaisUmButton(
                      label: 'Fechar tudo',
                      leadingIcon: Icons.schedule_rounded,
                      variant: MaisUmButtonVariant.outlined,
                      onPressed: () {
                        ref
                            .read(merchantOnboardingControllerProvider.notifier)
                            .updateWorkingHours({
                          for (final entry in hours.entries)
                            entry.key: entry.value.copyWith(isOpen: false),
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final day in sortedDays) ...[
                _WorkingHoursTile(
                  label: state.config.weekdayLabels[day] ?? day.toString(),
                  hours: hours[day]!,
                  onChanged: (value) {
                    ref
                        .read(merchantOnboardingControllerProvider.notifier)
                        .updateWorkingHours({
                      ...hours,
                      day: value,
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _WorkingHoursTile extends StatelessWidget {
  const _WorkingHoursTile({
    required this.label,
    required this.hours,
    required this.onChanged,
  });

  final String label;
  final WorkingHours hours;
  final ValueChanged<WorkingHours> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: hours.isOpen ? AppColors.white : AppColors.g100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: hours.isOpen ? AppColors.secondaryLight : AppColors.g300),
        boxShadow: hours.isOpen ? AppShadows.sm : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.primaryDarker,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            hours.isOpen ? '${hours.openTime} - ${hours.closeTime}' : 'Fechado',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          Switch(
            value: hours.isOpen,
            activeThumbColor: AppColors.secondary,
            onChanged: (value) => onChanged(hours.copyWith(isOpen: value)),
          ),
        ],
      ),
    );
  }
}
