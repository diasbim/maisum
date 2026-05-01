import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../app/providers.dart';
import '../domain/customer.dart';
import '../../sales/domain/sale.dart';

class CustomersController extends AsyncNotifier<List<Customer>> {
  String _query = '';

  @override
  Future<List<Customer>> build() => _load();

  Future<List<Customer>> _load() async {
    if (_query.isEmpty) {
      return ref.read(customerRepositoryProvider).getAll();
    }
    return ref.read(customerRepositoryProvider).search(_query);
  }

  Future<void> search(String query) async {
    _query = query;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<Customer> createCustomer({
    required String name,
    required String phone,
  }) async {
    final customer = await ref
        .read(customerRepositoryProvider)
        .createCustomer(name: name, phone: phone);
    state = await AsyncValue.guard(_load);
    return customer;
  }

  Future<void> refresh() async {
    _query = '';
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<Customer>>(
        CustomersController.new);

final customerDetailProvider =
    FutureProvider.family<Customer?, String>((ref, id) {
  return ref.read(customerRepositoryProvider).getById(id);
});

final customerSalesProvider =
    FutureProvider.family<List<Sale>, String>((ref, customerId) {
  return ref.read(saleDaoProvider).getByCustomer(customerId);
});
