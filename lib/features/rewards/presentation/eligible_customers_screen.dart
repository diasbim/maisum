import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/empty_state.dart';
import '../../customers/domain/customer.dart';
import '../domain/reward.dart';
import 'redeem_reward_screen.dart';

class EligibleCustomer {
  const EligibleCustomer({
    required this.customer,
    required this.eligibleRewards,
  });
  final Customer customer;
  final List<Reward> eligibleRewards;
}

final eligibleCustomersProvider =
    FutureProvider.autoDispose<List<EligibleCustomer>>((ref) async {
  final customers = await ref.read(customerRepositoryProvider).getAll();
  final rewards = await ref.read(rewardRepositoryProvider).getRewards();
  final active = rewards.where((r) => r.active).toList();

  if (active.isEmpty) return [];

  return customers
      .map((c) {
        final eligible = active
            .where((r) => r.pointsRequired <= c.totalPoints)
            .toList()
          ..sort((a, b) => a.pointsRequired.compareTo(b.pointsRequired));
        return EligibleCustomer(customer: c, eligibleRewards: eligible);
      })
      .where((e) => e.eligibleRewards.isNotEmpty)
      .toList()
    ..sort((a, b) => b.customer.totalPoints.compareTo(a.customer.totalPoints));
});

class EligibleCustomersScreen extends ConsumerWidget {
  const EligibleCustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibleAsync = ref.watch(eligibleCustomersProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text(AppStrings.clientesElegiveis),
        actions: [
          eligibleAsync.maybeWhen(
            data: (list) => list.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${list.length}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: eligibleAsync.when(
        data: (list) => list.isEmpty
            ? const EmptyState(
                title: AppStrings.nenhumClienteElegivel,
                assetPath: 'assets/images/empty_state.png',
                assetHeight: 220,
              )
            : RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () => ref.refresh(eligibleCustomersProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _EligibleTile(entry: list[i]),
                ),
              ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.secondary)),
        error: (_, __) => Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.tentar),
            onPressed: () => ref.refresh(eligibleCustomersProvider.future),
          ),
        ),
      ),
    );
  }
}

class _EligibleTile extends ConsumerWidget {
  const _EligibleTile({required this.entry});
  final EligibleCustomer entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final customer = entry.customer;
    final initials =
        customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      customer.phone,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${customer.totalPoints} pts',
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: entry.eligibleRewards
                .map(
                  (r) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${r.name} · ${r.pointsRequired} pts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 15),
                label: const Text('WhatsApp'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.g100),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _notify(customer),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.card_giftcard_rounded, size: 15),
                  label: const Text(AppStrings.resgatarBtn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _showRedeemSheet(context, ref, customer),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _notify(Customer customer) {
    final clean = customer.phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('258') ? clean : '258$clean';
    final msg = Uri.encodeComponent(
      'Olá ${customer.name}! Tem pontos suficientes para resgatar uma recompensa '
      'no programa MaisUm. Passe na nossa loja para aproveitar!',
    );
    launchUrl(
      Uri.parse('https://wa.me/$number?text=$msg'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showRedeemSheet(
      BuildContext context, WidgetRef ref, Customer customer) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RedeemRewardSheet(customer: customer),
    ).then((redeemed) {
      if (redeemed == true) {
        ref.invalidate(eligibleCustomersProvider);
      }
    });
  }
}
