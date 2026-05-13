import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/core/widgets/empty_state.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/customers/presentation/customer_list_screen.dart';
import 'package:maisum/features/customers/presentation/customers_controller.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

// Must extend the real controller so overrideWith type-checks pass.
class _FakeCustomersController extends CustomersController {
  _FakeCustomersController(this._customers);
  final List<Customer> _customers;

  @override
  Future<List<Customer>> build() async => _customers;

  @override
  Future<void> search(String query) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<Customer> createCustomer(
          {required String name, required String phone}) async =>
      Customer(
          id: 'new-id', name: name, phone: phone, createdAt: DateTime.now());
}

class _SlowCustomersController extends CustomersController {
  @override
  Future<List<Customer>> build() => Completer<List<Customer>>().future;

  @override
  Future<void> search(String query) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<Customer> createCustomer(
          {required String name, required String phone}) async =>
      throw UnimplementedError();
}

// ── Helper ───────────────────────────────────────────────────────────────────

Widget _buildCustomerList(List<Customer> customers) => ProviderScope(
      overrides: [
        customersControllerProvider
            .overrideWith(() => _FakeCustomersController(customers)),
      ],
      child: const MaterialApp(home: CustomerListScreen()),
    );

Customer _customer(String name, String phone, {int points = 0}) => Customer(
      id: 'id-$phone',
      name: name,
      phone: phone,
      totalPoints: points,
      createdAt: DateTime(2024, 1, 1),
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('CustomerListScreen — empty state', () {
    testWidgets('shows EmptyState widget when list is empty', (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows empty state message text', (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.semClientes), findsOneWidget);
    });

    testWidgets('shows Adicionar cliente action in empty state',
        (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.adicionarCliente), findsAtLeast(1));
    });
  });

  group('CustomerListScreen — populated state', () {
    final customers = [
      _customer('Ana Costa', '841000001', points: 10),
      _customer('Bruno Lopes', '842000002', points: 5),
    ];

    testWidgets('shows customer names', (tester) async {
      await tester.pumpWidget(_buildCustomerList(customers));
      await tester.pumpAndSettle();

      expect(find.text('Ana Costa'), findsOneWidget);
      expect(find.text('Bruno Lopes'), findsOneWidget);
    });

    testWidgets('shows customer phone numbers', (tester) async {
      await tester.pumpWidget(_buildCustomerList(customers));
      await tester.pumpAndSettle();

      expect(find.text('841000001'), findsOneWidget);
      expect(find.text('842000002'), findsOneWidget);
    });

    testWidgets('does not show EmptyState when customers exist',
        (tester) async {
      await tester.pumpWidget(_buildCustomerList(customers));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsNothing);
    });
  });

  group('CustomerListScreen — structure', () {
    testWidgets('shows app bar with Clientes title', (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.clientesTitle), findsOneWidget);
    });

    testWidgets('shows search TextField with hint', (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(AppStrings.buscarCliente), findsOneWidget);
    });

    testWidgets('shows FAB with person_add icon', (tester) async {
      await tester.pumpWidget(_buildCustomerList([]));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.person_add_rounded), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          customersControllerProvider
              .overrideWith(_SlowCustomersController.new),
        ],
        child: const MaterialApp(home: CustomerListScreen()),
      ));
      await tester.pump(); // one pump only — don't settle

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

