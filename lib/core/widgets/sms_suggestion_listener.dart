import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/sales/domain/suggested_sale.dart';
import '../../features/sales/presentation/sale_controller.dart';
import '../../features/sales/presentation/sale_success_screen.dart';
import '../../features/sales/presentation/new_sale_screen.dart';
import '../../features/sales/presentation/widgets/suggested_sale_bottom_sheet.dart';
import '../errors/app_error_mapper.dart';
import '../errors/app_error_reporter.dart';
import 'app_feedback.dart';

class SmsSuggestionListener extends ConsumerStatefulWidget {
  const SmsSuggestionListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SmsSuggestionListener> createState() =>
      _SmsSuggestionListenerState();
}

class _SmsSuggestionListenerState extends ConsumerState<SmsSuggestionListener> {
  final Queue<SuggestedSale> _queue = Queue<SuggestedSale>();
  bool _isShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(smsListenerServiceProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(smsSuggestionStreamProvider, (previous, next) {
      final suggestion = next.valueOrNull;
      if (suggestion == null) return;

      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) return;

      _queue.add(suggestion);
      try {
        ref.read(analyticsServiceProvider).record(
          eventType: 'sale_suggested',
          source: 'sms',
          properties: {
            'amount': suggestion.transaction.amount,
            'provider': suggestion.transaction.provider,
            'match_reason': suggestion.matchReason,
          },
        );
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'sms_suggestion_analytics');
      }
      if (!_isShowing) {
        _showNext();
      }
    });

    return widget.child;
  }

  Future<void> _showNext() async {
    if (_queue.isEmpty || _isShowing) return;

    _isShowing = true;
    final suggestion = _queue.removeFirst();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SuggestedSaleBottomSheet(
        suggestion: suggestion,
        onConfirm: () => _confirmSuggestion(sheetContext, suggestion),
        onManual: () => _manualSuggestion(sheetContext, suggestion),
        onIgnore: () => Navigator.of(sheetContext).pop(),
      ),
    );

    _isShowing = false;
    if (_queue.isNotEmpty && mounted) {
      _showNext();
    }
  }

  Future<void> _confirmSuggestion(
    BuildContext sheetContext,
    SuggestedSale suggestion,
  ) async {
    final customer = suggestion.customer;
    if (customer == null) {
      await _manualSuggestion(sheetContext, suggestion);
      return;
    }

    final saleCtrl = ref.read(saleControllerProvider.notifier);
    try {
      final result = await saleCtrl.createSale(
        customerId: customer.id,
        amount: suggestion.transaction.amount,
      );
      saleCtrl.reset();
      if (!mounted) return;

      try {
        ref.read(analyticsServiceProvider).record(
          eventType: 'sale_suggestion_accepted',
          source: 'sms',
          properties: {
            'amount': suggestion.transaction.amount,
            'provider': suggestion.transaction.provider,
            'match_reason': suggestion.matchReason,
          },
        );
      } catch (e, st) {
        AppErrorReporter.report(
          e,
          st,
          hint: 'sms_suggestion_accepted_analytics',
        );
      }

      Navigator.of(sheetContext).pop();
      if (!mounted) return;
      context.go('/sale-success', extra: SaleSuccessArgs(result: result));
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'sms_suggestion_confirm');
      if (!mounted) return;
      final info = AppErrorMapper.describe(e);
      AppFeedback.showRetryableError(
        context,
        message: info.message,
        onRetry: () {
          unawaited(_confirmSuggestion(sheetContext, suggestion));
        },
      );
    }
  }

  Future<void> _manualSuggestion(
    BuildContext sheetContext,
    SuggestedSale suggestion,
  ) async {
    Navigator.of(sheetContext).pop();
    if (!mounted) return;
    context.push(
      '/new-sale',
      extra: NewSaleArgs(prefilledAmount: suggestion.transaction.amount),
    );
  }
}
