import '../../../core/errors/app_exception.dart';
import '../../../core/services/connectivity_service.dart';
import 'return_bonus_api.dart';
import 'return_bonus_dao.dart';
import '../domain/return_bonus.dart';

class ReturnBonusRepository {
  ReturnBonusRepository(
    this._dao,
    this._api,
    this._connectivity, {
    required Future<String?> Function() resolveBearerToken,
  }) : _resolveBearerToken = resolveBearerToken;

  final ReturnBonusDao _dao;
  final ReturnBonusGateway _api;
  final ConnectivityService _connectivity;
  final Future<String?> Function() _resolveBearerToken;

  Future<ReturnBonus?> getActiveForCustomer(String customerId) =>
      _dao.getActiveForCustomer(customerId);

  Future<List<ReturnBonus>> getAllForCustomer(String customerId) =>
      _dao.getAllForCustomer(customerId);

  /// Redemption is always validated server-side (expiration, ownership,
  /// double-redeem) — this call never trusts or mutates local state first.
  Future<ReturnBonus> redeem({
    required String bonusId,
    required String customerId,
    String? redemptionSaleId,
  }) async {
    if (!_connectivity.isOnline || !await _connectivity.check()) {
      throw const NetworkException(
        'Resgatar o bónus requer ligação à internet.',
      );
    }

    final token = await _resolveBearerToken();
    if (token == null || token.isEmpty) {
      throw const AuthException();
    }

    final redeemed = await _api.redeem(
      bonusId: bonusId,
      customerId: customerId,
      redemptionSaleId: redemptionSaleId,
      bearerToken: token,
    );
    await _dao.applyServerBonus(redeemed);
    return redeemed;
  }
}
