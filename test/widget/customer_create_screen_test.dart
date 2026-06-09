import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/customers/presentation/customer_create_screen.dart';
import 'package:maisum/features/customers/presentation/customers_controller.dart';

class _FakeCustomersController extends CustomersController {
  @override
  Future<List<Customer>> build() async => const [];

  @override
  Future<Customer> createCustomer({
    required String name,
    required String phone,
  }) async {
    return Customer(
      id: 'customer-1',
      name: name,
      phone: phone,
      createdAt: DateTime(2024, 1, 1),
    );
  }
}

Widget _buildApp() {
  final router = GoRouter(
    initialLocation: '/customers/create',
    routes: [
      GoRoute(
        path: '/customers/create',
        builder: (_, __) => const CustomerCreateScreen(
          resumeSaleFlow: true,
          returnRoute: '/new-sale',
        ),
      ),
      GoRoute(
        path: '/new-sale',
        builder: (_, state) => Scaffold(
          body: Text('new-sale:${state.extra != null}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      customersControllerProvider.overrideWith(_FakeCustomersController.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('auto returns to sale flow after customer is created',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana Costa');
    await tester.enterText(find.byType(TextFormField).at(1), '841234567');
    await tester.tap(find.text('Criar cliente'));
    await tester.pumpAndSettle();

    expect(find.text('new-sale:true'), findsOneWidget);
  });
}
