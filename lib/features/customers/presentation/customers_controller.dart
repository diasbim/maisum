import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_exception.dart';
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
    state = await AsyncValue.guard(_load);
  }

  Future<Customer> createCustomer({
    required String name,
    required String phone,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty) throw ArgumentError(AppStrings.nameRequired);

    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .createCustomer(name: trimmedName, phone: trimmedPhone);
      state = await AsyncValue.guard(_load);
      ref.read(syncServiceProvider).processQueue();
      return customer;
    } on sqflite.DatabaseException catch (e) {
      final raw = e.toString().toLowerCase();
      if (raw.contains('idx_customers_scope_phone') ||
          raw.contains('unique constraint failed')) {
        throw const DatabaseException(AppStrings.customerPhoneDuplicate);
      }
      rethrow;
    }
  }

  Future<void> updateCustomer(
    String id, {
    required String name,
    required String phone,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty) throw ArgumentError(AppStrings.nameRequired);

    try {
      await ref
          .read(customerRepositoryProvider)
          .updateCustomer(id, name: trimmedName, phone: trimmedPhone);
    } on sqflite.DatabaseException catch (e) {
      final raw = e.toString().toLowerCase();
      if (raw.contains('idx_customers_scope_phone') ||
          raw.contains('unique constraint failed')) {
        throw const DatabaseException(AppStrings.customerPhoneDuplicate);
      }
      rethrow;
    }
    ref.invalidate(customerDetailProvider(id));
    state = await AsyncValue.guard(_load);
    ref.read(syncServiceProvider).processQueue();
  }

  Future<void> refresh() async {
    _query = '';
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<Customer>>(
  CustomersController.new,
);

final customerDetailProvider = FutureProvider.family<Customer?, String>((
  ref,
  id,
) {
  return ref.read(customerRepositoryProvider).getById(id);
});

final customerSalesProvider = FutureProvider.family<List<Sale>, String>((
  ref,
  customerId,
) {
  return ref.read(saleDaoProvider).getByCustomer(customerId);
});

final recentCustomersProvider = FutureProvider<List<Customer>>((ref) {
  return ref.read(customerRepositoryProvider).getRecent(limit: 6);
});
