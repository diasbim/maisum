import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

class NewSaleArgs {
  const NewSaleArgs({this.preselectedCustomerId});
  final String? preselectedCustomerId;
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
  Customer? _selectedCustomer;
  int? _quickAmount;
  List<Customer> _searchResults = [];
  bool _searching = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    final preselectedId = widget.args?.preselectedCustomerId;
    if (preselectedId != null) {
      _loadPreselectedCustomer(preselectedId);
    }
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

  @override
  void dispose() {
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
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    final results = await ref.read(customerRepositoryProvider).search(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.amountInvalid)),
      );
      return;
    }

    final saleCtrl = ref.read(saleControllerProvider.notifier);
    await saleCtrl.createSale(
      customerId: _selectedCustomer!.id,
      amount: _amount,
    );

    if (mounted) setState(() => _showSuccess = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saleState = ref.watch(saleControllerProvider);

    if (_showSuccess &&
        saleState is AsyncData<SaleResult?> &&
        saleState.value != null) {
      return _SuccessView(
        result: saleState.value!,
        onDone: () {
          ref.read(saleControllerProvider.notifier).reset();
          context.pop();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.novaVendaTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
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
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome ou telefone',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: _onPhoneChanged,
                ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                ..._searchResults.map(
                  (c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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

              const SizedBox(height: 28),

              // ── Step 2: Amount ────────────────────────────────────────────
              const _StepLabel(number: '2', label: AppStrings.valor),
              const SizedBox(height: 12),
              Row(
                children: [100, 200, 500]
                    .map((amt) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: QuickAmountButton(
                            amount: amt,
                            selected: _quickAmount == amt,
                            onTap: () => setState(() {
                              _quickAmount = _quickAmount == amt ? null : amt;
                              if (_quickAmount != null) _amountCtrl.clear();
                            }),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                ],
                decoration: const InputDecoration(
                  labelText: AppStrings.valorHint,
                  suffixText: 'MZN',
                ),
                onChanged: (_) => setState(() => _quickAmount = null),
              ),
              const SizedBox(height: 12),
              if (_amount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

              const SizedBox(height: 36),

              // ── Step 3: Confirm ───────────────────────────────────────────
              PrimaryButton(
                label: AppStrings.confirmarVenda,
                onPressed: _confirmSale,
                loading: saleState is AsyncLoading,
              ),
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
            child: const Icon(Icons.check_rounded,
                color: AppColors.primary, size: 22),
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
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.onSurfaceVariant),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.result, required this.onDone});
  final SaleResult result;
  final VoidCallback onDone;

  void _openWhatsApp(String phone, int points) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('258') ? clean : '258$clean';
    final msg = Uri.encodeComponent(
      'Obrigado pela sua visita! Ganhou $points pontos no programa MaisUm. Continue a colecionar para resgatar prémios!',
    );
    launchUrl(
      Uri.parse('https://wa.me/$number?text=$msg'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDarker],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 52,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  AppStrings.vendaRegistada,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '+ ${result.sale.points} ${AppStrings.pontosAtribuidos}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  result.customer.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 36),
                OutlinedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(AppStrings.notificarWhatsApp),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: () =>
                      _openWhatsApp(result.customer.phone, result.sale.points),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onDone,
                  child: const Text(
                    AppStrings.continuar2,
                    style: TextStyle(color: Colors.white70),
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
