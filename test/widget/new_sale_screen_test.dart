import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loyalty_app/app/providers.dart';
import 'package:loyalty_app/core/database/app_database.dart';
import 'package:loyalty_app/features/customers/data/customer_dao.dart';
import 'package:loyalty_app/features/customers/data/customer_repository.dart';
import 'package:loyalty_app/features/customers/domain/customer.dart';
import 'package:loyalty_app/features/customers/presentation/customers_controller.dart';
import 'package:loyalty_app/features/sales/presentation/new_sale_screen.dart';
import 'package:loyalty_app/features/sales/presentation/sale_controller.dart';
import 'package:loyalty_app/features/sync/data/sync_dao.dart';

class _FakeSaleController extends SaleController {
  @override
  Future<SaleResult?> build() async => null;
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

Widget _buildScreen(List<Customer> recentCustomers) => ProviderScope(
      overrides: [
        saleControllerProvider.overrideWith(_FakeSaleController.new),
        recentCustomersProvider.overrideWith((ref) async => recentCustomers),
      ],
      child: const MaterialApp(home: NewSaleScreen()),
    );

void main() {
  group('NewSaleScreen — recent customers', () {
    testWidgets('shows recent customers before freeform search and selects one',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen([
          _customer('Ana Costa', '841000001', points: 12),
          _customer('Bruno Lopes', '842000002', points: 5),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recentes'), findsOneWidget);
      expect(find.text('Ou pesquise'), findsOneWidget);
      expect(find.text('Ana Costa'), findsOneWidget);
      expect(find.text('Bruno Lopes'), findsOneWidget);

      await tester.tap(find.text('Ana Costa'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Costa'), findsOneWidget);
      expect(find.text('841000001'), findsOneWidget);
      expect(find.text('Recentes'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('debounces sale search before querying customers',
        (tester) async {
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
  });
}
