import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../subscription/domain/usage_metrics.dart';
import '../domain/sale.dart';
import '../../customers/domain/customer.dart';
import '../../customers/presentation/customers_controller.dart';

class SaleResult {
  const SaleResult({required this.sale, required this.customer});
  final Sale sale;
  final Customer customer;
}

enum SaleStep {
  customer,
  amount,
  confirmation,
  completed,
}

enum StepStatus {
  pending,
  active,
  completed,
}

class NewSaleFlowState {
  const NewSaleFlowState({
    required this.selectedCustomer,
    required this.selectedAmount,
    this.completed = false,
  });

  final Customer? selectedCustomer;
  final double? selectedAmount;
  final bool completed;

  SaleStep get currentStep {
    if (completed) {
      return SaleStep.completed;
    }
    if (selectedCustomer == null) {
      return SaleStep.customer;
    }
    if (selectedAmount == null || selectedAmount! <= 0) {
      return SaleStep.amount;
    }
    return SaleStep.confirmation;
  }

  StepStatus getCustomerStepStatus() {
    if (completed || selectedCustomer != null) {
      return StepStatus.completed;
    }
    return StepStatus.active;
  }

  StepStatus getAmountStepStatus() {
    if (completed) {
      return StepStatus.completed;
    }
    if (selectedCustomer == null) {
      return StepStatus.pending;
    }
    if (selectedAmount != null && selectedAmount! > 0) {
      return StepStatus.completed;
    }
    return StepStatus.active;
  }

  StepStatus getConfirmStepStatus() {
    if (completed) {
      return StepStatus.completed;
    }
    if (selectedCustomer == null) {
      return StepStatus.pending;
    }
    if (selectedAmount == null || selectedAmount! <= 0) {
      return StepStatus.pending;
    }
    return StepStatus.active;
  }
}

class SaleController extends AsyncNotifier<SaleResult?> {
  @override
  Future<SaleResult?> build() async => null;

  Future<SaleResult> createSale({
    required String customerId,
    required double amount,
  }) async {
    if (amount < 1) throw ArgumentError(AppStrings.amountInvalid);
    state = const AsyncLoading();

    try {
      final sale = await ref
          .read(saleRepositoryProvider)
          .createSale(customerId: customerId, amount: amount);

      try {
        await ref.read(usageTrackerProvider).record(
          metricKey: UsageMetrics.salesCount,
          quantity: 1,
          source: 'sale',
          metadata: {'amount': amount},
        );
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'sale_usage_metric');
      }

      try {
        await ref.read(analyticsServiceProvider).record(
          eventType: 'sale_registered',
          source: 'sale',
          properties: {'amount': amount, 'points': sale.points},
        );
        await ref.read(analyticsServiceProvider).record(
          eventType: 'sale_registration_completed',
          source: 'sale',
          properties: {
            'amount': amount,
            'points': sale.points,
            'customer_id': customerId,
          },
        );
        final streak = await ref.read(streakServiceProvider).getCurrentStreak();
        await ref.read(analyticsServiceProvider).record(
          eventType: 'streak_updated',
          source: 'sale',
          properties: {'days': streak.days, 'at_risk': streak.isAtRisk},
        );
      } catch (e, st) {
        AppErrorReporter.report(e, st, hint: 'sale_analytics');
      }

      final customer =
          await ref.read(customerRepositoryProvider).getById(customerId);
      if (customer == null) {
        throw StateError('Customer not found after sale creation');
      }

      // Refresh customer detail and sales list so UI reflects new points instantly
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customerSalesProvider(customerId));
      ref.invalidate(allSalesWithCustomerProvider);

      // Trigger background sync
      ref.read(syncServiceProvider).processQueue();

      final result = SaleResult(sale: sale, customer: customer);
      state = AsyncData(result);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  void reset() => state = const AsyncData(null);
}

final saleControllerProvider =
    AsyncNotifierProvider<SaleController, SaleResult?>(SaleController.new);
