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
import '../../../design_system/components/maisum_surface.dart';
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

/// Who keeps coming back, and who is slipping away.
///
/// Job: the merchant opens this to decide who to talk to today. The screen
/// therefore leads with a plain sentence explaining where the two lists come
/// from — the feature name alone ("Retenção inteligente") tells a shop owner
/// nothing — and then splits into the two decisions: reward the loyal ones,
/// recover the ones going quiet.
class RetentionDashboardScreen extends ConsumerWidget {
  const RetentionDashboardScreen({super.key});

  Future<void> _recalculate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(retentionDashboardProvider.notifier).recalculate();
      if (context.mounted) {
        AppFeedback.showSuccessToast(
          context,
          message: 'Listas atualizadas',
          subtitle: 'Recalculado com as vendas mais recentes.',
        );
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'retention_recalculate');
      if (context.mounted) {
        AppFeedback.showMessage(
          context,
          message: 'Não foi possível atualizar. Tente novamente.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(retentionPremiumAccessProvider);
    final dataAsync = ref.watch(retentionDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: MaisUmAppBar(
        title: 'Retenção de clientes',
        actions: [
          IconButton(
            onPressed: () => _recalculate(context, ref),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recalcular listas',
            constraints: const BoxConstraints(
              minWidth: AppControlSize.iconButton,
              minHeight: AppControlSize.iconButton,
            ),
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
                  featureName: 'Retenção de clientes',
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.md,
                      AppSpacing.xl,
                      0,
                    ),
                    child: _RetentionIntro(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.sm,
                    ),
                    child: TabBar(
                      indicatorColor: AppColors.secondaryDark,
                      indicatorWeight: 3,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.onSurfaceVariant,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                      unselectedLabelStyle:
                          const TextStyle(fontWeight: FontWeight.w500),
                      tabs: [
                        Tab(text: 'Fiéis · ${data.recurring.length}'),
                        Tab(text: 'Em risco · ${data.inactive.length}'),
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

/// Says, in one sentence, where these lists come from. Without it the merchant
/// has to guess whether the app is showing data it invented or data they fed it.
class _RetentionIntro extends StatelessWidget {
  const _RetentionIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaisUmSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.card,
      backgroundColor: AppColors.secondaryLight,
      borderColor: AppColors.secondary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.insights_rounded,
            color: AppColors.secondaryForeground,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quem volta e quem está a desaparecer',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Calculado a partir das vendas que registou. Recompense os '
                  'fiéis e chame de volta os que estão em risco.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringTab extends ConsumerWidget {
  const _RecurringTab({required this.customers});

  final List<RecurringCustomerSummary> customers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customers.isEmpty) {
      return const EmptyState(
        title: 'Ainda ninguém repetiu',
        subtitle:
            'Assim que um cliente voltar uma segunda vez, aparece aqui com o '
            'ritmo de visitas dele.',
      );
    }

    return _RetentionList(
      onRefresh: () => ref.read(retentionDashboardProvider.notifier).refresh(),
      itemCount: customers.length,
      itemBuilder: (index) => RecurringCustomerCard(customer: customers[index]),
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
        title: 'Ninguém em risco agora',
        subtitle:
            'Todos os seus clientes voltaram dentro do prazo esperado. '
            'Continue a registar vendas para manter esta lista atualizada.',
      );
    }

    return _RetentionList(
      onRefresh: () => ref.read(retentionDashboardProvider.notifier).refresh(),
      itemCount: widget.customers.length,
      itemBuilder: (index) {
        final customer = widget.customers[index];
        return InactiveCustomerCard(
          customer: customer,
          isSending: _sendingCustomerIds.contains(customer.customerId),
          onSendReminder: () => _sendReminder(customer),
        );
      },
    );
  }
}

/// Shared layout for both tabs: one column on a phone, two on a tablet, and
/// pull-to-refresh, which is what a merchant reaches for after a sale.
class _RetentionList extends StatelessWidget {
  const _RetentionList({
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
  });

  final Future<void> Function() onRefresh;
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.secondaryDark,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= AppBreakpoints.tablet + 120;
          const spacing = AppSpacing.md;
          final cardWidth = isWide
              ? (constraints.maxWidth - (AppSpacing.xl * 2) - spacing) / 2
              : constraints.maxWidth - (AppSpacing.xl * 2);

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                for (var index = 0; index < itemCount; index++)
                  SizedBox(width: cardWidth, child: itemBuilder(index)),
              ],
            ),
          );
        },
      ),
    );
  }
}
