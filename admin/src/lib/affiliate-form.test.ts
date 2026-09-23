import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  affiliateCodeAvailability,
  affiliateFieldFor,
  affiliateStanding,
  buildAffiliateShareMessage,
  buildWhatsAppShareUrl,
  canShareAffiliateCode,
  conversionRateText,
  describeBenefit,
  DEFAULT_CODE_VALIDITY_DAYS,
  expiresAtFrom,
  formatBenefitNumber,
  lastAffiliateActivityAt,
  maskAffiliatePhone,
  normalizeMozambiquePhone,
  parseAffiliateName,
  parseAffiliatePhone,
  parseBenefit,
  parseUsageLimit,
  parseValidityDays,
  PERCENTAGE_RANGE,
} from './affiliate-form';

/**
 * What the affiliate forms accept, and what the screens make of what they get.
 *
 * Two kinds of test live here. The first checks the rules directly. The second
 * reads the Functions source and asserts that the rules agree with the ones
 * the API applies — a client check that is looser than the server's sends a
 * request that is refused for a reason the form never mentioned, and one that
 * is tighter refuses something the product allows. Both are silent failures
 * until somebody tries the value in the gap.
 */

// `__dirname` is `.test-build` at run time, not `src/lib` — the same hop the
// neighbouring label test makes to reach the app's sources.
const readSource = (...segments: string[]) =>
  readFileSync(path.join(__dirname, '..', ...segments), 'utf8');

const CONTRACTS_TS = readSource('..', 'functions', 'src', 'affiliate_contracts.ts');
const API_CONTRACTS_TS = readSource(
  '..',
  'functions',
  'src',
  'affiliate_api_contracts.ts',
);
const FUNCTIONS_INDEX_TS = readSource('..', 'functions', 'src', 'index.ts');

/* ------------------------------------------------------------------- names */

test('a name is collapsed, not merely accepted', () => {
  const parsed = parseAffiliateName('  Ana   Maria  Matola ');
  assert.equal(parsed.ok && parsed.value, 'Ana Maria Matola');
});

test('a name without letters is refused against its own field', () => {
  for (const raw of ['', '   ', '123', '-Ana', '@ana']) {
    const parsed = parseAffiliateName(raw);
    assert.equal(parsed.ok, false, `accepted ${JSON.stringify(raw)}`);
    if (!parsed.ok) assert.equal(parsed.field, 'name');
  }
});

test('a name longer than the API accepts is refused here first', () => {
  assert.equal(parseAffiliateName('A'.repeat(61)).ok, false);
  assert.equal(parseAffiliateName('A'.repeat(60)).ok, true);
});

test('the name rule is the API’s rule', () => {
  // Copied rather than imported — Next will not bundle a runtime import from
  // the Functions package — so the copy is checked against the original.
  const pattern = /const NAME_PATTERN = (\/.*\/u);/.exec(API_CONTRACTS_TS);
  assert.ok(pattern, 'NAME_PATTERN moved in affiliate_api_contracts.ts');
  assert.ok(
    readSource('src', 'lib', 'affiliate-form.ts').includes(pattern[1]),
    'the portal and the API no longer agree on what a name is',
  );
});

/* ------------------------------------------------------------------ phones */

test('a Mozambican number is normalised however it was typed', () => {
  for (const raw of ['841234567', '84 123 4567', '+258841234567', '258841234567']) {
    assert.equal(normalizeMozambiquePhone(raw), '+258841234567', raw);
  }
});

test('a number that is not Mozambican is refused against the phone field', () => {
  for (const raw of ['', '12345', '881234567', '+351912345678']) {
    const parsed = parseAffiliatePhone(raw);
    assert.equal(parsed.ok, false, `accepted ${raw}`);
    if (!parsed.ok) assert.equal(parsed.field, 'phone');
  }
});

test('the accepted prefixes are the ones the API accepts', () => {
  const declared = /const MOZAMBIQUE_PHONE_PREFIXES = new Set\(\[([^\]]+)\]\)/.exec(
    FUNCTIONS_INDEX_TS,
  );
  assert.ok(declared, 'MOZAMBIQUE_PHONE_PREFIXES moved in index.ts');
  const prefixes = [...declared[1].matchAll(/'(\d{2})'/g)].map((m) => m[1]);
  assert.ok(prefixes.length >= 5, `found only ${prefixes.length} prefixes`);

  for (const prefix of prefixes) {
    assert.equal(
      normalizeMozambiquePhone(`${prefix}1234567`),
      `+258${prefix}1234567`,
      `${prefix} is accepted by the API and refused here`,
    );
  }
  // And nothing beyond them: a prefix the API rejects must not pass here and
  // fail later with a message the form cannot place.
  assert.equal(normalizeMozambiquePhone('811234567'), null);
});

test('a phone is masked to four digits, as the logs mask it', () => {
  assert.equal(maskAffiliatePhone('+258841234567', null), '***4567');
  assert.equal(maskAffiliatePhone(null, '4567'), '***4567');
  assert.equal(maskAffiliatePhone(null, null), '***');
});

/* ---------------------------------------------------------------- benefits */

test('a percentage outside the API’s range is refused with the range in words', () => {
  const low = parseBenefit('PERCENTAGE', String(PERCENTAGE_RANGE.min - 1));
  const high = parseBenefit('PERCENTAGE', String(PERCENTAGE_RANGE.max + 1));
  assert.equal(low.ok, false);
  assert.equal(high.ok, false);
  if (!high.ok) {
    assert.equal(high.field, 'benefit_value');
    assert.match(high.message, new RegExp(String(PERCENTAGE_RANGE.max)));
  }
});

test('the percentage range is the API’s range', () => {
  const declared = /PERCENTAGE_RANGE = \{ min: (\d+), max: (\d+) \}/.exec(
    CONTRACTS_TS,
  );
  assert.ok(declared, 'PERCENTAGE_RANGE moved in affiliate_contracts.ts');
  assert.equal(PERCENTAGE_RANGE.min, Number(declared[1]));
  assert.equal(PERCENTAGE_RANGE.max, Number(declared[2]));
});

test('points are whole, because half a point is not a thing', () => {
  assert.equal(parseBenefit('POINTS', '10').ok, true);
  assert.equal(parseBenefit('POINTS', '10.5').ok, false);
  assert.equal(parseBenefit('POINTS', '100001').ok, false);
});

test('money stops at two decimal places and at a ceiling', () => {
  assert.equal(parseBenefit('FIXED_AMOUNT', '50.25').ok, true);
  assert.equal(parseBenefit('FIXED_AMOUNT', '50.251').ok, false);
  assert.equal(parseBenefit('FIXED_AMOUNT', '1000001').ok, false);
});

test('a comma is read as a decimal point, because that is how it is typed', () => {
  const parsed = parseBenefit('FIXED_AMOUNT', '50,50');
  assert.equal(parsed.ok && parsed.value.value, 50.5);
});

test('zero and nothing are refused rather than defaulted', () => {
  // A benefit of zero is a code that promises something and gives nothing.
  assert.equal(parseBenefit('PERCENTAGE', '0').ok, false);
  assert.equal(parseBenefit('PERCENTAGE', '').ok, false);
  assert.equal(parseBenefit('PERCENTAGE', 'cinquenta').ok, false);
});

test('an unknown benefit type is refused against its own field', () => {
  const parsed = parseBenefit('CASHBACK', '10');
  assert.equal(parsed.ok, false);
  if (!parsed.ok) assert.equal(parsed.field, 'benefit_type');
});

test('every benefit type the contracts declare is accepted', () => {
  const declared = /BENEFIT_TYPE = \[([^\]]+)\]/.exec(CONTRACTS_TS);
  assert.ok(declared, 'BENEFIT_TYPE moved in affiliate_contracts.ts');
  const types = [...declared[1].matchAll(/'([A-Z_]+)'/g)].map((m) => m[1]);
  assert.equal(types.length, 3);

  for (const type of types) {
    assert.equal(parseBenefit(type, '10').ok, true, `${type} was refused`);
  }
});

/* ------------------------------------------------------- limits and dates */

test('a blank usage limit is unlimited, and zero is not blank', () => {
  const blank = parseUsageLimit('');
  assert.equal(blank.ok && blank.value, null);
  assert.equal(parseUsageLimit('0').ok, false);
  const ten = parseUsageLimit('10');
  assert.equal(ten.ok && ten.value, 10);
  assert.equal(parseUsageLimit('2.5').ok, false);
});

test('creating with no validity takes the plan’s default; editing takes none', () => {
  const created = parseValidityDays('');
  assert.equal(created.ok && created.value, DEFAULT_CODE_VALIDITY_DAYS);

  // On an edit, blank means "leave the dates alone". Defaulting there would
  // move a code that has not started yet to today without anyone asking.
  const edited = parseValidityDays('', { optional: true });
  assert.equal(edited.ok && edited.value, null);
});

test('the default validity is the one the contracts fix', () => {
  const declared = /DEFAULT_CODE_VALIDITY_DAYS = (\d+)/.exec(CONTRACTS_TS);
  assert.ok(declared, 'DEFAULT_CODE_VALIDITY_DAYS moved');
  assert.equal(DEFAULT_CODE_VALIDITY_DAYS, Number(declared[1]));
});

test('a validity outside what the API stores is refused here', () => {
  assert.equal(parseValidityDays('0').ok, false);
  assert.equal(parseValidityDays('731').ok, false);
  assert.equal(parseValidityDays('730').ok, true);
});

test('an expiry is the epoch the API expects', () => {
  const now = 1_700_000_000_000;
  assert.equal(expiresAtFrom(30, now), now + 30 * 86_400_000);
});

/* ------------------------------------------------- what the API called it */

test('a refusal lands on the field it is about', () => {
  assert.equal(affiliateFieldFor('invalid_percentage'), 'benefit_value');
  assert.equal(affiliateFieldFor('invalid_phone'), 'phone');
  assert.equal(affiliateFieldFor('invalid_dates'), 'validity_days');
  // A refusal about the record rather than a field belongs at the foot of the
  // form, not under an input it does not name.
  assert.equal(affiliateFieldFor('affiliate_not_found'), null);
  assert.equal(affiliateFieldFor(null), null);
});

test('every code routed to a field is one the API can actually send', () => {
  const table = /AFFILIATE_API_MESSAGE = \{([\s\S]*?)\n\} as const;/.exec(
    API_CONTRACTS_TS,
  );
  assert.ok(table, 'AFFILIATE_API_MESSAGE moved in affiliate_api_contracts.ts');
  const codes = new Set(
    [...table[1].matchAll(/^\s{2}(\w+):/gm)].map((match) => match[1]),
  );
  assert.ok(codes.size >= 20, `found only ${codes.size} codes`);

  for (const code of [
    'invalid_name',
    'invalid_phone',
    'invalid_benefit_type',
    'invalid_benefit_value',
    'invalid_percentage',
    'invalid_usage_limit',
    'invalid_dates',
    'invalid_first_visit_only',
  ]) {
    assert.ok(codes.has(code), `${code} is no longer sent by the API`);
    assert.ok(
      affiliateFieldFor(code) !== null,
      `${code} would land at the foot of the form`,
    );
  }
});

/* --------------------------------------------------------------- standing */

const CODE = {
  code: 'AFI-ANA-7K2P',
  status: 'ACTIVE',
  benefit_type: 'PERCENTAGE',
  benefit_value: 10,
  starts_at: null,
  expires_at: null,
  usage_limit: null,
  usage_count: 0,
  updated_at: null,
};

const AFFILIATE = {
  status: 'ACTIVE',
  link_status: 'ACTIVE',
  linked_at: null,
  created_at: null,
  updated_at: null,
  code: CODE,
};

test('suspension is told apart from being unlinked', () => {
  assert.equal(affiliateStanding(AFFILIATE), 'ACTIVE');
  assert.equal(
    affiliateStanding({ ...AFFILIATE, link_status: 'INACTIVE' }),
    'INACTIVE',
  );
  // A suspended affiliate is suspended everywhere; collapsing that into
  // "inactive" would hide a platform decision from the owner who has to
  // explain it.
  assert.equal(
    affiliateStanding({ ...AFFILIATE, status: 'SUSPENDED', link_status: 'INACTIVE' }),
    'SUSPENDED',
  );
});

test('a code is shareable only when the till would accept it', () => {
  const now = 1_800_000_000_000;
  assert.equal(canShareAffiliateCode(AFFILIATE, now), true);
  assert.equal(canShareAffiliateCode({ ...AFFILIATE, code: null }), false);
  assert.equal(
    canShareAffiliateCode({ ...AFFILIATE, code: { ...CODE, status: 'DISABLED' } }),
    false,
  );
  assert.equal(
    canShareAffiliateCode({ ...AFFILIATE, link_status: 'INACTIVE' }),
    false,
  );
  assert.equal(canShareAffiliateCode({ ...AFFILIATE, status: 'SUSPENDED' }), false);
  assert.equal(
    canShareAffiliateCode(
      { ...AFFILIATE, code: { ...CODE, expires_at: now } },
      now,
    ),
    false,
  );
  assert.equal(
    canShareAffiliateCode(
      { ...AFFILIATE, code: { ...CODE, starts_at: now + 1 } },
      now,
    ),
    false,
  );
  assert.equal(
    canShareAffiliateCode(
      {
        ...AFFILIATE,
        code: { ...CODE, usage_limit: 3, usage_count: 3 },
      },
      now,
    ),
    false,
  );
  assert.equal(
    affiliateCodeAvailability({ ...CODE, expires_at: now }, now),
    'EXPIRED',
  );
  assert.equal(
    affiliateCodeAvailability(
      { ...CODE, usage_limit: 3, usage_count: 3 },
      now,
    ),
    'EXHAUSTED',
  );
});

test('the last activity is the most recent of every date on the record', () => {
  assert.equal(
    lastAffiliateActivityAt({
      ...AFFILIATE,
      created_at: 1,
      linked_at: 2,
      updated_at: 3,
      code: { ...CODE, updated_at: 9 },
    }),
    9,
  );
  // A record nothing has happened to still has a date worth showing.
  assert.equal(
    lastAffiliateActivityAt({ ...AFFILIATE, created_at: 5 }),
    5,
  );
  assert.equal(lastAffiliateActivityAt(AFFILIATE), null);
});

/* ---------------------------------------------------------------- sharing */

test('a whole number is shared as a whole number', () => {
  assert.equal(formatBenefitNumber(50), '50');
  assert.equal(formatBenefitNumber(12.5), '12.5');
});

test('a benefit with no trustworthy value promises nothing', () => {
  assert.equal(describeBenefit('PERCENTAGE', 10), '10% de desconto');
  assert.equal(describeBenefit('FIXED_AMOUNT', 50), '50 MT de desconto');
  assert.equal(describeBenefit('POINTS', 20), '20 pontos');
  assert.equal(describeBenefit('PERCENTAGE', 0), null);
  assert.equal(describeBenefit(null, 10), null);
  assert.equal(describeBenefit('CASHBACK', 10), null);
});

test('the shared message is the one the app composes', () => {
  const message = buildAffiliateShareMessage({
    code: 'afi-ana-7k2p',
    businessName: 'Padaria Ana',
    benefitType: 'PERCENTAGE',
    benefitValue: 10,
  });

  // The app composes the same invitation in `affiliate_share_message.dart`.
  // The same code reaches a customer by two routes, and two wordings would
  // read as two different offers — so the app's template is the assertion,
  // rendered with the same values rather than restated here.
  const dart = readSource(
    '..',
    'lib',
    'features',
    'affiliates',
    'services',
    'affiliate_share_message.dart',
  );
  const block = /final lines = <String>\[([\s\S]*?)\n {2}\];/.exec(dart);
  assert.ok(block, 'the app no longer builds the message from a list of lines');

  const expected = [...block[1].matchAll(/'([^']*)'/g)]
    .map((match) =>
      match[1]
        // Uppercased, because that is how the code is printed everywhere else
        // and a lowercase copy invites a failed entry at the counter.
        .replace('$code', 'AFI-ANA-7K2P')
        .replace('$business', 'Padaria Ana')
        .replace('$benefit', '10% de desconto'),
    )
    .join('\n');

  assert.equal(message, expected);
});

test('a business with no name still produces a message somebody can send', () => {
  assert.match(
    buildAffiliateShareMessage({ code: 'X1', businessName: '   ' }),
    /o nosso negócio/,
  );
});

test('the share link carries the text and, when known, the number', () => {
  const withPhone = buildWhatsAppShareUrl({
    message: 'Olá! Use o código AFI-ANA-7K2P',
    phone: '+258841234567',
  });
  assert.ok(withPhone.startsWith('https://wa.me/258841234567?text='));
  assert.match(withPhone, /AFI-ANA-7K2P/);

  // Without a number WhatsApp opens the contact picker, which is the right
  // behaviour when the API withheld one.
  assert.ok(
    buildWhatsAppShareUrl({ message: 'x', phone: null }).startsWith(
      'https://wa.me/?text=',
    ),
  );
});

test('a message survives the round trip through the link', () => {
  const message = 'Olá! Use o código AFI-JOÃO-1A2B & ganhe 10% de desconto';
  const url = new URL(buildWhatsAppShareUrl({ message }));
  assert.equal(url.searchParams.get('text'), message);
});

/* ---------------------------------------------------------------- metrics */

test('a rate over no attempts is not zero', () => {
  // "0%" on the screen an owner opens to find out whether anyone has tried
  // answers a question nobody asked.
  assert.equal(
    conversionRateText({
      unique_validation_attempts: 0,
      confirmed_attributions: 0,
      conversion_rate: 0,
    }),
    '—',
  );
});

test('a rate is shown as a percentage of the attempts', () => {
  assert.equal(
    conversionRateText({
      unique_validation_attempts: 4,
      confirmed_attributions: 1,
      conversion_rate: 0.25,
    }),
    '25%',
  );
});

test('an unusable rate is recomputed rather than printed', () => {
  assert.equal(
    conversionRateText({
      unique_validation_attempts: 4,
      confirmed_attributions: 2,
      conversion_rate: Number.NaN,
    }),
    '50%',
  );
});
