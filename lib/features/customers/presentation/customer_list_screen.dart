import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/customer_card.dart';
import '../../../core/widgets/empty_state.dart';
import 'customers_controller.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text(AppStrings.clientesTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: AppStrings.buscarCliente,
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.g500, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                          ref
                              .read(customersControllerProvider.notifier)
                              .search('');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.g100),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.g100),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.secondary, width: 2),
                ),
              ),
              onChanged: (q) {
                setState(() {});
                ref.read(customersControllerProvider.notifier).search(q);
              },
            ),
          ),
        ),
      ),
      body: customers.when(
        data: (list) => list.isEmpty
            ? EmptyState(
                title: AppStrings.semClientes,
                actionLabel: AppStrings.adicionarCliente,
                onAction: () => _showAddCustomerSheet(context),
              )
            : RefreshIndicator(
                color: AppColors.secondary,
                onRefresh: () =>
                    ref.read(customersControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => CustomerCard(
                    name: list[i].name,
                    phone: list[i].phone,
                    totalPoints: list[i].totalPoints,
                    onTap: () => context.push('/customers/${list[i].id}'),
                  ),
                ),
              ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.secondary)),
        error: (e, _) => Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text(AppStrings.tentar),
            onPressed: () =>
                ref.read(customersControllerProvider.notifier).refresh(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCustomerSheet(context),
        child: const Icon(Icons.person_add_rounded),
      ),
    );
  }

  void _showAddCustomerSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: AppColors.g300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(AppStrings.adicionarCliente,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: AppStrings.nome, hintText: AppStrings.nomeHint),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.nameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: AppStrings.phoneNumber),
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
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    await ref
                        .read(customersControllerProvider.notifier)
                        .createCustomer(
                          name: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim(),
                        );
                  },
                  child: const Text(AppStrings.criarCliente),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
