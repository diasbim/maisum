import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/network/json_api_client.dart';
import '../../catalog/domain/merchant_item.dart';
import '../../sales/domain/sale_item.dart';
import '../domain/referral_sale_commit.dart';
import '../domain/referral_validation.dart';

/// The two calls a till makes about a referral code, in the order it makes them.
///
/// `validateCode` is a preview and is advisory only: it says what a code would
/// be worth so the cashier can tell the customer, and reserves nothing. Between
/// the preview and the confirmation the code can expire, be disabled or be used
/// up by another till, so `commitSale` re-runs every check on the server and is
/// the only call that decides anything.
///
/// Nothing here computes money. The request carries what was sold, to whom and
/// which code was typed; the benefit, the loyalty points and the affiliate's
/// reward come back from the server, which reads them off the stored code and
/// the business's own settings.
abstract interface class AffiliateSaleGateway {
  Future<ReferralValidationResult> validateCode({
    required String code,
    String? customerPhone,
    double? saleAmount,
  });

  Future<ReferralSaleCommit> commitSale({
    required String deviceId,
    required String localSaleId,
    required String customerId,
    required String customerPhone,
    required double grossAmount,
    required String code,
    List<SaleItemInput> items,
    List<String> itemIds,
  });
}

String referralSaleItemId(
  String deviceId,
  String localSaleId,
  int index,
) {
  final digest = sha256
      .convert(utf8.encode('$deviceId\u001f$localSaleId\u001f$index'))
      .toString()
      .substring(0, 40);
  return 'rsi_$digest';
}

class AffiliateSaleApi implements AffiliateSaleGateway {
  const AffiliateSaleApi(this._client, this._resolveAccessToken);

  final JsonApiClient _client;
  final Future<String?> Function() _resolveAccessToken;

  @override
  Future<ReferralValidationResult> validateCode({
    required String code,
    String? customerPhone,
    double? saleAmount,
  }) async {
    final response = await _client.post(
      '/merchant/referrals/validate-code',
      bearerToken: await _requireToken(),
      body: <String, Object?>{
        'code': code,
        if (customerPhone != null) 'customer_phone': customerPhone,
        if (saleAmount != null) 'sale_amount': saleAmount,
      },
    );
    return ReferralValidationResult.fromMap(
      _previewToDomain(_asMap(response.data)),
    );
  }

  /// The preview's wire shape, in the words the local model uses.
  ///
  /// The API answers `valid` with a nested `benefit: {type, value}`; the stored
  /// model speaks `is_valid` and `benefit_type`. Translating here, once, is
  /// what keeps a wire rename from reaching the database — and what keeps the
  /// model from having to accept two spellings of everything forever.
  Map<String, dynamic> _previewToDomain(Map<String, dynamic> wire) {
    final benefit = wire['benefit'];
    final isValid = wire['valid'] == true;
    return <String, dynamic>{
      'is_valid': isValid,
      'validated_at': wire['validated_at'],
      'normalized_code': wire['normalized_code'],
      'affiliate_code_id': wire['affiliate_code_id'],
      'affiliate_id': wire['affiliate_id'],
      'affiliate_name': wire['affiliate_name'],
      'sale_status': isValid ? 'PENDING' : 'REJECTED',
      'error_code': wire['reason'],
      'status_text':
          wire['message'] ?? (benefit is Map ? benefit['display_text'] : null),
      if (benefit is Map)
        'benefit': <String, dynamic>{
          'benefit_type': benefit['type'],
          'benefit_value': benefit['value'],
          'benefit_amount': benefit['discount_amount'],
          'display_text': benefit['display_text'],
        },
    };
  }

  /// The authoritative commit.
  ///
  /// `localSaleId` and `deviceId` are the idempotency key: a retry after a
  /// dropped response resolves to the sale already written rather than making a
  /// second one. The same pair must never be reused for a different sale — the
  /// server answers 409 if it is, which is a bug in the caller, not a conflict
  /// to retry.
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
    final response = await _client.post(
      '/merchant/referral-sales/commit',
      bearerToken: await _requireToken(),
      body: <String, Object?>{
        'device_id': deviceId,
        'local_sale_id': localSaleId,
        'customer_id': customerId,
        'customer_phone': customerPhone,
        // The gross, never a net: the server applies the discount, and a till
        // that sent an already-discounted amount would have it taken twice.
        'gross_amount': grossAmount,
        'code': code,
        'items': <Map<String, Object?>>[
          for (var index = 0; index < items.length; index++)
            _itemPayload(
              items[index],
              index < itemIds.length
                  ? itemIds[index]
                  : referralSaleItemId(deviceId, localSaleId, index),
            ),
        ],
      },
    );
    return ReferralSaleCommit.fromMap(_asMap(response.data));
  }

  Map<String, Object?> _itemPayload(SaleItemInput item, String id) {
    return <String, Object?>{
      'id': id,
      'merchant_item_id': item.merchantItemId,
      'name_snapshot': item.nameSnapshot,
      'type_snapshot': item.typeSnapshot.dbValue,
      'quantity': item.quantity,
      'unit_price': item.unitPrice,
      'subtotal': item.subtotal,
    };
  }

  Future<String> _requireToken() async {
    final token = await _resolveAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sessão expirada. Faça login novamente.');
    }
    return token;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('Referral sale response did not include object data');
  }
}
