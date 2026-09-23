import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/affiliates/data/affiliate_dao.dart';
import 'package:maisum/features/affiliates/data/affiliate_local_repository.dart';
import 'package:maisum/features/affiliates/data/affiliate_repository.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';
import 'package:maisum/features/sync/data/sync_projection.dart';
import 'package:maisum/features/sync/data/sync_transport.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';
import 'package:maisum/features/sync/sync_service.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';

/// The queue, carrying an offline referral to the server and back.
///
/// There is one queue and one processor; the affiliate feature is a projection
/// registered with it, not a second engine. These tests exercise the real
/// [SyncService] with a transport that answers the way the backend does, so
/// what is under test is the contract between them — retry policy, canonical
/// projection, terminal failure — rather than a reimplementation of it.
const _merchantId = 'shop-1';
const _deviceId = 'till-1';

class _ScriptedTransport implements SyncTransport {
  _ScriptedTransport();

  final List<SyncItem> processed = <SyncItem>[];
  final Map<String, Map<String, dynamic>> answers =
      <String, Map<String, dynamic>>{};
  Object? failWith;
  int failuresRemaining = 0;

  @override
  String get transportName => 'scripted';

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
    final answer = answers[item.entityType];
    if (answer == null) return null;
    return SyncProcessResult(canonicalEntity: answer);
  }
}

class _EmptyGateway implements AffiliateGateway {
  const _EmptyGateway();

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

class _FailingOnceProjection implements SyncProjection {
  _FailingOnceProjection(this.delegate);

  final SyncProjection delegate;
  bool _failed = false;

  @override
  Set<String> get entityTypes => delegate.entityTypes;

  @override
  Future<String?> applyCanonical(
    SyncItem item,
    Map<String, dynamic> canonical,
  ) {
    if (!_failed) {
      _failed = true;
      throw StateError('local database temporarily unavailable');
    }
    return delegate.applyCanonical(item, canonical);
  }

  @override
  Future<void> applyFailure(SyncItem item, {required String reason}) =>
      delegate.applyFailure(item, reason: reason);

  @override
  Future<void> refreshReadCaches() => delegate.refreshReadCaches();
}

void main() {
  late Database db;
  late SyncDao syncDao;
  late AffiliateLocalRepository repository;
  late _ScriptedTransport transport;
  late ConnectivityService connectivity;
  late StreamController<List<ConnectivityResult>> connectivityController;
  late SyncService service;

  Future<void> seedCachedCode() async {
    await db.insert('affiliates', <String, Object?>{
      'id': 'aff-1',
      'phone': '+258841110000',
      'normalized_phone': '258841110000',
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
      'code': 'AFI-ANA-7K2P',
      'normalized_code': 'AFI-ANA-7K2P',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': 1,
      'status': 'ACTIVE',
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
    await db.insert('affiliate_code_lookup_cache', <String, Object?>{
      'normalized_code': 'AFI-ANA-7K2P',
      'code_id': 'code-1',
      'merchant_id': _merchantId,
      'affiliate_id': 'aff-1',
      'code': 'AFI-ANA-7K2P',
      'status': 'ACTIVE',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'usage_count': 0,
      'first_visit_only': 1,
      'cached_at': 1000,
      'updated_at': 1000,
      'affiliate_display_name': 'Ana Silva',
      'affiliate_first_name': 'Ana',
      'affiliate_status': 'ACTIVE',
      'link_status': 'ACTIVE',
      'refreshed_at': 1000,
    });
    await db.insert('customers', <String, Object?>{
      'id': 'cust-1',
      'merchant_id': _merchantId,
      'name': 'Ana Cliente',
      'phone': '841234567',
      'total_points': 0,
      'total_visits': 0,
      'total_spent': 0,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 1,
    });
  }

  setUp(() async {
    db = await setUpTestDatabase();
    await db.insert('merchants', <String, Object?>{
      'id': _merchantId,
      'phone': '+258841234567',
      'merchant_name': 'Salão Bela',
      'slug': 'salao-bela',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
    syncDao = SyncDao(
      AppDatabase.instance,
      merchantId: _merchantId,
      deviceId: _deviceId,
    );
    repository = AffiliateLocalRepository(
      AppDatabase.instance,
      AffiliateDao(AppDatabase.instance, merchantId: _merchantId),
      merchantId: _merchantId,
      deviceId: _deviceId,
      gateway: const _EmptyGateway(),
    );
    transport = _ScriptedTransport();
    connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    connectivity = ConnectivityService(
      onConnectivityChanged: connectivityController.stream,
      checkConnectivity: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      initialOnline: true,
    );
    service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
      projections: <SyncProjection>[repository],
    );
    await seedCachedCode();
  });

  tearDown(() async {
    service.dispose();
    connectivity.dispose();
    await connectivityController.close();
    await tearDownTestDatabase();
  });

  Future<String> queueOfflineSale({String localSaleId = 'local-sale-1'}) async {
    final result = await repository.recordOfflineReferralSale(
      customerId: 'cust-1',
      customerPhone: '+258841234567',
      grossAmount: 300,
      code: 'AFI-ANA-7K2P',
      localSaleId: localSaleId,
    );
    return result.sale.id;
  }

  test('the referral sale is sent as one authoritative operation', () async {
    final saleId = await queueOfflineSale();
    transport.answers['referral_sale'] = <String, dynamic>{
      'outcome': 'committed',
      'sale': <String, dynamic>{'id': saleId},
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'attribution_status': 'CONFIRMED',
      },
    };

    await service.processQueue();

    // The ordinary sale path was not used: exactly one referral operation and
    // the customer's own totals, which is what an ordinary sale sends too.
    final sent = transport.processed.map((item) => item.entityType).toList();
    expect(sent, containsAll(<String>['referral_sale', 'customer']));
    expect(sent.where((type) => type == 'referral_sale'), hasLength(1));
    expect(sent.where((type) => type == 'sale'), isEmpty);

    final sale = (await db.query('sales')).single;
    expect(sale['referral_status'], 'ATTRIBUTED');
    expect(sale['synced'], 1);
    expect(await syncDao.getPending(), isEmpty);
  });

  test('a transient failure defers the operation without burning retries',
      () async {
    await queueOfflineSale();
    transport.failWith = const SyncTransportException(
      'Unable to resolve host',
      code: 'unavailable',
    );
    transport.failuresRemaining = 10;

    await service.processQueue();

    final stats = await syncDao.getStats();
    // Deferred, not failed: a retry storm against an outage is how a queue
    // exhausts itself and drops a real sale.
    expect(stats.pendingTotal, greaterThanOrEqualTo(1));
    expect(stats.failed, 0);
    expect(stats.pendingReady, 0);

    final sale = (await db.query('sales')).single;
    expect(sale['referral_status'], 'PENDING_SYNC');
  });

  test('a transient failure then success leaves one canonical set', () async {
    final saleId = await queueOfflineSale();
    transport.failWith = const SyncTransportException(
      'Unable to resolve host',
      code: 'unavailable',
    );
    transport.failuresRemaining = 1;
    transport.answers['referral_sale'] = <String, dynamic>{
      'outcome': 'committed',
      'sale': <String, dynamic>{'id': saleId},
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'attribution_status': 'CONFIRMED',
        'attribution': <String, dynamic>{
          'id': 'aa_1',
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'customer_id': 'cust-1',
          'status': 'CONFIRMED',
          'attributed_at': 5000,
          'created_at': 5000,
          'updated_at': 5000,
        },
      },
    };

    await service.processQueue();
    // The transient failure deferred the item with a backoff. Fast-forwarding
    // the schedule is what a later sync pass does; the point of the test is
    // what the second attempt writes, not how long it waits.
    await db.update('sync_queue', <String, Object?>{'next_attempt_at': 0});
    await service.processQueue();
    // A third pass is the replay the plan asks about: the same answer again.
    await db.update('sync_queue', <String, Object?>{
      'next_attempt_at': 0,
      'status': 'pending',
    });
    await service.processQueue();

    expect(await db.query('sales'), hasLength(1));
    expect(await db.query('affiliate_attributions'), hasLength(1));
    expect(await syncDao.getPending(), isEmpty);
  });

  test('a local projection failure retries the idempotent server answer',
      () async {
    final saleId = await queueOfflineSale();
    transport.answers['referral_sale'] = <String, dynamic>{
      'outcome': 'committed',
      'sale': <String, dynamic>{'id': saleId},
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'attribution_status': 'CONFIRMED',
      },
    };
    service.dispose();
    service = SyncService(
      AppDatabase.instance,
      syncDao,
      transport,
      connectivity,
      projections: <SyncProjection>[
        _FailingOnceProjection(repository),
      ],
    );

    await service.processQueue();

    final deferred = (await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: <Object?>['referral_sale'],
    ))
        .single;
    expect(deferred['status'], 'pending');
    expect(deferred['retry_count'], 1);
    expect((await db.query('sales')).single['referral_status'], 'PENDING_SYNC');

    await db.update(
      'sync_queue',
      <String, Object?>{'next_attempt_at': 0},
      where: 'entity_type = ?',
      whereArgs: <Object?>['referral_sale'],
    );
    await service.processQueue();

    expect((await db.query('sales')).single['referral_status'], 'ATTRIBUTED');
    expect(
      transport.processed.where((item) => item.entityType == 'referral_sale'),
      hasLength(2),
    );
    expect(
      await db.query(
        'sync_queue',
        where: 'entity_type = ?',
        whereArgs: <Object?>['referral_sale'],
      ),
      isEmpty,
    );
  });

  test('a permanent refusal closes the referral and keeps the sale', () async {
    await queueOfflineSale();
    transport.failWith = const SyncTransportException(
      'Sem permissão',
      code: 'permission-denied',
    );
    transport.failuresRemaining = 5;

    await service.processQueue();

    final sale = (await db.query('sales')).single;
    // The sale and the discount stand; only the referral is closed, and it is
    // closed as refused rather than left pending forever.
    expect(sale['referral_status'], 'REJECTED');
    expect(sale['amount'], 250.0);
    expect(sale['gross_amount'], 300.0);
    expect(sale['referral_benefit_amount'], 50.0);
    expect(await db.query('affiliate_rewards'), isEmpty);
  });

  test('a rejected code keeps the operation done, not retried', () async {
    final saleId = await queueOfflineSale();
    transport.answers['referral_sale'] = <String, dynamic>{
      'outcome': 'rejected',
      'reason': 'CODE_EXPIRED',
      'message': 'Código expirado.',
      'sale': <String, dynamic>{'id': saleId},
      'referral': <String, dynamic>{
        'affiliate_id': 'aff-1',
        'affiliate_code_id': 'code-1',
        'attribution': <String, dynamic>{
          'id': 'aa_rejected',
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'customer_id': 'cust-1',
          'status': 'REJECTED',
          'rejection_reason': 'CODE_EXPIRED',
          'attributed_at': 6000,
          'created_at': 6000,
          'updated_at': 6000,
        },
      },
    };

    await service.processQueue();

    // A refused code is a completed request, not a failed one: sending it again
    // would ask the server to refuse the same sale forever.
    expect(await syncDao.getPending(), isEmpty);
    expect(await syncDao.getFailedCount(), 0);
    final sale = (await db.query('sales')).single;
    expect(sale['referral_status'], 'REJECTED');
    expect(sale['referral_rejection_code'], 'CODE_EXPIRED');
    expect(
      (await db.query('affiliate_attributions')).single['status'],
      'REJECTED',
    );
  });

  test('a batch of queued sales all reach the server once each', () async {
    for (var index = 0; index < 8; index += 1) {
      await db.insert('customers', <String, Object?>{
        'id': 'cust-b$index',
        'merchant_id': _merchantId,
        'name': 'Cliente $index',
        'phone': '8412345${70 + index}',
        'total_points': 0,
        'total_visits': 0,
        'total_spent': 0,
        'created_at': 1000,
        'updated_at': 1000,
        'synced': 1,
      });
      await repository.recordOfflineReferralSale(
        customerId: 'cust-b$index',
        customerPhone: '+2588412345${70 + index}',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-batch-$index',
      );
    }

    await service.processQueue();

    final referralOps = transport.processed
        .where((item) => item.entityType == 'referral_sale')
        .toList();
    expect(referralOps, hasLength(8));
    expect(
      referralOps.map((item) => item.entityId).toSet(),
      hasLength(8),
    );
    expect(await syncDao.getPending(), isEmpty);
  });

  test('a provisional affiliate converges on the server identity', () async {
    final provisional = await repository.createAffiliateOffline(
      const AffiliateDraft(
        name: 'Beatriz Cossa',
        phone: '+258849998888',
        benefitType: 'FIXED_AMOUNT',
        benefitValue: 40,
      ),
    );
    transport.answers['affiliate'] = <String, dynamic>{
      'outcome': 'committed',
      'local_affiliate_id': provisional.affiliateId,
      'affiliate': <String, dynamic>{
        'id': 'aff-server',
        'merchant_id': _merchantId,
        'name': 'Beatriz Cossa',
        'first_name': 'Beatriz',
        'status': 'ACTIVE',
        'link_status': 'ACTIVE',
        'phone': '+258849998888',
        'code': <String, dynamic>{
          'id': 'code-server',
          'merchant_id': _merchantId,
          'affiliate_id': 'aff-server',
          'code': 'AFI-BEATRIZ-3K9P',
          'normalized_code': 'AFI-BEATRIZ-3K9P',
          'benefit_type': 'FIXED_AMOUNT',
          'benefit_value': 40,
          'status': 'ACTIVE',
          'usage_count': 0,
          'first_visit_only': true,
        },
      },
    };

    await service.processQueue();

    expect(await repository.provisionalAffiliates(), isEmpty);
    final affiliates = await db.query(
      'affiliates',
      where: 'display_name = ?',
      whereArgs: <Object?>['Beatriz Cossa'],
    );
    expect(affiliates, hasLength(1));
    expect(affiliates.single['id'], 'aff-server');
    expect(await syncDao.getPending(), isEmpty);
  });

  test('the payload carries the queue metadata the server keys on', () async {
    await queueOfflineSale();
    transport.answers['referral_sale'] = const <String, dynamic>{
      'outcome': 'deferred',
    };

    final queued = (await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: <Object?>['referral_sale'],
    ))
        .single;
    final payload =
        jsonDecode(queued['payload'] as String) as Map<String, dynamic>;
    expect(payload['device_id'], _deviceId);
    expect(payload['local_sale_id'], 'local-sale-1');
    expect(payload['idempotency_key'], 'sale:till-1:local-sale-1');
    expect(payload['merchant_id'], _merchantId);
  });
}
