import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/affiliates/data/affiliate_dao.dart';
import 'package:maisum/features/affiliates/data/affiliate_local_repository.dart';
import 'package:maisum/features/affiliates/data/affiliate_repository.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/domain/offline_referral.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/data/sale_repository.dart';
import 'package:maisum/features/sync/domain/sync_item.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/test_database.dart';

/// A sale made while the connection is down.
///
/// The invariant every test here defends is the same one: one purchase, one
/// local row, one authoritative operation. A till that wrote an ordinary sale
/// and a separate referral record would be billing the customer twice in the
/// books, and a till that queued two operations for one basket would have the
/// server write the sale twice.
const _merchantId = 'shop-1';
const _deviceId = 'till-1';

class _StaticGateway implements AffiliateGateway {
  _StaticGateway(this.affiliates);

  List<MerchantAffiliate> affiliates;
  int listCalls = 0;
  Object? error;

  @override
  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
  }) async {
    listCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return AffiliatePage<MerchantAffiliate>(items: affiliates);
  }

  @override
  Future<AffiliateListView> loadAffiliateList({String? status}) async =>
      AffiliateListView(
        items: <AffiliateListItem>[
          for (final affiliate in affiliates)
            AffiliateListItem(affiliate: affiliate),
        ],
      );

  @override
  Future<MerchantAffiliate> getAffiliate(String affiliateId) async =>
      affiliates.firstWhere((affiliate) => affiliate.id == affiliateId);

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

MerchantAffiliate _remoteAffiliate({
  String id = 'aff-1',
  String codeId = 'code-1',
  String code = 'AFI-ANA-7K2P',
  ReferralBenefitType benefitType = ReferralBenefitType.fixedAmount,
  double benefitValue = 50,
  AffiliateCodeStatus codeStatus = AffiliateCodeStatus.active,
  DateTime? expiresAt,
  int? usageLimit,
  int usageCount = 0,
  bool firstVisitOnly = true,
  AffiliateStatus status = AffiliateStatus.active,
  AffiliateMerchantStatus linkStatus = AffiliateMerchantStatus.active,
  String name = 'Ana Silva',
  String phone = '+258841110000',
}) {
  return MerchantAffiliate(
    id: id,
    merchantId: _merchantId,
    name: name,
    firstName: name.split(' ').first,
    status: status,
    linkStatus: linkStatus,
    phone: phone,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 3, 1),
    code: MerchantAffiliateCode(
      id: codeId,
      merchantId: _merchantId,
      affiliateId: id,
      code: code,
      normalizedCode: code,
      benefitType: benefitType,
      benefitValue: benefitValue,
      status: codeStatus,
      expiresAt: expiresAt,
      usageLimit: usageLimit,
      usageCount: usageCount,
      firstVisitOnly: firstVisitOnly,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 3, 1),
    ),
  );
}

void main() {
  late Database db;
  late AffiliateDao dao;
  late _StaticGateway gateway;
  late AffiliateLocalRepository repository;

  Future<void> seedCustomer({
    String id = 'cust-1',
    int totalVisits = 0,
    int totalPoints = 0,
  }) async {
    await db.insert('customers', <String, Object?>{
      'id': id,
      'merchant_id': _merchantId,
      'name': 'Ana Cliente',
      // Phones are uniquely indexed per merchant; deriving one from the id
      // keeps a test that needs several customers honest about that.
      'phone': '84${(1000000 + id.hashCode.abs() % 8999999)}',
      'total_points': totalPoints,
      'total_visits': totalVisits,
      'total_spent': 0,
      'created_at': 1000,
      'updated_at': 1000,
      'synced': 0,
    });
  }

  setUp(() async {
    db = await setUpFileTestDatabase();
    await db.insert('merchants', <String, Object?>{
      'id': _merchantId,
      'phone': '+258841234567',
      'merchant_name': 'Salão Bela',
      'slug': 'salao-bela',
      'subscription_status': 'TRIAL',
      'created_at': 1,
      'updated_at': 1,
    });
    dao = AffiliateDao(AppDatabase.instance, merchantId: _merchantId);
    gateway = _StaticGateway(<MerchantAffiliate>[]);
    repository = AffiliateLocalRepository(
      AppDatabase.instance,
      dao,
      merchantId: _merchantId,
      deviceId: _deviceId,
      gateway: gateway,
      pointsPerMzn: 100,
    );
  });

  tearDown(() async => tearDownFileTestDatabase());

  group('active code cache', () {
    test('a sync refreshes the codes a till can honour offline', () async {
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate()];

      await repository.refreshReadCaches();

      final cached = await dao.findCachedCode('AFI-ANA-7K2P');
      expect(cached, isNotNull);
      expect(cached!.benefitType, ReferralBenefitType.fixedAmount);
      expect(cached.benefitValue, 50);
      expect(cached.firstVisitOnly, isTrue);
      // The display data a cashier reads back, which v30 did not carry.
      expect(cached.affiliateDisplayName, 'Ana Silva');
      expect(cached.affiliateFirstName, 'Ana');
      expect(cached.affiliateStatus, 'ACTIVE');
      expect(cached.linkStatus, 'ACTIVE');
      expect(cached.refreshedAt, isNotNull);
    });

    test('a code the server stopped sending stops being honoured', () async {
      gateway.affiliates = <MerchantAffiliate>[
        _remoteAffiliate(),
        _remoteAffiliate(
          id: 'aff-2',
          codeId: 'code-2',
          code: 'AFI-BEA-9X4M',
          name: 'Beatriz Cossa',
          phone: '+258841110001',
        ),
      ];
      await repository.refreshReadCaches();
      expect(await dao.cachedCodeCount(), 2);

      // A disabled or unlinked code disappears from the API answer; a merge
      // would leave the till still granting its discount.
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate()];
      await repository.refreshReadCaches();

      expect(await dao.cachedCodeCount(), 1);
      expect(await dao.findCachedCode('AFI-BEA-9X4M'), isNull);
    });

    test('a second refresh is an update, not a duplicate', () async {
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate(usageCount: 1)];
      await repository.refreshReadCaches();
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate(usageCount: 4)];
      await repository.refreshReadCaches();

      expect(await dao.cachedCodeCount(), 1);
      expect((await dao.findCachedCode('AFI-ANA-7K2P'))!.usageCount, 4);
      expect(await db.query('affiliate_codes'), hasLength(1));
      expect(await db.query('affiliates'), hasLength(1));
    });
  });

  group('offline sale with a cached code', () {
    setUp(() async {
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate()];
      await repository.refreshReadCaches();
      await seedCustomer();
    });

    test('applies a fixed benefit and leaves the referral pending', () async {
      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'afi-ana-7k2p',
        localSaleId: 'local-sale-1',
      );

      expect(result.benefitApplied, isTrue);
      expect(result.sale.amount, 250);
      expect(result.sale.grossAmount, 300);
      expect(result.sale.referralBenefitAmount, 50);
      expect(result.sale.referralStatus, ReferralSaleStatus.pendingSync);
      // Points are earned on what the customer actually paid, exactly as the
      // online commit computes them.
      expect(result.sale.points, 2);

      // The row carries the id the server will derive, so the canonical sale
      // and this one are never two rows for one purchase.
      expect(
        result.sale.id,
        referralSaleDocumentId(
          deviceId: _deviceId,
          localSaleId: 'local-sale-1',
        ),
      );

      final sales = await db.query('sales');
      expect(sales, hasLength(1));
      expect(sales.single['referral_code_input'], 'AFI-ANA-7K2P');
      expect(sales.single['affiliate_code_id'], 'code-1');
      expect(sales.single['affiliate_id'], 'aff-1');
      expect(sales.single['referral_local_benefit_applied'], 1);
      expect(
        sales.single['referral_idempotency_key'],
        'sale:till-1:local-sale-1',
      );
    });

    test('queues one authoritative operation, never an ordinary sale',
        () async {
      await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-sale-1',
      );

      final queued = await db.query('sync_queue', orderBy: 'created_at ASC');
      expect(
        queued.map((row) => row['entity_type']),
        <String>['referral_sale', 'customer'],
      );

      final referral = queued.first;
      expect(referral['merchant_id'], _merchantId);
      expect(referral['device_id'], _deviceId);
      expect(referral['local_id'], 'local-sale-1');
      expect(referral['idempotency_key'], 'sale:till-1:local-sale-1');
      expect(referral['retry_count'], 0);
      expect(referral['status'], 'pending');
      expect(referral['last_sync_error'], isNull);

      final payload =
          jsonDecode(referral['payload'] as String) as Map<String, dynamic>;
      // The gross and the customer are immutable facts about the sale; the
      // benefit is reported as what was given, never as what is owed.
      expect(payload['gross_amount'], 300);
      expect(payload['net_amount'], 250);
      expect(payload['code'], 'AFI-ANA-7K2P');
      expect(payload['offline_benefit_applied'], isTrue);
      expect(payload['applied_benefit']['discount_amount'], 50);
      expect(payload['customer_phone'], '+258841234567');
      expect(payload['created_at'], isA<int>());
    });

    test('a percentage benefit uses the same rounding as the server', () async {
      gateway.affiliates = <MerchantAffiliate>[
        _remoteAffiliate(
          benefitType: ReferralBenefitType.percentage,
          benefitValue: 10,
        ),
      ];
      await repository.refreshReadCaches();

      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 333.33,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-pct',
      );

      expect(result.sale.referralBenefitAmount, 33.33);
      expect(result.sale.amount, 300.0);
    });

    test('a points benefit changes no money and credits nothing locally',
        () async {
      gateway.affiliates = <MerchantAffiliate>[
        _remoteAffiliate(
          benefitType: ReferralBenefitType.points,
          benefitValue: 120,
        ),
      ];
      await repository.refreshReadCaches();

      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-points',
      );

      expect(result.sale.amount, 300);
      expect(result.sale.referralBenefitType, ReferralBenefitType.points);
      expect(result.sale.referralBenefitAmount, 120);

      // The promotional points are a server-owned ledger entry. Adding them to
      // the balance here would be inventing a confirmed promotion for a code
      // the server has not agreed to.
      final customer = (await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: <Object?>['cust-1'],
      ))
          .single;
      expect(customer['total_points'], 3);
      expect(await db.query('loyalty_ledger'), isEmpty);
    });

    test('an expired code grants nothing but keeps the sale and the code',
        () async {
      gateway.affiliates = <MerchantAffiliate>[
        _remoteAffiliate(expiresAt: DateTime(2020, 1, 1)),
      ];
      await repository.refreshReadCaches();

      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-expired',
      );

      expect(result.benefitApplied, isFalse);
      expect(
        result.decision.errorCode,
        ReferralValidationErrorCode.codeExpired,
      );
      expect(result.sale.amount, 300);
      expect(result.sale.referralBenefitAmount, isNull);
      expect(result.sale.referralStatus, ReferralSaleStatus.pendingSync);

      final sale = (await db.query('sales')).single;
      expect(sale['referral_code_input'], 'AFI-ANA-7K2P');
      expect(sale['referral_local_benefit_applied'], 0);
    });

    test('a code this device never saw grants nothing and is still carried',
        () async {
      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ZZZ-0000',
        localSaleId: 'local-unknown',
      );

      expect(result.decision.isKnownCode, isFalse);
      expect(result.benefitApplied, isFalse);
      expect(result.sale.amount, 300);
      expect(result.sale.affiliateCodeId, isNull);

      final sale = (await db.query('sales')).single;
      expect(sale['referral_code_input'], 'AFI-ZZZ-0000');
      final payload = jsonDecode(
        (await db.query(
          'sync_queue',
          where: 'entity_type = ?',
          whereArgs: <Object?>['referral_sale'],
        ))
            .single['payload'] as String,
      ) as Map<String, dynamic>;
      expect(payload['code'], 'AFI-ZZZ-0000');
      expect(payload['offline_benefit_applied'], isFalse);
      expect(payload.containsKey('applied_benefit'), isFalse);
    });

    test('a provisional code is refused by the device that invented it',
        () async {
      final decision = await repository.previewOfflineReferral(
        code: 'LOCAL-ANA-4F2A91',
        grossAmount: 300,
        customerIsNew: true,
      );
      expect(decision.appliesBenefit, isFalse);
      expect(
        decision.errorCode,
        ReferralValidationErrorCode.codeNotFound,
      );
    });

    test('many queued sales keep their own keys and ids', () async {
      for (var index = 0; index < 12; index += 1) {
        await seedCustomer(id: 'cust-batch-$index');
        await repository.recordOfflineReferralSale(
          customerId: 'cust-batch-$index',
          customerPhone: '+25884123456$index',
          grossAmount: 300,
          code: 'AFI-ANA-7K2P',
          localSaleId: 'local-batch-$index',
        );
      }

      final sales = await db.query('sales');
      expect(sales, hasLength(12));
      expect(sales.map((row) => row['id']).toSet(), hasLength(12));

      final queued = await db.query(
        'sync_queue',
        where: 'entity_type = ?',
        whereArgs: <Object?>['referral_sale'],
      );
      expect(queued, hasLength(12));
      expect(
        queued.map((row) => row['idempotency_key']).toSet(),
        hasLength(12),
      );
    });

    test('the queued operation survives a restart', () async {
      await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-restart',
      );

      // Closing and reopening is the only honest way to assert this: an
      // operation held in memory is one a crash loses, and a sale nobody ever
      // reports is an affiliate never paid.
      db = await reopenFileTestDatabase();

      final queued = await db.query(
        'sync_queue',
        where: 'entity_type = ? AND status = ?',
        whereArgs: <Object?>['referral_sale', 'pending'],
      );
      expect(queued, hasLength(1));
      expect(queued.single['idempotency_key'], 'sale:till-1:local-restart');

      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'PENDING_SYNC');
      expect(sale['referral_local_benefit_applied'], 1);
    });
  });

  group('offline affiliate creation', () {
    const draft = AffiliateDraft(
      name: 'Beatriz Cossa',
      phone: '+258849998888',
      benefitType: 'FIXED_AMOUNT',
      benefitValue: 40,
      usageLimit: 10,
    );

    test('writes the person, the link and one provisional code', () async {
      final queuedAffiliate = await repository.createAffiliateOffline(draft);

      expect(queuedAffiliate.provisionalCode, startsWith('LOCAL-BEATRIZ-'));
      expect(queuedAffiliate.syncStatus, AffiliateSyncStatus.pending);

      expect(await db.query('affiliates'), hasLength(1));
      expect(await db.query('affiliate_merchants'), hasLength(1));
      final codes = await db.query('affiliate_codes');
      expect(codes, hasLength(1));
      expect(codes.single['provisional'], 1);
      expect(codes.single['sync_status'], 'PENDING');

      // A provisional code is never cached as usable: the device that invented
      // it must not honour it either.
      expect(await dao.cachedCodeCount(), 0);

      final queued = (await db.query(
        'sync_queue',
        where: 'entity_type = ?',
        whereArgs: <Object?>['affiliate'],
      ))
          .single;
      expect(queued['device_id'], _deviceId);
      expect(queued['local_id'], queuedAffiliate.localId);
      expect(
        queued['idempotency_key'],
        'affiliate:$_deviceId:${queuedAffiliate.localId}',
      );
      final payload =
          jsonDecode(queued['payload'] as String) as Map<String, dynamic>;
      expect(payload['name'], 'Beatriz Cossa');
      expect(payload['phone'], '+258849998888');
      expect(payload['benefit_type'], 'FIXED_AMOUNT');
      expect(payload['created_at'], isA<int>());
    });

    test('the server answer replaces the guess without duplicating the row',
        () async {
      final queuedAffiliate = await repository.createAffiliateOffline(draft);

      final canonical = _remoteAffiliate(
        id: 'aff-server',
        codeId: 'code-server',
        code: 'AFI-BEATRIZ-3K9P',
        name: 'Beatriz Cossa',
      );
      await repository.applyCanonical(
        SyncItem(
          id: 'q1',
          operation: 'create',
          entityType: affiliateSyncEntityType,
          entityId: queuedAffiliate.affiliateId,
          payload: '{}',
          createdAt: DateTime.now(),
        ),
        <String, dynamic>{
          'outcome': 'committed',
          'local_affiliate_id': queuedAffiliate.affiliateId,
          'affiliate': <String, dynamic>{
            'id': canonical.id,
            'merchant_id': _merchantId,
            'name': canonical.name,
            'first_name': canonical.firstName,
            'status': 'ACTIVE',
            'link_status': 'ACTIVE',
            'code': <String, dynamic>{
              'id': canonical.code!.id,
              'merchant_id': _merchantId,
              'affiliate_id': canonical.id,
              'code': canonical.code!.code,
              'normalized_code': canonical.code!.normalizedCode,
              'benefit_type': 'FIXED_AMOUNT',
              'benefit_value': 40,
              'status': 'ACTIVE',
              'usage_count': 0,
              'first_visit_only': true,
            },
          },
        },
      );

      final affiliates = await db.query('affiliates');
      expect(affiliates, hasLength(1));
      expect(affiliates.single['id'], 'aff-server');
      expect(affiliates.single['provisional'], 0);
      expect(affiliates.single['sync_status'], 'SYNCED');

      final codes = await db.query('affiliate_codes');
      expect(codes, hasLength(1));
      expect(codes.single['code'], 'AFI-BEATRIZ-3K9P');

      // The real code is immediately usable offline; the provisional one is
      // gone from every list.
      expect(await dao.findCachedCode('AFI-BEATRIZ-3K9P'), isNotNull);
      expect(await repository.provisionalAffiliates(), isEmpty);
    });

    test('a refusal keeps the row and says why', () async {
      final queuedAffiliate = await repository.createAffiliateOffline(draft);

      await repository.applyFailure(
        SyncItem(
          id: 'q1',
          operation: 'create',
          entityType: affiliateSyncEntityType,
          entityId: queuedAffiliate.affiliateId,
          payload: '{}',
          createdAt: DateTime.now(),
        ),
        reason: 'Este afiliado já está ligado a este negócio.',
      );

      final provisional = await repository.provisionalAffiliates();
      expect(provisional, hasLength(1));
      expect(provisional.single.isRejected, isTrue);
      expect(
        provisional.single.lastSyncError,
        'Este afiliado já está ligado a este negócio.',
      );
    });
  });

  group('the server answer, projected', () {
    late SyncItem item;

    setUp(() async {
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate()];
      await repository.refreshReadCaches();
      await seedCustomer();
      final result = await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-sale-1',
      );
      item = SyncItem(
        id: 'q1',
        operation: 'create',
        entityType: referralSaleSyncEntityType,
        entityId: result.sale.id,
        payload: '{}',
        createdAt: DateTime.now(),
      );
    });

    Map<String, dynamic> committedAnswer() => <String, dynamic>{
          'outcome': 'committed',
          'sale': <String, dynamic>{'id': item.entityId},
          'referral': <String, dynamic>{
            'affiliate_id': 'aff-1',
            'affiliate_code_id': 'code-1',
            'attribution_status': 'CONFIRMED',
            'monetary_benefit_applied': true,
            'attribution': <String, dynamic>{
              'id': 'aa_1',
              'merchant_id': _merchantId,
              'affiliate_id': 'aff-1',
              'affiliate_code_id': 'code-1',
              'customer_id': 'cust-1',
              'qualifying_sale_id': item.entityId,
              'status': 'CONFIRMED',
              'idempotency_key': 'affiliate-attribution:shop-1:hash',
              'attributed_at': 5000,
              'created_at': 5000,
              'updated_at': 5000,
            },
            'reward_record': <String, dynamic>{
              'id': 'ar_1',
              'affiliate_id': 'aff-1',
              'attribution_id': 'aa_1',
              'reward_type': 'FIRST_QUALIFYING_SALE',
              'value_type': 'POINTS',
              'value': 100,
              'status': 'PENDING',
              'idempotency_key': 'affiliate-reward:aa_1:FIRST_QUALIFYING_SALE',
              'created_at': 5000,
              'updated_at': 5000,
            },
          },
          'events': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'ae_1',
              'affiliate_id': 'aff-1',
              'event_type': 'REFERRAL_ATTRIBUTED',
              'attribution_id': 'aa_1',
              'sale_id': item.entityId,
              'customer_id': 'cust-1',
              'occurred_at': 5000,
              'created_at': 5000,
            },
          ],
        };

    test('an accepted referral confirms the sale and stores the records',
        () async {
      await repository.applyCanonical(item, committedAnswer());

      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'ATTRIBUTED');
      expect(sale['referral_status_message'], isNull);
      expect(sale['synced'], 1);
      // The money is untouched: the customer paid 250 and paid 250.
      expect(sale['amount'], 250.0);

      final attributions = await db.query('affiliate_attributions');
      expect(attributions, hasLength(1));
      expect(
        attributions.single['idempotency_key'],
        'affiliate-attribution:shop-1:hash',
      );
      expect(await db.query('affiliate_rewards'), hasLength(1));
      expect(await db.query('affiliate_events'), hasLength(1));
    });

    test('replaying the same answer converges on one canonical set', () async {
      await repository.applyCanonical(item, committedAnswer());
      await repository.applyCanonical(item, committedAnswer());

      expect(await db.query('sales'), hasLength(1));
      expect(await db.query('affiliate_attributions'), hasLength(1));
      expect(await db.query('affiliate_rewards'), hasLength(1));
      expect(await db.query('affiliate_events'), hasLength(1));
    });

    test('a refusal keeps the sale and the discount, and pays nobody',
        () async {
      await repository.applyCanonical(item, <String, dynamic>{
        'outcome': 'rejected',
        'reason': 'CODE_EXPIRED',
        'message': 'Código expirado.',
        'sale': <String, dynamic>{'id': item.entityId},
        'referral': <String, dynamic>{
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'monetary_benefit_applied': true,
          'attribution': <String, dynamic>{
            'id': 'aa_rejected',
            'merchant_id': _merchantId,
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
      });

      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'REJECTED');
      expect(sale['referral_rejection_code'], 'CODE_EXPIRED');
      expect(sale['referral_status_message'], 'Código expirado.');
      // The discount the customer already received is not reversed.
      expect(sale['amount'], 250.0);
      expect(sale['gross_amount'], 300.0);
      expect(sale['referral_benefit_amount'], 50.0);

      final attributions = await db.query('affiliate_attributions');
      expect(attributions.single['status'], 'REJECTED');
      expect(attributions.single['rejection_code'], 'CODE_EXPIRED');
      expect(await db.query('affiliate_rewards'), isEmpty);
    });

    test('a rejected referral survives a restart', () async {
      await repository.applyCanonical(item, <String, dynamic>{
        'outcome': 'rejected',
        'reason': 'CODE_USAGE_LIMIT_REACHED',
        'message': 'Código já atingiu o limite de usos.',
        'sale': <String, dynamic>{'id': item.entityId},
        'referral': const <String, dynamic>{},
      });

      db = await reopenFileTestDatabase();
      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'REJECTED');
      expect(sale['referral_rejection_code'], 'CODE_USAGE_LIMIT_REACHED');
    });

    test('a replay preserves a rejected referral as terminal', () async {
      await repository.applyCanonical(item, <String, dynamic>{
        'outcome': 'replayed',
        'sale': <String, dynamic>{'id': item.entityId},
        'referral': <String, dynamic>{
          'affiliate_id': 'aff-1',
          'affiliate_code_id': 'code-1',
          'attribution_status': 'REJECTED',
          'attribution': <String, dynamic>{
            'id': 'aa-replayed-rejected',
            'merchant_id': _merchantId,
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
      });

      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'REJECTED');
      expect(sale['referral_rejection_code'], 'CODE_EXPIRED');
      expect(sale['referral_status_message'], contains('expirad'));
    });

    test('a permanently failed operation closes the referral, not the sale',
        () async {
      await repository.applyFailure(item, reason: 'Sem permissão.');

      final sale = (await db.query('sales')).single;
      expect(sale['referral_status'], 'REJECTED');
      expect(sale['referral_status_message'], 'Sem permissão.');
      // The sale and the money it took stand.
      expect(sale['amount'], 250.0);
      expect(sale['gross_amount'], 300.0);
    });

    test('an uncached code accepted later never gets a retroactive discount',
        () async {
      // A second sale, this time with a code the till could not price.
      await seedCustomer(id: 'cust-2');
      final unpriced = await repository.recordOfflineReferralSale(
        customerId: 'cust-2',
        customerPhone: '+258841234568',
        grossAmount: 300,
        code: 'AFI-ZZZ-0000',
        localSaleId: 'local-sale-2',
      );
      expect(unpriced.sale.amount, 300);

      await repository.applyCanonical(
        SyncItem(
          id: 'q2',
          operation: 'create',
          entityType: referralSaleSyncEntityType,
          entityId: unpriced.sale.id,
          payload: '{}',
          createdAt: DateTime.now(),
        ),
        <String, dynamic>{
          'outcome': 'committed',
          'sale': <String, dynamic>{'id': unpriced.sale.id},
          'referral': <String, dynamic>{
            'affiliate_id': 'aff-2',
            'affiliate_code_id': 'code-2',
            'normalized_code': 'AFI-ZZZ-0000',
            'attribution_status': 'CONFIRMED',
            'monetary_benefit_applied': false,
            'retroactive_discount_applied': false,
            'benefit': <String, dynamic>{
              'type': 'FIXED_AMOUNT',
              'value': 50,
              'discount_amount': 0,
              'points_awarded': 0,
            },
            'attribution': <String, dynamic>{
              'id': 'aa-uncached-2',
              'merchant_id': _merchantId,
              'affiliate_id': 'aff-2',
              'affiliate_code_id': 'code-2',
              'customer_id': 'cust-2',
              'qualifying_sale_id': unpriced.sale.id,
              'status': 'CONFIRMED',
              'attributed_at': 6000,
              'created_at': 6000,
              'updated_at': 6000,
            },
            'reward_record': <String, dynamic>{
              'id': 'reward-uncached-2',
              'merchant_id': _merchantId,
              'affiliate_id': 'aff-2',
              'attribution_id': 'aa-uncached-2',
              'reward_type': 'FIRST_QUALIFYING_SALE',
              'value_type': 'POINTS',
              'value': 50,
              'status': 'PENDING',
              'trigger_sale_id': unpriced.sale.id,
              'created_at': 6000,
              'updated_at': 6000,
            },
          },
        },
      );

      final sale = (await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: <Object?>[unpriced.sale.id],
      ))
          .single;
      // Money is not refunded by a sync.
      expect(sale['amount'], 300.0);
      expect(sale['referral_benefit_amount'], isNull);
      expect(sale['referral_status'], 'ATTRIBUTED');
      expect(
        await db.query(
          'affiliates',
          where: 'id = ?',
          whereArgs: <Object?>['aff-2'],
        ),
        hasLength(1),
      );
      expect(
        await db.query(
          'affiliate_codes',
          where: 'id = ?',
          whereArgs: <Object?>['code-2'],
        ),
        hasLength(1),
      );
      expect(await db.query('affiliate_attributions'), hasLength(1));
      expect(await db.query('affiliate_rewards'), hasLength(1));
    });

    test('an uncached rejected code keeps its attribution history', () async {
      await seedCustomer(id: 'cust-4');
      final unpriced = await repository.recordOfflineReferralSale(
        customerId: 'cust-4',
        customerPhone: '+258841234570',
        grossAmount: 300,
        code: 'AFI-XXX-2222',
        localSaleId: 'local-sale-4',
      );

      await repository.applyCanonical(
        SyncItem(
          id: 'q4',
          operation: 'create',
          entityType: referralSaleSyncEntityType,
          entityId: unpriced.sale.id,
          payload: '{}',
          createdAt: DateTime.now(),
        ),
        <String, dynamic>{
          'outcome': 'rejected',
          'reason': 'CODE_EXPIRED',
          'message': 'Código expirado.',
          'sale': <String, dynamic>{'id': unpriced.sale.id},
          'referral': <String, dynamic>{
            'affiliate_id': 'aff-4',
            'affiliate_code_id': 'code-4',
            'normalized_code': 'AFI-XXX-2222',
            'benefit': <String, dynamic>{
              'type': 'FIXED_AMOUNT',
              'value': 25,
              'discount_amount': 0,
              'points_awarded': 0,
            },
            'attribution': <String, dynamic>{
              'id': 'aa-uncached-4',
              'merchant_id': _merchantId,
              'affiliate_id': 'aff-4',
              'affiliate_code_id': 'code-4',
              'customer_id': 'cust-4',
              'qualifying_sale_id': unpriced.sale.id,
              'status': 'REJECTED',
              'rejection_reason': 'CODE_EXPIRED',
              'attributed_at': 7000,
              'created_at': 7000,
              'updated_at': 7000,
            },
          },
        },
      );

      final sale = (await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: <Object?>[unpriced.sale.id],
      ))
          .single;
      expect(sale['referral_status'], 'REJECTED');
      expect(sale['referral_rejection_code'], 'CODE_EXPIRED');
      final attributions = await db.query(
        'affiliate_attributions',
        where: 'id = ?',
        whereArgs: <Object?>['aa-uncached-4'],
      );
      expect(attributions.single['status'], 'REJECTED');
      expect(await db.query('affiliate_rewards'), isEmpty);
    });

    test('a points benefit for an uncached code is credited by the server',
        () async {
      await seedCustomer(id: 'cust-3');
      final unpriced = await repository.recordOfflineReferralSale(
        customerId: 'cust-3',
        customerPhone: '+258841234569',
        grossAmount: 300,
        code: 'AFI-YYY-1111',
        localSaleId: 'local-sale-3',
      );

      await repository.applyCanonical(
        SyncItem(
          id: 'q3',
          operation: 'create',
          entityType: referralSaleSyncEntityType,
          entityId: unpriced.sale.id,
          payload: '{}',
          createdAt: DateTime.now(),
        ),
        <String, dynamic>{
          'outcome': 'committed',
          'sale': <String, dynamic>{'id': unpriced.sale.id},
          'referral': <String, dynamic>{
            'affiliate_id': 'aff-3',
            'affiliate_code_id': 'code-3',
            'attribution_status': 'CONFIRMED',
            'monetary_benefit_applied': false,
            'points_benefit_credited': true,
            'benefit': <String, dynamic>{
              'type': 'POINTS',
              'value': 120,
              'discount_amount': 0,
              'points_awarded': 120,
            },
          },
        },
      );

      final sale = (await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: <Object?>[unpriced.sale.id],
      ))
          .single;
      // Points are an entry in a ledger, and adding one costs the customer
      // nothing they have already paid — so this benefit does survive.
      expect(sale['referral_benefit_type'], 'POINTS');
      expect(sale['referral_benefit_amount'], 120.0);
      expect(sale['amount'], 300.0);
    });
  });

  group('what the offline path refuses to decide', () {
    test('no reward and no attribution exist until the server says so',
        () async {
      gateway.affiliates = <MerchantAffiliate>[_remoteAffiliate()];
      await repository.refreshReadCaches();
      await seedCustomer();

      await repository.recordOfflineReferralSale(
        customerId: 'cust-1',
        customerPhone: '+258841234567',
        grossAmount: 300,
        code: 'AFI-ANA-7K2P',
        localSaleId: 'local-sale-1',
      );
      await repository.createAffiliateOffline(
        const AffiliateDraft(
          name: 'Beatriz Cossa',
          phone: '+258849998888',
          benefitType: 'FIXED_AMOUNT',
          benefitValue: 40,
        ),
      );

      // Attribution and reward are the server's, always. A till that wrote one
      // would be paying an affiliate for an acquisition no other till has been
      // able to contest.
      expect(await db.query('affiliate_attributions'), isEmpty);
      expect(await db.query('affiliate_rewards'), isEmpty);
      expect(await db.query('affiliate_events'), isEmpty);
      // And it does not spend the code's budget either.
      expect((await dao.findCachedCode('AFI-ANA-7K2P'))!.usageCount, 0);

      // The only operations queued are the ones this feature owns; nothing
      // approves, cancels or pays anything.
      final operations = (await db.query('sync_queue'))
          .map((row) => '${row['entity_type']}/${row['operation']}')
          .toSet();
      expect(
        operations,
        <String>{'referral_sale/create', 'customer/update', 'affiliate/create'},
      );
    });

    test('an ordinary sale with no code is untouched by any of this', () async {
      await seedCustomer(id: 'cust-plain');
      final sales = SaleRepository(
        AppDatabase.instance,
        SaleDao(AppDatabase.instance, merchantId: _merchantId),
        merchantId: _merchantId,
        deviceId: _deviceId,
      );

      final sale = await sales.createSale(
        customerId: 'cust-plain',
        amount: 300,
      );

      expect(sale.amount, 300);
      expect(sale.grossAmount, isNull);
      expect(sale.referralStatus, isNull);
      expect(sale.affiliateCodeId, isNull);

      final row = (await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: <Object?>[sale.id],
      ))
          .single;
      expect(row['referral_code_input'], isNull);
      expect(row['referral_local_benefit_applied'], 0);

      // The path it has always taken: a `sale` create and the customer's
      // totals, and never the referral operation.
      final operations = (await db.query('sync_queue'))
          .map((queued) => queued['entity_type'])
          .toList();
      expect(operations, containsAll(<String>['sale', 'customer']));
      expect(operations.contains('referral_sale'), isFalse);
    });
  });
}
