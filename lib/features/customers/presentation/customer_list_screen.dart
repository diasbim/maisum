import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/client_created_success_sheet.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/utils/moz_phone_utils.dart';
import '../../sales/presentation/new_sale_screen.dart';
import '../domain/customer.dart';
import 'customers_controller.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();
  _CustomerFilter _filter = _CustomerFilter.all;
  Timer? _searchDebounce;
  bool _isSearching = false;

  void _handleBackPressed() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/dashboard');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersControllerProvider);
    final searchText = _searchCtrl.text.trim();

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: customers.when(
        data: (list) {
          final filtered = _applyFilter(list);
          final isSearching = searchText.isNotEmpty;
          final emptyTitle =
              isSearching ? 'Sem resultados' : AppStrings.semClientes;
          final emptySubtitle = isSearching
              ? 'Nenhum cliente encontrado para "$searchText". Ajuste a pesquisa ou limpe o campo para ver todos.'
              : 'Crie o primeiro cliente para começar a registar cortes e pontos sem complicação.';
          return RefreshIndicator(
            color: AppColors.secondary,
            onRefresh: () =>
                ref.read(customersControllerProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: _CustomerHeader(
                    controller: _searchCtrl,
                    isSearching: _isSearching,
                    showClear: _searchCtrl.text.isNotEmpty,
                    filter: _filter,
                    totalCustomers: list.length,
                    visibleCustomers: filtered.length,
                    onSearchChanged: (q) {
                      setState(() {});
                      _scheduleSearch(q);
                    },
                    onClear: () {
                      _searchDebounce?.cancel();
                      _searchCtrl.clear();
                      setState(() {});
                      ref.read(customersControllerProvider.notifier).search('');
                    },
                    onFilterChanged: (filter) {
                      setState(() => _filter = filter);
                    },
                    onBack: _handleBackPressed,
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                      actionLabel: AppStrings.adicionarCliente,
                      onAction: () => _showAddCustomerSheet(context),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CustomerCard(
                        name: filtered[i].name,
                        phone: filtered[i].phone,
                        totalPoints: filtered[i].totalPoints,
                        lastVisitLabel:
                            _formatLastVisit(_lastVisit(filtered[i])),
                        onTap: () =>
                            context.push('/customers/${filtered[i].id}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
        error: (e, _) {
          final info = AppErrorMapper.describe(e);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 36,
                    color: AppColors.g500,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    info.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text(AppStrings.tentar),
                    onPressed: () => ref
                        .read(customersControllerProvider.notifier)
                        .refresh(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddCustomerSheet(context),
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primaryDarker,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text(
            'Adicionar',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  DateTime _lastVisit(Customer customer) {
    return customer.updatedAt ?? customer.createdAt;
  }

  String _formatLastVisit(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return '$diff dias atrás';
  }

  List<Customer> _applyFilter(List<Customer> list) {
    final copy = [...list];
    switch (_filter) {
      case _CustomerFilter.recent:
        copy.sort((a, b) =>
            _lastVisit(b).millisecondsSinceEpoch -
            _lastVisit(a).millisecondsSinceEpoch);
      case _CustomerFilter.top:
        copy.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
      case _CustomerFilter.all:
        break;
    }
    return copy;
  }

  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _isSearching = false);
      ref.read(customersControllerProvider.notifier).search('');
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(customersControllerProvider.notifier).search(query).whenComplete(
        () {
          if (mounted) {
            setState(() => _isSearching = false);
          }
        },
      );
    });
  }

  Future<Customer> _createCustomer({
    required String name,
    required String phone,
  }) async {
    final customer = await ref
        .read(customersControllerProvider.notifier)
        .createCustomer(name: name, phone: phone);

    unawaited(
      ref.read(analyticsServiceProvider).record(
        eventType: 'client_created',
        source: 'customers',
        properties: {
          'customer_id': customer.id,
        },
      ),
    );

    return customer;
  }

  Future<void> _showCustomerCreatedSuccess(Customer customer) async {
    AppFeedback.showMessage(
      context,
      message: AppStrings.customerCreatedSuccess,
    );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ClientCreatedSuccessSheet(
        customerName: customer.name,
        totalPoints: customer.totalPoints,
        onRegisterSale: () async {
          Navigator.of(sheetContext).pop();
          unawaited(
            ref.read(analyticsServiceProvider).record(
              eventType: 'sale_registration_started',
              source: 'customers',
              properties: {
                'entry_point': 'client_created_success_sheet',
                'customer_id': customer.id,
              },
            ),
          );
          await context.push(
            '/new-sale',
            extra: NewSaleArgs(preselectedCustomerId: customer.id),
          );
        },
        onLater: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _showCustomerCreateErrorDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Não foi possível criar cliente'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.continuar2),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCustomerSheet(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final theme = Theme.of(context);
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppColors.g300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      AppStrings.adicionarCliente,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: nameCtrl,
                      enabled: !isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: AppStrings.nome,
                        hintText: AppStrings.nomeHint,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppStrings.nameRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      enabled: !isSaving,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: AppStrings.phoneNumber,
                        hintText: '84 000 0000',
                      ),
                      validator: MozPhoneUtils.validatorMessage,
                      onFieldSubmitted: (_) async {
                        if (isSaving) return;
                        if (!formKey.currentState!.validate()) return;
                        setModalState(() => isSaving = true);
                        try {
                          final customer = await _createCustomer(
                            name: nameCtrl.text.trim(),
                            phone: phoneCtrl.text.trim(),
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          await _showCustomerCreatedSuccess(customer);
                        } catch (e, st) {
                          AppErrorReporter.report(
                            e,
                            st,
                            hint: 'customer_create',
                          );
                          if (ctx.mounted) {
                            final info = AppErrorMapper.describe(e);
                            await _showCustomerCreateErrorDialog(info.message);
                          }
                        } finally {
                          if (ctx.mounted) {
                            setModalState(() => isSaving = false);
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);
                                try {
                                  final customer = await _createCustomer(
                                    name: nameCtrl.text.trim(),
                                    phone: phoneCtrl.text.trim(),
                                  );
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  await _showCustomerCreatedSuccess(customer);
                                } catch (e, st) {
                                  AppErrorReporter.report(
                                    e,
                                    st,
                                    hint: 'customer_create',
                                  );
                                  if (ctx.mounted) {
                                    final info = AppErrorMapper.describe(e);
                                    await _showCustomerCreateErrorDialog(
                                      info.message,
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setModalState(() => isSaving = false);
                                  }
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(AppStrings.criarCliente),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
  }
}

enum _CustomerFilter { all, recent, top }

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.controller,
    required this.isSearching,
    required this.showClear,
    required this.filter,
    required this.totalCustomers,
    required this.visibleCustomers,
    required this.onSearchChanged,
    required this.onClear,
    required this.onFilterChanged,
    required this.onBack,
  });

  final TextEditingController controller;
  final bool isSearching;
  final bool showClear;
  final _CustomerFilter filter;
  final int totalCustomers;
  final int visibleCustomers;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final ValueChanged<_CustomerFilter> onFilterChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final resultLabel = controller.text.trim().isEmpty
        ? AppStrings.clientesCount(totalCustomers)
        : AppStrings.clientesVisibleCount(visibleCustomers, totalCustomers);

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      AppStrings.clientesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: onSearchChanged,
                decoration: InputDecoration(
                  hintText: AppStrings.buscarCliente,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.g500,
                    size: 22,
                  ),
                  suffixIcon: showClear
                      ? IconButton(
                          onPressed: onClear,
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Limpar pesquisa',
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide:
                        const BorderSide(color: AppColors.secondary, width: 2),
                  ),
                ),
              ),
              if (isSearching)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              const SizedBox(height: 10),
              Text(
                resultLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      icon: Icons.people_alt_rounded,
                      active: filter == _CustomerFilter.all,
                      onTap: () => onFilterChanged(_CustomerFilter.all),
                    ),
                    const SizedBox(width: 10),
                    _FilterChip(
                      label: 'Recentes',
                      icon: Icons.schedule_rounded,
                      active: filter == _CustomerFilter.recent,
                      onTap: () => onFilterChanged(_CustomerFilter.recent),
                    ),
                    const SizedBox(width: 10),
                    _FilterChip(
                      label: 'Top clientes',
                      icon: Icons.emoji_events_rounded,
                      active: filter == _CustomerFilter.top,
                      onTap: () => onFilterChanged(_CustomerFilter.top),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        active ? AppColors.primaryDarker : Colors.white.withValues(alpha: 0.95);
    final background = active ? null : Colors.white.withValues(alpha: 0.14);
    final borderColor =
        active ? AppColors.secondaryDark : Colors.white.withValues(alpha: 0.35);
    final overlay = active
        ? AppColors.secondary.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.12);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      overlayColor: MaterialStatePropertyAll(overlay),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          gradient: active ? AppTheme.goldGradient : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
