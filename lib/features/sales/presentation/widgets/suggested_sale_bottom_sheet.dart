import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/moz_phone_utils.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../domain/suggested_sale.dart';

class SuggestedSaleBottomSheet extends StatelessWidget {
  const SuggestedSaleBottomSheet({
    super.key,
    required this.suggestion,
    required this.onConfirm,
    required this.onIgnore,
    required this.onManual,
  });

  final SuggestedSale suggestion;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customerName = suggestion.customer?.name ?? 'Cliente';
    final phone = suggestion.customer?.phone ?? suggestion.transaction.phone;
    final maskedPhone =
        phone == null ? null : MozPhoneUtils.maskForDisplay(phone);
    final amount = suggestion.transaction.amount.toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.g300,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: BrandMark(size: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Venda sugerida',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Recebido $amount MT de $customerName',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adicionar ${suggestion.points} pontos?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (maskedPhone != null && maskedPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_rounded,
                    size: 16, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  maskedPhone,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onIgnore,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    side: const BorderSide(color: AppColors.g300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Ignorar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onManual,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            child: const Text('Selecionar cliente'),
          ),
        ],
      ),
    );
  }
}
