import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pt_date_format.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/customer.dart';
import '../domain/customer_whatsapp_message.dart';
import '../../rewards/presentation/redeem_reward_screen.dart';
import '../../rewards/presentation/rewards_controller.dart';
import '../../rewards/domain/reward.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/new_sale_screen.dart';
import 'customers_controller.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(id));
    final salesAsync = ref.watch(customerSalesProvider(id));

    final customer = customerAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      floatingActionButton: customer != null
          ? FloatingActionButton.extended(
              heroTag: 'quick_sale_fab',
              backgroundColor: AppColors.secondary,
              foregroundColor: AppColors.primary,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text(AppStrings.novaVenda),
              onPressed: () => context.push(
                '/new-sale',
                extra: NewSaleArgs(preselectedCustomerId: customer.id),
              ),
            )
          : null,
      body: customerAsync.when(
        data: (customer) {
          if (customer == null) {
            return const Scaffold(
                body: EmptyState(title: 'Cliente nao encontrado'));
          }
          final initials =
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?';

          return CustomScrollView(
            slivers: [
              // ── Navy header ──────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: AppColors.primary,
                elevation: 0,
                scrolledUnderElevation: 0,
                actions: [
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
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Avatar
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Name + phone
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    customer.phone,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.6),
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            // WhatsApp button
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 20),
                              tooltip: AppStrings.enviarWhatsApp,
                              onPressed: () =>
                                  _openWhatsApp(context, ref, customer),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Points badge ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.primary,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.secondaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.secondary
                                          .withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const BrandMark(size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${customer.totalPoints} pts',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                AppStrings.historicoVendas,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                        color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            icon: const BrandMark(size: 16),
                            label: const Text(AppStrings.resgatarRecompensa),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              backgroundColor: AppColors.secondaryLight,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () =>
                                _showRedeemSheet(context, ref, customer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Sales list ───────────────────────────────────────────────
              salesAsync.when(
                data: (sales) => sales.isEmpty
                    ? const SliverFillRemaining(
                        child: EmptyState(
                          title: AppStrings.semVendas,
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SaleTile(sale: sales[i]),
                            ),
                            childCount: sales.length,
                          ),
                        ),
                      ),
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                      heightFactor: 3,
                      child: CircularProgressIndicator(
                          color: AppColors.secondary)),
                ),
                error: (_, __) =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          );
        },
        loading: () => const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: AppColors.secondary))),
        error: (e, _) => Scaffold(body: Center(child: Text(e.toString()))),
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
      builder: (_) => _EditCustomerSheet(customer: customer, customerId: id),
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
        ref.invalidate(customerDetailProvider(id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.resgateRegistado)),
        );
      }
    });
  }

  Future<void> _openWhatsApp(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    List<Sale> sales;
    List<Reward> rewards;
    try {
      sales = await ref.read(customerSalesProvider(id).future);
    } catch (_) {
      sales = const <Sale>[];
    }
    try {
      rewards = await ref.read(rewardsControllerProvider.future);
    } catch (_) {
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
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.erroGenerico)),
      );
    }
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});
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
            child: const Icon(Icons.receipt_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale.amount.toStringAsFixed(0)} MZN',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.onSurface),
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
              '+${sale.points} pts',
              style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.nameRequired)),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
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
                  borderRadius: BorderRadius.circular(2)),
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
