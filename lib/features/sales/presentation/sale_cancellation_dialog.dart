import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/widgets/app_feedback.dart';
import '../domain/sale.dart';
import 'sale_controller.dart';

Future<bool> showSaleCancellationDialog(
  BuildContext context,
  WidgetRef ref,
  Sale sale,
) async {
  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _SaleCancellationDialog(
      ref: ref,
      sale: sale,
    ),
  );
  return cancelled == true;
}

class _SaleCancellationDialog extends StatefulWidget {
  const _SaleCancellationDialog({
    required this.ref,
    required this.sale,
  });

  final WidgetRef ref;
  final Sale sale;

  @override
  State<_SaleCancellationDialog> createState() =>
      _SaleCancellationDialogState();
}

class _SaleCancellationDialogState extends State<_SaleCancellationDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _validationError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _validationError = 'O motivo é obrigatório.');
      return;
    }

    setState(() {
      _submitting = true;
      _validationError = null;
    });
    try {
      await widget.ref.read(saleControllerProvider.notifier).cancelSale(
            saleId: widget.sale.id,
            customerId: widget.sale.customerId,
            reason: reason,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.showMessage(
          context,
          message: error.toString(),
          isError: true,
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Anular venda'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O lançamento original será preservado e os pontos serão '
            'revertidos. Indique o motivo da correção.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: 'Motivo da anulação',
              errorText: _validationError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Anular venda'),
        ),
      ],
    );
  }
}
