import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/database/app_database.dart';
import 'package:maisum/core/errors/app_exception.dart';
import 'package:maisum/core/services/connectivity_service.dart';
import 'package:maisum/features/customers/data/customer_dao.dart';
import 'package:maisum/features/rewards/data/loyalty_redemption_api.dart';
import 'package:maisum/features/rewards/data/redemption_dao.dart';
import 'package:maisum/features/rewards/data/redemption_repository.dart';
import 'package:maisum/features/rewards/domain/redemption.dart';

import '../../helpers/test_database.dart';

class _FakeRedemptionGateway implements LoyaltyRedemptionGateway {
  _FakeRedemptionGateway({this.failOnce = false});

  bool failOnce;
  final List<String> idempotencyKeys = <String>[];

  @override
  Future<ConfirmedRedemption> redeem({
    required String merchantId,
    required String customerId,
    required String rewardId,
    required int pointsRequired,
    required String idempotencyKey,
    required String bearerToken,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (failOnce) {
      failOnce = false;
      throw const ServerException(
        statusCode: 503,
        message: 'Temporary failure',
      );
    }
    return ConfirmedRedemption(
      redemption: Redemption(
        id: 'redemption-$idempotencyKey',
        customerId: customerId,
        rewardId: rewardId,
        pointsSpent: pointsRequired,
        redeemedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        synced: true,
      ),
      confirmedPoints: 75,
    );
  }
}

void main() {
  late CustomerDao customerDao;
  late RedemptionDao redemptionDao;
  late ConnectivityService connectivity;
  late StreamController<List<ConnectivityResult>> connectivityChanges;

  setUp(() async {
    await setUpTestDatabase();
    customerDao = CustomerDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    redemptionDao = RedemptionDao(
      AppDatabase.instance,
      merchantId: 'merchant-1',
    );
    connectivityChanges =
        StreamController<List<ConnectivityResult>>.broadcast();
    connectivity = ConnectivityService(
      onConnectivityChanged: connectivityChanges.stream,
      checkConnectivity: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      initialOnline: true,
    );
  });

  tearDown(() async {
    connectivity.dispose();
    await connectivityChanges.close();
    await tearDownTestDatabase();
  });

  Future<String> seedCustomerAndReward() async {
    final customer = await customerDao.create(
      name: 'Ana',
      phone: '841234567',
    );
    final db = await AppDatabase.instance.database;
    await db.update(
      'customers',
      <String, Object?>{'confirmed_points': 100},
      where: 'id = ?',
      whereArgs: <Object?>[customer.id],
    );
    await db.insert('rewards', <String, Object?>{
      'id': 'reward-1',
      'merchant_id': 'merchant-1',
      'name': 'Coffee',
      'points_required': 25,
      'active': 1,
      'created_at': 1,
      'updated_at': 1,
      'synced': 1,
    });
    return customer.id;
  }

  RedemptionRepository repository(_FakeRedemptionGateway gateway) {
    return RedemptionRepository(
      redemptionDao,
      customerDao,
      gateway,
      connectivity,
      merchantId: 'merchant-1',
      resolveBearerToken: () async => 'token',
    );
  }

  test('requires connectivity before final redemption', () async {
    final customerId = await seedCustomerAndReward();
    connectivityChanges.add(<ConnectivityResult>[ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    final gateway = _FakeRedemptionGateway();

    await expectLater(
      repository(gateway).redeemReward(
        customerId: customerId,
        rewardId: 'reward-1',
        pointsRequired: 25,
      ),
      throwsA(isA<NetworkException>()),
    );
    expect(gateway.idempotencyKeys, isEmpty);
  });

  test('applies confirmed redemption and balance atomically', () async {
    final customerId = await seedCustomerAndReward();
    final gateway = _FakeRedemptionGateway();

    final redemption = await repository(gateway).redeemReward(
      customerId: customerId,
      rewardId: 'reward-1',
      pointsRequired: 25,
    );

    expect(redemption.pointsSpent, 25);
    final customer = await customerDao.getById(customerId);
    expect(customer?.confirmedPoints, 75);
    expect(customer?.totalPoints, 75);
    expect(
      await redemptionDao.getByCustomer(customerId),
      hasLength(1),
    );
  });

  test('reuses idempotency key after a lost server response', () async {
    final customerId = await seedCustomerAndReward();
    final gateway = _FakeRedemptionGateway(failOnce: true);
    final subject = repository(gateway);

    await expectLater(
      subject.redeemReward(
        customerId: customerId,
        rewardId: 'reward-1',
        pointsRequired: 25,
      ),
      throwsA(isA<ServerException>()),
    );
    await subject.redeemReward(
      customerId: customerId,
      rewardId: 'reward-1',
      pointsRequired: 25,
    );

    expect(gateway.idempotencyKeys, hasLength(2));
    expect(gateway.idempotencyKeys.first, gateway.idempotencyKeys.last);
  });
}
