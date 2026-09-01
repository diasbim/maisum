import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/connectivity_service.dart';
import '../domain/customer_models.dart';
import 'customer_app_api.dart';

class MerchantRedemptionService {
  MerchantRedemptionService(this._api, this._auth, this._connectivity);

  final CustomerAppApi _api;
  final FirebaseAuth _auth;
  final ConnectivityService _connectivity;

  Future<MerchantRedemptionPreview> resolve(String redemptionCode) async {
    return _api.resolveMerchantRedemption(
      await _token(),
      redemptionCode,
    );
  }

  Future<MerchantRedemptionPreview> consume({
    required String redemptionCode,
    required String idempotencyKey,
  }) async {
    return _api.consumeMerchantRedemption(
      await _token(),
      redemptionCode: redemptionCode,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<String> _token() async {
    if (!await _connectivity.check()) {
      throw const NetworkException(
        'É necessária ligação à internet para validar o resgate.',
      );
    }
    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sessão Firebase indisponível.');
    }
    return token;
  }
}
