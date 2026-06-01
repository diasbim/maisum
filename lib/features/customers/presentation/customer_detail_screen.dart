import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../domain/customer.dart';
import '../domain/customer_whatsapp_message.dart';
import '../../rewards/presentation/redeem_reward_screen.dart';
import '../../rewards/presentation/rewards_controller.dart';
import '../../rewards/domain/reward.dart';
import '../../rewards/domain/reward_progress.dart';
import '../../rewards/presentation/reward_progress_provider.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/new_sale_screen.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/domain/usage_metrics.dart';
import 'customers_controller.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _historyKey = GlobalKey();

  void _handleBackPressed() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/customers');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHistory() {
    final context = _historyKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerDetailProvider(widget.id));
    final salesAsync = ref.watch(customerSalesProvider(widget.id));
    final rewardProgressAsync = ref.watch(rewardProgressProvider(widget.id));

    final isCompact = MediaQuery.of(context).size.width < 360;
    // Keep enough room for identity, status, and metric cards in the hero section.
    final expandedHeight = isCompact ? 400.0 : 360.0;

    final customer = customerAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      bottomNavigationBar: customer == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _BottomCtaButton(
                label: AppStrings.novaVenda,
                onPressed: () => context.push(
                  '/new-sale',
                  extra: NewSaleArgs(preselectedCustomerId: customer.id),
                ),
              ),
            ),
      body: customerAsync.when(
        data: (customer) {
          if (customer == null) {
            return const Scaffold(
              body: EmptyState(title: AppStrings.clienteNaoEncontrado),
            );
          }

          final sales = salesAsync.valueOrNull ?? const <Sale>[];
          final initials =
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?';
          final isActive = _isActiveCustomer(customer, sales);
          final statusLabel =
              isActive ? AppStrings.clienteAtivo : AppStrings.clienteInativo;
          final statusColor = isActive ? AppColors.green : AppColors.amber;
          final phoneLabel = customer.phone.isEmpty
              ? AppStrings.phoneRequired
              : MozPhoneUtils.maskForDisplay(customer.phone);
          final approxValue = _formatApproxMzn(customer.totalPoints);
          final totalSpent = sales.fold<double>(
            0,
            (sum, sale) => sum + sale.amount,
          );
          final lastActivity = _lastActivity(customer, sales);
          final bottomPadding = MediaQuery.of(context).padding.bottom + 120;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: expandedHeight,
                pinned: true,
                backgroundColor: AppColors.primary,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _handleBackPressed,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Ver marcações',
                    onPressed: () => context.push('/appointments'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                    onPressed: () => _showEditSheet(context, ref, customer),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primaryDarker, AppColors.primary],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          isCompact ? 44 : 56,
                          20,
                          isCompact ? 18 : 22,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.secondary.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        phoneLabel,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.65,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _StatusChip(
                                        label: statusLabel,
                                        color: statusColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _PointsSummaryCard(
                              points: customer.totalPoints,
                              approxValue: approxValue,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _HeroMetricTile(
                                    label: 'Total em vendas',
                                    value:
                                        '${totalSpent.toStringAsFixed(0)} ${AppStrings.moedaMzn}',
                                    icon: Icons.payments_rounded,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _HeroMetricTile(
                                    label: 'Ultima atividade',
                                    value: _formatDayMonthYear(lastActivity),
                                    icon: Icons.schedule_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.primary,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acoes rapidas',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final itemWidth = (constraints.maxWidth - 12) / 2;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.start,
                              children: [
                                _ActionShortcut(
                                  icon: Icons.add_rounded,
                                  label: AppStrings.adicionarPontos,
                                  isPrimary: true,
                                  expand: false,
                                  width: itemWidth,
                                  onTap: () => context.push(
                                    '/new-sale',
                                    extra: NewSaleArgs(
                                      preselectedCustomerId: customer.id,
                                    ),
                                  ),
                                ),
                                _ActionShortcut(
                                  icon: Icons.chat_rounded,
                                  label: AppStrings.enviarWhatsApp,
                                  iconColor: const Color(0xFF27C26A),
                                  expand: false,
                                  width: itemWidth,
                                  onTap: () =>
                                      _openWhatsApp(context, ref, customer),
                                ),
                                _ActionShortcut(
                                  icon: Icons.receipt_long_rounded,
                                  label: AppStrings.verHistorico,
                                  expand: false,
                                  width: itemWidth,
                                  onTap: _scrollToHistory,
                                ),
                                _ActionShortcut(
                                  icon: Icons.card_giftcard_rounded,
                                  label: AppStrings.resgatarRecompensa,
                                  expand: false,
                                  width: itemWidth,
                                  onTap: () =>
                                      _showRedeemSheet(context, ref, customer),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        rewardProgressAsync.when(
                          data: (progress) => _RewardProgressPanel(
                            progress: progress,
                            onRedeem: progress.unlockedRewardName != null
                                ? () => _showRedeemSheet(context, ref, customer)
                                : null,
                          ),
                          loading: () => const SizedBox(height: 16),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                key: _historyKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        AppStrings.historicoCompras,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _scrollToHistory,
                        child: const Text(AppStrings.verTudo),
                      ),
                    ],
                  ),
                ),
              ),
              salesAsync.when(
                data: (sales) => sales.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            bottomPadding,
                          ),
                          child: const EmptyState(title: AppStrings.semVendas),
                        ),
                      )
                    : SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SaleTimelineItem(
                                sale: sales[i],
                                isLast: i == sales.length - 1,
                              ),
                            ),
                            childCount: sales.length,
                          ),
                        ),
                      ),
                loading: () => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomPadding),
                    child: const Center(
                      heightFactor: 3,
                      child: CircularProgressIndicator(
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ),
                error: (e, __) => SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
                    child: ErrorState(
                      error: e,
                      onRetry: () =>
                          ref.invalidate(customerSalesProvider(widget.id)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.secondary),
          ),
        ),
        error: (e, __) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorState(
                error: e,
                onRetry: () =>
                    ref.invalidate(customerDetailProvider(widget.id)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Customer customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _EditCustomerSheet(customer: customer, customerId: widget.id),
    );
  }

  void _showRedeemSheet(BuildContext context, WidgetRef ref, customer) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RedeemRewardSheet(customer: customer),
    ).then((redeemed) {
      if (redeemed == true && context.mounted) {
        ref.invalidate(customerDetailProvider(widget.id));
        AppFeedback.showSuccessToast(
          context,
          message: AppStrings.resgateRegistado,
        );
      }
    });
  }

  Future<void> _openWhatsApp(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final connectivity = ref.read(connectivityServiceProvider);
    final gate = ref.read(featureGateProvider);
    final decision = await gate.check(
      featureKey: FeatureKeys.whatsappAutomation,
      metricKey: UsageMetrics.whatsappMessages,
    );
    if (!decision.allowed) {
      if (context.mounted) {
        AppFeedback.showMessage(
          context,
          message: AppStrings.funcaoIndisponivel,
        );
      }
      return;
    }
    if (decision.softLimited && context.mounted) {
      AppFeedback.showMessage(
        context,
        message: AppStrings.limiteSoftAviso,
      );
    }

    List<Sale> sales;
    List<Reward> rewards;
    try {
      sales = await ref.read(customerSalesProvider(widget.id).future);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'customer_detail_sales');
      sales = const <Sale>[];
    }
    try {
      rewards = await ref.read(rewardsControllerProvider.future);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'customer_detail_rewards');
      rewards = const <Reward>[];
    }

    final draft = buildCustomerWhatsAppDraft(
      customer: customer,
      sales: sales,
      rewards: rewards,
    );
    final clean = customer.phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('258') ? clean : '258$clean';
    final url = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(draft.message)}',
    );
    if (!connectivity.isOnline) {
      await ref.read(notificationQueueServiceProvider).enqueueWhatsApp(
            phone: number,
            message: draft.message,
            source: 'customer_detail',
          );
      try {
        await ref.read(analyticsServiceProvider).record(
          eventType: 'whatsapp_sent',
          source: 'whatsapp',
          properties: {
            'queued': true,
            'source': 'customer_detail',
            'message_type': draft.type.name,
          },
        );
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'whatsapp_queued_analytics');
      }
      if (context.mounted) {
        AppFeedback.showSuccessToast(
          context,
          message: AppStrings.whatsappQueued,
        );
      }
      return;
    }
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      AppFeedback.showMessage(
        context,
        message: AppStrings.erroGenerico,
        isError: true,
      );
      return;
    }
    if (launched) {
      try {
        await ref.read(usageTrackerProvider).record(
          metricKey: UsageMetrics.whatsappMessages,
          source: 'whatsapp',
          metadata: {'message_type': draft.type.name},
        );
        await ref.read(analyticsServiceProvider).record(
          eventType: 'whatsapp_sent',
          source: 'whatsapp',
          properties: {
            'queued': false,
            'source': 'customer_detail',
            'message_type': draft.type.name,
          },
        );
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'whatsapp_sent_analytics');
      }
    }
  }

  DateTime _lastActivity(Customer customer, List<Sale>? sales) {
    if (sales != null && sales.isNotEmpty) {
      return sales
          .map((sale) => sale.createdAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return customer.updatedAt ?? customer.createdAt;
  }

  bool _isActiveCustomer(Customer customer, List<Sale>? sales) {
    final lastActivity = _lastActivity(customer, sales);
    final days = DateTime.now().difference(lastActivity).inDays;
    return days <= 30;
  }

  String _formatApproxMzn(int points) {
    final approxValue = points * AppConstants.pointsPerMzn;
    return '${AppStrings.aproxPrefix} $approxValue ${AppStrings.moedaMzn} '
        '${AppStrings.comprasSuffix}';
  }

  String _formatDayMonthYear(DateTime value) {
    final monthNames = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    final day = value.day.toString().padLeft(2, '0');
    return '$day ${monthNames[value.month - 1]} ${value.year}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointsSummaryCard extends StatelessWidget {
  const _PointsSummaryCard({required this.points, required this.approxValue});

  final int points;
  final String approxValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.saldoPontos,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$points ${AppStrings.pontosAbrev}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            approxValue,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetricTile extends StatelessWidget {
  const _HeroMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppColors.secondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class _ActionShortcut extends StatelessWidget {
  const _ActionShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.expand = true,
    this.width,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool expand;
  final double? width;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isPrimary ? Colors.white : AppColors.primary,
          fontWeight: FontWeight.w700,
        );

    final shortcut = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: isPrimary
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  )
                : null,
            color: isPrimary ? null : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isPrimary ? Colors.transparent : AppColors.g100,
            ),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? AppColors.primary.withValues(alpha: 0.24)
                    : AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? AppColors.secondary.withValues(alpha: 0.18)
                      : AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor ??
                      (isPrimary
                          ? AppColors.secondary
                          : AppColors.secondaryDark),
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ],
          ),
        ),
      ),
    );

    if (expand) {
      return Expanded(child: shortcut);
    }
    if (width != null) {
      return SizedBox(width: width, child: shortcut);
    }
    return shortcut;
  }
}

class _BottomCtaButton extends StatelessWidget {
  const _BottomCtaButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.secondary, AppColors.secondaryDark],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardProgressPanel extends StatelessWidget {
  const _RewardProgressPanel({required this.progress, this.onRedeem});

  final RewardProgress progress;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (progress.targetPoints == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.g100),
        ),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.semRecompensasAtivas,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasNext = progress.nextRewardName != null;
    final rewardName = progress.nextRewardName ?? progress.unlockedRewardName;
    final target = progress.targetPoints ?? 0;
    final displayTarget = target > 0 ? target : progress.currentPoints;
    final unclampedCurrent =
        !hasNext && displayTarget > 0 ? displayTarget : progress.currentPoints;
    final displayCurrent = displayTarget > 0
        ? unclampedCurrent.clamp(0, displayTarget).toInt()
        : unclampedCurrent;
    final statusText = hasNext
        ? '${AppStrings.faltam} ${progress.pointsRemaining} '
            '${AppStrings.pontosAbrev} ${AppStrings.para} $rewardName'
        : '${AppStrings.recompensaPronta} $rewardName';
    final progressValue = progress.progressFraction.clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: AppColors.secondaryDark,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.progressoProximaRecompensa,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: AppColors.g100,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$displayCurrent / $displayTarget ${AppStrings.pontosAbrev}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (onRedeem != null)
                      TextButton(
                        onPressed: onRedeem,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                        child: const Text(AppStrings.resgatarRecompensa),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTimelineItem extends StatelessWidget {
  const _SaleTimelineItem({required this.sale, required this.isLast});

  final Sale sale;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.secondary, width: 1.4),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.add,
                size: 16,
                color: AppColors.secondary,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 72,
                margin: const EdgeInsets.only(top: 2),
                color: AppColors.g100,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(child: _SaleCard(sale: sale)),
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale.amount.toStringAsFixed(0)} ${AppStrings.moedaMzn}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  PtDateFormat.dayMonthYearTime(sale.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${sale.points} ${AppStrings.pontosAbrev}',
              style: const TextStyle(
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCustomerSheet extends ConsumerStatefulWidget {
  const _EditCustomerSheet({required this.customer, required this.customerId});
  final Customer customer;
  final String customerId;

  @override
  ConsumerState<_EditCustomerSheet> createState() => _EditCustomerSheetState();
}

class _EditCustomerSheetState extends ConsumerState<_EditCustomerSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.customer.name);
    _phoneCtrl = TextEditingController(text: widget.customer.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: AppStrings.nameRequired,
        isError: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(customersControllerProvider.notifier)
          .updateCustomer(widget.customerId, name: name, phone: phone);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: e.toString(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.g300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(AppStrings.editarCliente, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: AppStrings.nome,
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: AppStrings.phoneNumber,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: AppStrings.guardar,
            onPressed: _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}
