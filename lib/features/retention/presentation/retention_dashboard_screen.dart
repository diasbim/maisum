import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/components/maisum_app_bar.dart';
import '../../customers/domain/customer.dart';
import '../../engage/domain/engage_models.dart';
import '../../engage/providers/engage_providers.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/domain/usage_metrics.dart';
import '../../subscription/presentation/feature_upsell_screen.dart';
import '../domain/retention_metric.dart';
import '../providers/retention_providers.dart';
import '../services/retention_reminder_service.dart';
import '../widgets/inactive_customer_card.dart';
import '../widgets/recurring_customer_card.dart';

class RetentionDashboardScreen extends ConsumerWidget {
  const RetentionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(retentionPremiumAccessProvider);
    final dataAsync = ref.watch(retentionDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: MaisUmAppBar(
        title: 'Retenção inteligente',
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(retentionDashboardProvider.notifier).recalculate(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recalcular',
          ),
        ],
      ),
      body: accessAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (_, __) => EmptyState(
          title: 'Não foi possível validar o plano',
          subtitle: 'Verifique a ligação e tente novamente.',
          actionLabel: 'Tentar de novo',
          onAction: () => ref.invalidate(retentionPremiumAccessProvider),
        ),
        data: (hasAccess) {
          if (!hasAccess) {
            return EmptyState(
              title: 'Retenção indisponível no seu plano',
              subtitle:
                  'Funcionalidade premium. Atualize para Pro ou Business para desbloquear.',
              actionLabel: 'Ver opções',
              onAction: () => context.push(
                featureUpsellLocation(
                  featureKey: FeatureKeys.engageViewRisk,
                  featureName: 'Retenção inteligente',
                  reason: 'plan_restricted',
                ),
              ),
            );
          }

          return dataAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => EmptyState(
              title: 'Não foi possível carregar a retenção',
              subtitle: 'Verifique a ligação e tente novamente.',
              actionLabel: 'Tentar de novo',
              onAction: () =>
                  ref.read(retentionDashboardProvider.notifier).refresh(),
            ),
            data: (data) => DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.md,
                    ),
                    child: TabBar(
                      indicatorColor: AppColors.secondary,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.onSurfaceVariant,
                      tabs: [
                        Tab(text: 'Recorrentes'),
                        Tab(text: 'Em risco'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _RecurringTab(customers: data.recurring),
                        _InactiveTab(customers: data.inactive),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecurringTab extends StatelessWidget {
  const _RecurringTab({required this.customers});

  final List<RecurringCustomerSummary> customers;

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const EmptyState(
        title: 'Sem clientes recorrentes',
        subtitle:
            'Assim que houver um padrão de retorno, os clientes aparecerão aqui.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        const spacing = AppSpacing.md;
        final cardWidth = isWide
            ? (constraints.maxWidth - (AppSpacing.xl * 2) - spacing) / 2
            : constraints.maxWidth - (AppSpacing.xl * 2);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final customer in customers)
                SizedBox(
                  width: cardWidth,
                  child: RecurringCustomerCard(customer: customer),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InactiveTab extends ConsumerStatefulWidget {
  const _InactiveTab({required this.customers});

  final List<InactiveCustomerSummary> customers;

  @override
  ConsumerState<_InactiveTab> createState() => _InactiveTabState();
}

class _InactiveTabState extends ConsumerState<_InactiveTab> {
  final Set<String> _sendingCustomerIds = <String>{};
  final RetentionReminderService _reminderService =
      const RetentionReminderService();

  Future<void> _sendReminder(InactiveCustomerSummary summary) async {
    if (_sendingCustomerIds.contains(summary.customerId)) return;

    setState(() => _sendingCustomerIds.add(summary.customerId));
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getById(summary.customerId);
      if (customer == null) {
        _showError('Não foi possível encontrar este cliente.');
        return;
      }
      if (customer.whatsappConsentStatus != CustomerConsentStatus.granted) {
        _showError(AppStrings.whatsappConsentRequired);
        return;
      }

      final decision = await ref.read(featureGateProvider).check(
            featureKey: FeatureKeys.whatsappAutomation,
            metricKey: UsageMetrics.whatsappMessages,
          );
      if (!decision.allowed) {
        if (mounted) {
          context.push(
            featureUpsellLocation(
              featureKey: FeatureKeys.whatsappAutomation,
              featureName: AppStrings.enviarWhatsApp,
              reason: decision.reason,
            ),
          );
        }
        return;
      }
      if (decision.softLimited && mounted) {
        AppFeedback.showMessage(context, message: AppStrings.limiteSoftAviso);
      }

      final outcome = await _reminderService.send(
        customer: customer,
        isOnline: ref.read(connectivityServiceProvider).isOnline,
        launchWhatsApp: (uri) => launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ),
      );

      switch (outcome) {
        case RetentionReminderDelivery.openedWhatsApp:
          await _recordReminderAction(customer, queued: false);
          if (mounted) {
            AppFeedback.showSuccessToast(
              context,
              message: 'WhatsApp aberto',
              subtitle: 'Lembrete pronto para enviar a ${customer.name}.',
            );
          }
        case RetentionReminderDelivery.offline:
          _showError(
            'Sem ligação. Volte a tentar quando estiver online para abrir o WhatsApp.',
          );
        case RetentionReminderDelivery.consentRequired:
          _showError(AppStrings.whatsappConsentRequired);
        case RetentionReminderDelivery.invalidPhone:
          _showError('Este cliente não tem um número de WhatsApp válido.');
        case RetentionReminderDelivery.failed:
          _showError(
            'Não foi possível abrir ou preparar o lembrete. Tente novamente.',
          );
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'retention_reminder',
      );
      _showError('Não foi possível preparar o lembrete. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _sendingCustomerIds.remove(summary.customerId));
      }
    }
  }

  Future<void> _recordReminderAction(
    Customer customer, {
    required bool queued,
  }) async {
    try {
      await ref.read(engageRepositoryProvider).logRecoveryAction(
        customerId: customer.id,
        actionType: RecoveryActionType.whatsapp,
        payload: {
          'source': 'retention_dashboard',
          'message_type': 'inactive_reminder',
          'delivery_mode': queued ? 'queued' : 'business_assisted',
        },
      );
      if (!queued) {
        await ref.read(usageTrackerProvider).record(
          metricKey: UsageMetrics.whatsappMessages,
          source: 'whatsapp',
          metadata: const {'message_type': 'inactive_reminder'},
        );
      }
      await ref.read(analyticsServiceProvider).record(
        eventType: 'whatsapp_sent',
        source: 'whatsapp',
        properties: {
          'queued': queued,
          'source': 'retention_dashboard',
          'message_type': 'inactive_reminder',
        },
      );
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'retention_reminder_attribution',
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      AppFeedback.showMessage(context, message: message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customers.isEmpty) {
      return const EmptyState(
        title: 'Sem clientes em risco',
        subtitle: 'Bom trabalho. A base está saudável neste momento.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        const spacing = AppSpacing.md;
        final cardWidth = isWide
            ? (constraints.maxWidth - (AppSpacing.xl * 2) - spacing) / 2
            : constraints.maxWidth - (AppSpacing.xl * 2);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final customer in widget.customers)
                SizedBox(
                  width: cardWidth,
                  child: InactiveCustomerCard(
                    customer: customer,
                    isSending:
                        _sendingCustomerIds.contains(customer.customerId),
                    onSendReminder: () => _sendReminder(customer),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
