import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:maisum/core/constants/app_constants.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/presentation/sale_cancellation_dialog.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('records correction integration', () {
    setUp(() async {
      await AppDatabase.instance.close();
      final databasePath = join(
        await getDatabasesPath(),
        AppConstants.dbName,
      );
      await deleteDatabase(databasePath);
    });

    tearDown(() => AppDatabase.instance.close());

    testWidgets(
      'archives, restores and cancels a sale using the device database',
      (tester) async {
        final database = AppDatabase.instance;
        final syncDao = SyncDao(database);
        final customerRepository = CustomerRepository(
          CustomerDao.unscoped(database),
          syncDao,
          appUserId: 'integration-staff',
        );
        final saleRepository = SaleRepository(
          database,
          SaleDao(database),
          appUserId: 'integration-staff',
        );

        final customer = await customerRepository.createCustomer(
          name: 'Cliente Integração',
          phone: '841234567',
        );
        final sale = await saleRepository.createSale(
          customerId: customer.id,
          amount: 350,
        );

        expect((await customerRepository.getById(customer.id))!.totalPoints, 3);

        final cancelled = await saleRepository.cancelSale(
          saleId: sale.id,
          reason: 'Valor introduzido incorretamente',
        );

        expect(cancelled.isCancelled, isTrue);
        expect(
            cancelled.cancellationReason, 'Valor introduzido incorretamente');
        expect((await customerRepository.getById(customer.id))!.totalPoints, 0);

        await customerRepository.archiveCustomer(customer.id);
        expect(await customerRepository.getAll(), isEmpty);
        expect(
          (await customerRepository.getArchived()).single.id,
          customer.id,
        );

        await customerRepository.restoreCustomer(customer.id);
        expect((await customerRepository.getAll()).single.id, customer.id);
        expect(await customerRepository.getArchived(), isEmpty);

        final queue = await syncDao.getPending();
        final cancellationItem = queue.singleWhere(
          (item) =>
              item.entityType == 'sale' &&
              item.entityId == sale.id &&
              item.operation == 'cancel',
        );
        final cancellationPayload =
            jsonDecode(cancellationItem.payload) as Map<String, dynamic>;
        expect(cancellationPayload['cancellation_status'], 'CANCELLED');
        expect(
          cancellationPayload['cancellation_reason'],
          'Valor introduzido incorretamente',
        );
      },
    );
  });

  testWidgets('sale cancellation dialog smoke test', (tester) async {
    final sale = Sale(
      id: 'smoke-sale',
      customerId: 'smoke-customer',
      amount: 500,
      points: 5,
      createdAt: DateTime(2026),
    );
    final controller = _SmokeSaleController(sale);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          saleControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showSaleCancellationDialog(
                    context,
                    ref,
                    sale,
                  ),
                  child: const Text('Abrir anulação'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir anulação'));
    await tester.pumpAndSettle();

    expect(find.text('Motivo da anulação'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Anular venda'));
    await tester.pump();
    expect(find.text('O motivo é obrigatório.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Venda registada por engano',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Anular venda'));
    await tester.pumpAndSettle();

    expect(controller.reason, 'Venda registada por engano');
    expect(find.text('Motivo da anulação'), findsNothing);
    expect(find.text('Abrir anulação'), findsOneWidget);
  });
}

class _SmokeSaleController extends SaleController {
  _SmokeSaleController(this.sale);

  final Sale sale;
  String? reason;

  @override
  Future<Sale> cancelSale({
    required String saleId,
    required String customerId,
    required String reason,
  }) async {
    this.reason = reason;
    return sale.copyWith(
      cancellationStatus: SaleCancellationStatus.cancelled,
      cancelledAt: DateTime(2026),
      cancellationReason: reason,
    );
  }
}
