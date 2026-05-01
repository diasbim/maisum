import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';
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
    state = const AsyncLoading();

    final sale = await ref.read(saleRepositoryProvider).createSale(
          customerId: customerId,
          amount: amount,
        );

    final customer = await ref.read(customerRepositoryProvider).getById(customerId);

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
