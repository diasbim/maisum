import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/quick_amount_button.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customers_controller.dart';
import 'sale_controller.dart';
import 'sale_success_screen.dart';

class NewSaleArgs {
  const NewSaleArgs({this.preselectedCustomerId, this.prefilledAmount});
  final String? preselectedCustomerId;
  final double? prefilledAmount;
}

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key, this.args});
  final NewSaleArgs? args;

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _phoneCtrl = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _amountCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _isSubmitting = false;
  Customer? _selectedCustomer;
  int? _quickAmount;
  int? _lastAmount;
  List<Customer> _searchResults = [];

  void _handleBackPressed() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/dashboard');
  }

  @override
  void initState() {
    super.initState();
    final preselectedId = widget.args?.preselectedCustomerId;
    if (preselectedId != null) {
      _loadPreselectedCustomer(preselectedId);
    }
    final prefilledAmount = widget.args?.prefilledAmount;
    if (prefilledAmount != null && prefilledAmount > 0) {
      _amountCtrl.text = prefilledAmount.toStringAsFixed(0);
    }
    _loadLastAmount();
  }

  Future<void> _loadPreselectedCustomer(String id) async {
    final customer = await ref.read(customerDaoProvider).getById(id);
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
        _phoneCtrl.text = customer.phone;
      });
    }
  }

  Future<void> _loadLastAmount() async {
    final lastAmount = await ref.read(saleDaoProvider).getLastSaleAmount();
    if (!mounted) return;
    setState(() => _lastAmount = lastAmount);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _phoneCtrl.dispose();
    _phoneFocusNode.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount {
    if (_quickAmount != null) return _quickAmount!.toDouble();
    return double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
  }

  int get _points => (_amount / AppConstants.pointsPerMzn).floor();

  Future<void> _onPhoneChanged(String query) async {
    final trimmed = query.trim();
    _searchDebounce?.cancel();

    if (trimmed.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final results =
          await ref.read(customerRepositoryProvider).searchForSale(trimmed);
      if (!mounted || _phoneCtrl.text.trim() != trimmed) {
        return;
      }
      setState(() {
        _searchResults = results;
      });
    });
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _phoneCtrl.text = c.phone;
      _searchResults = [];
    });
  }

  Future<void> _createAndSelectCustomer() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    try {
      final customer = await ref
          .read(customersControllerProvider.notifier)
          .createCustomer(name: phone, phone: phone);
      _selectCustomer(customer);
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: AppStrings.customerCreatedSuccess,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final info = AppErrorMapper.describe(e);
      AppFeedback.showMessage(context, message: info.message);
    }
  }

  Future<void> _confirmSale() async {
    if (_isSubmitting) return;

    if (_selectedCustomer == null) {
      AppFeedback.showMessage(
        context,
        message: 'Selecione um cliente primeiro.',
      );
      return;
    }
    if (_amount < 1) {
      AppFeedback.showMessage(context, message: AppStrings.amountInvalid);
      return;
    }

    final saleCtrl = ref.read(saleControllerProvider.notifier);
    final customer = _selectedCustomer!;
    setState(() => _isSubmitting = true);
    try {
      final result = await saleCtrl.createSale(
        customerId: customer.id,
        amount: _amount,
      );

      saleCtrl.reset();
      if (!mounted) return;
      context.go('/sale-success', extra: SaleSuccessArgs(result: result));
    } catch (e) {
      if (!mounted) return;
      final info = AppErrorMapper.describe(e);
      AppFeedback.showMessage(context, message: info.message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _resetFormForNextSale() {
    final submittedAmount = _amount;
    _searchDebounce?.cancel();
    setState(() {
      _selectedCustomer = null;
      _searchResults = [];
      _quickAmount = null;
      _lastAmount = submittedAmount > 0 ? submittedAmount.toInt() : _lastAmount;
      _phoneCtrl.clear();
      _amountCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _phoneFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final saleState = ref.watch(saleControllerProvider);
    final recentCustomers = ref.watch(recentCustomersProvider);
    final showRecentCustomers =
        _selectedCustomer == null && _phoneCtrl.text.trim().isEmpty;
    final pointsBaseMzn = AppConstants.salePointsBaseMzn;
    final pointsPerBase = (pointsBaseMzn / AppConstants.pointsPerMzn).floor();
    final pointsPerBaseLabel = pointsPerBase == 1
        ? '1 ${AppStrings.pontosAbrev}'
        : '$pointsPerBase ${AppStrings.pontosAbrev}';

    return Scaffold(
      backgroundColor: AppColors.surface,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: _ConfirmSaleButton(
          loading: saleState is AsyncLoading || _isSubmitting,
          onPressed: (saleState is AsyncLoading || _isSubmitting)
              ? null
              : _confirmSale,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SaleHeader(onBack: _handleBackPressed),
            Transform.translate(
              offset: const Offset(0, -26),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: '1. ${AppStrings.cliente}',
                      actionText: AppStrings.verTudo,
                      onAction: () => context.push('/customers'),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedCustomer != null)
                      _SelectedCustomerCard(
                        customer: _selectedCustomer!,
                        onClear: () => setState(() {
                          _selectedCustomer = null;
                          _phoneCtrl.clear();
                        }),
                      )
                    else ...[
                      if (showRecentCustomers)
                        recentCustomers.when(
                          data: (customers) {
                            if (customers.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return SizedBox(
                              height: 156,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: customers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  return _CustomerCard(
                                    customer: customer,
                                    onTap: () => _selectCustomer(customer),
                                  );
                                },
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      if (showRecentCustomers) const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        focusNode: _phoneFocusNode,
                        keyboardType: TextInputType.text,
                        autofocus: widget.args?.preselectedCustomerId == null,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: AppStrings.nomeOuTelefoneCliente,
                          prefixIcon: Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide(color: AppColors.g100),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide(color: AppColors.g100),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide(color: AppColors.primary),
                          ),
                        ),
                        onChanged: _onPhoneChanged,
                      ),
                      if (_searchResults.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            children: _searchResults
                                .map(
                                  (c) => _SearchResultTile(
                                    customer: c,
                                    onTap: () => _selectCustomer(c),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      if (_searchResults.isEmpty &&
                          _phoneCtrl.text
                                  .replaceAll(RegExp(r'\D'), '')
                                  .length >=
                              AppConstants.minSalePhoneDigitsForNewCustomer)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.person_add_rounded),
                            label: const Text(AppStrings.novoCliente),
                            onPressed: _createAndSelectCustomer,
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    _SectionTitle(title: '2. ${AppStrings.valor}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: AppConstants.saleQuickAmounts
                          .map(
                            (amt) => QuickAmountButton(
                              amount: amt,
                              selected: _quickAmount == amt,
                              onTap: () => setState(() {
                                _quickAmount = _quickAmount == amt ? null : amt;
                                if (_quickAmount != null) _amountCtrl.clear();
                              }),
                            ),
                          )
                          .toList()
                        ..addAll(
                          _lastAmount == null
                              ? const []
                              : [
                                  QuickAmountButton(
                                    amount: _lastAmount!,
                                    label: AppStrings.ultimo,
                                    selected: _quickAmount == _lastAmount,
                                    onTap: () => setState(() {
                                      _quickAmount = _quickAmount == _lastAmount
                                          ? null
                                          : _lastAmount;
                                      if (_quickAmount != null) {
                                        _amountCtrl.clear();
                                      }
                                    }),
                                  ),
                                ],
                        ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: AppStrings.outroValor,
                        suffixText: AppStrings.moedaMzn,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(color: AppColors.g100),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(color: AppColors.g100),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                      onChanged: (_) => setState(() => _quickAmount = null),
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(title: '3. ${AppStrings.resumo}'),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      points: _points,
                      pointsBaseMzn: pointsBaseMzn,
                      pointsPerBaseLabel: pointsPerBaseLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SaleHeader extends StatelessWidget {
  const _SaleHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 8, 20, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDarker, AppColors.primary],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                onPressed: onBack,
              ),
              const Expanded(
                child: Text(
                  AppStrings.novaVendaTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 10),
          const _StepIndicator(currentStep: 1),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const steps = [
      AppStrings.cliente,
      AppStrings.valorStep,
      AppStrings.confirmar,
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepDot(index: i + 1, label: steps[i], active: currentStep == i + 1),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: currentStep > i + 1
                    ? AppColors.secondary
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.active,
  });

  final int index;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final textColor =
        active ? AppColors.secondary : Colors.white.withValues(alpha: 0.7);
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AppColors.secondary : Colors.white,
            shape: BoxShape.circle,
            border: active
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.primaryDarker,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionText,
    required this.onAction,
  });

  final String title;
  final String actionText;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryLight),
          child: Text(actionText),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
    );
  }
}

class _SelectedCustomerCard extends StatelessWidget {
  const _SelectedCustomerCard({required this.customer, required this.onClear});
  final Customer customer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100),
      ),
      child: Row(
        children: [
          _CustomerAvatar(name: customer.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  customer.phone,
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _PointsPill(points: customer.totalPoints),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 170,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.g100),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CustomerAvatar(name: customer.name, radius: 16),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _PointsPill(points: customer.totalPoints),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.g100),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            _CustomerAvatar(name: customer.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.phone,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _PointsPill(points: customer.totalPoints),
          ],
        ),
      ),
    );
  }
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.name, this.radius = 18});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: AppColors.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});
  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.green),
          const SizedBox(width: 4),
          Text(
            '$points ${AppStrings.pontosAbrev}',
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.points,
    required this.pointsBaseMzn,
    required this.pointsPerBaseLabel,
  });

  final int points;
  final int pointsBaseMzn;
  final String pointsPerBaseLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppStrings.clienteGanhara,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$points ${AppStrings.pontosAbrev}',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.green,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$pointsPerBaseLabel ${AppStrings.por} $pointsBaseMzn ${AppStrings.moedaMzn}',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.pontosAposConfirmacao,
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmSaleButton extends StatelessWidget {
  const _ConfirmSaleButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: AppStrings.confirmarVenda,
      onPressed: onPressed,
      loading: loading,
      trailingIcon: Icons.arrow_forward_rounded,
      height: 58,
    );
  }
}
