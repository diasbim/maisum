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
import '../widgets/sale_progress_stepper.dart';
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

enum _SaleInitializationState {
  loading,
  ready,
  noCustomers,
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _amountCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _isSelectingCustomer = false;
  bool _showCompletedStepper = false;
  int? _completedPoints;
  Customer? _selectedCustomer;
  int? _quickAmount;
  int? _lastAmount;
  _SaleInitializationState _initializationState =
      _SaleInitializationState.loading;

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
    final prefilledAmount = widget.args?.prefilledAmount;
    if (prefilledAmount != null && prefilledAmount > 0) {
      _amountCtrl.text = prefilledAmount.toStringAsFixed(0);
    }
    _loadLastAmount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSaleFlow();
    });
  }

  Future<void> _loadLastAmount() async {
    final lastAmount = await ref.read(saleDaoProvider).getLastSaleAmount();
    if (!mounted) return;
    setState(() => _lastAmount = lastAmount);
  }

  Future<void> _initializeSaleFlow() async {
    final preselectedId = widget.args?.preselectedCustomerId;
    if (preselectedId != null) {
      final preselected =
          await ref.read(customerRepositoryProvider).getById(preselectedId);
      if (!mounted) return;
      if (preselected != null) {
        setState(() {
          _selectedCustomer = preselected;
          _initializationState = _SaleInitializationState.ready;
        });
        return;
      }
    }

    final customers = await ref.read(customerRepositoryProvider).getAll();
    if (!mounted) return;

    if (customers.isEmpty) {
      setState(() {
        _selectedCustomer = null;
        _initializationState = _SaleInitializationState.noCustomers;
      });
      return;
    }

    final lastCustomer = await _getLastUsedCustomer();
    if (!mounted) return;

    if (lastCustomer != null) {
      setState(() {
        _selectedCustomer = lastCustomer;
        _initializationState = _SaleInitializationState.ready;
      });
      return;
    }

    setState(() {
      _initializationState = _SaleInitializationState.ready;
    });

    await _openCustomerSelector(customers: customers);
  }

  Future<Customer?> _getLastUsedCustomer() async {
    final latestSale = await ref.read(saleDaoProvider).getLatestWithCustomer();
    final customerId = latestSale?['customer_id'] as String?;
    if (customerId == null || customerId.isEmpty) {
      return null;
    }
    return ref.read(customerRepositoryProvider).getById(customerId);
  }

  Future<void> _openCustomerSelector({List<Customer>? customers}) async {
    if (_isSelectingCustomer) return;

    final sourceCustomers =
        customers ?? await ref.read(customerRepositoryProvider).getAll();
    if (!mounted || sourceCustomers.isEmpty) {
      return;
    }

    setState(() => _isSelectingCustomer = true);

    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CustomerSelectionSheet(customers: sourceCustomers),
    );

    if (!mounted) return;

    setState(() => _isSelectingCustomer = false);
    if (selected != null) {
      _selectCustomer(selected);
    }
  }

  Future<void> _openCreateCustomerFlow() async {
    if (_isSubmitting) return;
    await context.push('/customers/create?resumeSaleFlow=1');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount {
    if (_quickAmount != null) return _quickAmount!.toDouble();
    return double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
  }

  double? get _selectedAmount => _amount > 0 ? _amount : null;

  bool get _canSubmit => _selectedCustomer != null && _selectedAmount != null;

  String get _buttonLabel {
    if (_initializationState == _SaleInitializationState.noCustomers) {
      return 'Adicionar Cliente';
    }
    if (_selectedCustomer == null) {
      return AppStrings.selecionarCliente;
    }
    if (_selectedAmount == null) {
      return 'Escolha um valor';
    }
    return AppStrings.confirmarVenda;
  }

  NewSaleFlowState get _flowState => NewSaleFlowState(
        selectedCustomer: _selectedCustomer,
        selectedAmount: _selectedAmount,
        completed: _showCompletedStepper,
      );

  int get _points => (_amount / AppConstants.pointsPerMzn).floor();

  void _selectCustomer(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _showCompletedStepper = false;
      _completedPoints = null;
      _initializationState = _SaleInitializationState.ready;
    });
  }

  void _changeCustomer() {
    setState(() {
      _selectedCustomer = null;
      _showCompletedStepper = false;
      _completedPoints = null;
    });
    _openCustomerSelector();
  }

  Future<void> _confirmSale() async {
    if (_isSubmitting || !_canSubmit) return;

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

      if (!mounted) return;
      setState(() {
        _showCompletedStepper = true;
        _completedPoints = result.sale.points;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1000));

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

  @override
  Widget build(BuildContext context) {
    final saleState = ref.watch(saleControllerProvider);
    final flowState = _flowState;
    final isBusy = saleState is AsyncLoading || _isSubmitting;
    final noCustomers =
        _initializationState == _SaleInitializationState.noCustomers;
    final isInitializing =
        _initializationState == _SaleInitializationState.loading;
    const pointsBaseMzn = AppConstants.salePointsBaseMzn;
    final pointsPerBase = (pointsBaseMzn / AppConstants.pointsPerMzn).floor();
    final pointsPerBaseLabel = pointsPerBase == 1
        ? '1 ${AppStrings.pontosAbrev}'
        : '$pointsPerBase ${AppStrings.pontosAbrev}';
    final canOpenSelector =
        !isBusy && !isInitializing && !noCustomers && !_isSelectingCustomer;
    final action = _canSubmit
        ? _confirmSale
        : noCustomers
            ? _openCreateCustomerFlow
            : _selectedCustomer == null
                ? (canOpenSelector ? _openCustomerSelector : null)
                : null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: _ConfirmSaleButton(
          label: _buttonLabel,
          loading: isBusy,
          onPressed: action,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SaleHeader(
              onBack: _handleBackPressed,
              customerStatus: flowState.getCustomerStepStatus(),
              amountStatus: flowState.getAmountStepStatus(),
              confirmStatus: flowState.getConfirmStepStatus(),
            ),
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
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Builder(
                  builder: (context) {
                    if (isInitializing) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (noCustomers) {
                      return _NoCustomersState(
                        onAddCustomer: _openCreateCustomerFlow,
                      );
                    }

                    return Column(
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
                            onChange: _changeCustomer,
                          )
                        else
                          _AwaitingCustomerSelectionCard(
                            selecting: _isSelectingCustomer,
                            onSelectCustomer:
                                canOpenSelector ? _openCustomerSelector : null,
                          ),
                        if (_showCompletedStepper &&
                            _completedPoints != null) ...[
                          const SizedBox(height: 12),
                          _SaleCompletionHint(points: _completedPoints!),
                        ],
                        if (_selectedCustomer != null) ...[
                          const SizedBox(height: 20),
                          const _SectionTitle(title: '2. ${AppStrings.valor}'),
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
                                      _quickAmount =
                                          _quickAmount == amt ? null : amt;
                                      if (_quickAmount != null) {
                                        _amountCtrl.clear();
                                      }
                                      _showCompletedStepper = false;
                                      _completedPoints = null;
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
                                            _quickAmount =
                                                _quickAmount == _lastAmount
                                                    ? null
                                                    : _lastAmount;
                                            if (_quickAmount != null) {
                                              _amountCtrl.clear();
                                            }
                                            _showCompletedStepper = false;
                                            _completedPoints = null;
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
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d,.]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              hintText: AppStrings.outroValor,
                              suffixText: AppStrings.moedaMzn,
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(16)),
                                borderSide: BorderSide(color: AppColors.g100),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(16)),
                                borderSide: BorderSide(color: AppColors.g100),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(16)),
                                borderSide:
                                    BorderSide(color: AppColors.primary),
                              ),
                            ),
                            onChanged: (_) => setState(() {
                              _quickAmount = null;
                              _showCompletedStepper = false;
                              _completedPoints = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          const _SectionTitle(title: '3. ${AppStrings.resumo}'),
                          const SizedBox(height: 12),
                          _SummaryCard(
                            points: _points,
                            pointsBaseMzn: pointsBaseMzn,
                            pointsPerBaseLabel: pointsPerBaseLabel,
                          ),
                        ],
                      ],
                    );
                  },
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

class _NoCustomersState extends StatelessWidget {
  const _NoCustomersState({required this.onAddCustomer});

  final VoidCallback onAddCustomer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.person_off_rounded, color: AppColors.onSurfaceVariant),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum cliente registado',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Para registrar uma venda, adicione primeiro um cliente.',
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAddCustomer,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Adicionar Cliente'),
          ),
        ),
      ],
    );
  }
}

class _AwaitingCustomerSelectionCard extends StatelessWidget {
  const _AwaitingCustomerSelectionCard({
    required this.selecting,
    required this.onSelectCustomer,
  });

  final bool selecting;
  final VoidCallback? onSelectCustomer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_search_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Selecione um cliente para continuar.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onSelectCustomer,
            child: selecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Selecionar'),
          ),
        ],
      ),
    );
  }
}

class _CustomerSelectionSheet extends StatelessWidget {
  const _CustomerSelectionSheet({required this.customers});

  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecionar cliente',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final customer = customers[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  leading: _CustomerAvatar(name: customer.name),
                  title: Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    customer.phone,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  trailing: _PointsPill(points: customer.totalPoints),
                  onTap: () => Navigator.of(context).pop(customer),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: customers.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleHeader extends StatelessWidget {
  const _SaleHeader({
    required this.onBack,
    required this.customerStatus,
    required this.amountStatus,
    required this.confirmStatus,
  });

  final VoidCallback onBack;
  final StepStatus customerStatus;
  final StepStatus amountStatus;
  final StepStatus confirmStatus;

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
          SaleProgressStepper(
            customerStatus: customerStatus,
            amountStatus: amountStatus,
            confirmStatus: confirmStatus,
          ),
        ],
      ),
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
  const _SelectedCustomerCard({required this.customer, required this.onChange});
  final Customer customer;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.g100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cliente Selecionado',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
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
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onChange,
              child: const Text('Alterar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.name, this.radius = 20});
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

class _SaleCompletionHint extends StatelessWidget {
  const _SaleCompletionHint({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.celebration_rounded,
            color: AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.vendaRegistada,
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '+$points ${AppStrings.pontosAtribuidos}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _ConfirmSaleButton extends StatelessWidget {
  const _ConfirmSaleButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: label,
      onPressed: onPressed,
      loading: loading,
      trailingIcon: Icons.arrow_forward_rounded,
      height: 58,
    );
  }
}
