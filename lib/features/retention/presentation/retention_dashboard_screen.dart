import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/retention_metric.dart';
import '../providers/retention_providers.dart';
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
      appBar: AppBar(
        title: const Text('Retencao inteligente'),
        backgroundColor: AppColors.offWhite,
        foregroundColor: AppColors.onSurface,
        iconTheme: const IconThemeData(color: AppColors.onSurface),
        titleTextStyle: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        elevation: 0,
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
          title: 'Nao foi possivel validar o plano',
          subtitle: 'Verifique a ligacao e tente novamente.',
          actionLabel: 'Tentar de novo',
          onAction: () => ref.invalidate(retentionPremiumAccessProvider),
        ),
        data: (hasAccess) {
          if (!hasAccess) {
            return EmptyState(
              title: 'Retencao indisponivel no seu plano',
              subtitle:
                  'Funcionalidade premium. Atualize para Pro ou Business para desbloquear.',
              actionLabel: 'Gerir plano',
              onAction: () => context.push('/subscription-admin'),
            );
          }

          return dataAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
            error: (_, __) => EmptyState(
              title: 'Nao foi possivel carregar a retencao',
              subtitle: 'Verifique a ligacao e tente novamente.',
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
        subtitle: 'Assim que houver padrao de retorno, eles aparecerao aqui.',
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

class _InactiveTab extends ConsumerWidget {
  const _InactiveTab({required this.customers});

  final List<InactiveCustomerSummary> customers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customers.isEmpty) {
      return const EmptyState(
        title: 'Sem clientes em risco',
        subtitle: 'Bom trabalho. A base esta saudavel neste momento.',
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
                  child: InactiveCustomerCard(
                    customer: customer,
                    onSendReminder: () {
                      AppFeedback.showSuccessToast(
                        context,
                        message: 'Lembrete preparado',
                        subtitle: customer.name,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
