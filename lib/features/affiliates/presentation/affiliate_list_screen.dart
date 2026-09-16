import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/affiliate_repository.dart';
import '../domain/affiliate.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../providers/affiliate_providers.dart';
import 'widgets/affiliate_widgets.dart';

/// Who brings this business customers, and what is owed to them.
///
/// The list is the entry point for everything else in the feature, so it is
/// deliberately the only screen that shows all four facts at once — state,
/// customers brought, rewards waiting, last sign of life — and every other
/// screen is reached from a card rather than from a menu.
class AffiliateListScreen extends ConsumerStatefulWidget {
  const AffiliateListScreen({super.key});

  @override
  ConsumerState<AffiliateListScreen> createState() =>
      _AffiliateListScreenState();
}

class _AffiliateListScreenState extends ConsumerState<AffiliateListScreen> {
  AffiliateListFilter _filter = AffiliateListFilter.all;

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(affiliateListProvider(_filter));
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? false;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: MaisUmAppBar(
        title: 'Afiliados',
        actions: [
          IconButton(
            tooltip: 'Métricas',
            onPressed: () => context.push('/affiliates/metrics'),
            icon: const Icon(Icons.insights_rounded),
          ),
          IconButton(
            tooltip: 'Recompensas',
            onPressed: () => context.push('/affiliates/rewards'),
            icon: const Icon(Icons.card_giftcard_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: MaisUmButton(
          key: const Key('affiliate-add-button'),
          label: 'Adicionar afiliado',
          leadingIcon: Icons.person_add_alt_1_rounded,
          // Only the owner may create one, and the server enforces it. The
          // button stays visible so a staff member can see the feature exists
          // and ask, rather than wondering why the screen looks broken.
          onPressed:
              isOwner && online ? () => context.push('/affiliates/new') : null,
          animationDuration: Duration.zero,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(affiliateListProvider(_filter)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (!online) ...[
              const AffiliateOfflineNotice(
                message: 'Sem ligação. Vê os dados já carregados, mas não é '
                    'possível adicionar nem alterar afiliados.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _FilterRow(
              selected: _filter,
              onChanged: (filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: AppSpacing.lg),
            AffiliateAsyncView<AffiliateListView>(
              value: listAsync,
              loadingLabel: 'A carregar afiliados',
              onRetry: () => ref.invalidate(affiliateListProvider(_filter)),
              builder: (context, view) {
                if (view.isEmpty) {
                  return _EmptyAffiliates(
                    canAdd: isOwner && online,
                    onAdd: () => context.push('/affiliates/new'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (view.truncated) ...[
                      const AffiliateTruncatedBanner(
                        detail: 'A lista está incompleta: há mais afiliados do '
                            'que conseguimos mostrar de uma vez.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (view.rewardsUnavailable) ...[
                      const AffiliateTruncatedBanner(
                        detail: 'Não foi possível contar todas as recompensas '
                            'pendentes. A contagem fica por confirmar.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    for (final item in view.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: AffiliateCard(
                          item: item,
                          isOwner: isOwner,
                          onTap: () => context.push(
                            '/affiliates/${item.affiliate.id}',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onChanged});

  final AffiliateListFilter selected;
  final ValueChanged<AffiliateListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final filter in AffiliateListFilter.values)
          ChoiceChip(
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) => onChanged(filter),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
      ],
    );
  }
}

class _EmptyAffiliates extends StatelessWidget {
  const _EmptyAffiliates({required this.canAdd, required this.onAdd});

  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return MaisUmSurface(
      key: const Key('affiliate-empty-state'),
      width: double.infinity,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.xl),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.handshake_outlined, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Ainda não tem afiliados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Um afiliado recebe um código para partilhar. Quando alguém novo '
            'usa esse código numa compra, o cliente ganha um benefício e o '
            'afiliado ganha uma recompensa.',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          MaisUmButton(
            label: 'Adicionar afiliado',
            leadingIcon: Icons.person_add_alt_1_rounded,
            variant: MaisUmButtonVariant.outlined,
            foregroundColor: AppColors.primary,
            onPressed: canAdd ? onAdd : null,
            animationDuration: Duration.zero,
          ),
        ],
      ),
    );
  }
}

class AffiliateCard extends StatelessWidget {
  const AffiliateCard({
    super.key,
    required this.item,
    required this.isOwner,
    required this.onTap,
  });

  final AffiliateListItem item;
  final bool isOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final affiliate = item.affiliate;
    final status = affiliateStatusLabel(affiliate);
    final pendingRewards = item.pendingRewards;
    final pendingRewardsLabel =
        pendingRewards == null ? 'por confirmar' : '$pendingRewards';
    final phone = affiliatePhoneForRole(
      isOwner: isOwner,
      phone: affiliate.phone,
      phoneLast4: affiliate.phoneLast4,
    );
    final lastActivity = affiliate.lastActivityAt;

    return MaisUmSurface(
      onTap: onTap,
      semanticButton: true,
      semanticLabel: 'Afiliado ${affiliate.name}. '
          'Estado: $status. '
          'Clientes indicados: ${item.referredCustomers}. '
          'Recompensas pendentes: $pendingRewardsLabel. '
          'Última atividade: ${_activityLabel(lastActivity)}.',
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                affiliate.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              _statusChip(affiliate),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            phone,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _CardFact(
                icon: Icons.group_add_rounded,
                label: 'Clientes indicados',
                value: '${item.referredCustomers}',
              ),
              _CardFact(
                icon: Icons.pending_actions_rounded,
                label: 'Recompensas pendentes',
                value: pendingRewards == null ? '—' : '$pendingRewards',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Última atividade: ${_activityLabel(lastActivity)}',
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(MerchantAffiliate affiliate) {
    if (affiliate.status == AffiliateStatus.suspended) {
      return const AffiliateStatusChip(
        label: 'Suspenso',
        icon: Icons.block_rounded,
        color: AppColors.error,
      );
    }
    if (!affiliate.isLinkActive ||
        affiliate.status == AffiliateStatus.inactive) {
      return const AffiliateStatusChip(
        label: 'Inativo',
        icon: Icons.pause_circle_outline_rounded,
        color: AppColors.onSurfaceVariant,
      );
    }
    return const AffiliateStatusChip(
      label: 'Ativo',
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.success,
    );
  }
}

String _activityLabel(DateTime? value) {
  if (value == null) return 'sem registo';
  return PtDateFormat.dayMonthYearTime(value);
}

class _CardFact extends StatelessWidget {
  const _CardFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Text.rich rather than two Texts in a Row: at a large text scale the label
    // has to be able to wrap under itself, and a Row of fixed Texts can only
    // overflow.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: AppColors.secondaryForeground),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
