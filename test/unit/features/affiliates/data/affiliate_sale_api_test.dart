import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/affiliates/data/affiliate_sale_api.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/referral_sale_commit.dart';
import 'package:maisum/features/affiliates/domain/referral_validation.dart';
import 'package:maisum/features/catalog/domain/merchant_item.dart';
import 'package:maisum/features/sales/domain/sale_item.dart';

/// What the till sends to commit a referred sale, and what it makes of the
/// answer.
///
/// The request half matters as much as the response half: the endpoint is
/// authoritative precisely because it is not told what anything is worth, so a
/// body that started carrying a discount or a reward would be a regression
/// worth failing over even though the server would ignore it.
void main() {
  late HttpServer server;
  late AffiliateSaleApi api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = AffiliateSaleApi(
      JsonApiClient(baseUrl: 'http://${server.address.host}:${server.port}'),
      () async => 'test-token',
    );
  });

  tearDown(() => server.close(force: true));

  test('sends the gross amount, the code and nothing that prices the sale',
      () async {
    final capture = <String, dynamic>{};
    final served = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/merchant/referral-sales/commit');
      capture.addAll(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_committedResponse()));
      await request.response.close();
    });

    await api.commitSale(
      deviceId: 'till-1',
      localSaleId: 'local-1',
      customerId: 'cust-1',
      customerPhone: '841234567',
      grossAmount: 500,
      code: 'AFI-ANA-7K2P',
      items: [
        const SaleItemInput(
          merchantItemId: 'item-1',
          nameSnapshot: 'Corte',
          typeSnapshot: MerchantItemType.service,
          quantity: 2,
          unitPrice: 250,
        ),
      ],
      itemIds: const ['sale-item-1'],
    );
    await served;

    expect(capture['device_id'], 'till-1');
    expect(capture['local_sale_id'], 'local-1');
    expect(capture['customer_id'], 'cust-1');
    expect(capture['gross_amount'], 500);
    expect(capture['code'], 'AFI-ANA-7K2P');
    // Everything the server decides is absent from what the till may say.
    for (final forbidden in [
      'amount',
      'points',
      'benefit_type',
      'benefit_value',
      'discount_amount',
      'reward_value',
      'affiliate_id',
      'merchant_id',
    ]) {
      expect(capture, isNot(contains(forbidden)), reason: forbidden);
    }

    final items = (capture['items'] as List).cast<Map<String, dynamic>>();
    expect(items.single['id'], 'sale-item-1');
    expect(items.single['type_snapshot'], 'SERVICE');
    expect(items.single['quantity'], 2);
  });

  test('maps a committed sale into the canonical sale and its referral',
      () async {
    final served = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_committedResponse()));
      await request.response.close();
    });

    final commit = await api.commitSale(
      deviceId: 'till-1',
      localSaleId: 'local-1',
      customerId: 'cust-1',
      customerPhone: '841234567',
      grossAmount: 500,
      code: 'AFI-ANA-7K2P',
    );
    await served;

    expect(commit.outcome, ReferralSaleCommitOutcome.committed);
    expect(commit.isAccepted, isTrue);
    expect(commit.wasReplay, isFalse);

    final sale = commit.sale!;
    expect(sale.id, 'sale_canonical');
    // What the customer paid, with the gross kept beside it.
    expect(sale.amount, 450);
    expect(sale.grossAmount, 500);
    expect(sale.points, 4);
    expect(sale.referralBenefitType, ReferralBenefitType.fixedAmount);
    expect(sale.referralBenefitAmount, 50);
    expect(sale.affiliateCodeId, 'ac1');
    expect(sale.referralStatus, ReferralSaleStatus.attributed);
    expect(sale.isReferred, isTrue);
    // The server already has it; it must never go back up the queue.
    expect(sale.synced, isTrue);

    expect(commit.benefit!.discountAmount, 50);
    expect(commit.attributionId, 'aa_1');
    expect(commit.reward!.value, 100);
    expect(commit.reward!.status, 'PENDING');
  });

  test('a replay is reported as one, and not as a second sale', () async {
    final served = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      final body = _committedResponse();
      final data = body['data'] as Map<String, dynamic>;
      data['outcome'] = 'replayed';
      data['replayed'] = true;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });

    final commit = await api.commitSale(
      deviceId: 'till-1',
      localSaleId: 'local-1',
      customerId: 'cust-1',
      customerPhone: '841234567',
      grossAmount: 500,
      code: 'AFI-ANA-7K2P',
    );
    await served;

    expect(commit.outcome, ReferralSaleCommitOutcome.replayed);
    expect(commit.wasReplay, isTrue);
    expect(commit.sale!.id, 'sale_canonical');
  });

  test('a refused code comes back as a reason, not as an exception', () async {
    final served = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'data': {
            'outcome': 'rejected',
            'code': 'referral_rejected',
            'reason': 'CODE_EXPIRED',
            'message': 'Este código expirou.',
          },
        }));
      await request.response.close();
    });

    final commit = await api.commitSale(
      deviceId: 'till-1',
      localSaleId: 'local-1',
      customerId: 'cust-1',
      customerPhone: '841234567',
      grossAmount: 500,
      code: 'AFI-ANA-7K2P',
    );
    await served;

    // The sale can still be made without a code; that is the whole point of
    // answering rather than throwing.
    expect(commit.isAccepted, isFalse);
    expect(commit.sale, isNull);
    expect(commit.errorCode, ReferralValidationErrorCode.codeExpired);
    expect(commit.message, 'Este código expirou.');
  });

  test('the preview asks the advisory endpoint, not the committing one',
      () async {
    final served = server.first.then((request) async {
      expect(request.uri.path, '/merchant/referrals/validate-code');
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'data': {
            'valid': true,
            'affiliate_id': 'af1',
            'affiliate_name': 'Ana',
            'affiliate_code_id': 'ac1',
            'normalized_code': 'AFI-ANA-7K2P',
            'first_visit_only': true,
            'benefit': {
              'type': 'FIXED_AMOUNT',
              'value': 50,
              'display_text': '50 MT de desconto',
            },
            'validated_at': 1800000000000,
          },
        }));
      await request.response.close();
    });

    final preview = await api.validateCode(
      code: 'AFI-ANA-7K2P',
      customerPhone: '841234567',
      saleAmount: 500,
    );
    await served;

    expect(preview.isValid, isTrue);
    expect(preview.affiliateCodeId, 'ac1');
  });
}

Map<String, dynamic> _committedResponse() => {
      'success': true,
      'data': {
        'outcome': 'committed',
        'sale': {
          'id': 'sale_canonical',
          'merchant_id': 'm1',
          'customer_id': 'cust-1',
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
        'idempotency_key': 'sale:till-1:local-1',
        'replayed': false,
      },
    };
