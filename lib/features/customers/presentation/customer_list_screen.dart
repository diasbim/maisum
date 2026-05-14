import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/customer_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: customers.when(
        data: (list) {
          final filtered = _applyFilter(list);
          return RefreshIndicator(
            color: AppColors.secondary,
            onRefresh: () =>
                ref.read(customersControllerProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _CustomerHeader(
                    controller: _searchCtrl,
                    showClear: _searchCtrl.text.isNotEmpty,
                    filter: _filter,
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
                    onBack: () => context.pop(),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: AppStrings.semClientes,
                      subtitle:
                          'Crie o primeiro cliente para começar a registar cortes e pontos sem complicação.',
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
        error: (e, _) => Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.tentar),
            onPressed: () =>
                ref.read(customersControllerProvider.notifier).refresh(),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddCustomerSheet(context),
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primaryDarker,
          icon: const Icon(Icons.person_add_rounded),
          label: const Text(
            'Cliente',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
      ref.read(customersControllerProvider.notifier).search('');
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(customersControllerProvider.notifier).search(query);
    });
  }

  void _showAddCustomerSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final theme = Theme.of(context);
    var isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
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
                    decoration: const InputDecoration(
                      labelText: AppStrings.phoneNumber,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? AppStrings.phoneRequired
                        : null,
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
                                await ref
                                    .read(customersControllerProvider.notifier)
                                    .createCustomer(
                                      name: nameCtrl.text.trim(),
                                      phone: phoneCtrl.text.trim(),
                                    );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                              } catch (e, st) {
                                AppErrorReporter.report(
                                  e,
                                  st,
                                  hint: 'customer_create',
                                );
                                if (ctx.mounted) {
                                  final info = AppErrorMapper.describe(e);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(info.message)),
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
          );
        },
      ),
    );
  }
}

enum _CustomerFilter { all, recent, top }

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.controller,
    required this.showClear,
    required this.filter,
    required this.onSearchChanged,
    required this.onClear,
    required this.onFilterChanged,
    required this.onBack,
  });

  final TextEditingController controller;
  final bool showClear;
  final _CustomerFilter filter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;
  final ValueChanged<_CustomerFilter> onFilterChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    AppStrings.clientesTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: AppStrings.buscarCliente,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.g500,
                    size: 22,
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          color: AppColors.primary,
                        ),
                        if (showClear) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: onClear,
                            icon: const Icon(Icons.close_rounded),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints.tightFor(width: 28),
                          ),
                        ],
                      ],
                    ),
                  ),
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
              const SizedBox(height: 16),
              Row(
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

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
