import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_state.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../settings/domain/staff_member.dart';
import '../../subscription/domain/subscription_snapshot.dart';
import '../../subscription/domain/usage_quota.dart';
import '../../subscription/domain/feature_keys.dart';
import '../domain/admin_audit_event.dart';
import '../domain/admin_merchant_summary.dart';
import '../domain/admin_operations_summary.dart';
import '../domain/admin_plan_catalog.dart';
import '../providers/admin_portal_providers.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_service.dart';

enum AdminPortalSection {
  overview,
  merchants,
  plans,
  operations,
  selfService,
}

class AdminPortalShell extends ConsumerWidget {
  const AdminPortalShell({
    super.key,
    required this.section,
    this.merchantId,
  });

  final AdminPortalSection section;
  final String? merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(activeAppUserRoleProvider);
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? false;
    final isInternalAdmin =
        ref.watch(isInternalAdminProvider).valueOrNull ?? false;
    final activeMerchantId = ref.watch(activeMerchantIdProvider);
    final sections = _AdminPortalDestination.allowedFor(
      isInternalAdmin: isInternalAdmin,
      isOwner: isOwner,
    );
    final selected = _AdminPortalDestination.fromSection(section);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: Row(
          children: [
            _AdminNavigationRail(
              destinations: sections,
              selected: selected,
              onSelected: (destination) => context.go(destination.path),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AdminTopBar(
                    roleLabel: role.maybeWhen(
                      data: (value) => value,
                      orElse: () => '...',
                    ),
                    merchantId: activeMerchantId,
                  ),
                  Expanded(
                    child: _AdminSectionBody(
                      section: section,
                      merchantId: merchantId,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminNavigationRail extends StatelessWidget {
  const _AdminNavigationRail({
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  final List<_AdminPortalDestination> destinations;
  final _AdminPortalDestination selected;
  final ValueChanged<_AdminPortalDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      color: AppColors.primaryDarker,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Administração MaisUm',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...destinations.map(
            (destination) => _AdminNavButton(
              destination: destination,
              selected: selected == destination,
              onPressed: () => onSelected(destination),
            ),
          ),
          const Spacer(),
          Text(
            'Painel de operações internas e autoatendimento do negócio',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.g300,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _AdminNavButton extends StatelessWidget {
  const _AdminNavButton({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final _AdminPortalDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primary : AppColors.g100;
    final background = selected ? AppColors.secondary : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(destination.icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
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

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({required this.roleLabel, required this.merchantId});

  final String roleLabel;
  final String? merchantId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portal de administração',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Operações internas e autoatendimento do responsável do negócio',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _AdminContextPill(
            icon: Icons.badge_outlined,
            label: _translateUserRole(roleLabel),
          ),
          const SizedBox(width: 8),
          _AdminContextPill(
            icon: Icons.storefront_outlined,
            label: merchantId ?? 'Sem âmbito de negócio',
          ),
        ],
      ),
    );
  }
}

class _AdminContextPill extends StatelessWidget {
  const _AdminContextPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.g100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionBody extends ConsumerWidget {
  const _AdminSectionBody({required this.section, this.merchantId});

  final AdminPortalSection section;
  final String? merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section == AdminPortalSection.merchants) {
      final selectedMerchantId = merchantId?.trim();
      if (selectedMerchantId != null && selectedMerchantId.isNotEmpty) {
        return _MerchantDetailSection(merchantId: selectedMerchantId);
      }
      return const _MerchantDirectorySection();
    }

    if (section == AdminPortalSection.operations) {
      return const _AdminOperationsSection();
    }

    if (section == AdminPortalSection.plans) {
      return const _AdminPlansSection();
    }

    if (section == AdminPortalSection.selfService) {
      return const _OwnerSelfServiceSection();
    }

    return const _AdminOverviewSection();
  }
}

class _AdminOverviewSection extends ConsumerWidget {
  const _AdminOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminOperationsSummaryProvider);
    final plans = ref.watch(adminPlanCatalogProvider);
    final auditEvents = ref.watch(adminAuditEventsProvider(null));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Visão geral da administração',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Painel em tempo real para operações internas da MaisUm e autoatendimento do responsável do negócio.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        summary.when(
          loading: () =>
              const _AdminLoadingPanel(title: 'Métricas da visão geral'),
          error: (error, _) => _AdminErrorPanel(
            title: 'Métricas da visão geral',
            error: error,
            onRetry: () => ref.invalidate(adminOperationsSummaryProvider),
          ),
          data: (value) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Negócios',
                  value: '${value.merchantCount}',
                  icon: Icons.storefront_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Subscrições ativas',
                  value: '${value.activeSubscriptionCount}',
                  icon: Icons.verified_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Eventos de utilização (24h)',
                  value: '${value.usageEvents24h}',
                  icon: Icons.bolt_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Última auditoria administrativa',
                  value: _formatOptionalDate(value.lastAdminAuditAt),
                  icon: Icons.manage_history_outlined,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            plans.when(
              loading: () =>
                  const _AdminLoadingPanel(title: 'Catálogo de planos'),
              error: (error, _) => _AdminErrorPanel(
                title: 'Catálogo de planos',
                error: error,
                onRetry: () => ref.invalidate(adminPlanCatalogProvider),
              ),
              data: (items) {
                final activePlans = items.where((plan) => plan.isActive).length;
                final activePrices = items.fold<int>(
                  0,
                  (total, plan) =>
                      total +
                      plan.prices.where((price) => price.isActive).length,
                );
                final enabledFeatures = items.fold<int>(
                  0,
                  (total, plan) =>
                      total +
                      plan.features
                          .where((feature) => feature.isEnabled)
                          .length,
                );
                return _AdminDetailPanel(
                  title: 'Catálogo de planos',
                  rows: [
                    _AdminDetailRow(label: 'Planos', value: '${items.length}'),
                    _AdminDetailRow(
                      label: 'Planos ativos',
                      value: '$activePlans',
                    ),
                    _AdminDetailRow(
                      label: 'Preços ativos',
                      value: '$activePrices',
                    ),
                    _AdminDetailRow(
                      label: 'Funcionalidades ativadas',
                      value: '$enabledFeatures',
                    ),
                  ],
                );
              },
            ),
            const _AdminOverviewLinksPanel(),
          ],
        ),
        const SizedBox(height: 20),
        auditEvents.when(
          loading: () => const _AdminLoadingPanel(
            title: 'Auditoria administrativa recente',
          ),
          error: (error, _) => _AdminErrorPanel(
            title: 'Auditoria administrativa recente',
            error: error,
            onRetry: () => ref.invalidate(adminAuditEventsProvider(null)),
          ),
          data: (items) => _AdminAuditEventTable(
            events: items.take(5).toList(growable: false),
            emptyTitle: 'Ainda não há eventos de auditoria',
            emptySubtitle:
                'As alterações de planos, preços, funcionalidades e permissões aparecerão aqui.',
          ),
        ),
      ],
    );
  }
}

class _MerchantDirectorySection extends ConsumerStatefulWidget {
  const _MerchantDirectorySection();

  @override
  ConsumerState<_MerchantDirectorySection> createState() =>
      _MerchantDirectorySectionState();
}

class _MerchantDirectorySectionState
    extends ConsumerState<_MerchantDirectorySection> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _search.trim();
    final searchKey = search.isEmpty ? null : search;
    final merchants = ref.watch(adminMerchantSummariesProvider(searchKey));

    return merchants.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (error, _) => ErrorState(
        error: error,
        onRetry: () =>
            ref.invalidate(adminMerchantSummariesProvider(searchKey)),
      ),
      data: (items) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diretório de negócios',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pesquisar e consultar o negócio, o plano, a equipa e o resumo de utilização.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Limpar pesquisa',
                          ),
                    hintText: 'Pesquisar por nome, telefone ou ID',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.g100),
                    ),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _MerchantSummaryTable(merchants: items),
        ],
      ),
    );
  }
}

class _MerchantSummaryTable extends StatelessWidget {
  const _MerchantSummaryTable({required this.merchants});

  final List<AdminMerchantSummary> merchants;

  @override
  Widget build(BuildContext context) {
    if (merchants.isEmpty) {
      return const _AdminEmptyPanel(
        title: 'Nenhum negócio encontrado',
        subtitle:
            'A API administrativa devolveu um diretório de negócios vazio.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor:
              WidgetStateProperty.all(AppColors.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Negócio')),
            DataColumn(label: Text('Telefone')),
            DataColumn(label: Text('Plano')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Equipa')),
            DataColumn(label: Text('Registos de utilização')),
            DataColumn(label: Text('Atualizado')),
          ],
          rows: merchants.map((merchant) {
            return DataRow(
              onSelectChanged: (_) {
                context.go(
                  '/admin/merchants/${Uri.encodeComponent(merchant.id)}',
                );
              },
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translateMerchantName(merchant.name),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        merchant.id,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(merchant.phone)),
                DataCell(
                  Text(_translatePlanName(
                      merchant.planName ?? merchant.planCode ?? '-')),
                ),
                DataCell(_StatusBadge(
                    label: merchant.subscriptionStatus ?? 'Unknown')),
                DataCell(
                  Text('${merchant.activeStaffCount}/${merchant.staffCount}'),
                ),
                DataCell(Text('${merchant.usageBalanceCount}')),
                DataCell(Text(_formatDate(merchant.updatedAt))),
              ],
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _MerchantDetailSection extends ConsumerWidget {
  const _MerchantDetailSection({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminMerchantDetailProvider(merchantId));

    return detail.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (error, _) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(adminMerchantDetailProvider(merchantId)),
      ),
      data: (detail) {
        final summary = detail.summary;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/admin/merchants'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Diretório de negócios'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translateMerchantName(summary.name),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Resumo apenas de leitura da saúde do negócio, da subscrição, da utilização e da configuração.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _StatusBadge(label: summary.subscriptionStatus ?? 'Unknown'),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Equipa ativa',
                    value: '${summary.activeStaffCount}/${summary.staffCount}',
                    icon: Icons.group_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Saldos de utilização',
                    value: '${summary.usageBalanceCount}',
                    icon: Icons.data_usage_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Utilização consumida',
                    value: '${detail.usageUsedTotal}',
                    icon: Icons.speed_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Permissões',
                    value: '${detail.entitlementCount}',
                    icon: Icons.key_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AdminDetailPanel(
                  title: 'Negócio',
                  rows: [
                    _AdminDetailRow(
                      label: 'ID do negócio',
                      value: summary.id,
                      selectable: true,
                    ),
                    _AdminDetailRow(label: 'Telefone', value: summary.phone),
                    _AdminDetailRow(
                      label: 'Criado em',
                      value: _formatDate(summary.createdAt),
                    ),
                    _AdminDetailRow(
                      label: 'Atualizado em',
                      value: _formatDate(summary.updatedAt),
                    ),
                    _AdminDetailRow(
                      label: 'Última atualização operacional',
                      value: _formatOptionalDate(
                        summary.lastOperationalUpdateAt,
                      ),
                    ),
                  ],
                ),
                _AdminDetailPanel(
                  title: 'Subscrição',
                  rows: [
                    _AdminDetailRow(
                      label: 'Plano',
                      value: _translatePlanName(
                        _formatOptionalText(
                            summary.planName ?? summary.planCode),
                      ),
                    ),
                    _AdminDetailRow(
                      label: 'Versão do plano',
                      value: _formatOptionalNumber(detail.planVersion),
                    ),
                    _AdminDetailRow(
                      label: 'Versão do preço',
                      value: _formatOptionalNumber(detail.pricingVersion),
                    ),
                    _AdminDetailRow(
                      label: 'Fim do teste',
                      value: _formatOptionalDate(detail.trialEndsAt),
                    ),
                    _AdminDetailRow(
                      label: 'Fim do período de tolerância',
                      value: _formatOptionalDate(detail.graceEndsAt),
                    ),
                    _AdminDetailRow(
                      label: 'Período',
                      value:
                          '${_formatOptionalDate(detail.periodStart)} - ${_formatOptionalDate(detail.periodEnd)}',
                    ),
                  ],
                ),
                _AdminDetailPanel(
                  title: 'Operações',
                  rows: [
                    _AdminDetailRow(
                      label: 'Último início de sessão da equipa',
                      value: _formatOptionalDate(detail.lastStaffLoginAt),
                    ),
                    _AdminDetailRow(
                      label: 'Eventos de utilização',
                      value: '${detail.usageEventCount}',
                    ),
                    _AdminDetailRow(
                      label: 'Último evento de utilização',
                      value: _formatOptionalDate(detail.lastUsageEventAt),
                    ),
                    _AdminDetailRow(
                      label: 'Utilização atualizada em',
                      value: _formatOptionalDate(detail.usageUpdatedAt),
                    ),
                    _AdminDetailRow(
                      label: 'Indicadores de funcionalidade',
                      value: '${detail.featureFlagCount}',
                    ),
                    _AdminDetailRow(
                      label: 'Registos de configuração remota',
                      value: '${detail.remoteConfigCount}',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _EntitlementOverridePanel(merchantId: summary.id),
            const SizedBox(height: 20),
            _AdminAuditEventSection(
              merchantId: summary.id,
              title: 'Histórico de auditoria do negócio',
              description:
                  'Alterações administrativas no âmbito do negócio atualmente em análise.',
              emptyTitle: 'Ainda não há eventos de auditoria deste negócio',
              emptySubtitle:
                  'Os ajustes de permissões e futuras ações de suporte deste negócio aparecerão aqui.',
            ),
          ],
        );
      },
    );
  }
}

class _OwnerSelfServiceSection extends ConsumerWidget {
  const _OwnerSelfServiceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(subscriptionSnapshotProvider);
    final staff = ref.watch(staffMembersProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final merchantId = ref.watch(activeMerchantIdProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Autoatendimento do responsável',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vista do responsável sobre o estado do plano, o acesso da equipa e a saúde da sincronização no âmbito atual do negócio.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AdminMetricCard(
              metric: _AdminMetric(
                label: 'Âmbito do negócio',
                value: merchantId ?? '-',
                icon: Icons.storefront_outlined,
              ),
            ),
            _AdminMetricCard(
              metric: _AdminMetric(
                label: 'Fila de sincronização',
                value: _formatSyncQueue(syncStatus),
                icon: Icons.sync_rounded,
              ),
            ),
            _AdminMetricCard(
              metric: _AdminMetric(
                label: 'Conectividade',
                value: syncStatus.isOnline ? 'Ligado' : 'Sem ligação',
                icon: syncStatus.isOnline
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _OwnerSubscriptionPanel(snapshot: snapshot),
            _OwnerSyncPanel(status: syncStatus),
            _OwnerStaffPanel(staff: staff),
          ],
        ),
      ],
    );
  }
}

class _OwnerSubscriptionPanel extends ConsumerWidget {
  const _OwnerSubscriptionPanel({required this.snapshot});

  final AsyncValue<SubscriptionSnapshot> snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 430,
      child: snapshot.when(
        loading: () => const _AdminLoadingPanel(title: 'Subscrição'),
        error: (error, _) => _AdminErrorPanel(
          title: 'Subscrição',
          error: error,
          onRetry: () => ref.invalidate(subscriptionSnapshotProvider),
        ),
        data: (value) {
          final state = value.state;
          final quota = value.whatsappQuota;
          return _AdminDetailPanel(
            title: 'Subscrição',
            rows: [
              _AdminDetailRow(
                label: 'Plano',
                value: _translatePlanName(
                  state?.resolvedPlanName ?? value.plan.displayName,
                ),
              ),
              _AdminDetailRow(
                label: 'Estado',
                value: _translateStatusLabel(value.status.code),
              ),
              _AdminDetailRow(
                label: 'Versão do plano',
                value: _formatOptionalNumber(state?.planVersion),
              ),
              _AdminDetailRow(
                label: 'Versão do preço',
                value: _formatOptionalNumber(state?.pricingVersion),
              ),
              _AdminDetailRow(
                label: 'Quota do WhatsApp',
                value: _formatQuota(quota),
              ),
              _AdminDetailRow(
                label: 'Reposição da quota',
                value: _formatDate(quota.resetAt),
              ),
              _AdminDetailRow(
                label: 'Atualizado em',
                value: _formatOptionalDate(state?.updatedAt),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OwnerSyncPanel extends ConsumerWidget {
  const _OwnerSyncPanel({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 430,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.g100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado da sincronização',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Fase',
                value: _translateSyncPhase(status.phase.name),
              ),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Pendentes',
                value: '${status.pendingCount}',
              ),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Falhas',
                value: '${status.failedCount}',
              ),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Última sincronização',
                value: _formatOptionalDate(status.lastSyncAt),
              ),
            ),
            if (status.lastError != null)
              _AdminDetailRowView(
                row: _AdminDetailRow(label: 'Erro', value: status.lastError!),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: status.isSyncing
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).sync(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sincronizar agora'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerStaffPanel extends ConsumerWidget {
  const _OwnerStaffPanel({required this.staff});

  final AsyncValue<List<StaffMember>> staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 640,
      child: staff.when(
        loading: () => const _AdminLoadingPanel(title: 'Acesso da equipa'),
        error: (error, _) => _AdminErrorPanel(
          title: 'Acesso da equipa',
          error: error,
          onRetry: () => ref.invalidate(staffMembersProvider),
        ),
        data: (members) => _OwnerStaffTable(members: members),
      ),
    );
  }
}

class _OwnerStaffTable extends StatelessWidget {
  const _OwnerStaffTable({required this.members});

  final List<StaffMember> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const _AdminEmptyPanel(
        title: 'Sem membros da equipa',
        subtitle:
            'Convide a equipa no ecrã móvel de definições do responsável.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(AppColors.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Telefone')),
            DataColumn(label: Text('Perfil')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Último início de sessão')),
            DataColumn(label: Text('Atualizado')),
          ],
          rows: members.map((member) {
            return DataRow(cells: [
              DataCell(Text(member.phone)),
              DataCell(Text(_translateUserRole(member.role))),
              DataCell(_StatusBadge(label: member.status)),
              DataCell(Text(_formatOptionalDate(member.lastLoginAt))),
              DataCell(Text(_formatDate(member.updatedAt))),
            ]);
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _AdminLoadingPanel extends StatelessWidget {
  const _AdminLoadingPanel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(title),
        ],
      ),
    );
  }
}

class _AdminErrorPanel extends StatelessWidget {
  const _AdminErrorPanel({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _EntitlementOverridePanel extends ConsumerStatefulWidget {
  const _EntitlementOverridePanel({required this.merchantId});

  final String merchantId;

  @override
  ConsumerState<_EntitlementOverridePanel> createState() =>
      _EntitlementOverridePanelState();
}

class _EntitlementOverridePanelState
    extends ConsumerState<_EntitlementOverridePanel> {
  String _featureKey = FeatureKeys.whatsappAutomation;
  bool _isEnabled = true;
  AsyncValue<void> _submission = const AsyncData(null);
  final _limitController = TextEditingController();
  final _unitController = TextEditingController(text: 'mensal');

  @override
  void dispose() {
    _limitController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _submission.isLoading;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajuste de permissão',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Aplica um ajuste de funcionalidade no âmbito do negócio e regista-o no histórico de auditoria administrativa.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _featureKey,
                  decoration:
                      const InputDecoration(labelText: 'Funcionalidade'),
                  items: FeatureKeys.all
                      .map(
                        (featureKey) => DropdownMenuItem(
                          value: featureKey,
                          child: Text(featureKey),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _featureKey = value);
                          }
                        },
                ),
              ),
              SizedBox(
                width: 150,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativado'),
                  value: _isEnabled,
                  onChanged: isSaving
                      ? null
                      : (value) => setState(() => _isEnabled = value),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _limitController,
                  enabled: !isSaving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Limite'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _unitController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilledButton.icon(
                onPressed: isSaving ? null : () => _submit(context),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_outlined),
                label: const Text('Aplicar ajuste'),
              ),
            ],
          ),
          if (_submission.hasError) ...[
            const SizedBox(height: 10),
            Text(
              _submission.error.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  int? _readLimit() {
    final text = _limitController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _submit(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submission = const AsyncLoading());
    try {
      await ref.read(adminPortalApiProvider).overrideEntitlement(
            merchantId: widget.merchantId,
            featureKey: _featureKey,
            isEnabled: _isEnabled,
            limitValue: _readLimit(),
            unit: _unitController.text.trim().isEmpty
                ? null
                : _normalizeUnitInput(_unitController.text),
          );
      ref.invalidate(adminMerchantDetailProvider(widget.merchantId));
      ref.invalidate(adminAuditEventsProvider(null));
      ref.invalidate(adminAuditEventsProvider(widget.merchantId));
      if (mounted) {
        setState(() => _submission = const AsyncData(null));
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _submission = AsyncError(error, stackTrace));
      }
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Ajuste de permissão aplicado')),
    );
  }
}

class _AdminOperationsSection extends ConsumerWidget {
  const _AdminOperationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminOperationsSummaryProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Operações',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Saúde geral de negócios, subscrições, utilização, recuperação e auditoria.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        summary.when(
          loading: () => const _AdminLoadingPanel(title: 'Resumo operacional'),
          error: (error, _) => _AdminErrorPanel(
            title: 'Resumo operacional',
            error: error,
            onRetry: () => ref.invalidate(adminOperationsSummaryProvider),
          ),
          data: (summary) => _OperationsSummaryGrid(summary: summary),
        ),
        const SizedBox(height: 20),
        const _AdminAuditEventSection(
          title: 'Histórico de auditoria das operações',
          description:
              'Alterações administrativas auditadas em planos, preços, funcionalidades e ajustes por negócio.',
          emptyTitle: 'Ainda não há eventos de auditoria',
          emptySubtitle:
              'As alterações administrativas aparecerão aqui quando os endpoints auditados forem executados.',
          embedded: true,
        ),
      ],
    );
  }
}

class _OperationsSummaryGrid extends StatelessWidget {
  const _OperationsSummaryGrid({required this.summary});

  final AdminOperationsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Negócios',
            value: '${summary.merchantCount}',
            icon: Icons.storefront_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Subscrições ativas',
            value: '${summary.activeSubscriptionCount}',
            icon: Icons.verified_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Subscrições em teste',
            value: '${summary.trialSubscriptionCount}',
            icon: Icons.hourglass_bottom_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Precisam de atenção',
            value: '${summary.attentionSubscriptionCount}',
            icon: Icons.report_problem_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Equipa ativa',
            value: '${summary.activeStaffCount}',
            icon: Icons.group_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Eventos de utilização (24h)',
            value: '${summary.usageEvents24h}',
            icon: Icons.bolt_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Tarefas de recuperação abertas',
            value: '${summary.openRecoveryTaskCount}',
            icon: Icons.assignment_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Relatórios de visita (24h)',
            value: '${summary.visitReports24h}',
            icon: Icons.fact_check_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Respostas a inquéritos (24h)',
            value: '${summary.surveyResponses24h}',
            icon: Icons.rate_review_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Auditoria administrativa (24h)',
            value: '${summary.adminAuditEvents24h}',
            icon: Icons.history_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Última auditoria administrativa',
            value: _formatOptionalDate(summary.lastAdminAuditAt),
            icon: Icons.manage_history_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Último evento de utilização',
            value: _formatOptionalDate(summary.lastUsageEventAt),
            icon: Icons.timeline_outlined,
          ),
        ),
      ],
    );
  }
}

class _AdminPlansSection extends ConsumerWidget {
  const _AdminPlansSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(adminPlanCatalogProvider);

    return plans.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (error, _) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(adminPlanCatalogProvider),
      ),
      data: (items) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Catálogo de planos',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gerir versões de planos e preços ativos usados no registo de negócios e no estado da subscrição.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          _AdminPlanCatalogTable(plans: items),
          const SizedBox(height: 20),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              _PlanUpsertPanel(),
              _PriceUpsertPanel(),
              _PlanFeatureUpsertPanel(),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminPlanCatalogTable extends StatelessWidget {
  const _AdminPlanCatalogTable({required this.plans});

  final List<AdminPlanCatalogItem> plans;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const _AdminEmptyPanel(
        title: 'Nenhum plano configurado',
        subtitle: 'Crie uma versão de plano para começar a compor o catálogo.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(AppColors.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Plano')),
            DataColumn(label: Text('Versão')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Preços ativos')),
            DataColumn(label: Text('Funcionalidades')),
            DataColumn(label: Text('Atualizado')),
          ],
          rows: plans.map((plan) {
            final activePrices = plan.prices
                .where((price) => price.isActive)
                .map(_formatPrice)
                .join(', ');
            final enabledFeatures = plan.features
                .where((feature) => feature.isEnabled)
                .map((feature) => feature.featureKey)
                .toList(growable: false);
            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translatePlanName(plan.name),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        plan.planCode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                DataCell(Text('${plan.version}')),
                DataCell(_StatusBadge(
                  label: _translateStatusLabel(
                    plan.isActive ? 'ACTIVE' : 'INACTIVE',
                  ),
                )),
                DataCell(Text(activePrices.isEmpty ? '-' : activePrices)),
                DataCell(Text(
                  enabledFeatures.isEmpty
                      ? '${plan.features.length} configuradas'
                      : enabledFeatures.join(', '),
                )),
                DataCell(Text(_formatDate(plan.updatedAt))),
              ],
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _PlanUpsertPanel extends ConsumerStatefulWidget {
  const _PlanUpsertPanel();

  @override
  ConsumerState<_PlanUpsertPanel> createState() => _PlanUpsertPanelState();
}

class _PlanUpsertPanelState extends ConsumerState<_PlanUpsertPanel> {
  final _planCodeController = TextEditingController();
  final _versionController = TextEditingController(text: '1');
  final _nameController = TextEditingController();
  bool _isActive = true;
  AsyncValue<void> _submission = const AsyncData(null);

  @override
  void dispose() {
    _planCodeController.dispose();
    _versionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _submission.isLoading;
    return _AdminMutationPanel(
      width: 430,
      title: 'Criar ou atualizar plano',
      description:
          'Cria ou atualiza uma versão do plano no catálogo e, opcionalmente, marca-a como ativa.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Código do plano'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Nome visível'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _versionController,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Versão'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo'),
                value: _isActive,
                onChanged: isSaving
                    ? null
                    : (value) => setState(() => _isActive = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: isSaving ? null : () => _submit(context),
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.library_add_outlined),
            label: const Text('Guardar plano'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final version = int.tryParse(_versionController.text.trim());
    if (version == null) {
      setState(() => _submission = AsyncError(
            ArgumentError('A versão deve ser um número.'),
            StackTrace.current,
          ));
      return;
    }

    setState(() => _submission = const AsyncLoading());
    try {
      await ref.read(adminPortalApiProvider).upsertPlan(
            planCode: _planCodeController.text.trim(),
            version: version,
            name: _nameController.text.trim(),
            isActive: _isActive,
          );
      ref.invalidate(adminPlanCatalogProvider);
      ref.invalidate(adminAuditEventsProvider(null));
      if (mounted) {
        setState(() => _submission = const AsyncData(null));
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _submission = AsyncError(error, stackTrace));
      }
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Plano guardado')),
    );
  }
}

class _PriceUpsertPanel extends ConsumerStatefulWidget {
  const _PriceUpsertPanel();

  @override
  ConsumerState<_PriceUpsertPanel> createState() => _PriceUpsertPanelState();
}

class _PriceUpsertPanelState extends ConsumerState<_PriceUpsertPanel> {
  final _planCodeController = TextEditingController();
  final _pricingVersionController = TextEditingController(text: '1');
  final _currencyController = TextEditingController(text: 'MZN');
  final _amountController = TextEditingController();
  final _billingPeriodController = TextEditingController(text: 'mensal');
  bool _isActive = true;
  AsyncValue<void> _submission = const AsyncData(null);

  @override
  void dispose() {
    _planCodeController.dispose();
    _pricingVersionController.dispose();
    _currencyController.dispose();
    _amountController.dispose();
    _billingPeriodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _submission.isLoading;
    return _AdminMutationPanel(
      width: 430,
      title: 'Criar ou atualizar preço',
      description:
          'Cria ou atualiza uma versão de preço para um plano e uma moeda.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Código do plano'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pricingVersionController,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Versão do preço'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _currencyController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Moeda'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amountController,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montante'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _billingPeriodController,
                enabled: !isSaving,
                decoration:
                    const InputDecoration(labelText: 'Período de faturação'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo'),
          value: _isActive,
          onChanged:
              isSaving ? null : (value) => setState(() => _isActive = value),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: isSaving ? null : () => _submit(context),
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sell_outlined),
            label: const Text('Guardar preço'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final pricingVersion = int.tryParse(_pricingVersionController.text.trim());
    final amount = int.tryParse(_amountController.text.trim());
    if (pricingVersion == null || amount == null) {
      setState(() => _submission = AsyncError(
            ArgumentError(
              'A versão do preço e o montante devem ser números.',
            ),
            StackTrace.current,
          ));
      return;
    }

    setState(() => _submission = const AsyncLoading());
    try {
      await ref.read(adminPortalApiProvider).upsertPrice(
            planCode: _planCodeController.text.trim(),
            pricingVersion: pricingVersion,
            currency: _currencyController.text.trim(),
            amount: amount,
            billingPeriod: _normalizeUnitInput(_billingPeriodController.text),
            isActive: _isActive,
          );
      ref.invalidate(adminPlanCatalogProvider);
      ref.invalidate(adminAuditEventsProvider(null));
      if (mounted) {
        setState(() => _submission = const AsyncData(null));
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _submission = AsyncError(error, stackTrace));
      }
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Preço guardado')),
    );
  }
}

class _PlanFeatureUpsertPanel extends ConsumerStatefulWidget {
  const _PlanFeatureUpsertPanel();

  @override
  ConsumerState<_PlanFeatureUpsertPanel> createState() =>
      _PlanFeatureUpsertPanelState();
}

class _PlanFeatureUpsertPanelState
    extends ConsumerState<_PlanFeatureUpsertPanel> {
  final _planCodeController = TextEditingController();
  final _planVersionController = TextEditingController(text: '1');
  final _limitController = TextEditingController();
  final _unitController = TextEditingController(text: 'mensal');
  String _featureKey = FeatureKeys.whatsappAutomation;
  bool _isEnabled = true;
  AsyncValue<void> _submission = const AsyncData(null);

  @override
  void dispose() {
    _planCodeController.dispose();
    _planVersionController.dispose();
    _limitController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _submission.isLoading;
    return _AdminMutationPanel(
      width: 430,
      title: 'Criar ou atualizar funcionalidade',
      description:
          'Configura uma funcionalidade para uma versão específica do plano.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Código do plano'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _planVersionController,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Versão do plano'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativado'),
                value: _isEnabled,
                onChanged: isSaving
                    ? null
                    : (value) => setState(() => _isEnabled = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _featureKey,
          decoration: const InputDecoration(labelText: 'Funcionalidade'),
          items: FeatureKeys.all
              .map(
                (featureKey) => DropdownMenuItem(
                  value: featureKey,
                  child: Text(featureKey),
                ),
              )
              .toList(growable: false),
          onChanged: isSaving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _featureKey = value);
                  }
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _limitController,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Limite'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _unitController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Unidade'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: isSaving ? null : () => _submit(context),
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.rule_outlined),
            label: const Text('Guardar funcionalidade'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final planVersion = int.tryParse(_planVersionController.text.trim());
    final limitValue = _limitController.text.trim().isEmpty
        ? null
        : int.tryParse(_limitController.text.trim());
    if (planVersion == null ||
        (_limitController.text.trim().isNotEmpty && limitValue == null)) {
      setState(() => _submission = AsyncError(
            ArgumentError(
              'A versão do plano e o limite devem ser números.',
            ),
            StackTrace.current,
          ));
      return;
    }

    setState(() => _submission = const AsyncLoading());
    try {
      await ref.read(adminPortalApiProvider).upsertPlanFeature(
            planCode: _planCodeController.text.trim(),
            planVersion: planVersion,
            featureKey: _featureKey,
            isEnabled: _isEnabled,
            limitValue: limitValue,
            unit: _unitController.text.trim().isEmpty
                ? null
                : _normalizeUnitInput(_unitController.text),
          );
      ref.invalidate(adminPlanCatalogProvider);
      ref.invalidate(adminAuditEventsProvider(null));
      if (mounted) {
        setState(() => _submission = const AsyncData(null));
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _submission = AsyncError(error, stackTrace));
      }
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Funcionalidade do plano guardada')),
    );
  }
}

class _AdminMutationPanel extends StatelessWidget {
  const _AdminMutationPanel({
    required this.width,
    required this.title,
    required this.description,
    required this.children,
    this.error,
  });

  final double width;
  final String title;
  final String description;
  final List<Widget> children;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.g100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ...children,
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminAuditEventSection extends ConsumerWidget {
  const _AdminAuditEventSection({
    required this.title,
    required this.description,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.merchantId,
    this.embedded = false,
  });

  final String title;
  final String description;
  final String emptyTitle;
  final String emptySubtitle;
  final String? merchantId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(adminAuditEventsProvider(merchantId));

    return events.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (error, _) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(adminAuditEventsProvider(merchantId)),
      ),
      data: (items) => ListView(
        shrinkWrap: embedded || merchantId != null,
        physics: embedded || merchantId != null
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: embedded ? EdgeInsets.zero : const EdgeInsets.all(24),
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          _AdminAuditEventTable(
            events: items,
            emptyTitle: emptyTitle,
            emptySubtitle: emptySubtitle,
          ),
        ],
      ),
    );
  }
}

class _AdminAuditEventTable extends StatelessWidget {
  const _AdminAuditEventTable({
    required this.events,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<AdminAuditEvent> events;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _AdminEmptyPanel(
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(AppColors.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Hora')),
            DataColumn(label: Text('Ação')),
            DataColumn(label: Text('Alvo')),
            DataColumn(label: Text('Responsável')),
            DataColumn(label: Text('Negócio')),
          ],
          rows: events.map((event) {
            return DataRow(
              cells: [
                DataCell(Text(_formatDateTime(event.createdAt))),
                DataCell(_StatusBadge(label: event.action)),
                DataCell(
                  Text(
                    '${event.targetType}${event.targetId == null ? '' : ' / ${event.targetId}'}',
                  ),
                ),
                DataCell(
                  Text(
                    event.actorAppUserId ??
                        event.actorFirebaseUid ??
                        event.actorRole ??
                        '-',
                  ),
                ),
                DataCell(Text(event.merchantId ?? '-')),
              ],
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _AdminDetailPanel extends StatelessWidget {
  const _AdminDetailPanel({required this.title, required this.rows});

  final String title;
  final List<_AdminDetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 390,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.g100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            ...rows.map((row) => _AdminDetailRowView(row: row)),
          ],
        ),
      ),
    );
  }
}

class _AdminDetailRowView extends StatelessWidget {
  const _AdminDetailRowView({required this.row});

  final _AdminDetailRow row;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w700,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              row.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: row.selectable
                ? SelectableText(row.value, style: valueStyle)
                : Text(row.value, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

class _AdminDetailRow {
  const _AdminDetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.trim().toUpperCase();
    final color = switch (normalized) {
      'ACTIVE' => AppColors.green,
      'TRIAL' || 'GRACE' || 'INVITED' => AppColors.amber,
      'PAST_DUE' || 'CANCELED' || 'CANCELLED' || 'SUSPENDED' => AppColors.red,
      _ => AppColors.g500,
    };
    final displayLabel = _translateStatusLabel(normalized);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        displayLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _AdminEmptyPanel extends StatelessWidget {
  const _AdminEmptyPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.g100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hour:$minute';
}

String _formatOptionalDate(DateTime? date) {
  return date == null ? '-' : _formatDate(date);
}

String _formatOptionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? '-' : trimmed;
}

String _formatOptionalNumber(int? value) {
  return value == null ? '-' : '$value';
}

String _formatPrice(AdminPlanPrice price) {
  return '${price.amount} ${price.currency} / ${_translateUnitLabel(price.billingPeriod)}';
}

String _translateMerchantName(String value) {
  final trimmed = value.trim();
  if (trimmed.toUpperCase() == 'MERCHANT') {
    return 'Negócio';
  }
  return trimmed.isEmpty ? value : trimmed;
}

String _translatePlanName(String value) {
  final trimmed = value.trim();
  if (trimmed.toUpperCase() == 'PLAN') {
    return 'Plano';
  }
  return trimmed;
}

String _translateUserRole(String value) {
  final normalized = value.trim().toUpperCase();
  return switch (normalized) {
    'OWNER' => 'Responsável',
    'STAFF' => 'Equipa',
    'ADMIN' || 'INTERNAL_ADMIN' => 'Administrador interno',
    _ => value,
  };
}

String _translateStatusLabel(String value) {
  final normalized = value.trim().toUpperCase();
  return switch (normalized) {
    'ACTIVE' => 'ATIVO',
    'TRIAL' => 'TESTE',
    'GRACE' => 'TOLERÂNCIA',
    'PAST_DUE' => 'EM ATRASO',
    'CANCELED' || 'CANCELLED' => 'CANCELADO',
    'SUSPENDED' => 'SUSPENSO',
    'INACTIVE' => 'INATIVO',
    'INVITED' => 'CONVIDADO',
    'PENDING' => 'PENDENTE',
    'FAILED' => 'FALHA',
    'UNKNOWN' => 'DESCONHECIDO',
    _ => normalized,
  };
}

String _translateSyncPhase(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'synced' => 'Sincronizado',
    'syncing' => 'A sincronizar',
    'offline' => 'Sem ligação',
    'pendingchanges' => 'Alterações pendentes',
    'syncfailed' => 'Sincronização com falha',
    'retrying' => 'A tentar novamente',
    _ => value,
  };
}

String _translateUnitLabel(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'monthly' || 'mensal' => 'mensal',
    'weekly' || 'semanal' => 'semanal',
    'daily' || 'diário' || 'diario' => 'diário',
    'yearly' || 'annual' || 'anual' => 'anual',
    _ => value.trim(),
  };
}

String _normalizeUnitInput(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'monthly' || 'mensal' => 'monthly',
    'weekly' || 'semanal' => 'weekly',
    'daily' || 'diário' || 'diario' => 'daily',
    'yearly' || 'annual' || 'anual' => 'yearly',
    _ => value.trim(),
  };
}

String _formatSyncQueue(SyncStatus status) {
  return '${status.pendingCount} pendentes / ${status.failedCount} falhas';
}

String _formatQuota(UsageQuotaSummary quota) {
  if (quota.limit == null) {
    return '${quota.used} usados / ilimitado';
  }
  return '${quota.used}/${quota.limit} usados';
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.metric});

  final _AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.g100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 14),
            Text(
              metric.value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOverviewLinksPanel extends StatelessWidget {
  const _AdminOverviewLinksPanel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 430,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.g100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Área administrativa',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Entre diretamente nas áreas operacionais com dados em tempo real e alterações auditadas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AdminOverviewLinkButton(
                  label: 'Negócios',
                  icon: Icons.store_mall_directory_outlined,
                  path: '/admin/merchants',
                ),
                _AdminOverviewLinkButton(
                  label: 'Planos',
                  icon: Icons.sell_outlined,
                  path: '/admin/plans',
                ),
                _AdminOverviewLinkButton(
                  label: 'Operações',
                  icon: Icons.monitor_heart_outlined,
                  path: '/admin/operations',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOverviewLinkButton extends StatelessWidget {
  const _AdminOverviewLinkButton({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => context.go(path),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

enum _AdminPortalDestination {
  overview(
    section: AdminPortalSection.overview,
    label: 'Visão geral',
    path: '/admin',
    icon: Icons.dashboard_outlined,
  ),
  merchants(
    section: AdminPortalSection.merchants,
    label: 'Negócios',
    path: '/admin/merchants',
    icon: Icons.store_mall_directory_outlined,
  ),
  plans(
    section: AdminPortalSection.plans,
    label: 'Planos e preços',
    path: '/admin/plans',
    icon: Icons.sell_outlined,
  ),
  operations(
    section: AdminPortalSection.operations,
    label: 'Operações',
    path: '/admin/operations',
    icon: Icons.monitor_heart_outlined,
  ),
  selfService(
    section: AdminPortalSection.selfService,
    label: 'Autoatendimento do responsável',
    path: '/admin/self-service',
    icon: Icons.manage_accounts_outlined,
  );

  const _AdminPortalDestination({
    required this.section,
    required this.label,
    required this.path,
    required this.icon,
  });

  final AdminPortalSection section;
  final String label;
  final String path;
  final IconData icon;

  static _AdminPortalDestination fromSection(AdminPortalSection section) {
    return _AdminPortalDestination.values.firstWhere(
      (destination) => destination.section == section,
    );
  }

  static List<_AdminPortalDestination> allowedFor({
    required bool isInternalAdmin,
    required bool isOwner,
  }) {
    return _AdminPortalDestination.values.where((destination) {
      if (destination.section == AdminPortalSection.selfService) {
        return isOwner;
      }
      return isInternalAdmin;
    }).toList(growable: false);
  }
}

class _AdminMetric {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}
