import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/customers/presentation/customers_controller.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

class _FakeSaleController extends SaleController {
  _FakeSaleController({this.onCreateSale});

  final Future<SaleResult> Function({
    required String customerId,
    required double amount,
  })? onCreateSale;
  int createSaleCalls = 0;

  @override
  Future<SaleResult?> build() async => null;

  @override
  Future<SaleResult> createSale({
    required String customerId,
    required double amount,
  }) async {
    createSaleCalls++;
    final handler = onCreateSale;
    if (handler != null) {
      return handler(customerId: customerId, amount: amount);
    }
    return SaleResult(
      sale: Sale(
        id: 'sale-1',
        customerId: customerId,
        amount: amount,
        points: 1,
        createdAt: DateTime(2024, 1, 1),
      ),
      customer: _customer('Ana Costa', '841000001', points: 13),
    );
  }
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository(this.onSaleSearch)
      : super(CustomerDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final Future<List<Customer>> Function(String query) onSaleSearch;
  final List<String> calls = [];

  @override
  Future<List<Customer>> searchForSale(String query) async {
    calls.add(query);
    return onSaleSearch(query);
  }
}

Customer _customer(String name, String phone, {int points = 0}) => Customer(
      id: 'id-$phone',
      name: name,
      phone: phone,
      totalPoints: points,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
    );

Widget _buildScreen(
  List<Customer> recentCustomers, {
  _FakeSaleController? saleController,
}) =>
    ProviderScope(
      overrides: [
        saleControllerProvider.overrideWith(
          () => saleController ?? _FakeSaleController(),
        ),
        recentCustomersProvider.overrideWith((ref) async => recentCustomers),
      ],
      child: const MaterialApp(home: NewSaleScreen()),
    );

Widget _buildScreenWithRouter(
  List<Customer> recentCustomers, {
  _FakeSaleController? saleController,
}) {
  final router = GoRouter(
    initialLocation: '/new-sale',
    routes: [
      GoRoute(path: '/new-sale', builder: (_, __) => const NewSaleScreen()),
      GoRoute(
        path: '/sale-success',
        builder: (_, __) =>
            const Scaffold(body: Text('sale-success-destination')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      saleControllerProvider.overrideWith(
        () => saleController ?? _FakeSaleController(),
      ),
      recentCustomersProvider.overrideWith((ref) async => recentCustomers),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await setUpTestDatabase();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  group('NewSaleScreen — recent customers', () {
    testWidgets(
      'shows recent customers before freeform search and selects one',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen([
            _customer('Ana Costa', '841000001', points: 12),
            _customer('Bruno Lopes', '842000002', points: 5),
          ]),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ana Costa'), findsOneWidget);
        expect(find.text('Bruno Lopes'), findsOneWidget);

        await tester.tap(find.text('Ana Costa'));
        await tester.pumpAndSettle();

        expect(find.text('Ana Costa'), findsOneWidget);
        expect(find.text('841000001'), findsOneWidget);
        expect(find.text(AppStrings.nomeOuTelefoneCliente), findsNothing);
      },
    );

    testWidgets('debounces sale search before querying customers', (
      tester,
    ) async {
      final repository = _FakeCustomerRepository(
        (query) async => [_customer('Ana Costa', '841000001', points: 12)],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            saleControllerProvider.overrideWith(_FakeSaleController.new),
            recentCustomersProvider.overrideWith((ref) async => const []),
            customerRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: NewSaleScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Ana');
      await tester.pump(const Duration(milliseconds: 200));

      expect(repository.calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(repository.calls, ['Ana']);
      expect(find.text('Ana Costa'), findsOneWidget);
    });

    testWidgets('prevents duplicate submit while first request is in-flight', (
      tester,
    ) async {
      final completer = Completer<SaleResult>();
      final controller = _FakeSaleController(
        onCreateSale: ({required customerId, required amount}) =>
            completer.future,
      );

      await tester.pumpWidget(
        _buildScreen([
          _customer('Ana Costa', '841000001', points: 12),
        ], saleController: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ana Costa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '200');
      await tester.pump();

      await tester.tap(find.text(AppStrings.confirmarVenda));
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(controller.createSaleCalls, 1);

      completer.complete(
        SaleResult(
          sale: Sale(
            id: 'sale-2',
            customerId: 'id-841000001',
            amount: 200,
            points: 2,
            createdAt: DateTime(2024, 1, 1),
          ),
          customer: _customer('Ana Costa', '841000001', points: 14),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('shows error feedback and re-enables submit after failure', (
      tester,
    ) async {
      final controller = _FakeSaleController(
        onCreateSale: ({required customerId, required amount}) async {
          throw StateError('forced failure');
        },
      );

      await tester.pumpWidget(
        _buildScreen([
          _customer('Ana Costa', '841000001', points: 12),
        ], saleController: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ana Costa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '200');
      await tester.pump();

      await tester.tap(find.text(AppStrings.confirmarVenda));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.erroGenerico), findsOneWidget);
      expect(find.text(AppStrings.confirmarVenda), findsOneWidget);

      await tester.tap(find.text(AppStrings.confirmarVenda));
      await tester.pump();

      expect(controller.createSaleCalls, 2);
    });

    testWidgets('navigates to success screen after confirming sale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _FakeSaleController();

      await tester.pumpWidget(
        _buildScreenWithRouter([
          _customer('Ana Costa', '841000001', points: 12),
        ], saleController: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ana Costa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '200');
      await tester.pump();

      await tester.tap(find.text(AppStrings.confirmarVenda));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('sale-success-destination'), findsOneWidget);
      expect(controller.createSaleCalls, 1);
    });
  });
}
