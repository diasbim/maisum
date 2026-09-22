import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/auth/presentation/auth_controller.dart';
import 'package:maisum/features/catalog/data/merchant_catalog_repository.dart';
import 'package:maisum/features/catalog/domain/merchant_item.dart';
import 'package:maisum/features/catalog/presentation/merchant_catalog_screen.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/sync_service.dart';

const _unset = Object();

/// In-memory double: the screen talks to the repository and to
/// [syncServiceProvider] directly (there is no controller layer to fake
/// instead), so a real SQLite-backed widget test would need a full sync
/// stack. Faking the repository keeps this a pure UI test, matching how the
/// rest of this app's widget tests fake at the controller boundary.
class _FakeMerchantCatalogRepository implements MerchantCatalogRepository {
  final List<MerchantItem> items = [];
  int _counter = 0;

  @override
  String? get appUserId => null;

  @override
  Future<List<MerchantItem>> getServices() async =>
      items.where((item) => item.type == MerchantItemType.service).toList();

  @override
  Future<List<MerchantItem>> getProducts() async =>
      items.where((item) => item.type == MerchantItemType.product).toList();

  @override
  Future<List<MerchantItem>> getActiveItems() async =>
      items.where((item) => item.isActive).toList();

  @override
  Future<MerchantItem> save({
    required String name,
    required MerchantItemType type,
    double? defaultPrice,
    bool isActive = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Nome obrigatorio.');
    final item = MerchantItem(
      id: 'item-${_counter++}',
      name: trimmed,
      type: type,
      defaultPrice: defaultPrice,
      isActive: isActive,
      displayOrder: items.length,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    items.add(item);
    return item;
  }

  @override
  Future<MerchantItem?> update(
    String id, {
    String? name,
    Object? defaultPrice = _unset,
    bool? isActive,
    int? displayOrder,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index == -1) return null;
    final current = items[index];
    final updated = current.copyWith(
      name: name,
      defaultPrice: identical(defaultPrice, _unset)
          ? current.defaultPrice
          : (defaultPrice as num?)?.toDouble(),
      isActive: isActive,
      displayOrder: displayOrder,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<bool> delete(String id) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index == -1) return false;
    items.removeAt(index);
    return true;
  }
}

/// A [SyncService] that never touches a real database, connectivity plugin,
/// or transport: the screen fires `processQueue()` after every write, and
/// this keeps that call a no-op instead of requiring a full sync stack.
class _NoopSyncService extends SyncService {
  _NoopSyncService()
      : super(
          AppDatabase.instance,
          SyncDao(AppDatabase.instance),
          null,
          ConnectivityService(
            initialOnline: false,
            onConnectivityChanged: const Stream<List<ConnectivityResult>>.empty(),
            checkConnectivity: () async => const [ConnectivityResult.none],
          ),
        );

  @override
  void init() {}

  @override
  Future<void> processQueue() async {}
}

Widget _buildScreen(_FakeMerchantCatalogRepository repository) {
  final router = GoRouter(
    initialLocation: '/catalog',
    routes: [
      GoRoute(
        path: '/catalog',
        builder: (_, __) => const MerchantCatalogScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('dashboard')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      activeMerchantIdProvider.overrideWithValue('merchant-1'),
      merchantCatalogRepositoryProvider.overrideWithValue(repository),
      syncServiceProvider.overrideWithValue(_NoopSyncService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows an empty state for a merchant with no services',
      (tester) async {
    await tester.pumpWidget(_buildScreen(_FakeMerchantCatalogRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum serviço registado'), findsOneWidget);
  });

  testWidgets('creates a service and lists it', (tester) async {
    await tester.pumpWidget(_buildScreen(_FakeMerchantCatalogRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar Serviço'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Corte');
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço padrão opcional'),
      '350',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Corte'), findsOneWidget);
    expect(find.text('350 MZN'), findsOneWidget);
    expect(find.text('Nenhum serviço registado'), findsNothing);
  });

  testWidgets('deactivating a service updates its label', (tester) async {
    final repository = _FakeMerchantCatalogRepository();
    await tester.pumpWidget(_buildScreen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar Serviço'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Barba');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Desativar'));
    await tester.pumpAndSettle();

    expect(find.text('Item desativado.'), findsOneWidget);
    expect(find.textContaining('Inativo'), findsOneWidget);
  });

  testWidgets('deleting an unused service removes it from the list',
      (tester) async {
    final repository = _FakeMerchantCatalogRepository();
    await tester.pumpWidget(_buildScreen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar Serviço'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Manicure');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar').last);
    await tester.pumpAndSettle();

    expect(find.text('Item apagado.'), findsOneWidget);
    expect(find.text('Manicure'), findsNothing);
    expect(find.text('Nenhum serviço registado'), findsOneWidget);
  });

  testWidgets('switches to the products tab', (tester) async {
    await tester.pumpWidget(_buildScreen(_FakeMerchantCatalogRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Produtos'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum produto registado'), findsOneWidget);
  });
}
