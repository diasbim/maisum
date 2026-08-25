import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../design_system/design_system.dart';
import '../domain/merchant_item.dart';

class MerchantCatalogScreen extends ConsumerWidget {
  const MerchantCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/dashboard'),
          ),
          title: const Text('Produtos e serviços'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Serviços'),
              Tab(text: 'Produtos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CatalogTab(type: MerchantItemType.service),
            _CatalogTab(type: MerchantItemType.product),
          ],
        ),
      ),
    );
  }
}

class _CatalogTab extends ConsumerWidget {
  const _CatalogTab({required this.type});

  final MerchantItemType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(
      type == MerchantItemType.service
          ? merchantCatalogServicesProvider
          : merchantCatalogProductsProvider,
    );
    final title = type == MerchantItemType.service ? 'Serviço' : 'Produto';

    return itemsAsync.when(
      data: (items) => RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            MaisUmButton(
              onPressed: () => _openEditor(context, ref),
              label: 'Adicionar $title',
              leadingIcon: Icons.add_rounded,
              variant: MaisUmButtonVariant.secondary,
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              EmptyState(
                title: 'Nenhum ${title.toLowerCase()} cadastrado',
                subtitle: 'Crie itens para selecionar durante uma venda.',
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CatalogItemCard(
                    item: item,
                    onEdit: () => _openEditor(context, ref, item: item),
                    onToggleActive: () => _toggleActive(context, ref, item),
                    onDelete: () => _delete(context, ref, item),
                  ),
                ),
              ),
          ],
        ),
      ),
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.secondary),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: MaisUmButton(
            onPressed: () => _refresh(ref),
            label: AppStrings.tentar,
            leadingIcon: Icons.refresh_rounded,
            variant: MaisUmButtonVariant.outlined,
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    MerchantItem? item,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CatalogItemSheet(type: type, item: item),
    );
    if (saved == true) _refresh(ref);
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    MerchantItem item,
  ) async {
    await ref.read(merchantCatalogRepositoryProvider).update(
          item.id,
          isActive: !item.isActive,
        );
    ref.read(syncServiceProvider).processQueue();
    _refresh(ref);
    if (!context.mounted) return;
    AppFeedback.showMessage(
      context,
      message: item.isActive ? 'Item desativado.' : 'Item ativado.',
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MerchantItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar item'),
        content: Text('Apagar "${item.name}" do catálogo?'),
        actions: [
          MaisUmButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: 'Cancelar',
            variant: MaisUmButtonVariant.ghost,
            fullWidth: false,
            height: 40,
          ),
          MaisUmButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: 'Apagar',
            variant: MaisUmButtonVariant.danger,
            fullWidth: false,
            height: 40,
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted =
        await ref.read(merchantCatalogRepositoryProvider).delete(item.id);
    ref.read(syncServiceProvider).processQueue();
    _refresh(ref);
    if (!context.mounted) return;
    AppFeedback.showMessage(
      context,
      message: deleted
          ? 'Item apagado.'
          : 'Item já usado em vendas. Desative-o em vez de o apagar.',
      isError: !deleted,
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(merchantCatalogServicesProvider);
    ref.invalidate(merchantCatalogProductsProvider);
    ref.invalidate(activeMerchantItemsProvider);
  }
}

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final MerchantItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final price = item.defaultPrice == null
        ? 'Sem preço padrão'
        : '${item.defaultPrice!.toStringAsFixed(0)} ${AppStrings.moedaMzn}';
    return MaisUmSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: AppRadius.lg,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.isActive
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.g100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.type == MerchantItemType.service
                  ? Icons.room_service_rounded
                  : Icons.inventory_2_rounded,
              color: item.isActive ? AppColors.primary : AppColors.g500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.isActive ? price : '$price · Inativo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: item.isActive
                            ? AppColors.onSurfaceVariant
                            : AppColors.g500,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: item.isActive ? 'Desativar' : 'Ativar',
            onPressed: onToggleActive,
            icon: Icon(
              item.isActive
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Apagar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _CatalogItemSheet extends ConsumerStatefulWidget {
  const _CatalogItemSheet({required this.type, this.item});

  final MerchantItemType type;
  final MerchantItem? item;

  @override
  ConsumerState<_CatalogItemSheet> createState() => _CatalogItemSheetState();
}

class _CatalogItemSheetState extends ConsumerState<_CatalogItemSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _priceCtrl = TextEditingController(
      text: item?.defaultPrice == null
          ? ''
          : item!.defaultPrice!.toStringAsFixed(0),
    );
    _isActive = item?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.item == null ? 'Novo item' : 'Editar item';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Preço padrão opcional',
              suffixText: AppStrings.moedaMzn,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            title: const Text('Ativo'),
            onChanged: (value) => setState(() => _isActive = value),
          ),
          const SizedBox(height: 12),
          MaisUmButton(
            onPressed: _saving ? null : _save,
            label: 'Guardar',
            isLoading: _saving,
            leadingIcon: Icons.check_rounded,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppFeedback.showMessage(
        context,
        message: 'Informe o nome do item.',
        isError: true,
      );
      return;
    }
    final priceText = _priceCtrl.text.trim().replaceAll(',', '.');
    final price = priceText.isEmpty ? null : double.tryParse(priceText);
    if (priceText.isNotEmpty && price == null) {
      AppFeedback.showMessage(
        context,
        message: 'Preço inválido.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(merchantCatalogRepositoryProvider);
      final item = widget.item;
      if (item == null) {
        await repo.save(
          name: name,
          type: widget.type,
          defaultPrice: price,
          isActive: _isActive,
        );
      } else {
        await repo.update(
          item.id,
          name: name,
          defaultPrice: price,
          isActive: _isActive,
        );
      }
      ref.read(syncServiceProvider).processQueue();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showMessage(
        context,
        message: AppStrings.erroGenerico,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
