import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_api.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_repository.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/referral_sale_commit.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/catalog/data/merchant_catalog_dao.dart';
import 'package:maisum/features/catalog/data/merchant_catalog_repository.dart';
import 'package:maisum/features/catalog/domain/merchant_item.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/sales/data/sale_dao.dart';
import 'package:maisum/features/sales/domain/sale_item.dart';
import 'package:maisum/features/sync/data/sync_dao.dart';

import '../../helpers/test_database.dart';

/// Storing the server's answer, and storing it once.
///
/// The referred sale is committed online and projected here, so everything
/// worth asserting is about the projection being faithful and idempotent: the
/// canonical id is kept, the sale is already synced, and a replay does not add
/// the points a second time.
void main() {
  late AppDatabase db;
  late CustomerDao customerDao;
  late SaleDao saleDao;
  late _FakeAffiliateSaleGateway gateway;
  late AffiliateSaleRepository repo;
  const merchantId = 'merchant-1';
  const deviceId = 'device-1';
  late String customerId;

  setUp(() async {
    await setUpTestDatabase();
    db = AppDatabase.instance;
    customerDao = CustomerDao(db, merchantId: merchantId);
    saleDao = SaleDao(db, merchantId: merchantId);
    gateway = _FakeAffiliateSaleGateway();
    repo = AffiliateSaleRepository(
      db,
      gateway,
      merchantId: merchantId,
      deviceId: deviceId,
      appUserId: 'user-1',
    );

    final customer = await customerDao.create(
      name: 'Nova Cliente',
      phone: '840000401',
    );
    customerId = customer.id;
    gateway.customerId = customerId;
  });

  tearDown(tearDownTestDatabase);

  Future<ReferralSaleCommit> commit({
    List<SaleItemInput> items = const <SaleItemInput>[],
  }) {
    return repo.commitReferredSale(
      customerId: customerId,
      customerPhone: '+258840000401',
      grossAmount: 500,
      code: 'AFI-ANA-7K2P',
      localSaleId: 'local-1',
      items: items,
    );
  }

  test('stores the canonical sale exactly as the server decided it', () async {
    final result = await commit();

    expect(result.outcome, ReferralSaleCommitOutcome.committed);
    final stored = await saleDao.getById('sale_canonical');
    expect(stored, isNotNull);
    expect(stored!.amount, 450, reason: 'the discount is the server\'s');
    expect(stored.grossAmount, 500);
    expect(stored.points, 4);
    expect(stored.affiliateCodeId, 'ac1');
    expect(stored.referralBenefitType, ReferralBenefitType.fixedAmount);
    expect(stored.referralStatus, ReferralSaleStatus.attributed);
    // Already authoritative: putting it on the queue would upload a copy of
    // the record the server wrote.
    expect(stored.synced, isTrue);

    final queued = await db.database.then((database) => database.query(
          'sync_queue',
          where: 'entity_type = ?',
          whereArgs: ['sale'],
        ));
    expect(queued, isEmpty, reason: 'the sale must not be queued for upload');
  });

  test('moves the customer points once and queues the customer, not the sale',
      () async {
    await commit();

    expect((await customerDao.getById(customerId))!.totalPoints, 4);

    final database = await db.database;
    final queue = await database.query('sync_queue');
    expect(queue.length, 1);
    expect(queue.single['entity_type'], 'customer');
    expect(queue.single['entity_id'], customerId);
    expect(queue.single['operation'], 'update');
    final payload =
        jsonDecode(queue.single['payload'] as String) as Map<String, dynamic>;
    expect(payload['merchant_id'], merchantId);
  });

  test('a replay of the same commit changes nothing a second time', () async {
    await commit();
    gateway.outcome = 'replayed';
    final replay = await commit();

    expect(replay.wasReplay, isTrue);
    final database = await db.database;
    final sales = await database.query('sales');
    expect(sales.length, 1);
    // The points were added when the sale first arrived, and not again.
    expect((await customerDao.getById(customerId))!.totalPoints, 4);
    expect((await database.query('sync_queue')).length, 1);
  });

  test('a replay with items sends the same item ids', () async {
    final catalog = MerchantCatalogRepository(
      MerchantCatalogDao(db, merchantId: merchantId),
      SyncDao(db, merchantId: merchantId, deviceId: deviceId),
    );
    final service = await catalog.save(
      name: 'Corte',
      type: MerchantItemType.service,
      defaultPrice: 250,
    );
    final items = [
      SaleItemInput.fromMerchantItem(service, quantity: 2),
    ];

    await commit(items: items);
    gateway.outcome = 'replayed';
    await commit(items: items);

    expect(gateway.requests, hasLength(2));
    expect(
      gateway.requests[0]['items'],
      gateway.requests[1]['items'],
      reason: 'a retry must preserve the server request fingerprint',
    );
  });

  test('stores the items the sale was made of', () async {
    final catalog = MerchantCatalogRepository(
      MerchantCatalogDao(db, merchantId: merchantId),
      SyncDao(db, merchantId: merchantId, deviceId: deviceId),
    );
    final service = await catalog.save(
      name: 'Corte',
      type: MerchantItemType.service,
      defaultPrice: 250,
    );

    await commit(items: [
      SaleItemInput.fromMerchantItem(service, quantity: 2),
    ]);

    final database = await db.database;
    final items = await database.query('sale_items');
    expect(items.length, 1);
    expect(items.single['sale_id'], 'sale_canonical');
    expect(items.single['name_snapshot'], 'Corte');
    expect(items.single['quantity'], 2);
    expect(items.single['synced'], 1);
  });

  test('a refused code touches nothing at all', () async {
    gateway.outcome = 'rejected';

    final result = await commit();

    expect(result.isAccepted, isFalse);
    expect(result.errorCode, ReferralValidationErrorCode.codeExpired);
    final database = await db.database;
    expect(await database.query('sales'), isEmpty);
    expect(await database.query('sync_queue'), isEmpty);
    expect((await customerDao.getById(customerId))!.totalPoints, 0);
  });

  test('the gross amount is what is sent, and the code with it', () async {
    await commit();

    expect(gateway.lastRequest['gross_amount'], 500);
    expect(gateway.lastRequest['code'], 'AFI-ANA-7K2P');
    expect(gateway.lastRequest['device_id'], deviceId);
    expect(gateway.lastRequest['local_sale_id'], 'local-1');
  });

  test('requires stable merchant and device identities', () {
    expect(
      () => AffiliateSaleRepository(
        db,
        gateway,
        merchantId: '',
        deviceId: deviceId,
      ),
      throwsArgumentError,
    );
    expect(
      () => AffiliateSaleRepository(
        db,
        gateway,
        merchantId: merchantId,
        deviceId: '',
      ),
      throwsArgumentError,
    );
  });
}

/// The server, as far as the repository is concerned.
///
/// It answers with a canonical sale under an id of its own choosing, which is
/// the behaviour that matters: the local id the till made up is not the id the
/// sale ends up with, and the repository has to store the server's.
class _FakeAffiliateSaleGateway implements AffiliateSaleGateway {
  String outcome = 'committed';
  String customerId = 'cust-1';
  Map<String, Object?> lastRequest = <String, Object?>{};
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Future<ReferralValidationResult> validateCode({
    required String code,
    String? customerPhone,
    double? saleAmount,
  }) async {
    throw UnimplementedError('the repository does not preview');
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
    lastRequest = <String, Object?>{
      'device_id': deviceId,
      'local_sale_id': localSaleId,
      'customer_id': customerId,
      'customer_phone': customerPhone,
      'gross_amount': grossAmount,
      'code': code,
      'items': itemIds,
    };
    requests.add(Map<String, Object?>.from(lastRequest));

    if (outcome == 'rejected') {
      return ReferralSaleCommit.fromMap(<String, dynamic>{
        'outcome': 'rejected',
        'reason': 'CODE_EXPIRED',
        'message': 'Este código expirou.',
      });
    }

    return ReferralSaleCommit.fromMap(<String, dynamic>{
      'outcome': outcome,
      'sale': {
        'id': 'sale_canonical',
        'merchant_id': 'merchant-1',
        'customer_id': this.customerId,
        'amount': 450,
        'points': 4,
        'gross_amount': 500,
        'referral_benefit_type': 'FIXED_AMOUNT',
        'referral_benefit_value': 50,
        'referral_benefit_amount': 50,
        'affiliate_code_id': 'ac1',
        'referral_status': 'ATTRIBUTED',
        'created_at': 1800000000000,
        'updated_at': 1800000000000,
        'cancellation_status': 'ACTIVE',
      },
      'referral': {
        'affiliate_id': 'af1',
        'affiliate_code_id': 'ac1',
        'normalized_code': 'AFI-ANA-7K2P',
        'benefit': {
          'type': 'FIXED_AMOUNT',
          'value': 50,
          'discount_amount': 50,
          'points_awarded': 0,
          'display_text': '50 MT de desconto',
        },
        'attribution_id': 'aa_1',
        'attribution_status': 'CONFIRMED',
        'reward': {
          'id': 'ar_1',
          'type': 'FIRST_QUALIFYING_SALE',
          'value': 100,
          'status': 'PENDING',
        },
      },
      'idempotency_key': 'sale:device-1:local-1',
      'replayed': outcome == 'replayed',
    });
  }
}
