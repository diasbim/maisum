import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
// The Android tag-data pigeon type isn't part of nfc_manager's public
// export surface, so it is imported directly to build a fake discovered
// [NfcTag] below (there is no real NFC hardware on the emulator/simulator
// this test runs on).
import 'package:nfc_manager/src/nfc_manager_android/pigeon.g.dart'
    show TagPigeon;

import 'package:maisum/app/providers.dart';
import 'package:maisum/core/constants/app_strings.dart';
import 'package:maisum/features/customer_app/data/customer_app_api.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/nfc_cards/domain/nfc_card_reader.dart';
import 'package:maisum/features/nfc_cards/presentation/customer_nfc_card_screen.dart';
import 'package:maisum/features/nfc_cards/presentation/merchant_nfc_card_link_screen.dart';
import 'package:maisum/features/nfc_cards/presentation/merchant_nfc_card_screen.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/presentation/rewards_controller.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';

/// Fakes only the platform-agnostic [NfcManager] surface used by
/// [NfcCardReader]. Real NFC hardware doesn't exist on the emulator this
/// test runs on, so a "card tap" is simulated by having the session
/// immediately discover a tag carrying the given UID bytes.
class _FakeNfcManager extends NfcManager {
  _FakeNfcManager({this.availability = NfcAvailability.enabled, this.uidBytes});

  final NfcAvailability availability;
  final List<int>? uidBytes;

  @override
  Future<bool> isAvailable() async => availability == NfcAvailability.enabled;

  @override
  Future<NfcAvailability> checkAvailability() async => availability;

  @override
  Future<void> startSession({
    required Set<NfcPollingOption> pollingOptions,
    required void Function(NfcTag tag) onDiscovered,
    String? alertMessageIos,
    bool invalidateAfterFirstReadIos = true,
    void Function(NfcReaderSessionErrorIos)? onSessionErrorIos,
    bool noPlatformSoundsAndroid = false,
  }) async {
    final bytes = uidBytes;
    if (bytes == null) return;
    onDiscovered(
      NfcTag(
        data: TagPigeon(
          handle: 'fake-handle',
          id: Uint8List.fromList(bytes),
          techList: const ['android.nfc.tech.NfcA'],
        ),
      ),
    );
  }

  @override
  Future<void> stopSession({
    String? alertMessageIos,
    String? errorMessageIos,
  }) async {}
}

NfcCardReader _fakeReader({
  NfcAvailability availability = NfcAvailability.enabled,
  List<int>? uidBytes,
}) =>
    NfcCardReader(
      manager: _FakeNfcManager(availability: availability, uidBytes: uidBytes),
    );

class _FakeCustomerAppApi extends Fake implements CustomerAppApi {
  Object? resolveError;
  Map<String, dynamic>? resolveResult;
  String? lastResolvedCardUid;

  Map<String, dynamic>? linkResult;
  String? lastLinkedCardUid;
  String? lastLinkedPhone;

  @override
  Future<Map<String, dynamic>> resolveMerchantNfcCard(
    String token, {
    required String cardUid,
    bool createCustomerIfMissing = true,
  }) async {
    lastResolvedCardUid = cardUid;
    final error = resolveError;
    if (error != null) throw error;
    return resolveResult!;
  }

  @override
  Future<Map<String, dynamic>> linkMerchantNfcCard(
    String token, {
    required String cardUid,
    String? customerId,
    String? phone,
    String? customerName,
    bool createCustomerIfMissing = true,
  }) async {
    lastLinkedCardUid = cardUid;
    lastLinkedPhone = phone;
    return linkResult!;
  }
}

class _FakeCustomerRepository extends Fake implements CustomerRepository {
  Customer? upserted;

  @override
  Future<Customer> upsertCustomerFromNfcResolve({
    required String customerId,
    required String? name,
    required String? phone,
    required int totalPoints,
    required String cardUid,
  }) async {
    final customer = Customer(
      id: customerId,
      name: (name == null || name.isEmpty) ? 'Cliente' : name,
      phone: phone ?? '',
      totalPoints: totalPoints,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
    );
    upserted = customer;
    return customer;
  }
}

class _FakeCustomerAppRepository extends Fake implements CustomerAppRepository {
  String? linkedCardUid;
  String? revokedCardUid;

  @override
  Future<Map<String, dynamic>> linkNfcCard(String cardUid) async {
    linkedCardUid = cardUid;
    return {'card_uid': cardUid, 'linked': true};
  }

  @override
  Future<Map<String, dynamic>> revokeNfcCard(String cardUid) async {
    revokedCardUid = cardUid;
    return {'card_uid': cardUid, 'revoked': true};
  }
}

class _FakeRewardsController extends RewardsController {
  @override
  Future<List<Reward>> build() async => const <Reward>[];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final auth = MockFirebaseAuth(
    mockUser: MockUser(uid: 'merchant-uid-1'),
    signedIn: true,
  );

  Widget buildMerchantResolveScreen({
    required NfcCardReader reader,
    required _FakeCustomerAppApi api,
    required _FakeCustomerRepository customerRepository,
  }) {
    final router = GoRouter(
      initialLocation: '/merchant/customer-nfc',
      routes: [
        GoRoute(
          path: '/merchant/customer-nfc',
          builder: (_, __) => MerchantNfcCardScreen(reader: reader),
        ),
        GoRoute(
          path: '/merchant/customer-nfc/link',
          builder: (_, __) => const Scaffold(body: Text('link-screen-stub')),
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
    return ProviderScope(
      overrides: [
        firebaseAuthInstanceProvider.overrideWithValue(auth),
        customerAppApiProvider.overrideWithValue(api),
        customerRepositoryProvider.overrideWithValue(customerRepository),
        rewardsControllerProvider.overrideWith(_FakeRewardsController.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets(
    'merchant reads a known card, resolves the customer and registers a sale',
    (tester) async {
      final api = _FakeCustomerAppApi()
        ..resolveResult = {
          'business_id': 'biz-1',
          'customer': {
            'customer_id': 'customer-nfc-1',
            'name': 'Ana Mucavele',
            'phone': '841234567',
            'total_points': 120,
          },
          'customer_created': false,
        };
      final customerRepository = _FakeCustomerRepository();

      await tester.pumpWidget(
        buildMerchantResolveScreen(
          reader: _fakeReader(uidBytes: [0x04, 0xA2, 0x2C, 0x9B]),
          api: api,
          customerRepository: customerRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ler cartão'));
      await tester.pumpAndSettle();

      expect(api.lastResolvedCardUid, '04A22C9B');
      expect(customerRepository.upserted?.id, 'customer-nfc-1');
      expect(find.text('Ana Mucavele'), findsOneWidget);
      expect(find.text('841234567'), findsOneWidget);
      expect(find.text('120 pontos'), findsOneWidget);

      await tester.tap(find.text('Registar venda'));
      await tester.pumpAndSettle();

      expect(find.text('new-sale:customer-nfc-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('merchant opens the benefit sheet for the resolved customer',
      (tester) async {
    final api = _FakeCustomerAppApi()
      ..resolveResult = {
        'customer': {
          'customer_id': 'customer-nfc-2',
          'name': 'Bruno Lima',
          'phone': '842000002',
          'total_points': 50,
        },
        'customer_created': false,
      };
    await tester.pumpWidget(
      buildMerchantResolveScreen(
        reader: _fakeReader(uidBytes: [0x0B, 0x44, 0xFF, 0x10]),
        api: api,
        customerRepository: _FakeCustomerRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ler cartão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atribuir benefício'));
    await tester.pumpAndSettle();

    expect(find.text('Bruno Lima · 50 pts disponíveis'), findsOneWidget);
    expect(find.text(AppStrings.semRecompensas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'merchant sees a friendly message when a card has no matching customer',
    (tester) async {
      final api = _FakeCustomerAppApi()..resolveError = StateError('not found');
      await tester.pumpWidget(
        buildMerchantResolveScreen(
          reader: _fakeReader(uidBytes: [0x11, 0x22, 0x33, 0x44]),
          api: api,
          customerRepository: _FakeCustomerRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ler cartão'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.erroGenerico), findsOneWidget);
      expect(find.text('Registar venda'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'merchant navigates from the resolve screen to the assisted link screen',
    (tester) async {
      await tester.pumpWidget(
        buildMerchantResolveScreen(
          reader: _fakeReader(),
          api: _FakeCustomerAppApi(),
          customerRepository: _FakeCustomerRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Associar cartão a um cliente'));
      await tester.pumpAndSettle();

      expect(find.text('link-screen-stub'), findsOneWidget);
    },
  );

  testWidgets(
    'merchant assisted link requires a phone before reading a card',
    (tester) async {
      final reader = _fakeReader(uidBytes: [0x01, 0x02, 0x03, 0x04]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthInstanceProvider.overrideWithValue(auth),
            customerAppApiProvider.overrideWithValue(_FakeCustomerAppApi()),
          ],
          child: MaterialApp(home: MerchantNfcCardLinkScreen(reader: reader)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ler cartão e associar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Introduza o número de telefone do cliente.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'merchant assisted link reads a card and links a new customer by phone',
    (tester) async {
      final reader = _fakeReader(uidBytes: [0x01, 0x02, 0x03, 0x04]);
      final api = _FakeCustomerAppApi()
        ..linkResult = {
          'card_uid': '01020304',
          'business_id': 'biz-1',
          'customer_id': 'customer-3',
          'customer_created': true,
        };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthInstanceProvider.overrideWithValue(auth),
            customerAppApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(home: MerchantNfcCardLinkScreen(reader: reader)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '841234567');
      await tester.tap(find.text('Ler cartão e associar'));
      await tester.pumpAndSettle();

      expect(api.lastLinkedCardUid, '01020304');
      expect(api.lastLinkedPhone, '841234567');
      expect(find.text('Cartão associado a um novo cliente.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('customer links and then revokes their own physical card',
      (tester) async {
    final reader = _fakeReader(uidBytes: [0x05, 0x06, 0x07, 0x08]);
    final repository = _FakeCustomerAppRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerAppRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: CustomerNfcCardScreen(reader: reader)),
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

    await tester.tap(find.text('Desassociar este cartão'));
    await tester.pumpAndSettle();

    expect(repository.revokedCardUid, '05060708');
    expect(find.text('Cartão desassociado da sua conta.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'customer sees a friendly message when the device has no NFC hardware',
    (tester) async {
      final reader = _fakeReader(availability: NfcAvailability.unsupported);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAppRepositoryProvider.overrideWithValue(
              _FakeCustomerAppRepository(),
            ),
          ],
          child: MaterialApp(home: CustomerNfcCardScreen(reader: reader)),
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
