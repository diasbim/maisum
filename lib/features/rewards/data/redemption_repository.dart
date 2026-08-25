import '../../../core/errors/app_exception.dart';
import '../../../core/services/connectivity_service.dart';
import '../../customers/data/customer_dao.dart';
import '../domain/redemption.dart';
import 'loyalty_redemption_api.dart';
import 'redemption_dao.dart';

class RedemptionRepository {
  RedemptionRepository(
    this._redemptionDao,
    this._customerDao,
    this._api,
    this._connectivity, {
    required this.merchantId,
    required Future<String?> Function() resolveBearerToken,
  }) : _resolveBearerToken = resolveBearerToken;

  final RedemptionDao _redemptionDao;
  final CustomerDao _customerDao;
  final LoyaltyRedemptionGateway _api;
  final ConnectivityService _connectivity;
  final String merchantId;
  final Future<String?> Function() _resolveBearerToken;

  Future<Redemption> redeemReward({
    required String customerId,
    required String rewardId,
    required int pointsRequired,
  }) async {
    if (!_connectivity.isOnline || !await _connectivity.check()) {
      throw const NetworkException(
        'A redenção final requer ligação à internet.',
      );
    }

    final customer = await _customerDao.getById(customerId);
    if (customer == null) {
      throw const UnknownException('Cliente não encontrado');
    }
    final confirmedPoints = customer.confirmedPoints;
    if (confirmedPoints != null && confirmedPoints < pointsRequired) {
      throw const UnknownException(
        'Pontos confirmados insuficientes para resgatar esta recompensa',
      );
    }

    final token = await _resolveBearerToken();
    if (token == null || token.isEmpty) {
      throw const AuthException();
    }

    final request = await _redemptionDao.getOrCreatePendingRequest(
      customerId: customerId,
      rewardId: rewardId,
      pointsRequired: pointsRequired,
    );
    try {
      final confirmed = await _api.redeem(
        merchantId: merchantId,
        customerId: customerId,
        rewardId: rewardId,
        pointsRequired: request.pointsRequired,
        idempotencyKey: request.id,
        bearerToken: token,
      );
      await _redemptionDao.applyConfirmedRedemption(
        requestId: request.id,
        redemption: confirmed.redemption,
        confirmedPoints: confirmed.confirmedPoints,
      );
      return confirmed.redemption;
    } catch (error) {
      await _redemptionDao.recordRequestFailure(request.id, error);
      rethrow;
    }
  }

  Future<List<Redemption>> getByCustomer(String customerId) =>
      _redemptionDao.getByCustomer(customerId);
}
