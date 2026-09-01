import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'package:maisum/app/providers.dart';
import 'package:maisum/features/customer_app/data/customer_app_api.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/nfc_cards/presentation/customer_nfc_card_screen.dart';
import 'package:maisum/features/nfc_cards/presentation/merchant_nfc_card_screen.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/presentation/rewards_controller.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';

import '../helpers/fake_nfc.dart';

class _FakeCustomerAppApi extends Fake implements CustomerAppApi {
  Map<String, dynamic>? resolveResult;
  String? lastResolvedCardUid;

  @override
  Future<Map<String, dynamic>> resolveMerchantNfcCard(
    String token, {
    required String cardUid,
    bool createCustomerIfMissing = true,
  }) async {
    lastResolvedCardUid = cardUid;
    return resolveResult!;
  }
}

class _FakeCustomerRepository extends Fake implements CustomerRepository {
  @override
  Future<Customer> upsertCustomerFromNfcResolve({
    required String customerId,
    required String? name,
    required String? phone,
    required int totalPoints,
    required String cardUid,
  }) async =>
      Customer(
        id: customerId,
        name: name ?? 'Cliente',
        phone: phone ?? '',
        totalPoints: totalPoints,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
      );
}

class _FakeCustomerAppRepository extends Fake implements CustomerAppRepository {
  String? linkedCardUid;

  @override
  Future<Map<String, dynamic>> linkNfcCard(String cardUid) async {
    linkedCardUid = cardUid;
    return {'card_uid': cardUid, 'linked': true};
  }
}

class _FakeRewardsController extends RewardsController {
  @override
  Future<List<Reward>> build() async => const <Reward>[];
}

void main() {
  final auth = MockFirebaseAuth(
    mockUser: MockUser(uid: 'merchant-uid-1'),
    signedIn: true,
  );

  testWidgets(
    'MerchantNfcCardScreen resolves a tapped card and offers to register a sale',
    (tester) async {
      final api = _FakeCustomerAppApi()
        ..resolveResult = {
          'customer': {
            'customer_id': 'customer-1',
            'name': 'Ana Mucavele',
            'phone': '841234567',
            'total_points': 120,
          },
          'customer_created': false,
        };
      final router = GoRouter(
        initialLocation: '/merchant/customer-nfc',
        routes: [
          GoRoute(
            path: '/merchant/customer-nfc',
            builder: (_, __) => MerchantNfcCardScreen(
              reader: fakeNfcCardReader(uidBytes: [0x04, 0xA2, 0x2C, 0x9B]),
            ),
          ),
          GoRoute(
            path: '/merchant/customer-nfc/link',
            builder: (_, __) => const Scaffold(body: Text('link-stub')),
          ),
          GoRoute(
            path: '/new-sale',
            builder: (_, state) {
              final args = state.extra as NewSaleArgs?;
              return Scaffold(
                body: Text('new-sale:${args?.preselectedCustomerId}'),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthInstanceProvider.overrideWithValue(auth),
            customerAppApiProvider.overrideWithValue(api),
            customerRepositoryProvider.overrideWithValue(
              _FakeCustomerRepository(),
            ),
            rewardsControllerProvider.overrideWith(_FakeRewardsController.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ler cartão'));
      await tester.pumpAndSettle();

      expect(api.lastResolvedCardUid, '04A22C9B');
      expect(find.text('Ana Mucavele'), findsOneWidget);

      await tester.tap(find.text('Registar venda'));
      await tester.pumpAndSettle();

      expect(find.text('new-sale:customer-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CustomerNfcCardScreen links a tapped card to the signed-in account',
    (tester) async {
      final repository = _FakeCustomerAppRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAppRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: CustomerNfcCardScreen(
              reader: fakeNfcCardReader(uidBytes: [0x05, 0x06, 0x07, 0x08]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Associar cartão'));
      await tester.pumpAndSettle();

      expect(repository.linkedCardUid, '05060708');
      expect(
        find.text('Cartão associado à sua conta com sucesso.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CustomerNfcCardScreen shows a friendly message when NFC is unsupported',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAppRepositoryProvider.overrideWithValue(
              _FakeCustomerAppRepository(),
            ),
          ],
          child: MaterialApp(
            home: CustomerNfcCardScreen(
              reader: fakeNfcCardReader(
                availability: NfcAvailability.unsupported,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Associar cartão'));
      await tester.pumpAndSettle();

      expect(
        find.text('Este dispositivo não suporta leitura de cartões NFC.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
