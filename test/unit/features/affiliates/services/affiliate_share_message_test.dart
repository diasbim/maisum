import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/affiliates/domain/affiliate.dart';
import 'package:maisum/features/affiliates/domain/affiliate_code.dart';
import 'package:maisum/features/affiliates/domain/merchant_affiliate_dtos.dart';
import 'package:maisum/features/affiliates/services/affiliate_share_message.dart';

/// What the affiliate is handed, and what the app refuses to hand them.
///
/// The share is a message a person forwards to their contacts, so two things
/// have to hold: the text has to be readable by someone who was not in the
/// shop, and the link has to survive the trip — an unencoded newline or accent
/// turns the whole message into a truncated one.
MerchantAffiliateCode _code({
  ReferralBenefitType type = ReferralBenefitType.fixedAmount,
  double value = 50,
  AffiliateCodeStatus status = AffiliateCodeStatus.active,
  DateTime? startsAt,
  DateTime? expiresAt,
  int? usageLimit,
  int usageCount = 0,
}) {
  return MerchantAffiliateCode(
    id: 'code-1',
    merchantId: 'shop-1',
    affiliateId: 'aff-1',
    code: 'afi-ana-7k2p',
    normalizedCode: 'AFI-ANA-7K2P',
    benefitType: type,
    benefitValue: value,
    status: status,
    startsAt: startsAt,
    expiresAt: expiresAt,
    usageLimit: usageLimit,
    usageCount: usageCount,
  );
}

MerchantAffiliate _affiliate({
  MerchantAffiliateCode? code,
  AffiliateStatus status = AffiliateStatus.active,
  AffiliateMerchantStatus linkStatus = AffiliateMerchantStatus.active,
  String? phone = '+258841234567',
}) {
  return MerchantAffiliate(
    id: 'aff-1',
    merchantId: 'shop-1',
    name: 'Ana Silva',
    firstName: 'Ana',
    status: status,
    linkStatus: linkStatus,
    phone: phone,
    code: code ?? _code(),
  );
}

void main() {
  group('share message', () {
    test('names the business, the code and the benefit', () {
      final message = buildAffiliateShareMessage(
        code: 'AFI-ANA-7K2P',
        businessName: 'Salão Bela',
        benefitType: ReferralBenefitType.fixedAmount,
        benefitValue: 50,
      );

      expect(message, contains('AFI-ANA-7K2P'));
      expect(message, contains('Salão Bela'));
      expect(message, contains('50 MT de desconto'));
    });

    test('omits the benefit line rather than promising nothing', () {
      final message = buildAffiliateShareMessage(
        code: 'AFI-ANA-7K2P',
        businessName: 'Salão Bela',
      );

      expect(message, isNot(contains('recebe')));
      expect(message, contains('AFI-ANA-7K2P'));
    });

    test('writes a whole percentage without a decimal tail', () {
      final message = buildAffiliateShareMessage(
        code: 'X',
        businessName: 'Loja',
        benefitType: ReferralBenefitType.percentage,
        benefitValue: 10,
      );

      expect(message, contains('10% de desconto'));
      expect(message, isNot(contains('10.0')));
    });
  });

  group('whatsapp link', () {
    test('encodes the message instead of putting it in raw', () {
      final uri = buildWhatsAppShareUri(
        message: 'Olá!\nUse o código AFI-ANA-7K2P',
        phone: '841234567',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/258841234567');
      // The raw string never reaches the query: a literal newline would end the
      // message where WhatsApp stops reading it.
      expect(uri.toString(), isNot(contains('\n')));
      expect(uri.queryParameters['text'], contains('AFI-ANA-7K2P'));
      expect(uri.queryParameters['text'], contains('Olá!'));
    });

    test('opens the contact picker when there is no number to send to', () {
      final uri = buildWhatsAppShareUri(message: 'Olá', phone: null);

      expect(uri.path, '/');
      expect(uri.queryParameters['text'], 'Olá');
    });

    test('adds the country code once', () {
      expect(
        buildWhatsAppShareUri(message: 'a', phone: '+258841234567').path,
        '/258841234567',
      );
      expect(
        buildWhatsAppShareUri(message: 'a', phone: '84 123 4567').path,
        '/258841234567',
      );
    });
  });

  group('share draft', () {
    test('is offered for a confirmed, active code', () {
      final draft = buildAffiliateShareDraft(
        affiliate: _affiliate(),
        businessName: 'Salão Bela',
      );

      expect(draft, isNotNull);
      expect(draft!.message, contains('AFI-ANA-7K2P'));
    });

    test('is withheld when the code is disabled', () {
      final draft = buildAffiliateShareDraft(
        affiliate: _affiliate(
          code: _code(status: AffiliateCodeStatus.disabled),
        ),
        businessName: 'Salão Bela',
      );

      expect(draft, isNull);
    });

    test('is withheld when the affiliate is suspended', () {
      final draft = buildAffiliateShareDraft(
        affiliate: _affiliate(status: AffiliateStatus.suspended),
        businessName: 'Salão Bela',
      );

      expect(draft, isNull);
    });

    test('is withheld when the link to this business is inactive', () {
      final draft = buildAffiliateShareDraft(
        affiliate: _affiliate(linkStatus: AffiliateMerchantStatus.inactive),
        businessName: 'Salão Bela',
      );

      expect(draft, isNull);
    });

    test('is withheld when the code is expired or exhausted', () {
      final expired = buildAffiliateShareDraft(
        affiliate: _affiliate(
          code: _code(expiresAt: DateTime.now()),
        ),
        businessName: 'Salão Bela',
      );
      final exhausted = buildAffiliateShareDraft(
        affiliate: _affiliate(
          code: _code(usageLimit: 3, usageCount: 3),
        ),
        businessName: 'Salão Bela',
      );

      expect(expired, isNull);
      expect(exhausted, isNull);
    });
  });
}
