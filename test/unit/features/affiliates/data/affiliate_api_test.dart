import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/network/json_api_client.dart';
import 'package:maisum/features/affiliates/data/affiliate_api.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/affiliate_reward.dart';

/// What the merchant affiliate API sends, and what the app makes of it.
///
/// Two things are load-bearing here and neither is obvious from the screens.
/// The first is that a list answer carries its own honesty flag beside the
/// rows — `truncated` — and dropping it would let the app present a partial
/// list as a complete one. The second is that every enum is parsed strictly:
/// a status this build cannot name is a contract break, and defaulting it
/// would silently relabel a suspended affiliate as an active one.
void main() {
  late HttpServer server;
  late AffiliateApi api;
  late List<HttpRequest> requests;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = <HttpRequest>[];
    api = AffiliateApi(
      JsonApiClient(baseUrl: 'http://${server.address.host}:${server.port}'),
      () async => 'test-token',
    );
  });

  tearDown(() => server.close(force: true));

  test('reads a list page with its paging and truncation flags', () async {
    final served = _respond(server, requests, _affiliateListBody());

    final page = await api.listAffiliates(status: 'ACTIVE', limit: 100);
    await served;

    expect(requests.single.uri.path, '/merchant/affiliates');
    expect(requests.single.uri.queryParameters['status'], 'ACTIVE');
    expect(requests.single.uri.queryParameters['limit'], '100');

    expect(page.items, hasLength(1));
    expect(page.total, 7);
    expect(page.hasMore, isTrue);
    expect(page.truncated, isTrue);

    final affiliate = page.items.single;
    expect(affiliate.name, 'Ana Silva');
    expect(affiliate.status, AffiliateStatus.active);
    expect(affiliate.linkStatus, AffiliateMerchantStatus.inactive);
    expect(affiliate.phoneLast4, '4567');
    expect(affiliate.code?.benefitType, ReferralBenefitType.fixedAmount);
    expect(affiliate.code?.usageCount, 3);
    expect(affiliate.code?.usageLimit, isNull);
    expect(affiliate.code?.isUnlimited, isTrue);
    // An inactive link cannot be shared even though the code itself is active.
    expect(affiliate.canShareCode, isFalse);
  });

  test('sends the creation body in the words the server parses', () async {
    final served = _respond(server, requests, _affiliateBody());

    await api.createAffiliate(
      name: 'Ana Silva',
      phone: '+258841234567',
      benefitType: 'FIXED_AMOUNT',
      benefitValue: 50,
      usageLimit: null,
      includeUsageLimit: true,
      firstVisitOnly: true,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(1730000000000),
    );
    final body = await served;

    expect(body!['name'], 'Ana Silva');
    expect(body['phone'], '+258841234567');
    expect(body['benefit_type'], 'FIXED_AMOUNT');
    expect(body['benefit_value'], 50);
    expect(body['first_visit_only'], true);
    expect(body['expires_at'], 1730000000000);
    // Present and null: that is how "no limit" is said, and omitting the key
    // would let the server apply a default the owner did not choose.
    expect(body.containsKey('usage_limit'), isTrue);
    expect(body['usage_limit'], isNull);
  });

  test('sends the validity pair together or not at all', () async {
    final served = _respond(server, requests, _codeBody());

    await api.updateCode(codeId: 'code-1', usageLimit: 10);
    final body = await served;

    expect(body!.containsKey('starts_at'), isFalse);
    expect(body.containsKey('expires_at'), isFalse);
    expect(body['usage_limit'], 10);
  });

  test('clears a usage limit with an explicit null', () async {
    final served = _respond(server, requests, _codeBody());

    await api.updateCode(codeId: 'code-1', clearUsageLimit: true);
    final body = await served;

    expect(body!.containsKey('usage_limit'), isTrue);
    expect(body['usage_limit'], isNull);
  });

  test('reads metrics, including the truncation flag inside the object',
      () async {
    final served = _respond(server, requests, _metricsBody());

    final metrics = await api.merchantMetrics();
    await served;

    expect(requests.single.uri.path, '/merchant/affiliates/metrics');
    expect(metrics.confirmedAttributions, 4);
    expect(metrics.returnedCustomers, 2);
    expect(metrics.pendingRewardPoints, 300);
    expect(metrics.conversionRate, closeTo(0.5, 0.0001));
    expect(metrics.hasConversionRate, isTrue);
    expect(metrics.truncated, isTrue);
    expect(metrics.affiliateId, isNull);
  });

  test('says there is no conversion rate when nothing was ever tried',
      () async {
    final served = _respond(server, requests, _metricsBody(attempts: 0));

    final metrics = await api.merchantMetrics();
    await served;

    expect(metrics.hasConversionRate, isFalse);
  });

  test('reads a reward with the wire spelling of its value', () async {
    final served = _respond(server, requests, _rewardListBody());

    final page = await api.listRewards(status: 'PENDING');
    await served;

    final reward = page.items.single;
    expect(reward.type, AffiliateRewardType.firstQualifyingSale);
    expect(reward.valueType, AffiliateRewardValueType.points);
    expect(reward.value, 100);
    expect(reward.status, AffiliateRewardStatus.pending);
    expect(reward.isDecidable, isTrue);
    expect(reward.attributionId, isNull);
  });

  test('an approved reward is no longer decidable', () async {
    final served = _respond(
      server,
      requests,
      _rewardListBody(status: 'APPROVED'),
    );

    final page = await api.listRewards();
    await served;

    expect(page.items.single.isDecidable, isFalse);
  });

  test('refuses to invent a status it does not know', () async {
    final served = _respond(
      server,
      requests,
      _rewardListBody(status: 'SETTLED'),
    );

    await expectLater(api.listRewards(), throwsA(isA<FormatException>()));
    await served;
  });

  test('surfaces the server refusal message for a non-owner', () async {
    final served = _respond(
      server,
      requests,
      <String, Object?>{
        'success': false,
        'code': 'forbidden_role',
        'message': 'Só o responsável do negócio pode fazer esta alteração.',
      },
      status: 403,
    );

    await expectLater(
      api.approveReward('reward-1'),
      throwsA(
        predicate(
          (error) => error.toString().contains(
              'Só o responsável do negócio pode fazer esta alteração.'),
        ),
      ),
    );
    await served;
  });
}

/// Answers the next request and hands back the body it carried.
Future<Map<String, dynamic>?> _respond(
  HttpServer server,
  List<HttpRequest> requests,
  Object body, {
  int status = 200,
}) async {
  final request = await server.first;
  requests.add(request);
  final raw = await utf8.decoder.bind(request).join();
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
  if (raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : null;
}

Map<String, Object?> _affiliateListBody() => <String, Object?>{
      'success': true,
      'data': <Object?>[_affiliateData()],
      'paging': <String, Object?>{'limit': 100, 'offset': 0, 'has_more': true},
      'total': 7,
      'truncated': true,
    };

Map<String, Object?> _affiliateBody() => <String, Object?>{
      'success': true,
      'data': _affiliateData(),
    };

Map<String, Object?> _affiliateData() => <String, Object?>{
      'id': 'aff-1',
      'merchant_id': 'shop-1',
      'name': 'Ana Silva',
      'first_name': 'Ana',
      'last_name': 'Silva',
      'phone': '+258841234567',
      'phone_last4': '4567',
      'status': 'ACTIVE',
      'link_status': 'INACTIVE',
      'linked_at': 1730000000000,
      'created_at': 1730000000000,
      'updated_at': 1730000500000,
      'code': _codeData(),
    };

Map<String, Object?> _codeData() => <String, Object?>{
      'id': 'code-1',
      'merchant_id': 'shop-1',
      'affiliate_id': 'aff-1',
      'code': 'AFI-ANA-7K2P',
      'normalized_code': 'AFI-ANA-7K2P',
      'benefit_type': 'FIXED_AMOUNT',
      'benefit_value': 50,
      'starts_at': 1730000000000,
      'expires_at': 1732592000000,
      'usage_limit': null,
      'usage_count': 3,
      'first_visit_only': true,
      'status': 'ACTIVE',
      'created_at': null,
      'updated_at': null,
    };

Map<String, Object?> _codeBody() => <String, Object?>{
      'success': true,
      'data': _codeData(),
    };

Map<String, Object?> _metricsBody({int attempts = 8}) => <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'merchant_id': 'shop-1',
        'affiliate_id': null,
        'unique_validation_attempts': attempts,
        'confirmed_attributions': 4,
        'rejected_attributions': 1,
        'returned_customers': 2,
        'pending_reward_count': 3,
        'pending_reward_points': 300,
        'approved_reward_count': 1,
        'approved_reward_points': 100,
        'conversion_rate': 0.5,
        'last_activity_at': 1730000000000,
        'truncated': true,
      },
    };

Map<String, Object?> _rewardListBody({String status = 'PENDING'}) =>
    <String, Object?>{
      'success': true,
      'data': <Object?>[
        <String, Object?>{
          'id': 'reward-1',
          'merchant_id': 'shop-1',
          'affiliate_id': 'aff-1',
          'attribution_id': null,
          'type': 'FIRST_QUALIFYING_SALE',
          'value': 100,
          'value_type': 'POINTS',
          'status': status,
          'trigger_sale_id': 'sale-1',
          'approved_by': null,
          'approved_at': null,
          'paid_at': null,
          'cancelled_at': null,
          'created_at': 1730000000000,
          'updated_at': 1730000000000,
        },
      ],
      'paging': <String, Object?>{'limit': 100, 'offset': 0, 'has_more': false},
      'total': 1,
      'truncated': false,
    };
