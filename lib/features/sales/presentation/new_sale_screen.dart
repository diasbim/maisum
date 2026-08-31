import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/quick_amount_button.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../design_system/design_system.dart';
import '../../catalog/domain/merchant_item.dart';
import '../../customers/domain/customer.dart';
import '../domain/sale_item.dart';
import '../widgets/sale_progress_stepper.dart';
import 'sale_controller.dart';
import 'sale_success_screen.dart';

class NewSaleArgs {
  const NewSaleArgs({
    this.preselectedCustomerId,
    this.prefilledAmount,
    this.replacesSaleId,
  });
  final String? preselectedCustomerId;
  final double? prefilledAmount;
  final String? replacesSaleId;
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
  List<SaleItemInput> _selectedSaleItems = <SaleItemInput>[];
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSaleFlow();
    });
  }

  Future<void> _initializeSaleFlow() async {
    final preselectedId = widget.args?.preselectedCustomerId;
    if (preselectedId != null) {
      final preselected =
          await ref.read(customerRepositoryProvider).getById(preselectedId);
      if (!mounted) return;
      if (preselected != null && !preselected.isArchived) {
        final latestSale =
            await ref.read(saleDaoProvider).getLatestWithCustomer();
        if (!mounted) return;
        setState(() {
          _lastAmount = _amountFromLatestSale(latestSale);
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

    final latestSale = await ref.read(saleDaoProvider).getLatestWithCustomer();
    if (!mounted) return;
    final lastAmount = _amountFromLatestSale(latestSale);
    final lastCustomer = await _getLastUsedCustomer(latestSale);
    if (!mounted) return;

    if (lastCustomer != null) {
      setState(() {
        _lastAmount = lastAmount;
        _selectedCustomer = lastCustomer;
        _initializationState = _SaleInitializationState.ready;
      });
      return;
    }

    setState(() {
      _lastAmount = lastAmount;
      _initializationState = _SaleInitializationState.ready;
    });

    unawaited(_openCustomerSelector(customers: customers));
  }

  int? _amountFromLatestSale(Map<String, dynamic>? latestSale) {
    final amount = latestSale?['amount'] as num?;
    return amount?.round();
  }

  Future<Customer?> _getLastUsedCustomer(
      Map<String, dynamic>? latestSale) async {
    final customerId = latestSale?['customer_id'] as String?;
    if (customerId == null || customerId.isEmpty) {
      return null;
    }
    final customer =
        await ref.read(customerRepositoryProvider).getById(customerId);
    return customer == null || customer.isArchived ? null : customer;
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

  int get _pointsPerMzn =>
      ref
          .read(activeBusinessProfileProvider)
          .valueOrNull
          ?.loyalty
          .pointsPerMzn ??
      AppConstants.pointsPerMzn;

  int get _points => (_amount / _pointsPerMzn).floor();

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
        items: _selectedSaleItems,
        replacesSaleId: widget.args?.replacesSaleId,
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

  Future<void> _openSaleItemsSelector() async {
    if (_isSubmitting) return;
    final selected = await showModalBottomSheet<List<SaleItemInput>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _SaleItemsSelectionSheet(initialItems: _selectedSaleItems),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedSaleItems = selected);
  }

  void _removeSaleItem(String merchantItemId) {
    setState(() {
      _selectedSaleItems = _selectedSaleItems
          .where((item) => item.merchantItemId != merchantItemId)
          .toList();
    });
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
    final loyalty =
        ref.watch(activeBusinessProfileProvider).valueOrNull?.loyalty;
    final pointsBaseMzn =
        loyalty?.pointsPerMzn ?? AppConstants.salePointsBaseMzn;
    final pointsPerBase = (pointsBaseMzn / _pointsPerMzn).floor();
    final quickAmounts = loyalty?.quickAmounts ?? AppConstants.saleQuickAmounts;
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
              child: MaisUmSurface(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                radius: AppRadius.xl,
                animationDuration: Duration.zero,
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
                            children: quickAmounts
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
                          const SizedBox(height: 12),
                          MaisUmButton(
                            onPressed: isBusy ? null : _openSaleItemsSelector,
                            label: 'Adicionar produtos e serviços',
                            leadingIcon: Icons.add_rounded,
                            variant: MaisUmButtonVariant.outlined,
                            foregroundColor: AppColors.primary,
                          ),
                          if (_selectedSaleItems.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _SelectedSaleItemsChips(
                              items: _selectedSaleItems,
                              onRemove: _removeSaleItem,
                            ),
                          ],
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
          'Para registar uma venda, adicione primeiro um cliente.',
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),
        MaisUmButton(
          onPressed: onAddCustomer,
          label: 'Adicionar Cliente',
          variant: MaisUmButtonVariant.outlined,
          leadingIcon: Icons.person_add_alt_1_rounded,
          animationDuration: Duration.zero,
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
    return MaisUmSurface(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      variant: MaisUmSurfaceVariant.muted,
      radius: AppRadius.lg,
      animationDuration: Duration.zero,
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
          MaisUmButton(
            onPressed: onSelectCustomer,
            label: 'Selecionar',
            isLoading: selecting,
            variant: MaisUmButtonVariant.ghost,
            fullWidth: false,
            height: 36,
            radius: AppRadius.md,
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
          const MaisUmSheetHeader(
            title: 'Selecionar cliente',
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
                return MaisUmSurface(
                  onTap: () => Navigator.of(context).pop(customer),
                  semanticButton: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  radius: AppRadius.lg,
                  animationDuration: Duration.zero,
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
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              customer.phone,
                              style: const TextStyle(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PointsPill(points: customer.totalPoints),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: customers.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedSaleItemsChips extends StatelessWidget {
  const _SelectedSaleItemsChips({required this.items, required this.onRemove});

  final List<SaleItemInput> items;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecionado',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => InputChip(
                  label: Text(
                    item.quantity > 1
                        ? '${item.nameSnapshot} x${item.quantity}'
                        : item.nameSnapshot,
                  ),
                  onDeleted: () => onRemove(item.merchantItemId),
                  deleteIcon: const Icon(Icons.close_rounded, size: 18),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SaleItemsSelectionSheet extends ConsumerStatefulWidget {
  const _SaleItemsSelectionSheet({required this.initialItems});

  final List<SaleItemInput> initialItems;

  @override
  ConsumerState<_SaleItemsSelectionSheet> createState() =>
      _SaleItemsSelectionSheetState();
}

class _SaleItemsSelectionSheetState
    extends ConsumerState<_SaleItemsSelectionSheet> {
  final _searchCtrl = TextEditingController();
  late Map<String, SaleItemInput> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final item in widget.initialItems) item.merchantItemId: item,
    };
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(activeMerchantItemsProvider);
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxSheetHeight =
        (mediaQuery.size.height - bottomInset - mediaQuery.padding.top - 16)
            .clamp(240.0, mediaQuery.size.height * 0.9)
            .toDouble();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: maxSheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Produtos e serviços',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () =>
                        Navigator.of(context).pop(widget.initialItems),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar...',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: itemsAsync.when(
                  data: _buildItemsList,
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child:
                          CircularProgressIndicator(color: AppColors.secondary),
                    ),
                  ),
                  error: (_, __) => Center(
                    child: MaisUmButton(
                      onPressed: () =>
                          ref.invalidate(activeMerchantItemsProvider),
                      label: AppStrings.tentar,
                      leadingIcon: Icons.refresh_rounded,
                      variant: MaisUmButtonVariant.outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MaisUmButton(
                onPressed: () =>
                    Navigator.of(context).pop(_selected.values.toList()),
                label: 'Confirmar',
                leadingIcon: Icons.check_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsList(List<MerchantItem> items) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? items
        : items
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
    if (filtered.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: EmptyState(
              title:
                  items.isEmpty ? 'Catálogo vazio' : 'Nenhum item encontrado',
              subtitle: items.isEmpty
                  ? 'Crie produtos e serviços no catálogo para os usar aqui.'
                  : null,
            ),
          ),
        ],
      );
    }

    final services = filtered
        .where((item) => item.type == MerchantItemType.service)
        .toList();
    final products = filtered
        .where((item) => item.type == MerchantItemType.product)
        .toList();

    return ListView(
      children: [
        if (services.isNotEmpty) ...[
          const _SaleItemSectionLabel('SERVIÇOS'),
          ...services.map(_itemTile),
        ],
        if (products.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SaleItemSectionLabel('PRODUTOS'),
          ...products.map(_itemTile),
        ],
      ],
    );
  }

  Widget _itemTile(MerchantItem item) {
    final selected = _selected[item.id];
    final isSelected = selected != null;
    final price = item.defaultPrice == null
        ? null
        : '${item.defaultPrice!.toStringAsFixed(0)} ${AppStrings.moedaMzn}';
    return MaisUmSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      radius: AppRadius.lg,
      selected: isSelected,
      shadows: const [],
      onTap: () => _toggle(item),
      semanticButton: true,
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => _toggle(item),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (price != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    price,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isSelected)
            _QuantityStepper(
              value: selected.quantity,
              onChanged: (quantity) => _setQuantity(item.id, quantity),
            ),
        ],
      ),
    );
  }

  void _toggle(MerchantItem item) {
    setState(() {
      if (_selected.containsKey(item.id)) {
        _selected.remove(item.id);
      } else {
        _selected[item.id] = SaleItemInput.fromMerchantItem(item);
      }
    });
  }

  void _setQuantity(String merchantItemId, int quantity) {
    final current = _selected[merchantItemId];
    if (current == null) return;
    setState(() {
      _selected[merchantItemId] = current.copyWith(quantity: quantity);
    });
  }
}

class _SaleItemSectionLabel extends StatelessWidget {
  const _SaleItemSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Diminuir',
          onPressed: value <= 1 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline_rounded),
          color: Colors.white,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Aumentar',
          onPressed: value >= 999 ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline_rounded),
          color: Colors.white,
        ),
      ],
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
        MaisUmButton(
          onPressed: onAction,
          label: actionText,
          variant: MaisUmButtonVariant.ghost,
          foregroundColor: AppColors.primaryLight,
          fullWidth: false,
          height: 36,
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
    return MaisUmSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      variant: MaisUmSurfaceVariant.muted,
      radius: AppRadius.lg,
      animationDuration: Duration.zero,
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
            child: MaisUmButton(
              onPressed: onChange,
              label: 'Alterar',
              variant: MaisUmButtonVariant.ghost,
              fullWidth: false,
              height: 36,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
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
    return MaisUmSurface(
      padding: const EdgeInsets.all(16),
      variant: MaisUmSurfaceVariant.success,
      radius: AppRadius.lg,
      borderColor: AppColors.green.withValues(alpha: 0.2),
      animationDuration: Duration.zero,
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
    return MaisUmSurface(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      variant: MaisUmSurfaceVariant.success,
      radius: AppRadius.md,
      borderColor: AppColors.success.withValues(alpha: 0.22),
      animationDuration: Duration.zero,
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
    return MaisUmButton(
      label: label,
      onPressed: onPressed,
      isLoading: loading,
      trailingIcon: Icons.arrow_forward_rounded,
      height: 58,
      animationDuration: Duration.zero,
    );
  }
}
