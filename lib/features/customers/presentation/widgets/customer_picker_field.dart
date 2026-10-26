import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_layout.dart';
import '../../../../design_system/components/maisum_sheet_header.dart';
import '../../../../design_system/components/maisum_text_field.dart';
import '../../domain/customer.dart';
import '../customers_controller.dart';

/// Picks a customer by name instead of asking for an id.
///
/// Customer ids are UUIDs (`_uuid.v4()`), so every screen that asked the
/// merchant to type one was unusable in practice — the visit report refused to
/// submit without a value nobody could produce. This field carries the id
/// internally and shows the merchant a name and a phone number.
class CustomerPickerField extends ConsumerWidget {
  const CustomerPickerField({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.hintText,
    this.helperText,
    this.optional = false,
    this.enabled = true,
  });

  final String label;
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;
  final String? hintText;
  final String? helperText;

  /// Adds a clear button and lets the sheet be dismissed without a choice.
  final bool optional;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final customer = selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          label: customer == null
              ? '$label. Nenhum cliente escolhido.'
              : '$label. ${customer.name} escolhido.',
          child: InkWell(
            onTap: enabled ? () => _openPicker(context, ref) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppControlSize.button,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: enabled ? AppColors.white : AppColors.g100,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: customer == null ? AppColors.g300 : AppColors.primary,
                  width: customer == null ? 1.2 : 1.6,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    customer == null
                        ? Icons.person_search_rounded
                        : Icons.person_rounded,
                    color: customer == null
                        ? AppColors.onSurfaceVariant
                        : AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: customer == null
                        ? Text(
                            hintText ?? 'Escolher cliente',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (customer.phone.trim().isNotEmpty)
                                Text(
                                  customer.phone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (customer != null && optional && enabled)
                    IconButton(
                      tooltip: 'Remover cliente',
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.onSurfaceVariant,
                      onPressed: () => onChanged(null),
                    )
                  else
                    const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _CustomerPickerSheet(
        title: label,
        selectedId: selected?.id,
      ),
    );
    if (picked != null) onChanged(picked);
  }
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet({required this.title, this.selectedId});

  final String title;
  final String? selectedId;

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Leaves room for the keyboard: the search field is the first thing the
    // merchant touches, and a fixed-height sheet would hide the results
    // behind it.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MaisUmSheetHeader(
                title: widget.title,
                subtitle: 'Procure pelo nome ou telemóvel.',
              ),
              const SizedBox(height: AppSpacing.md),
              MaisUmTextField(
                controller: _searchController,
                hintText: 'Procurar cliente',
                prefixIcon: const Icon(Icons.search_rounded),
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: ref.watch(customerSearchProvider(_query)).when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.secondary,
                    ),
                  ),
                  error: (_, __) => Center(
                    child: Text(
                      'Não foi possível carregar os clientes.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  data: (customers) {
                    if (customers.isEmpty) {
                      return Center(
                        child: Text(
                          _query.trim().isEmpty
                              ? 'Ainda não tem clientes registados.'
                              : 'Nenhum cliente encontrado.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.g100),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        final isSelected = customer.id == widget.selectedId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          minVerticalPadding: AppSpacing.md,
                          selected: isSelected,
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                          title: Text(
                            customer.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: customer.phone.trim().isEmpty
                              ? null
                              : Text(
                                  customer.phone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                          onTap: () => Navigator.pop(context, customer),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
