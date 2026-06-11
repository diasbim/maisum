import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

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

Future<Customer> _insertCustomer(String name, String phone) {
  return CustomerDao(AppDatabase.instance).create(name: name, phone: phone);
}

Future<void> _insertSale({
  required String customerId,
  double amount = 200,
}) async {
  await SaleDao(AppDatabase.instance)
      .create(customerId: customerId, amount: amount);
}

Widget _buildScreen({
  NewSaleArgs? args,
  _FakeSaleController? saleController,
}) {
  return ProviderScope(
    overrides: [
      saleControllerProvider.overrideWith(
        () => saleController ?? _FakeSaleController(),
      ),
    ],
    child: MaterialApp(home: NewSaleScreen(args: args)),
  );
}

Widget _buildScreenWithRouter() {
  final router = GoRouter(
    initialLocation: '/new-sale',
    routes: [
      GoRoute(path: '/new-sale', builder: (_, __) => const NewSaleScreen()),
      GoRoute(
        path: '/customers/create',
        builder: (_, state) => Scaffold(
          body: Text(
              'customer-create:${state.uri.queryParameters['"' "'resumeSaleFlow'" '"']}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      saleControllerProvider.overrideWith(_FakeSaleController.new),
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

  group('NewSaleScreen UX flow', () {
    testWidgets('opens customer selector automatically when customers exist', (
      tester,
    ) async {
      await _insertCustomer('Ana Silva', '841000001');
      await _insertCustomer('Bruno Lima', '842000002');

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Selecionar cliente'), findsOneWidget);
      expect(find.text('Escolha um cliente'), findsNothing);
    });

    testWidgets('auto-selects last used customer and shows amount section', (
      tester,
    ) async {
      final first = await _insertCustomer('Ana Silva', '841000001');
      final last = await _insertCustomer('Carlos Dias', '843000003');
      await _insertSale(customerId: first.id, amount: 100);
      await _insertSale(customerId: last.id, amount: 200);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      final created = await _insertCustomer('Carlos', '845000005');

      await tester.pumpWidget(
        _buildScreen(args: NewSaleArgs(preselectedCustomerId: created.id)),
      );
      await tester.pumpAndSettle();

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
      await _insertCustomer('Ana Silva', '841000001');
      await _insertCustomer('Bruno Lima', '842000002');

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bruno Lima'));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adicionar Cliente').first);
      await tester.pumpAndSettle();

      expect(find.text('customer-create:1'), findsOneWidget);
    });
  });
}
