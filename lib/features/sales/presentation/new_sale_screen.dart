import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/quick_amount_button.dart';
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
  final _amountCtrl = TextEditingController();
  Timer? _searchDebounce;
  Customer? _selectedCustomer;
  int? _quickAmount;
  int? _lastAmount;
  List<Customer> _searchResults = [];

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
    final customer = await ref
        .read(customersControllerProvider.notifier)
        .createCustomer(name: phone, phone: phone);
    _selectCustomer(customer);
  }

  Future<void> _confirmSale() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um cliente primeiro')),
      );
      return;
    }
    if (_amount < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStrings.amountInvalid)));
      return;
    }

    final saleCtrl = ref.read(saleControllerProvider.notifier);
    final result = await saleCtrl.createSale(
      customerId: _selectedCustomer!.id,
      amount: _amount,
    );

    saleCtrl.reset();
    if (!mounted) return;
    context.go('/sale-success', extra: SaleSuccessArgs(result: result));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saleState = ref.watch(saleControllerProvider);
    final recentCustomers = ref.watch(recentCustomersProvider);
    final showRecentCustomers =
        _selectedCustomer == null && _phoneCtrl.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.novaVendaTitle)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: PrimaryButton(
          label: AppStrings.confirmarVenda,
          onPressed: _confirmSale,
          loading: saleState is AsyncLoading,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Step 1: Customer ──────────────────────────────────────────
              const _StepLabel(number: '1', label: 'Cliente'),
              const SizedBox(height: 12),
              if (_selectedCustomer != null)
                _SelectedCustomerTile(
                  customer: _selectedCustomer!,
                  onClear: () => setState(() {
                    _selectedCustomer = null;
                    _phoneCtrl.clear();
                  }),
                )
              else ...[
                if (showRecentCustomers) ...[
                  Text(
                    'Recentes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  recentCustomers.when(
                    data: (customers) {
                      if (customers.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            return _RecentCustomerButton(
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
                  const SizedBox(height: 12),
                  Text(
                    'Ou pesquise',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.text,
                  autofocus: widget.args?.preselectedCustomerId == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome ou telefone',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: _onPhoneChanged,
                ),
                if (_searchResults.isNotEmpty) const SizedBox(height: 8),
                ..._searchResults.map(
                  (c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${c.totalPoints} pts',
                        style: const TextStyle(
                          color: AppColors.secondaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: () => _selectCustomer(c),
                  ),
                ),
                if (_searchResults.isEmpty &&
                    _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 7)
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

              // ── Step 2: Amount ────────────────────────────────────────────
              const _StepLabel(number: '2', label: AppStrings.valor),
              const SizedBox(height: 12),
              Text(
                'Atalhos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [100, 200, 300, 500]
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
                              label: 'Último',
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
              const SizedBox(height: 10),
              Text(
                'Outro valor',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                ],
                decoration: const InputDecoration(
                  hintText: AppStrings.valorHint,
                  suffixText: 'MZN',
                ),
                onChanged: (_) => setState(() => _quickAmount = null),
              ),
              const SizedBox(height: 12),
              if (_amount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: const BrandMark(size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '+ $_points ${AppStrings.pontosPreview}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.label});
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
        ),
      ],
    );
  }
}

class _SelectedCustomerTile extends StatelessWidget {
  const _SelectedCustomerTile({required this.customer, required this.onClear});
  final Customer customer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${customer.totalPoints} pts',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
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

class _RecentCustomerButton extends StatelessWidget {
  const _RecentCustomerButton({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.centerLeft,
          side: const BorderSide(color: AppColors.g100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700,
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
                  const SizedBox(height: 4),
                  Text(
                    '${customer.totalPoints} pts',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
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
