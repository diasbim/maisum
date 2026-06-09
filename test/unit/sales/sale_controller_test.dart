import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

class _FakeSaleRepository extends SaleRepository {
  _FakeSaleRepository({
    required AppDatabase db,
    required SaleDao saleDao,
    required this.onCreateSale,
  }) : super(db, saleDao);

  final Future<Sale> Function({
    required String customerId,
    required double amount,
  }) onCreateSale;

  @override
  Future<Sale> createSale({
    required String customerId,
    required double amount,
  }) {
    return onCreateSale(customerId: customerId, amount: amount);
  }
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository({
    required this.onGetById,
    required CustomerDao customerDao,
    required SyncDao syncDao,
  }) : super(customerDao, syncDao);

  final Future<Customer?> Function(String id) onGetById;

  @override
  Future<Customer?> getById(String id) => onGetById(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CustomerDao customerDao;
  late SyncDao syncDao;
  late SaleDao saleDao;

  setUp(() async {
    await setUpTestDatabase();
    customerDao = CustomerDao(AppDatabase.instance);
    syncDao = SyncDao(AppDatabase.instance);
    saleDao = SaleDao(AppDatabase.instance);
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test(
    'createSale sets AsyncError and rethrows when repository fails',
    () async {
      final connectivity = ConnectivityService(
        initialOnline: true,
        onConnectivityChanged: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      final repository = _FakeSaleRepository(
        db: AppDatabase.instance,
        saleDao: saleDao,
        onCreateSale: ({required customerId, required amount}) async {
          throw StateError('repo failed');
        },
      );

      final customerRepository = _FakeCustomerRepository(
        customerDao: customerDao,
        syncDao: syncDao,
        onGetById: (_) async => null,
      );

      final container = ProviderContainer(
        overrides: [
          saleRepositoryProvider.overrideWithValue(repository),
          customerRepositoryProvider.overrideWithValue(customerRepository),
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
      );
      addTearDown(() {
        connectivity.dispose();
        container.dispose();
      });

      await expectLater(
        container
            .read(saleControllerProvider.notifier)
            .createSale(customerId: 'cust-1', amount: 200),
        throwsA(isA<StateError>()),
      );

      final state = container.read(saleControllerProvider);
      expect(state, isA<AsyncError<SaleResult?>>());
    },
  );

  test(
    'createSale sets AsyncError and rethrows when customer lookup is null',
    () async {
      final connectivity = ConnectivityService(
        initialOnline: true,
        onConnectivityChanged: const Stream<List<ConnectivityResult>>.empty(),
        checkConnectivity: () async => [ConnectivityResult.wifi],
      );
      final repository = _FakeSaleRepository(
        db: AppDatabase.instance,
        saleDao: saleDao,
        onCreateSale: ({required customerId, required amount}) async {
          return Sale(
            id: 'sale-1',
            customerId: customerId,
            amount: amount,
            points: 2,
            createdAt: DateTime(2024, 1, 1),
          );
        },
      );

      final customerRepository = _FakeCustomerRepository(
        customerDao: customerDao,
        syncDao: syncDao,
        onGetById: (_) async => null,
      );

      final container = ProviderContainer(
        overrides: [
          saleRepositoryProvider.overrideWithValue(repository),
          customerRepositoryProvider.overrideWithValue(customerRepository),
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
      );
      addTearDown(() {
        connectivity.dispose();
        container.dispose();
      });

      await expectLater(
        container
            .read(saleControllerProvider.notifier)
            .createSale(customerId: 'cust-1', amount: 200),
        throwsA(isA<StateError>()),
      );

      final state = container.read(saleControllerProvider);
      expect(state, isA<AsyncError<SaleResult?>>());
    },
  );
}
