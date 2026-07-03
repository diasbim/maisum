import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_state.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../settings/domain/staff_member.dart';
import '../../subscription/domain/subscription_snapshot.dart';
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
                'Maisum Admin',
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
            'Internal ops and merchant self-service shell',
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
                  'Admin portal',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Internal operations and merchant owner self-service',
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
            label: roleLabel,
          ),
          const SizedBox(width: 8),
          _AdminContextPill(
            icon: Icons.storefront_outlined,
            label: merchantId ?? 'No merchant scope',
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
          'Admin overview',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Live control surface for internal Maisum operations and merchant owner self-service.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        summary.when(
          loading: () => const _AdminLoadingPanel(title: 'Overview metrics'),
          error: (error, _) => _AdminErrorPanel(
            title: 'Overview metrics',
            error: error,
            onRetry: () => ref.invalidate(adminOperationsSummaryProvider),
          ),
          data: (value) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Merchants',
                  value: '${value.merchantCount}',
                  icon: Icons.storefront_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Active subscriptions',
                  value: '${value.activeSubscriptionCount}',
                  icon: Icons.verified_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Usage events 24h',
                  value: '${value.usageEvents24h}',
                  icon: Icons.bolt_outlined,
                ),
              ),
              _AdminMetricCard(
                metric: _AdminMetric(
                  label: 'Last admin audit',
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
              loading: () => const _AdminLoadingPanel(title: 'Plan catalog'),
              error: (error, _) => _AdminErrorPanel(
                title: 'Plan catalog',
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
                  title: 'Plan catalog',
                  rows: [
                    _AdminDetailRow(label: 'Plans', value: '${items.length}'),
                    _AdminDetailRow(
                      label: 'Active plans',
                      value: '$activePlans',
                    ),
                    _AdminDetailRow(
                      label: 'Active prices',
                      value: '$activePrices',
                    ),
                    _AdminDetailRow(
                      label: 'Enabled features',
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
          loading: () => const _AdminLoadingPanel(title: 'Recent admin audit'),
          error: (error, _) => _AdminErrorPanel(
            title: 'Recent admin audit',
            error: error,
            onRetry: () => ref.invalidate(adminAuditEventsProvider(null)),
          ),
          data: (items) => _AdminAuditEventTable(
            events: items.take(5).toList(growable: false),
            emptyTitle: 'No audit events yet',
            emptySubtitle:
                'Plan, pricing, feature, and entitlement changes will appear here.',
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
                      'Merchant directory',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Search and inspect merchant tenancy, plan, staff, and usage summary state.',
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
                            tooltip: 'Clear search',
                          ),
                    hintText: 'Search by name, phone, or ID',
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
        title: 'No merchants found',
        subtitle: 'The admin API returned an empty merchant directory.',
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
            DataColumn(label: Text('Merchant')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Plan')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Staff')),
            DataColumn(label: Text('Usage rows')),
            DataColumn(label: Text('Updated')),
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
                        merchant.name,
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
                DataCell(Text(merchant.planName ?? merchant.planCode ?? '-')),
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
                label: const Text('Merchant directory'),
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
                        summary.name,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Read-only tenant health, subscription, usage, and configuration snapshot.',
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
                    label: 'Active staff',
                    value: '${summary.activeStaffCount}/${summary.staffCount}',
                    icon: Icons.group_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Usage balances',
                    value: '${summary.usageBalanceCount}',
                    icon: Icons.data_usage_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Usage consumed',
                    value: '${detail.usageUsedTotal}',
                    icon: Icons.speed_outlined,
                  ),
                ),
                _AdminMetricCard(
                  metric: _AdminMetric(
                    label: 'Entitlements',
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
                  title: 'Tenant',
                  rows: [
                    _AdminDetailRow(
                      label: 'Merchant ID',
                      value: summary.id,
                      selectable: true,
                    ),
                    _AdminDetailRow(label: 'Phone', value: summary.phone),
                    _AdminDetailRow(
                      label: 'Created',
                      value: _formatDate(summary.createdAt),
                    ),
                    _AdminDetailRow(
                      label: 'Updated',
                      value: _formatDate(summary.updatedAt),
                    ),
                    _AdminDetailRow(
                      label: 'Last operational update',
                      value: _formatOptionalDate(
                        summary.lastOperationalUpdateAt,
                      ),
                    ),
                  ],
                ),
                _AdminDetailPanel(
                  title: 'Subscription',
                  rows: [
                    _AdminDetailRow(
                      label: 'Plan',
                      value: _formatOptionalText(
                        summary.planName ?? summary.planCode,
                      ),
                    ),
                    _AdminDetailRow(
                      label: 'Plan version',
                      value: _formatOptionalNumber(detail.planVersion),
                    ),
                    _AdminDetailRow(
                      label: 'Pricing version',
                      value: _formatOptionalNumber(detail.pricingVersion),
                    ),
                    _AdminDetailRow(
                      label: 'Trial ends',
                      value: _formatOptionalDate(detail.trialEndsAt),
                    ),
                    _AdminDetailRow(
                      label: 'Grace ends',
                      value: _formatOptionalDate(detail.graceEndsAt),
                    ),
                    _AdminDetailRow(
                      label: 'Period',
                      value:
                          '${_formatOptionalDate(detail.periodStart)} - ${_formatOptionalDate(detail.periodEnd)}',
                    ),
                  ],
                ),
                _AdminDetailPanel(
                  title: 'Operations',
                  rows: [
                    _AdminDetailRow(
                      label: 'Last staff login',
                      value: _formatOptionalDate(detail.lastStaffLoginAt),
                    ),
                    _AdminDetailRow(
                      label: 'Usage events',
                      value: '${detail.usageEventCount}',
                    ),
                    _AdminDetailRow(
                      label: 'Last usage event',
                      value: _formatOptionalDate(detail.lastUsageEventAt),
                    ),
                    _AdminDetailRow(
                      label: 'Usage updated',
                      value: _formatOptionalDate(detail.usageUpdatedAt),
                    ),
                    _AdminDetailRow(
                      label: 'Feature flags',
                      value: '${detail.featureFlagCount}',
                    ),
                    _AdminDetailRow(
                      label: 'Remote config rows',
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
              title: 'Merchant audit trail',
              description:
                  'Tenant-scoped admin changes for the merchant currently under review.',
              emptyTitle: 'No merchant audit events yet',
              emptySubtitle:
                  'Entitlement overrides and future support actions for this merchant will appear here.',
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
          'Merchant self-service',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Owner view for plan status, team access, and sync health for the current merchant scope.',
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
                label: 'Merchant scope',
                value: merchantId ?? '-',
                icon: Icons.storefront_outlined,
              ),
            ),
            _AdminMetricCard(
              metric: _AdminMetric(
                label: 'Sync queue',
                value:
                    '${syncStatus.pendingCount} pending / ${syncStatus.failedCount} failed',
                icon: Icons.sync_rounded,
              ),
            ),
            _AdminMetricCard(
              metric: _AdminMetric(
                label: 'Connectivity',
                value: syncStatus.isOnline ? 'Online' : 'Offline',
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
        loading: () => const _AdminLoadingPanel(title: 'Subscription'),
        error: (error, _) => _AdminErrorPanel(
          title: 'Subscription',
          error: error,
          onRetry: () => ref.invalidate(subscriptionSnapshotProvider),
        ),
        data: (value) {
          final state = value.state;
          final quota = value.whatsappQuota;
          return _AdminDetailPanel(
            title: 'Subscription',
            rows: [
              _AdminDetailRow(
                label: 'Plan',
                value: state?.resolvedPlanName ?? value.plan.displayName,
              ),
              _AdminDetailRow(
                label: 'Status',
                value: value.status.code,
              ),
              _AdminDetailRow(
                label: 'Plan version',
                value: _formatOptionalNumber(state?.planVersion),
              ),
              _AdminDetailRow(
                label: 'Pricing version',
                value: _formatOptionalNumber(state?.pricingVersion),
              ),
              _AdminDetailRow(
                label: 'WhatsApp quota',
                value: quota.limit == null
                    ? '${quota.used} used / unlimited'
                    : '${quota.used}/${quota.limit} used',
              ),
              _AdminDetailRow(
                label: 'Quota resets',
                value: _formatDate(quota.resetAt),
              ),
              _AdminDetailRow(
                label: 'Updated',
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
              'Sync health',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            _AdminDetailRowView(
              row: _AdminDetailRow(label: 'Phase', value: status.phase.name),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Pending',
                value: '${status.pendingCount}',
              ),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Failed',
                value: '${status.failedCount}',
              ),
            ),
            _AdminDetailRowView(
              row: _AdminDetailRow(
                label: 'Last sync',
                value: _formatOptionalDate(status.lastSyncAt),
              ),
            ),
            if (status.lastError != null)
              _AdminDetailRowView(
                row: _AdminDetailRow(label: 'Error', value: status.lastError!),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: status.isSyncing
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).sync(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
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
        loading: () => const _AdminLoadingPanel(title: 'Team access'),
        error: (error, _) => _AdminErrorPanel(
          title: 'Team access',
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
        title: 'No staff members',
        subtitle: 'Invite staff from the mobile owner settings screen.',
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
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Last login')),
            DataColumn(label: Text('Updated')),
          ],
          rows: members.map((member) {
            return DataRow(cells: [
              DataCell(Text(member.phone)),
              DataCell(Text(member.role)),
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
            label: const Text('Retry'),
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
  final _unitController = TextEditingController(text: 'monthly');

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
            'Entitlement override',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Applies one merchant-scoped feature override and records it in the admin audit log.',
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
                  decoration: const InputDecoration(labelText: 'Feature'),
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
                  title: const Text('Enabled'),
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
                  decoration: const InputDecoration(labelText: 'Limit'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _unitController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(labelText: 'Unit'),
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
                label: const Text('Apply override'),
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
                : _unitController.text.trim(),
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
      const SnackBar(content: Text('Entitlement override applied')),
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
          'Operations',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'System-wide tenant, subscription, usage, recovery, and audit health.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        summary.when(
          loading: () => const _AdminLoadingPanel(title: 'Operations summary'),
          error: (error, _) => _AdminErrorPanel(
            title: 'Operations summary',
            error: error,
            onRetry: () => ref.invalidate(adminOperationsSummaryProvider),
          ),
          data: (summary) => _OperationsSummaryGrid(summary: summary),
        ),
        const SizedBox(height: 20),
        const _AdminAuditEventSection(
          title: 'Operations audit log',
          description:
              'Audited admin changes across plans, pricing, features, and tenant overrides.',
          emptyTitle: 'No audit events yet',
          emptySubtitle:
              'Admin mutations will appear here once audited endpoints run.',
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
            label: 'Merchants',
            value: '${summary.merchantCount}',
            icon: Icons.storefront_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Active subscriptions',
            value: '${summary.activeSubscriptionCount}',
            icon: Icons.verified_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Trial subscriptions',
            value: '${summary.trialSubscriptionCount}',
            icon: Icons.hourglass_bottom_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Needs attention',
            value: '${summary.attentionSubscriptionCount}',
            icon: Icons.report_problem_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Active staff',
            value: '${summary.activeStaffCount}',
            icon: Icons.group_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Usage events 24h',
            value: '${summary.usageEvents24h}',
            icon: Icons.bolt_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Open recovery tasks',
            value: '${summary.openRecoveryTaskCount}',
            icon: Icons.assignment_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Visit reports 24h',
            value: '${summary.visitReports24h}',
            icon: Icons.fact_check_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Surveys 24h',
            value: '${summary.surveyResponses24h}',
            icon: Icons.rate_review_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Admin audit 24h',
            value: '${summary.adminAuditEvents24h}',
            icon: Icons.history_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Last admin audit',
            value: _formatOptionalDate(summary.lastAdminAuditAt),
            icon: Icons.manage_history_outlined,
          ),
        ),
        _AdminMetricCard(
          metric: _AdminMetric(
            label: 'Last usage event',
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
            'Plans catalog',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage plan versions and active prices used by merchant onboarding and subscription state.',
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
        title: 'No plans configured',
        subtitle: 'Create a plan version to start building the catalog.',
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
            DataColumn(label: Text('Plan')),
            DataColumn(label: Text('Version')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Active prices')),
            DataColumn(label: Text('Features')),
            DataColumn(label: Text('Updated')),
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
                        plan.name,
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
                  label: plan.isActive ? 'ACTIVE' : 'INACTIVE',
                )),
                DataCell(Text(activePrices.isEmpty ? '-' : activePrices)),
                DataCell(Text(
                  enabledFeatures.isEmpty
                      ? '${plan.features.length} configured'
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
      title: 'Create or update plan',
      description:
          'Upsert one catalog plan version and optionally mark it active.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Plan code'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Display name'),
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
                decoration: const InputDecoration(labelText: 'Version'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
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
            label: const Text('Save plan'),
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
            ArgumentError('Version must be a number.'),
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
      const SnackBar(content: Text('Plan saved')),
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
  final _billingPeriodController = TextEditingController(text: 'monthly');
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
      title: 'Create or update price',
      description: 'Upsert one price version for a plan and currency.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Plan code'),
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
                decoration: const InputDecoration(labelText: 'Pricing version'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _currencyController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Currency'),
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
                decoration: const InputDecoration(labelText: 'Amount'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _billingPeriodController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Billing period'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
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
            label: const Text('Save price'),
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
            ArgumentError('Pricing version and amount must be numbers.'),
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
            billingPeriod: _billingPeriodController.text.trim(),
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
      const SnackBar(content: Text('Price saved')),
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
  final _unitController = TextEditingController(text: 'monthly');
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
      title: 'Create or update feature',
      description: 'Configure one feature gate for a specific plan version.',
      error: _submission.error,
      children: [
        TextField(
          controller: _planCodeController,
          enabled: !isSaving,
          decoration: const InputDecoration(labelText: 'Plan code'),
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
                decoration: const InputDecoration(labelText: 'Plan version'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
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
          decoration: const InputDecoration(labelText: 'Feature'),
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
                decoration: const InputDecoration(labelText: 'Limit'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _unitController,
                enabled: !isSaving,
                decoration: const InputDecoration(labelText: 'Unit'),
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
            label: const Text('Save feature'),
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
            ArgumentError('Plan version and limit must be numbers.'),
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
                : _unitController.text.trim(),
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
      const SnackBar(content: Text('Plan feature saved')),
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
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Actor')),
            DataColumn(label: Text('Merchant')),
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
      'TRIAL' => AppColors.amber,
      'PAST_DUE' || 'CANCELLED' => AppColors.red,
      _ => AppColors.g500,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized,
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
  return '${price.amount} ${price.currency} / ${price.billingPeriod}';
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
              'Admin workbench',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Jump directly into operational areas with live data and audited mutations.',
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
                  label: 'Merchants',
                  icon: Icons.store_mall_directory_outlined,
                  path: '/admin/merchants',
                ),
                _AdminOverviewLinkButton(
                  label: 'Plans',
                  icon: Icons.sell_outlined,
                  path: '/admin/plans',
                ),
                _AdminOverviewLinkButton(
                  label: 'Operations',
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
    label: 'Overview',
    path: '/admin',
    icon: Icons.dashboard_outlined,
  ),
  merchants(
    section: AdminPortalSection.merchants,
    label: 'Merchants',
    path: '/admin/merchants',
    icon: Icons.store_mall_directory_outlined,
  ),
  plans(
    section: AdminPortalSection.plans,
    label: 'Plans and pricing',
    path: '/admin/plans',
    icon: Icons.sell_outlined,
  ),
  operations(
    section: AdminPortalSection.operations,
    label: 'Operations',
    path: '/admin/operations',
    icon: Icons.monitor_heart_outlined,
  ),
  selfService(
    section: AdminPortalSection.selfService,
    label: 'Owner self-service',
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
