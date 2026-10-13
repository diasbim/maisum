import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/affiliate_repository.dart';
import '../domain/merchant_affiliate_dtos.dart';
import '../providers/affiliate_providers.dart';
import '../services/affiliate_share_message.dart';
import 'widgets/affiliate_widgets.dart';

/// One affiliate, everything about them, and the two decisions an owner makes.
///
/// The numbers are read from the metrics endpoint rather than counted here.
/// Counting a list the server truncated would produce a smaller, confident and
/// wrong number, which is exactly the failure this screen is meant to avoid.
class AffiliateDetailScreen extends ConsumerWidget {
  const AffiliateDetailScreen({super.key, required this.affiliateId});

  final String affiliateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(affiliateDetailProvider(affiliateId));
    final isOwner = ref.watch(isOwnerUserProvider).valueOrNull ?? false;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const MaisUmAppBar(
        title: 'Afiliado',
        fallbackLocation: '/affiliates',
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(affiliateDetailProvider(affiliateId)),
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
                message: 'Sem ligação. Pode consultar, mas alterar o afiliado '
                    'ou o código só é possível online.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AffiliateAsyncView<AffiliateDetailSnapshot>(
              value: detailAsync,
              loadingLabel: 'A carregar afiliado',
              skeletonLines: 4,
              onRetry: () =>
                  ref.invalidate(affiliateDetailProvider(affiliateId)),
              builder: (context, snapshot) => _DetailBody(
                snapshot: snapshot,
                isOwner: isOwner,
                online: online,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.snapshot,
    required this.isOwner,
    required this.online,
  });

  final AffiliateDetailSnapshot snapshot;
  final bool isOwner;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affiliate = snapshot.affiliate;
    final metrics = snapshot.metrics;
    final code = affiliate.code;
    final businessName =
        ref.watch(authControllerProvider).valueOrNull?.merchantName ?? '';
    final draft = isOwner
        ? buildAffiliateShareDraft(
            affiliate: affiliate,
            businessName: businessName,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.truncated) ...[
          const AffiliateTruncatedBanner(
            detail: 'Alguns números deste afiliado estão incompletos porque há '
                'mais registos do que conseguimos ler de uma vez.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        MaisUmSurface(
          radius: AppRadius.lg,
          padding: const EdgeInsets.all(AppSpacing.lg),
          animationDuration: Duration.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                affiliate.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                affiliatePhoneForRole(
                  isOwner: isOwner,
                  phone: affiliate.phone,
                  phoneLast4: affiliate.phoneLast4,
                ),
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              AffiliateStatusChip(
                label: affiliateStatusLabel(affiliate),
                icon: affiliate.isLinkActive
                    ? Icons.check_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                color: affiliate.isLinkActive
                    ? AppColors.success
                    : AppColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _CodeCard(
          code: code,
          canShare: draft != null,
          onShare: draft == null ? null : () => _share(context, draft),
          onEdit: isOwner && online && code != null
              ? () => context.push('/affiliates/${affiliate.id}/code')
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AffiliateMetricTile(
                label: 'Clientes indicados',
                value: '${metrics.confirmedAttributions}',
                icon: Icons.group_add_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AffiliateMetricTile(
                label: 'Clientes que voltaram',
                value: '${metrics.returnedCustomers}',
                icon: Icons.repeat_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AffiliateMetricTile(
                label: 'Recompensas pendentes',
                value: '${metrics.pendingRewardCount}',
                hint: '${metrics.pendingRewardPoints} pontos',
                icon: Icons.pending_actions_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AffiliateMetricTile(
                label: 'Recompensas aprovadas',
                value: '${metrics.approvedRewardCount}',
                hint: '${metrics.approvedRewardPoints} pontos',
                icon: Icons.verified_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        MaisUmButton(
          label: 'Ver recompensas',
          leadingIcon: Icons.card_giftcard_rounded,
          variant: MaisUmButtonVariant.outlined,
          foregroundColor: AppColors.primary,
          onPressed: () => context.push(
            '/affiliates/rewards?affiliateId=${affiliate.id}',
          ),
          animationDuration: Duration.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        _LinkStateButton(
          affiliate: affiliate,
          enabled: isOwner && online,
        ),
        if (!isOwner) ...[
          const SizedBox(height: AppSpacing.md),
          const AffiliateOfflineNotice(
            message: 'Só o responsável do negócio pode ativar, desativar ou '
                'alterar o código deste afiliado.',
          ),
        ],
      ],
    );
  }

  Future<void> _share(BuildContext context, AffiliateShareDraft draft) async {
    final launched = await launchUrl(
      draft.uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      AppFeedback.showMessage(
        context,
        message: 'Não foi possível abrir o WhatsApp.',
        isError: true,
      );
    }
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.canShare,
    required this.onShare,
    required this.onEdit,
  });

  final MerchantAffiliateCode? code;
  final bool canShare;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final value = code;
    return MaisUmSurface(
      key: const Key('affiliate-code-card'),
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      animationDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Código',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            value?.code.toUpperCase() ?? 'Sem código',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: AppColors.onSurface,
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              [
                describeReferralBenefit(
                        value.benefitType, value.benefitValue) ??
                    'benefício por definir',
                value.isUnlimited
                    ? 'sem limite de usos'
                    : 'restam ${value.remainingUses} usos',
                value.firstVisitOnly
                    ? 'só na primeira visita'
                    : 'também para clientes atuais',
              ].join(' · '),
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          MaisUmButton(
            key: const Key('affiliate-detail-share-button'),
            label: 'Partilhar código',
            leadingIcon: Icons.share_rounded,
            onPressed: canShare ? onShare : null,
            animationDuration: Duration.zero,
          ),
          if (!canShare) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'A partilha fica desativada enquanto o código não estiver ativo '
              'e confirmado pelo sistema.',
              style: TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          MaisUmButton(
            key: const Key('affiliate-code-settings-button'),
            label: 'Definições do código',
            leadingIcon: Icons.tune_rounded,
            variant: MaisUmButtonVariant.outlined,
            foregroundColor: AppColors.primary,
            onPressed: onEdit,
            animationDuration: Duration.zero,
          ),
        ],
      ),
    );
  }
}

class _LinkStateButton extends ConsumerStatefulWidget {
  const _LinkStateButton({required this.affiliate, required this.enabled});

  final MerchantAffiliate affiliate;
  final bool enabled;

  @override
  ConsumerState<_LinkStateButton> createState() => _LinkStateButtonState();
}

class _LinkStateButtonState extends ConsumerState<_LinkStateButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final activate = !widget.affiliate.isLinkActive;
    setState(() => _busy = true);
    try {
      await ref
          .read(affiliateAdminControllerProvider.notifier)
          .setAffiliateActive(
            affiliateId: widget.affiliate.id,
            active: activate,
          );
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        message: activate ? 'Afiliado reativado' : 'Afiliado desativado',
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: AppErrorMapper.describe(error).message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.affiliate.isLinkActive;
    return MaisUmButton(
      key: const Key('affiliate-link-toggle'),
      label: active ? 'Desativar afiliado' : 'Reativar afiliado',
      leadingIcon: active
          ? Icons.pause_circle_outline_rounded
          : Icons.play_circle_outline,
      variant:
          active ? MaisUmButtonVariant.danger : MaisUmButtonVariant.outlined,
      foregroundColor: active ? null : AppColors.primary,
      isLoading: _busy,
      onPressed: widget.enabled && !_busy ? _toggle : null,
      animationDuration: Duration.zero,
    );
  }
}
