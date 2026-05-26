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

class SaleController extends AsyncNotifier<SaleResult?> {
  @override
  Future<SaleResult?> build() async => null;

  Future<SaleResult> createSale({
    required String customerId,
    required double amount,
  }) async {
    if (amount < 1) throw ArgumentError(AppStrings.amountInvalid);
    state = const AsyncLoading();

    final sale = await ref.read(saleRepositoryProvider).createSale(
          customerId: customerId,
          amount: amount,
        );

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
        properties: {
          'days': streak.days,
          'at_risk': streak.isAtRisk,
        },
      );
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'sale_analytics');
    }

    final customer =
        await ref.read(customerRepositoryProvider).getById(customerId);

    // Refresh customer detail and sales list so UI reflects new points instantly
    ref.invalidate(customerDetailProvider(customerId));
    ref.invalidate(customerSalesProvider(customerId));
    ref.invalidate(allSalesWithCustomerProvider);

    // Trigger background sync
    ref.read(syncServiceProvider).processQueue();

    final result = SaleResult(
      sale: sale,
      customer: customer!,
    );
    state = AsyncData(result);
    return result;
  }

  void reset() => state = const AsyncData(null);
}

final saleControllerProvider =
    AsyncNotifierProvider<SaleController, SaleResult?>(SaleController.new);
