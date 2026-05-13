import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/feature_keys.dart';
import '../domain/plan_catalog.dart';
import '../domain/subscription_snapshot.dart';

class SubscriptionAdminScreen extends ConsumerWidget {
  const SubscriptionAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(subscriptionSnapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.subscricaoAdmin)),
      body: snapshot.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (data) => _SubscriptionAdminBody(snapshot: data),
      ),
    );
  }
}

class _SubscriptionAdminBody extends StatelessWidget {
  const _SubscriptionAdminBody({required this.snapshot});

  final SubscriptionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final planDefinition = PlanCatalog.forPlan(snapshot.plan);
    final state = snapshot.state;
    final quota = snapshot.whatsappQuota;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SectionCard(
          title: AppStrings.planoAtual,
          children: [
            _InfoRow(
              label: AppStrings.planoAtual,
              value: planDefinition.displayName,
            ),
            _InfoRow(
              label: AppStrings.estadoSubscricao,
              value: snapshot.status.displayName,
            ),
            if (state?.periodStart != null && state?.periodEnd != null)
              _InfoRow(
                label: AppStrings.periodo,
                value:
                    '${_formatDate(state!.periodStart!)} - ${_formatDate(state.periodEnd!)}',
              ),
            if (state?.trialEndsAt != null)
              _InfoRow(
                label: AppStrings.testeAte,
                value: _formatDate(state!.trialEndsAt!),
              ),
            if (state?.graceEndsAt != null)
              _InfoRow(
                label: AppStrings.graciaAte,
                value: _formatDate(state!.graceEndsAt!),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: AppStrings.limites,
          children: [
            _QuotaTile(
              title: AppStrings.quotaWhatsApp,
              used: quota.used,
              limit: quota.limit,
              remaining: quota.remaining,
              resetAt: quota.resetAt,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: AppStrings.funcionalidades,
          children: FeatureKeys.all
              .map((featureKey) => _FeatureRow(
                    featureKey: featureKey,
                    enabled: _isFeatureEnabled(featureKey, snapshot),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: AppStrings.flagsRemotas,
          children: snapshot.flags.isEmpty
              ? [const _MutedRow('Sem flags remotas')]
              : snapshot.flags
                  .map(
                    (flag) => _InfoRow(
                      label: flag.flagKey,
                      value: flag.isEnabled ? 'On' : 'Off',
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  bool _isFeatureEnabled(String featureKey, SubscriptionSnapshot snapshot) {
    final explicit = snapshot.entitlements
        .where((entitlement) => entitlement.featureKey == featureKey)
        .toList();
    if (explicit.isNotEmpty) {
      return explicit.first.isEnabled;
    }
    final plan = PlanCatalog.forPlan(snapshot.plan);
    return plan.allowsFeature(featureKey);
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.featureKey, required this.enabled});

  final String featureKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: enabled ? AppColors.green : AppColors.g500,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              featureKey.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotaTile extends StatelessWidget {
  const _QuotaTile({
    required this.title,
    required this.used,
    required this.limit,
    required this.remaining,
    required this.resetAt,
  });

  final String title;
  final int used;
  final int? limit;
  final int? remaining;
  final DateTime resetAt;

  @override
  Widget build(BuildContext context) {
    final limitLabel = limit == null ? 'Ilimitado' : '$limit';
    final remainingLabel = remaining == null ? 'Ilimitado' : '$remaining';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _MetricPill(label: AppStrings.quotaUsadas, value: '$used'),
            const SizedBox(width: 8),
            _MetricPill(label: 'Limite', value: limitLabel),
            const SizedBox(width: 8),
            _MetricPill(label: AppStrings.quotaRestante, value: remainingLabel),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${AppStrings.quotaRenova}: ${_formatDate(resetAt)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
          ),
        ],
      ),
    );
  }
}

class _MutedRow extends StatelessWidget {
  const _MutedRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: AppColors.onSurfaceVariant),
    );
  }
}
