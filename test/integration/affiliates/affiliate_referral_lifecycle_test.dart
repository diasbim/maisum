import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/affiliates/data/affiliate_dao.dart';
import 'package:maisum/features/affiliates/data/affiliate_local_repository.dart';
import 'package:maisum/features/affiliates/data/affiliate_repository.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_api.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_repository.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/domain/offline_referral.dart';
import 'package:maisum/features/affiliates/domain/referral_sale_commit.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sales/domain/sale_item.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/data/sync_projection.dart';
import 'package:maisum/features/sync/data/sync_transport.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';
import 'package:maisum/features/sync/sync_service.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';

/// The seven scenarios of the source prompt's §12, seen from the till.
///
/// The server half of each one is proved in
/// `functions/src/affiliate_referral_lifecycle.test.ts`, against the real
/// commit transaction. This is the other half: what the device does before the
/// server answers, what it stores when the answer arrives, and — the part no
/// single-seam test can see — that a whole scenario leaves exactly one sale,
/// one customer movement and one queued operation behind.
///
/// It runs on real SQLite through the real repositories and the real
/// [SyncService]. What stands in for the backend is [_FakeReferralServer],
/// which is deliberately stateful: it counts what it was asked to do, so
/// "confirmed once" is a number this test can read rather than a hope. It is
/// not a reimplementation of the server's rules — it replays the answers the
/// Functions suite pins down.
///
/// No emulator, no credentials and no network are involved. The emulator
/// command is in `docs/afiliados/PLAN.md` §10 and has not been run here.
const _merchantId = 'shop-1';
const _deviceId = 'till-1';
const _code = 'AFI-ANA-7K2P';
const _customerPhone = '+258841234567';

/* ------------------------------------------------------------ the "server" */

class _FakeReferralServer implements AffiliateSaleGateway {
  _FakeReferralServer();

  /// Set to a reason to make every preview and commit refuse.
  String? rejectWith;
  String rejectMessage = 'Este código expirou.';

  final Set<String> committedKeys = <String>{};
  final List<Map<String, Object?>> commitRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> previewRequests = <Map<String, Object?>>[];

  /// How many times the reconciliation endpoint did the work.
  int reconciliations = 0;

  @override
  Future<ReferralValidationResult> validateCode({
    required String code,
    String? customerPhone,
    double? saleAmount,
  }) async {
    previewRequests.add(<String, Object?>{
      'code': code,
      'customer_phone': customerPhone,
      'sale_amount': saleAmount,
    });
    final reason = rejectWith;
    if (reason != null) {
      return ReferralValidationResult.fromMap(<String, dynamic>{
        'is_valid': false,
        'validated_at': 1800000000000,
        'error_code': reason,
        'status_text': rejectMessage,
      });
    }
    return ReferralValidationResult.fromMap(<String, dynamic>{
      'is_valid': true,
      'validated_at': 1800000000000,
      'normalized_code': _code,
      'affiliate_code_id': 'code-1',
      'affiliate_id': 'aff-1',
      'affiliate_name': 'Ana Silva',
      'sale_status': 'ATTRIBUTED',
      'benefit': <String, dynamic>{
        'benefit_type': 'FIXED_AMOUNT',
        'benefit_value': 50,
        'benefit_amount': 50,
        'display_text': '50 MT de desconto',
      },
    });
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
  }) async {
    final key = 'sale:$deviceId:$localSaleId';
    commitRequests.add(<String, Object?>{
      'device_id': deviceId,
      'local_sale_id': localSaleId,
      'customer_id': customerId,
      'customer_phone': customerPhone,
      'gross_amount': grossAmount,
      'code': code,
      'idempotency_key': key,
    });

    final reason = rejectWith;
    if (reason != null) {
      return ReferralSaleCommit.fromMap(<String, dynamic>{
        'outcome': 'rejected',
        'reason': reason,
        'message': rejectMessage,
      });
    }

    final replayed = !committedKeys.add(key);
    return ReferralSaleCommit.fromMap(
      committedAnswer(
        saleId: referralSaleDocumentId(
          deviceId: deviceId,
          localSaleId: localSaleId,
        ),
        customerId: customerId,
        replayed: replayed,
      ),
    );
  }

  /// The answer the reconciliation endpoint gives for a queued offline sale.
  Map<String, dynamic> reconcile(SyncItem item) {
    reconciliations += 1;
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final saleId = item.entityId;
    final reason = rejectWith;
    if (reason != null) {
      return <String, dynamic>{
        'outcome': 'rejected',
        'reason': reason,
        'message': rejectMessage,
        'sale': <String, dynamic>{'id': saleId},
        'referral': <String, dynamic>{
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'attribution_status': 'REJECTED',
          'attribution': <String, dynamic>{
            'id': 'aa_rejected',
            'merchant_id': _merchantId,
            'affiliate_id': 'aff-1',
            'affiliate_code_id': 'code-1',
            'customer_id': payload['customer_id'],
            'status': 'REJECTED',
            'rejection_reason': reason,
            'attributed_at': 6000,
            'created_at': 6000,
            'updated_at': 6000,
          },
        },
      };
    }

    final replayed = !committedKeys.add(saleId);
    return committedAnswer(
      saleId: saleId,
      customerId: payload['customer_id'] as String,
      replayed: replayed,
    );
  }

  Map<String, dynamic> committedAnswer({
    required String saleId,
    required String customerId,
    required bool replayed,
  }) {
    return <String, dynamic>{
      'outcome': replayed ? 'replayed' : 'committed',
      'sale': <String, dynamic>{
        'id': saleId,
        'merchant_id': _merchantId,
        'customer_id': customerId,
        'amount': 450,
        'points': 4,
        'gross_amount': 500,
        'referral_benefit_type': 'FIXED_AMOUNT',
        'referral_benefit_value': 50,
        'referral_benefit_amount': 50,
        'affiliate_code_id': 'code-1',
        'affiliate_id': 'aff-1',
        'referral_status': 'ATTRIBUTED',
        'created_at': 1800000000000,
        'updated_at': 1800000000000,
        'cancellation_status': 'ACTIVE',
      },
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'normalized_code': _code,
        'benefit': <String, dynamic>{
          'type': 'FIXED_AMOUNT',
          'value': 50,
          'discount_amount': 50,
          'points_awarded': 0,
          'display_text': '50 MT de desconto',
        },
        'attribution_id': 'aa_1',
        'attribution_status': 'CONFIRMED',
        'attribution': <String, dynamic>{
          'id': 'aa_1',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'customer_id': customerId,
          'status': 'CONFIRMED',
          'attributed_at': 5000,
          'created_at': 5000,
          'updated_at': 5000,
        },
        'reward': <String, dynamic>{
          'id': 'ar_1',
          'type': 'FIRST_QUALIFYING_SALE',
          'value': 100,
          'status': 'PENDING',
        },
        'reward_record': <String, dynamic>{
          'id': 'ar_1',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-1',
          'attribution_id': 'aa_1',
          'reward_type': 'FIRST_QUALIFYING_SALE',
          'value_type': 'POINTS',
          'value': 100,
          'status': 'PENDING',
          'trigger_sale_id': saleId,
          'created_at': 5000,
          'updated_at': 5000,
        },
      },
      'idempotency_key': 'sale:$_deviceId:$saleId',
      'replayed': replayed,
    };
  }

  /// What the server answers once it has recognised a returning customer.
  Map<String, dynamic> returnAnswer({
    required String saleId,
    required String customerId,
  }) {
    return <String, dynamic>{
      'outcome': 'committed',
      'sale': <String, dynamic>{'id': saleId},
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'attribution_status': 'CONFIRMED',
        'attribution': <String, dynamic>{
          'id': 'aa_1',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'customer_id': customerId,
          'status': 'CONFIRMED',
          'attributed_at': 5000,
          'created_at': 5000,
          'updated_at': 9000,
        },
        'reward_record': <String, dynamic>{
          'id': 'ar_return',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-1',
          'attribution_id': 'aa_1',
          'reward_type': 'CUSTOMER_RETURN',
          'value_type': 'POINTS',
          'value': 40,
          'status': 'PENDING',
          'trigger_sale_id': saleId,
          'created_at': 9000,
          'updated_at': 9000,
        },
      },
      'events': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'ae_return_$saleId',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-1',
          'event_type': 'REFERRED_CUSTOMER_RETURNED',
          'occurred_at': 9000,
          'created_at': 9000,
        },
      ],
    };
  }
}

/// The queue's transport, answering out of the fake server.
class _ServerTransport implements SyncTransport {
  _ServerTransport(this.server);

  final _FakeReferralServer server;
  final List<SyncItem> processed = <SyncItem>[];
  Object? failWith;
  int failuresRemaining = 0;

  @override
  String get transportName => 'fake-server';

  @override
  Future<List<Map<String, dynamic>>> fetchCollection(String entityType) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionSince({
    required String entityType,
    required String orderField,
    int? lastValue,
    String? lastDocId,
    int limit = 200,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<SyncProcessResult?> processSyncItem(SyncItem item) async {
    final failure = failWith;
    if (failure != null && failuresRemaining > 0) {
      failuresRemaining -= 1;
      processed.add(item);
      throw failure;
    }
    processed.add(item);
    if (item.entityType != 'referral_sale') return null;
    return SyncProcessResult(canonicalEntity: server.reconcile(item));
  }
}

class _NoRemoteAffiliates implements AffiliateGateway {
  const _NoRemoteAffiliates();

  @override
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  }) async =>
      const AffiliatePage<MerchantAffiliate>(items: <MerchantAffiliate>[]);

  @override
  Future<AffiliateListView> loadAffiliateList({String? status}) async =>
      const AffiliateListView(items: <AffiliateListItem>[]);

  @override
  Future<MerchantAffiliate> getAffiliate(String affiliateId) =>
      throw UnimplementedError();

  @override
  Future<AffiliateDetailSnapshot> loadAffiliateDetail(String affiliateId) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliate> createAffiliate(AffiliateDraft draft) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliate> setAffiliateActive({
    required String affiliateId,
    required bool active,
  }) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliateCode> updateCode(AffiliateCodeEdit edit) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliateCode> setCodeEnabled({
    required String codeId,
    required bool enabled,
  }) =>
      throw UnimplementedError();

  @override
  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
  }) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliateReward> approveReward(String rewardId) =>
      throw UnimplementedError();

  @override
  Future<MerchantAffiliateReward> cancelReward(String rewardId) =>
      throw UnimplementedError();

  @override
  Future<AffiliateMetricsSummary> merchantMetrics() =>
      throw UnimplementedError();
}

void main() {
  late Database db;
  late SyncDao syncDao;
  late AffiliateLocalRepository offline;
  late AffiliateSaleRepository online;
  late SaleRepository ordinarySales;
  late _FakeReferralServer server;
  late _ServerTransport transport;
  late ConnectivityService connectivity;
  late StreamController<List<ConnectivityResult>> connectivityEvents;
  late SyncService sync;

  Future<void> seedCustomer({
    required String id,
    String phone = '841234567',
    int totalVisits = 0,
    int totalPoints = 0,
  }) async {
    await db.insert('customers', <String, Object?>{
      'id': id,
      'merchant_id': _merchantId,
      'name': 'Joana Cliente',
      'phone': phone,
      'total_points': totalPoints,
      'total_visits': totalVisits,
      'total_spent': totalVisits > 0 ? 400 : 0,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
  }

  Future<void> seedCachedCode({
    int expiresAt = 4102444800000,
    bool firstVisitOnly = true,
  }) async {
    await db.insert('affiliates', <String, Object?>{
      'id': 'aff-1',
      'phone': '+258840000001',
      'normalized_phone': '258840000001',
      'first_name': 'Ana',
      'display_name': 'Ana Silva',
      'status': 'ACTIVE',
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
    await db.insert('affiliate_codes', <String, Object?>{
      'id': 'code-1',
      'merchant_id': _merchantId,
      'affiliate_id': 'aff-1',
      'code': _code,
      'normalized_code': _code,
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': firstVisitOnly ? 1 : 0,
      'status': 'ACTIVE',
      'expires_at': expiresAt,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
    await db.insert('affiliate_code_lookup_cache', <String, Object?>{
      'normalized_code': _code,
      'code_id': 'code-1',
      'merchant_id': _merchantId,
      'affiliate_id': 'aff-1',
      'code': _code,
      'status': 'ACTIVE',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': firstVisitOnly ? 1 : 0,
      'expires_at': expiresAt,
      'cached_at': 1000,
      'updated_at': 1000,
      'affiliate_display_name': 'Ana Silva',
      'affiliate_first_name': 'Ana',
      'affiliate_status': 'ACTIVE',
      'link_status': 'ACTIVE',
      'refreshed_at': 1000,
    });
  }

  Future<List<Map<String, Object?>>> rows(String table) =>
      db.query(table, orderBy: 'rowid ASC');

  setUp(() async {
    db = await setUpFileTestDatabase();
    await db.insert('merchants', <String, Object?>{
      'id': _merchantId,
      'phone': '+258841234500',
      'merchant_name': 'Salão Bela',
      'slug': 'salao-bela',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });

    server = _FakeReferralServer();
    syncDao = SyncDao(
      AppDatabase.instance,
      merchantId: _merchantId,
      deviceId: _deviceId,
    );
    offline = AffiliateLocalRepository(
      AppDatabase.instance,
      AffiliateDao(AppDatabase.instance, merchantId: _merchantId),
      merchantId: _merchantId,
      deviceId: _deviceId,
      gateway: const _NoRemoteAffiliates(),
      pointsPerMzn: 100,
    );
    online = AffiliateSaleRepository(
      AppDatabase.instance,
      server,
      merchantId: _merchantId,
      deviceId: _deviceId,
      appUserId: 'user-1',
    );
    ordinarySales = SaleRepository(
      AppDatabase.instance,
      SaleDao(AppDatabase.instance, merchantId: _merchantId),
      merchantId: _merchantId,
      deviceId: _deviceId,
      appUserId: 'user-1',
    );

    transport = _ServerTransport(server);
    connectivityEvents = StreamController<List<ConnectivityResult>>.broadcast();
    connectivity = ConnectivityService(
      onConnectivityChanged: connectivityEvents.stream,
      checkConnectivity: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      initialOnline: true,
    );
    sync = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
      projections: <SyncProjection>[offline],
    );
  });

  tearDown(() async {
    sync.dispose();
    connectivity.dispose();
    await connectivityEvents.close();
    await tearDownFileTestDatabase();
  });

  /* ========================================================== scenario one */

  group('§12.1 a new customer with a valid code', () {
    setUp(() async {
      await seedCachedCode();
      await seedCustomer(id: 'cust-1');
    });

    test('is discounted, earns ordinary points and keeps one sale', () async {
      final preview = await server.validateCode(
        code: 'afi-ana-7k2p',
        customerPhone: _customerPhone,
        saleAmount: 500,
      );
      expect(preview.isValid, isTrue);
      expect(preview.benefit?.benefitAmount, 50);
      // The panel names the affiliate, never an id.
      expect(preview.affiliateFirstName, 'Ana');

      final commit = await online.commitReferredSale(
        customerId: 'cust-1',
        customerPhone: _customerPhone,
        grossAmount: 500,
        code: 'afi-ana-7k2p',
        localSaleId: 'local-1',
      );

      expect(commit.outcome, ReferralSaleCommitOutcome.committed);
      expect(commit.attributionStatus, 'CONFIRMED');
      expect(commit.reward?.status, 'PENDING');

      final sales = await rows('sales');
      expect(sales, hasLength(1));
      expect(sales.single['amount'], 450.0);
      expect(sales.single['gross_amount'], 500.0);
      // Points on what the customer paid, by the same rule as any other sale.
      expect(sales.single['points'], 4);
      expect(sales.single['referral_status'], 'ATTRIBUTED');
      expect(sales.single['synced'], 1);

      // The customer's points moved once, and the customer — not the sale —
      // is what the queue carries.
      final customer = (await rows('customers')).single;
      expect(customer['total_points'], 4);
      final queued = await rows('sync_queue');
      expect(queued.map((row) => row['entity_type']), <String>['customer']);
    });

    test('never queues the sale, because the server already has it', () async {
      await online.commitReferredSale(
        customerId: 'cust-1',
        customerPhone: _customerPhone,
        grossAmount: 500,
        code: _code,
        localSaleId: 'local-1',
      );

      final queued = await rows('sync_queue');
      expect(
        queued.where((row) => row['entity_type'] == 'referral_sale'),
        isEmpty,
      );
      expect(queued.where((row) => row['entity_type'] == 'sale'), isEmpty);
      expect((await rows('sales')).single['referral_status'], 'ATTRIBUTED');
    });
  });

  /* ========================================================== scenario two */

  test(
      '§12.2 an existing customer is refused and the sale is finished without a code',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-old', totalVisits: 4, totalPoints: 30);
    server.rejectWith = 'CUSTOMER_NOT_ELIGIBLE';
    server.rejectMessage = 'Este código é só para clientes novos.';

    final refused = await online.commitReferredSale(
      customerId: 'cust-old',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );

    expect(refused.outcome, ReferralSaleCommitOutcome.rejected);
    expect(refused.errorCode, ReferralValidationErrorCode.customerNotEligible);
    expect(refused.message, 'Este código é só para clientes novos.');
    // Nothing was written: the basket is still the cashier's to ring up.
    expect(await rows('sales'), isEmpty);
    expect(await rows('sync_queue'), isEmpty);

    // The till falls back to the ordinary sale, which is the path that shipped
    // before this feature and is unchanged by it.
    final ordinary = await ordinarySales.createSale(
      customerId: 'cust-old',
      amount: 500,
    );

    expect(ordinary.amount, 500, reason: 'no discount without an attribution');
    expect(ordinary.points, 5);
    final sales = await rows('sales');
    expect(sales, hasLength(1));
    expect(sales.single['gross_amount'], isNull);
    expect(sales.single['affiliate_code_id'], isNull);
    expect(sales.single['referral_status'], isNull);
    expect(sales.single['referral_idempotency_key'], isNull);

    // And nothing about an affiliate was recorded for it.
    expect(await rows('affiliate_attributions'), isEmpty);
    expect(await rows('affiliate_rewards'), isEmpty);
    expect(
      (await rows('sync_queue')).map((row) => row['entity_type']).toSet(),
      <String>{'sale', 'customer'},
    );
  });

  /* ======================================================== scenario three */

  test('§12.3 an expired code says so plainly and the sale still goes through',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');
    server.rejectWith = 'CODE_EXPIRED';
    server.rejectMessage = 'Este código expirou.';

    final refused = await online.commitReferredSale(
      customerId: 'cust-1',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );

    expect(refused.outcome, ReferralSaleCommitOutcome.rejected);
    expect(refused.message, 'Este código expirou.');
    // A cashier with a customer waiting reads a sentence, not an id.
    expect(refused.message, isNot(contains('aff-1')));
    expect(refused.message, isNot(contains('code-1')));
    expect(await rows('sales'), isEmpty);

    final ordinary = await ordinarySales.createSale(
      customerId: 'cust-1',
      amount: 500,
    );
    expect(ordinary.amount, 500);
    expect((await rows('sales')).single['referral_status'], isNull);
  });

  test(
      '§12.3 an expired code the device already knows about is refused offline too',
      () async {
    // Expired long before the sale: the cache alone is enough to refuse it,
    // which is what stops a discount being given that will not stand.
    await seedCachedCode(expiresAt: 1000);
    await seedCustomer(id: 'cust-1');

    final decision = await offline.previewOfflineReferral(
      code: _code,
      grossAmount: 500,
      customerIsNew: true,
    );

    expect(decision.appliesBenefit, isFalse);

    final result = await offline.recordOfflineReferralSale(
      customerId: 'cust-1',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );

    // The sale is made, at full price, and the code travels with it so the
    // server can still record what was attempted.
    expect(result.benefitApplied, isFalse);
    expect(result.sale.amount, 500);
    expect((await rows('sales')).single['referral_code_input'], _code);
  });

  /* ========================================================= scenario four */

  test(
      '§12.4 a double submit leaves exactly one sale, one movement and one queue row',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');

    Future<ReferralSaleCommit> submit() => online.commitReferredSale(
          customerId: 'cust-1',
          customerPhone: _customerPhone,
          grossAmount: 500,
          code: _code,
          // The same local id: a second tap on the same basket, or a retry
          // after a dropped response.
          localSaleId: 'local-1',
        );

    final first = await submit();
    final second = await submit();
    final third = await submit();

    expect(first.wasReplay, isFalse);
    expect(second.wasReplay, isTrue);
    expect(third.wasReplay, isTrue);
    // Every call carried the same idempotency key, which is why the server
    // could recognise them.
    expect(
      server.commitRequests
          .map((request) => request['idempotency_key'])
          .toSet(),
      <String>{'sale:$_deviceId:local-1'},
    );

    expect(await rows('sales'), hasLength(1));
    expect((await rows('customers')).single['total_points'], 4);
    final queued = await rows('sync_queue');
    expect(
      queued.where((row) => row['entity_type'] == 'customer'),
      hasLength(1),
    );
    expect(queued.where((row) => row['entity_type'] == 'sale'), isEmpty);
  });

  /* ========================================================= scenario five */

  group('§12.5 an offline sale with a cached code', () {
    setUp(() async {
      await seedCachedCode();
      await seedCustomer(id: 'cust-1');
    });

    test('is pending, then confirmed exactly once when the till reconnects',
        () async {
      final offlineSale = await offline.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: _customerPhone,
        grossAmount: 500,
        code: 'afi-ana-7k2p',
        localSaleId: 'local-1',
      );

      // Pending: the benefit is given, the acquisition is not claimed.
      expect(offlineSale.benefitApplied, isTrue);
      expect(offlineSale.sale.amount, 450);
      expect(offlineSale.sale.referralStatus, ReferralSaleStatus.pendingSync);
      expect(await rows('affiliate_attributions'), isEmpty);
      expect(await rows('affiliate_rewards'), isEmpty);
      expect(
        (await syncDao.getPending()).map((item) => item.entityType),
        contains('referral_sale'),
      );

      // Reconnect.
      await sync.processQueue();

      final sale = (await rows('sales')).single;
      expect(sale['referral_status'], 'ATTRIBUTED');
      expect(sale['amount'], 450.0);
      expect(sale['synced'], 1);
      expect(await rows('affiliate_attributions'), hasLength(1));
      expect(await rows('affiliate_rewards'), hasLength(1));
      expect(server.reconciliations, 1);
      expect(await syncDao.getPending(), isEmpty);
    });

    test('is not confirmed twice by a retry storm', () async {
      await offline.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: _customerPhone,
        grossAmount: 500,
        code: _code,
        localSaleId: 'local-1',
      );

      // Three network failures, then the answer, then passes over a queue
      // somebody keeps re-arming: the shape of a flaky reconnect.
      transport.failWith = const SyncTransportException(
        'Unable to resolve host',
        code: 'unavailable',
      );
      transport.failuresRemaining = 3;
      for (var pass = 0; pass < 6; pass++) {
        await db.update('sync_queue', <String, Object?>{
          'next_attempt_at': 0,
          'status': 'pending',
        });
        await sync.processQueue();
      }

      expect(await rows('sales'), hasLength(1));
      expect(await rows('affiliate_attributions'), hasLength(1));
      expect(await rows('affiliate_rewards'), hasLength(1));
      expect((await rows('sales')).single['referral_status'], 'ATTRIBUTED');
      expect(await syncDao.getPending(), isEmpty);
    });

    test('survives the app being killed before it syncs', () async {
      await offline.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: _customerPhone,
        grossAmount: 500,
        code: _code,
        localSaleId: 'local-1',
      );

      db = await reopenFileTestDatabase();

      // Everything is rebuilt the way the app rebuilds it at launch.
      final restartedOffline = AffiliateLocalRepository(
        AppDatabase.instance,
        AffiliateDao(AppDatabase.instance, merchantId: _merchantId),
        merchantId: _merchantId,
        deviceId: _deviceId,
        gateway: const _NoRemoteAffiliates(),
      );
      final restartedSync = SyncService(
        AppDatabase.instance,
        SyncDao(
          AppDatabase.instance,
          merchantId: _merchantId,
          deviceId: _deviceId,
        ),
        transport,
        connectivity,
        projections: <SyncProjection>[restartedOffline],
      );
      addTearDown(restartedSync.dispose);

      expect((await rows('sales')).single['referral_status'], 'PENDING_SYNC');
      await restartedSync.processQueue();

      expect((await rows('sales')).single['referral_status'], 'ATTRIBUTED');
      expect(await rows('affiliate_attributions'), hasLength(1));
      expect(server.reconciliations, 1, reason: 'the restart re-sent the sale');
    });

    test('a night of queued sales reaches the server once each', () async {
      for (var index = 0; index < 8; index++) {
        await seedCustomer(id: 'night-$index', phone: '84100000$index');
        await offline.recordOfflineReferralSale(
          customerId: 'night-$index',
          customerPhone: '+25884100000$index',
          grossAmount: 500,
          code: _code,
          localSaleId: 'local-$index',
        );
      }

      // Eight sales, eight distinct keys: the server can tell them apart.
      final keys = (await rows('sync_queue'))
          .where((row) => row['entity_type'] == 'referral_sale')
          .map((row) => row['idempotency_key'])
          .toSet();
      expect(keys, hasLength(8));

      await sync.processQueue();
      // A second pass over an empty queue must not resend anything.
      await sync.processQueue();

      expect(await rows('sales'), hasLength(8));
      expect(server.reconciliations, 8);
      expect(
        transport.processed
            .where((item) => item.entityType == 'referral_sale')
            .map((item) => item.entityId)
            .toSet(),
        hasLength(8),
        reason: 'two sales shared a canonical id',
      );
      expect(await syncDao.getPending(), isEmpty);
    });
  });

  /* ========================================================== scenario six */

  test(
      '§12.6 a code that expires before the sync keeps the sale and pays nobody',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');

    final offlineSale = await offline.recordOfflineReferralSale(
      customerId: 'cust-1',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );
    expect(offlineSale.benefitApplied, isTrue);

    // Between the sale and the sync, the code expired on the server.
    server.rejectWith = 'CODE_EXPIRED';
    server.rejectMessage = 'Este código expirou.';
    await sync.processQueue();

    final sale = (await rows('sales')).single;
    // The sale stands and the discount stands: the customer has gone home.
    expect(sale['amount'], 450.0);
    expect(sale['gross_amount'], 500.0);
    expect(sale['referral_benefit_amount'], 50.0);
    expect(sale['referral_status'], 'REJECTED');
    expect(sale['referral_rejection_code'], 'CODE_EXPIRED');
    expect(sale['referral_status_message'], 'Este código expirou.');

    // The refusal is history the merchant can read, and nobody is owed.
    final attributions = await rows('affiliate_attributions');
    expect(attributions, hasLength(1));
    expect(attributions.single['status'], 'REJECTED');
    expect(attributions.single['rejection_code'], 'CODE_EXPIRED');
    expect(await rows('affiliate_rewards'), isEmpty);

    // And it is terminal: the queue does not keep asking.
    expect(await syncDao.getPending(), isEmpty);
    await sync.processQueue();
    expect((await rows('sales')).single['referral_status'], 'REJECTED');
    expect(await rows('affiliate_rewards'), isEmpty);
  });

  /* ======================================================== scenario seven */

  test(
      '§12.7 an ordinary return is queued and canonical return records project once',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');

    // The first visit: referred, committed, attributed.
    await online.commitReferredSale(
      customerId: 'cust-1',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );

    // The second visit, a week later, with no code — which is how a return
    // almost always arrives. It takes the ordinary path, untouched.
    final second = await ordinarySales.createSale(
      customerId: 'cust-1',
      amount: 300,
    );
    expect(second.affiliateCodeId, isNull);
    expect(second.referralStatus, isNull);
    expect(second.points, 3);
    expect(
      (await rows('sync_queue'))
          .where((row) => row['entity_type'] == 'sale')
          .map((row) => row['entity_id']),
      <String>[second.id],
    );

    // The backend lifecycle test executes the actual return command and the
    // source-contract test pins its ordinary-sale trigger. This device-side
    // test has two explicit assertions: the return uses the ordinary sale
    // queue, and the server's resulting records project idempotently.
    final canonicalSaleId = (await rows('sales'))
            .firstWhere((row) => row['referral_status'] == 'ATTRIBUTED')['id']
        as String;
    final answer = server.returnAnswer(
      saleId: canonicalSaleId,
      customerId: 'cust-1',
    );
    final item = SyncItem(
      id: 'queue-return',
      operation: 'create',
      entityType: 'referral_sale',
      entityId: canonicalSaleId,
      payload: jsonEncode(<String, dynamic>{'customer_id': 'cust-1'}),
      createdAt: DateTime.fromMillisecondsSinceEpoch(9000),
    );
    await offline.applyCanonical(item, answer);
    await offline.applyCanonical(item, answer);

    final rewards = await rows('affiliate_rewards');
    expect(
      rewards.where((row) => row['reward_type'] == 'CUSTOMER_RETURN'),
      hasLength(1),
    );
    final events = await rows('affiliate_events');
    expect(
      events.where((row) => row['event_type'] == 'REFERRED_CUSTOMER_RETURNED'),
      hasLength(1),
      reason: 'the return was recorded twice',
    );
  });

  /* ============================================== the sale that has no code */

  test('a sale with no code never touches the referral path at all', () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');

    final sale = await ordinarySales.createSale(
      customerId: 'cust-1',
      amount: 500,
    );

    expect(sale.amount, 500);
    expect(sale.points, 5);
    expect(sale.grossAmount, isNull);
    expect(sale.affiliateCodeId, isNull);
    expect(sale.referralStatus, isNull);
    expect(server.commitRequests, isEmpty);
    expect(server.previewRequests, isEmpty);
    expect(server.reconciliations, 0);
    expect(await rows('affiliate_attributions'), isEmpty);
    expect(await rows('affiliate_rewards'), isEmpty);
    expect(
      (await rows('sync_queue')).map((row) => row['entity_type']).toSet(),
      <String>{'sale', 'customer'},
      reason: 'the ordinary sale queue changed shape',
    );
  });

  test('a queued referral operation carries every field the plan requires',
      () async {
    await seedCachedCode();
    await seedCustomer(id: 'cust-1');

    await offline.recordOfflineReferralSale(
      customerId: 'cust-1',
      customerPhone: _customerPhone,
      grossAmount: 500,
      code: _code,
      localSaleId: 'local-1',
    );

    final queued = (await rows('sync_queue')).firstWhere(
      (row) => row['entity_type'] == 'referral_sale',
    );
    for (final column in <String>[
      'local_id',
      'device_id',
      'created_at',
      'idempotency_key',
      'status',
      'retry_count',
    ]) {
      expect(queued[column], isNotNull, reason: '$column is missing');
    }
    expect(queued['idempotency_key'], 'sale:$_deviceId:local-1');
    expect(queued['last_sync_error'], isNull);
    expect(queued['retry_count'], 0);

    // And no phone number is used as a key anywhere in it.
    expect(queued['idempotency_key'].toString(), isNot(contains('841234567')));
    expect(queued['local_id'].toString(), isNot(contains('841234567')));
  });
}
