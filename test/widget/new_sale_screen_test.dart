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
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

class _FakeSaleController extends SaleController {
  _FakeSaleController({this.onCreateSale});

  final Future<SaleResult> Function({
    required String customerId,
    required double amount,
  })? onCreateSale;

  @override
  Future<SaleResult?> build() async => null;

  @override
  Future<SaleResult> createSale({
    required String customerId,
    required double amount,
  }) async {
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
      customer: Customer(
        id: customerId,
        name: 'Ana Silva',
        phone: '841000001',
        totalPoints: 13,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
      ),
    );
  }
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository(this.customers)
      : super(CustomerDao(AppDatabase.instance), SyncDao(AppDatabase.instance));

  final List<Customer> customers;

  @override
  Future<List<Customer>> getAll() async => customers;

  @override
  Future<Customer?> getById(String id) async {
    for (final customer in customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }
}

class _FakeSaleDao extends SaleDao {
  _FakeSaleDao({this.latestSale}) : super(AppDatabase.instance);

  final Map<String, dynamic>? latestSale;

  @override
  Future<Map<String, dynamic>?> getLatestWithCustomer() async => latestSale;
}

Future<void> _pumpSaleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _buildScreen({
  NewSaleArgs? args,
  _FakeSaleController? saleController,
  List<Customer> customers = const [],
  Map<String, dynamic>? latestSale,
}) {
  return ProviderScope(
    overrides: [
      customerRepositoryProvider.overrideWithValue(
        _FakeCustomerRepository(customers),
      ),
      saleDaoProvider.overrideWithValue(_FakeSaleDao(latestSale: latestSale)),
      saleControllerProvider.overrideWith(
        () => saleController ?? _FakeSaleController(),
      ),
    ],
    child: MaterialApp(home: NewSaleScreen(args: args)),
  );
}

Widget _buildScreenWithRouter({List<Customer> customers = const []}) {
  final router = GoRouter(
    initialLocation: '/new-sale',
    routes: [
      GoRoute(path: '/new-sale', builder: (_, __) => const NewSaleScreen()),
      GoRoute(
        path: '/customers/create',
        builder: (_, state) => Scaffold(
          body: Text(
            'customer-create:${state.uri.queryParameters['resumeSaleFlow']}',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      customerRepositoryProvider.overrideWithValue(
        _FakeCustomerRepository(customers),
      ),
      saleDaoProvider.overrideWithValue(_FakeSaleDao()),
      saleControllerProvider.overrideWith(_FakeSaleController.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Customer _customer(String id, String name, String phone) {
  return Customer(
    id: id,
    name: name,
    phone: phone,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 2),
  );
}

Map<String, dynamic> _latestSaleFor(Customer customer, double amount) => {
      'customer_id': customer.id,
      'amount': amount,
    };

void main() {
  group('NewSaleScreen UX flow', () {
    testWidgets('opens customer selector automatically when customers exist', (
      tester,
    ) async {
      final customers = [
        _customer('customer-1', 'Ana Silva', '841000001'),
        _customer('customer-2', 'Bruno Lima', '842000002'),
      ];

      await tester.pumpWidget(_buildScreen(customers: customers));
      await _pumpSaleUi(tester);

      expect(find.text('Selecionar cliente'), findsWidgets);
      expect(find.text('Escolha um cliente'), findsNothing);

      await tester.tap(find.text('Ana Silva'));
      await _pumpSaleUi(tester);
    });

    testWidgets('auto-selects last used customer and shows amount section', (
      tester,
    ) async {
      final first = _customer('customer-1', 'Ana Silva', '841000001');
      final last = _customer('customer-2', 'Carlos Dias', '843000003');

      await tester.pumpWidget(
        _buildScreen(
          customers: [first, last],
          latestSale: _latestSaleFor(last, 200),
        ),
      );
      await _pumpSaleUi(tester);

      expect(find.text('Cliente Selecionado'), findsOneWidget);
      expect(find.text('Carlos Dias'), findsOneWidget);
      expect(find.text('843000003'), findsOneWidget);
      expect(find.text('Alterar'), findsOneWidget);
      expect(find.text('2. ${AppStrings.valor}'), findsOneWidget);
      expect(find.text('Selecionar cliente'), findsNothing);
    });

    testWidgets('shows dedicated empty state when no customers exist', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreenWithRouter());
      await _pumpSaleUi(tester);

      expect(find.text('Nenhum cliente registado'), findsOneWidget);
      expect(
        find.text('Para registrar uma venda, adicione primeiro um cliente.'),
        findsOneWidget,
      );
      expect(find.text('Adicionar Cliente'), findsWidgets);
      expect(find.text('2. ${AppStrings.valor}'), findsNothing);
    });

    testWidgets('resumes with preselected customer and starts at step 2', (
      tester,
    ) async {
      final created = _customer('customer-1', 'Carlos', '845000005');

      await tester.pumpWidget(
        _buildScreen(
          args: NewSaleArgs(preselectedCustomerId: created.id),
          customers: [created],
        ),
      );
      await _pumpSaleUi(tester);

      expect(find.text('Cliente Selecionado'), findsOneWidget);
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('845000005'), findsOneWidget);
      expect(find.text('2. ${AppStrings.valor}'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('selecting customer updates stepper and reveals amount options',
        (
      tester,
    ) async {
      final customers = [
        _customer('customer-1', 'Ana Silva', '841000001'),
        _customer('customer-2', 'Bruno Lima', '842000002'),
      ];

      await tester.pumpWidget(_buildScreen(customers: customers));
      await _pumpSaleUi(tester);

      await tester.tap(find.text('Bruno Lima'));
      await _pumpSaleUi(tester);

      expect(find.text('Cliente Selecionado'), findsOneWidget);
      expect(find.text('Bruno Lima'), findsOneWidget);
      expect(find.text('Escolha um valor'), findsOneWidget);
      expect(find.text('2. ${AppStrings.valor}'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('add customer CTA routes to create flow with resume flag', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreenWithRouter());
      await _pumpSaleUi(tester);

      await tester.tap(find.text('Adicionar Cliente').first);
      await _pumpSaleUi(tester);

      expect(find.text('customer-create:1'), findsOneWidget);
    });
  });
}
