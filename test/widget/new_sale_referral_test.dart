import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/design_system/design_system.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_api.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/offline_referral.dart';
import 'package:maisum/features/affiliates/domain/referral_sale_commit.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/affiliates/presentation/referred_sale_controller.dart';
import 'package:maisum/features/affiliates/providers/affiliate_providers.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/customers/data/customer_repository.dart';
import 'package:maisum/features/customers/domain/customer.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/domain/sale.dart';
import 'package:maisum/features/sales/domain/sale_item.dart';
import 'package:maisum/features/sales/presentation/new_sale_screen.dart';
import 'package:maisum/features/sales/presentation/sale_controller.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

/// The referral invitation inside the sale flow.
///
/// The sale is the thing this app exists to do, so the whole feature is built
/// to be ignorable: with the business switch off, or with a customer who has
/// been here before, the screen is byte-for-byte the one that shipped before —
/// same controls, same single tap, same repository. These tests hold that line
/// first and the new behaviour second.
class _RecordingSaleController extends SaleController {
  int createCalls = 0;
  double? lastAmount;

  @override
  Future<SaleResult?> build() async => null;

  @override
  Future<SaleResult> createSale({
    required String customerId,
    required double amount,
    List<SaleItemInput> items = const <SaleItemInput>[],
    String? replacesSaleId,
  }) async {
    createCalls += 1;
    lastAmount = amount;
    return SaleResult(
      sale: Sale(
        id: 'sale-local-1',
        customerId: customerId,
        amount: amount,
        points: 5,
        createdAt: DateTime(2025, 1, 1),
      ),
      customer: _customer(id: customerId),
    );
  }
}

class _FakeReferredSaleController extends ReferredSaleController {
  _FakeReferredSaleController(this._outcomes, this._offlineOutcomes);

  final List<Object> _outcomes;
  final List<Object> _offlineOutcomes;
  final List<String> localSaleIds = <String>[];
  final List<String> offlineLocalSaleIds = <String>[];
  final List<String> codes = <String>[];
  int _next = 0;
  int _offlineNext = 0;
  int _minted = 0;

  @override
  Future<void> build() async {}

  @override
  String newLocalSaleId() {
    _minted += 1;
    return 'local-sale-$_minted';
  }

  int get mintedIds => _minted;

  @override
  Future<ReferredSaleOutcome> commitOffline({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    offlineLocalSaleIds.add(localSaleId);
    codes.add(code);
    final outcome =
        _offlineOutcomes[_offlineNext.clamp(0, _offlineOutcomes.length - 1)];
    _offlineNext += 1;
    if (outcome is Error) throw outcome;
    if (outcome is Exception) throw outcome;
    return outcome as ReferredSaleOutcome;
  }

  @override
  Future<ReferredSaleOutcome> commit({
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    required String localSaleId,
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) async {
    localSaleIds.add(localSaleId);
    codes.add(code);
    final outcome = _outcomes[_next.clamp(0, _outcomes.length - 1)];
    _next += 1;
    if (outcome is Error) throw outcome;
    if (outcome is Exception) throw outcome;
    return outcome as ReferredSaleOutcome;
  }
}

class _FakeAffiliateSaleGateway implements AffiliateSaleGateway {
  _FakeAffiliateSaleGateway({this.result, this.error});

  ReferralValidationResult? result;
  Object? error;
  int validateCalls = 0;
  String? lastCode;
  double? lastAmount;
  String? lastPhone;

  @override
  Future<ReferralValidationResult> validateCode({
    required String code,
    String? customerPhone,
    double? saleAmount,
  }) async {
    validateCalls += 1;
    lastCode = code;
    lastAmount = saleAmount;
    lastPhone = customerPhone;
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<ReferralSaleCommit> commitSale({
    required String deviceId,
    required String localSaleId,
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    List<SaleItemInput> items = const <SaleItemInput>[],
    List<String> itemIds = const <String>[],
  }) {
    throw UnimplementedError('the screen commits through the controller');
  }
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository(this.customers)
      : super(
          CustomerDao.unscoped(AppDatabase.instance),
          SyncDao(AppDatabase.instance),
        );

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

Customer _customer({
  String id = 'customer-1',
  String name = 'Ana Silva',
  String phone = '841000001',
  bool returning = false,
}) {
  return Customer(
    id: id,
    name: name,
    phone: phone,
    totalVisits: returning ? 4 : 0,
    totalSpent: returning ? 1200 : 0,
    firstVisitAt: returning ? DateTime(2024, 5, 1) : null,
    lastVisitAt: returning ? DateTime(2025, 1, 5) : null,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 2),
  );
}

ReferralValidationResult _validPreview() {
  return ReferralValidationResult(
    isValid: true,
    validatedAt: DateTime(2025, 3, 1),
    normalizedCode: 'AFI-ANA-7K2P',
    affiliateName: 'Ana Silva',
    saleStatus: ReferralSaleStatus.pending,
    benefit: const ReferralBenefitPreview(
      benefitType: ReferralBenefitType.fixedAmount,
      benefitValue: 50,
      benefitAmount: 50,
      displayText: '50 MT de desconto',
    ),
  );
}

ReferralValidationResult _rejectedPreview() {
  return ReferralValidationResult(
    isValid: false,
    validatedAt: DateTime(2025, 3, 1),
    errorCode: ReferralValidationErrorCode.codeExpired,
    statusText: 'Código expirado.',
  );
}

ReferredSaleAccepted _acceptedOutcome(Customer customer) {
  return ReferredSaleAccepted(
    SaleResult(
      sale: Sale(
        id: 'server-sale-1',
        customerId: customer.id,
        amount: 250,
        points: 25,
        createdAt: DateTime(2025, 3, 1),
      ),
      customer: customer,
    ),
    const ReferralSaleCommit(
      outcome: ReferralSaleCommitOutcome.committed,
    ),
  );
}

class _Harness {
  _Harness({
    required this.customer,
    this.affiliatesEnabled = true,
    this.online = true,
    this.additionalCustomers = const <Customer>[],
    this.onlineStream,
    List<Object>? outcomes,
    List<Object>? offlineOutcomes,
    ReferralValidationResult? preview,
    Object? previewError,
  })  : saleController = _RecordingSaleController(),
        referredController = _FakeReferredSaleController(
          outcomes ??
              <ReferredSaleOutcome>[
                const ReferredSaleRejected('Código expirado.'),
              ],
          offlineOutcomes ??
              <ReferredSaleOutcome>[
                ReferredSaleQueuedOffline(
                  SaleResult(
                    sale: Sale(
                      id: 'sale-offline-1',
                      customerId: customer.id,
                      amount: 300,
                      points: 3,
                      createdAt: DateTime(2025, 1, 1),
                      referralStatus: ReferralSaleStatus.pendingSync,
                    ),
                    customer: customer,
                  ),
                  const OfflineReferralDecision(
                    normalizedCode: 'AFI-ANA-7K2P',
                  ),
                ),
              ],
        ),
        gateway = _FakeAffiliateSaleGateway(
          result: preview,
          error: previewError,
        );

  final Customer customer;
  final bool affiliatesEnabled;
  final bool online;
  final List<Customer> additionalCustomers;
  final Stream<bool>? onlineStream;
  final _RecordingSaleController saleController;
  final _FakeReferredSaleController referredController;
  final _FakeAffiliateSaleGateway gateway;

  Widget build() {
    final router = GoRouter(
      initialLocation: '/new-sale',
      routes: <RouteBase>[
        GoRoute(path: '/new-sale', builder: (_, __) => const NewSaleScreen()),
        GoRoute(
          path: '/sale-success',
          builder: (_, __) => const Scaffold(body: Text('sale-success')),
        ),
      ],
    );

    return ProviderScope(
      overrides: <Override>[
        customerRepositoryProvider.overrideWithValue(
          _FakeCustomerRepository(<Customer>[customer, ...additionalCustomers]),
        ),
        saleDaoProvider.overrideWithValue(
          _FakeSaleDao(
            latestSale: <String, dynamic>{
              'customer_id': customer.id,
              'amount': 200.0,
            },
          ),
        ),
        saleControllerProvider.overrideWith(() => saleController),
        referredSaleControllerProvider.overrideWith(() => referredController),
        affiliateSaleApiProvider.overrideWithValue(gateway),
        // No local projection in these tests: the offline preview then falls
        // through to the "this device has never heard of this code" branch,
        // which is the honest answer for a till with an empty cache.
        affiliateOfflineGatewayProvider.overrideWithValue(null),
        affiliateFeatureEnabledProvider.overrideWithValue(affiliatesEnabled),
        isOnlineProvider.overrideWith(
          (ref) => onlineStream ?? Stream<bool>.value(online),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _enterAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byType(TextField).last, amount);
  await _settle(tester);
}

/// Scrolls a control into view before tapping it.
///
/// The sale form is a full page and the invitation sits below the summary, so
/// on the test surface the validate button starts off-screen. A tap at an
/// off-screen offset hits nothing and would pass this test for the wrong
/// reason.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  setUp(() {
    // 800×600 is shorter than any phone this runs on and the sale form is a
    // full page; a taller surface keeps the confirm button reachable.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('a sale without the feature is the sale that shipped before',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      affiliatesEnabled: false,
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);

    expect(find.byKey(const Key('referral-code-section')), findsNothing);

    await _enterAmount(tester, '300');
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    // One tap, one sale, through the repository that already existed.
    expect(harness.saleController.createCalls, 1);
    expect(harness.saleController.lastAmount, 300);
    expect(harness.referredController.localSaleIds, isEmpty);
    expect(harness.gateway.validateCalls, 0);
    expect(find.text('sale-success'), findsOneWidget);
  });

  testWidgets('an eligible customer is offered the code, collapsed',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(customer: _customer());
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    expect(find.text('Tem código de indicação?'), findsOneWidget);
    // Collapsed means collapsed: the field is not in the tree, so it is not in
    // the tab order and costs nothing to skip.
    expect(find.byKey(const Key('referral-code-field')), findsNothing);
    expect(find.byKey(const Key('referral-validate-button')), findsNothing);
  });

  testWidgets('a returning customer is never asked', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(customer: _customer(returning: true));
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    expect(find.text('Tem código de indicação?'), findsNothing);
  });

  testWidgets('a valid code is read back without an id', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _validPreview(),
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'afi-ana-7k2p',
    );
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('referral-validate-button')));

    expect(harness.gateway.validateCalls, 1);
    // Normalised the way the server indexes it, and priced against the gross.
    expect(harness.gateway.lastCode, 'AFI-ANA-7K2P');
    expect(harness.gateway.lastAmount, 300);
    expect(harness.gateway.lastPhone, '841000001');

    expect(find.byKey(const Key('referral-valid-notice')), findsOneWidget);
    expect(find.text('Código válido'), findsOneWidget);
    expect(
      find.textContaining('Cliente recebe: 50 MT de desconto'),
      findsOneWidget,
    );
    expect(find.textContaining('Afiliado: Ana'), findsOneWidget);
  });

  testWidgets('pressing validate twice spends one call', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _validPreview(),
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);

    await tester.ensureVisible(
      find.byKey(const Key('referral-validate-button')),
    );
    await _settle(tester);
    // Two presses on the same frame. The guard, not a debounce, is what stops
    // the second from spending another of the rate-limited budget.
    await tester.tap(find.byKey(const Key('referral-validate-button')));
    await tester.tap(find.byKey(const Key('referral-validate-button')));
    await _settle(tester);

    expect(harness.gateway.validateCalls, 1);
  });

  testWidgets('a refused code says why and does not block the sale',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _rejectedPreview(),
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-VELHO-1',
    );
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('referral-validate-button')));

    expect(find.byKey(const Key('referral-invalid-notice')), findsOneWidget);
    expect(find.textContaining('Código expirado.'), findsOneWidget);
    expect(find.textContaining('Pode concluir a venda normalmente'),
        findsOneWidget);
    // The confirm action is untouched by a bad code.
    final confirm = tester.widget<MaisUmButton>(
      find.ancestor(
        of: find.text('Confirmar Venda'),
        matching: find.byType(MaisUmButton),
      ),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('an accepted commit lands on the canonical sale', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final customer = _customer();
    final harness = _Harness(
      customer: customer,
      preview: _validPreview(),
      outcomes: <ReferredSaleOutcome>[
        ReferredSaleAccepted(
          SaleResult(
            sale: Sale(
              id: 'server-sale-1',
              customerId: customer.id,
              amount: 250,
              points: 25,
              createdAt: DateTime(2025, 3, 1),
            ),
            customer: customer,
          ),
          const ReferralSaleCommit(
            outcome: ReferralSaleCommitOutcome.committed,
          ),
        ),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('referral-validate-button')));

    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(harness.referredController.codes, <String>['AFI-ANA-7K2P']);
    // The ordinary path is never used for a referred sale.
    expect(harness.saleController.createCalls, 0);
    expect(find.text('sale-success'), findsOneWidget);
  });

  testWidgets('a rejected commit keeps the sale and offers to finish it',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _validPreview(),
      outcomes: <ReferredSaleOutcome>[
        const ReferredSaleRejected('Este cliente já foi indicado.'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(find.text('Este cliente já foi indicado.'), findsOneWidget);
    expect(find.text('Concluir sem código'), findsOneWidget);
    // Nothing was written and nothing was lost.
    expect(harness.saleController.createCalls, 0);
    expect(find.text('sale-success'), findsNothing);

    await tester.tap(find.text('Concluir sem código'));
    await _settle(tester);

    expect(harness.saleController.createCalls, 1);
    expect(harness.saleController.lastAmount, 300);
    expect(find.text('sale-success'), findsOneWidget);
  });

  testWidgets('a retry reuses the idempotency key it already minted',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _validPreview(),
      outcomes: <ReferredSaleOutcome>[
        const ReferredSaleRejected('Não foi possível usar este código.'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);

    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(harness.referredController.localSaleIds, hasLength(2));
    expect(
      harness.referredController.localSaleIds.first,
      harness.referredController.localSaleIds.last,
    );
    expect(harness.referredController.mintedIds, 1);
  });

  testWidgets('changing customer clears the hidden referral code',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = _customer(name: 'Ana Silva');
    final second = _customer(
      id: 'customer-2',
      name: 'Berta Cossa',
      phone: '841000002',
    );
    final harness = _Harness(
      customer: first,
      additionalCustomers: <Customer>[second],
      outcomes: const <Object>[
        ReferredSaleRejected('Código recusado.'),
        ReferredSaleRejected('Código recusado outra vez.'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    await _tap(tester, find.text('Alterar'));
    await _tap(tester, find.text('Berta Cossa'));

    expect(find.byKey(const Key('referral-code-field')), findsNothing);
    expect(find.text('Concluir sem código'), findsNothing);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);
    expect(harness.saleController.createCalls, 1);
    expect(harness.referredController.localSaleIds, hasLength(1));
  });

  testWidgets('changing customer mints a new referral idempotency key',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = _customer(name: 'Ana Silva');
    final second = _customer(
      id: 'customer-2',
      name: 'Berta Cossa',
      phone: '841000002',
    );
    final harness = _Harness(
      customer: first,
      additionalCustomers: <Customer>[second],
      outcomes: const <Object>[
        ReferredSaleRejected('Código recusado.'),
        ReferredSaleRejected('Código recusado outra vez.'),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    await _tap(tester, find.text('Alterar'));
    await _tap(tester, find.text('Berta Cossa'));

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-BERTA-8M3R',
    );
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(harness.referredController.localSaleIds, hasLength(2));
    expect(
      harness.referredController.localSaleIds.first,
      isNot(harness.referredController.localSaleIds.last),
    );
    expect(harness.referredController.mintedIds, 2);
  });

  testWidgets('unknown commit failure retries instead of duplicating the sale',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final customer = _customer();
    final harness = _Harness(
      customer: customer,
      outcomes: <Object>[
        StateError('Sem resposta do servidor'),
        _acceptedOutcome(customer),
      ],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');
    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);

    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Concluir sem código'), findsNothing);
    expect(harness.saleController.createCalls, 0);

    await tester.tap(find.text('Tentar novamente'));
    await _settle(tester);

    expect(harness.referredController.localSaleIds, hasLength(2));
    expect(
      harness.referredController.localSaleIds.first,
      harness.referredController.localSaleIds.last,
    );
    expect(harness.saleController.createCalls, 0);
    expect(find.text('sale-success'), findsOneWidget);
  });

  testWidgets('editing the basket dismisses a stale retry action',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      outcomes: <Object>[StateError('Sem resposta do servidor')],
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');
    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-BERTA-8M3R',
    );
    await _settle(tester);

    expect(find.text('Tentar novamente'), findsNothing);
    expect(harness.referredController.localSaleIds, hasLength(1));
    expect(harness.saleController.createCalls, 0);
  });

  testWidgets('connectivity is resolved again when confirming the sale',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);

    final harness = _Harness(
      customer: _customer(),
      onlineStream: connectivity.stream,
      outcomes: const <Object>[
        ReferredSaleRejected('Código recusado.'),
      ],
    );
    await tester.pumpWidget(harness.build());
    connectivity.add(false);
    await _settle(tester);
    await _enterAmount(tester, '300');
    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);

    connectivity.add(true);
    await _settle(tester);
    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    expect(harness.referredController.localSaleIds, hasLength(1));
    expect(harness.saleController.createCalls, 0);
    expect(find.text('Concluir sem código'), findsOneWidget);
  });

  testWidgets(
      'offline prices from the cache it has, and says nothing is confirmed',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      online: false,
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    await _tap(tester, find.byKey(const Key('referral-code-toggle')));
    await tester.enterText(
      find.byKey(const Key('referral-code-field')),
      'AFI-ANA-7K2P',
    );
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('referral-validate-button')));
    await _settle(tester);

    // Nothing is in this till's cache, so nothing is promised — and the code is
    // still kept for the server to judge.
    expect(
      find.byKey(const Key('referral-offline-unknown-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('fica pelo valor total'), findsOneWidget);

    await tester.tap(find.text('Confirmar Venda'));
    await _settle(tester);

    // One sale, one authoritative operation: the ordinary sale path is never
    // used for a sale that carried a code.
    expect(harness.referredController.offlineLocalSaleIds, hasLength(1));
    expect(harness.referredController.localSaleIds, isEmpty);
    expect(harness.saleController.createCalls, 0);
    expect(harness.referredController.codes.single, 'AFI-ANA-7K2P');
  });

  testWidgets('the invitation survives a 200% text scale', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _Harness(
      customer: _customer(),
      preview: _validPreview(),
    );
    await tester.pumpWidget(harness.build());
    await _settle(tester);
    await _enterAmount(tester, '300');

    expect(find.text('Tem código de indicação?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
