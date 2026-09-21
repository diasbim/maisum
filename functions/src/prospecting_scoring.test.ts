import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_GEOGRAPHY,
  DEFAULT_SCORING,
  bandFor,
  findIcpIndustry,
} from './prospecting_config.js';
import {
  isTargetGeography,
  qualify,
  scoreProspect,
  UNKNOWN_SIGNALS,
  type ScoringSignals,
} from './prospecting_scoring.js';

/**
 * Every criterion is checked by moving one input and asserting the delta, not
 * by asserting a total. A test that says "this lead scores 73" breaks whenever
 * any weight is tuned and tells you nothing about which one; a test that says
 * "adding a website adds exactly five" is still true after the tuning and
 * fails precisely when the website criterion is what broke.
 */

const geography = DEFAULT_GEOGRAPHY;
const config = DEFAULT_SCORING;

function score(overrides: Partial<ScoringSignals>) {
  return scoreProspect({ ...UNKNOWN_SIGNALS, ...overrides }, config, geography);
}

function criterion(result: ReturnType<typeof score>, key: string) {
  const found = result.dimensions
    .flatMap((dimension) => dimension.criteria)
    .find((entry) => entry.key === key);
  assert.ok(found, `no criterion named ${key}`);
  return found;
}

/* ------------------------------------------------------------ business fit */

test('a business nothing is known about scores zero', () => {
  const result = score({});
  assert.equal(result.total, 0);
  assert.equal(result.band, 'LOW_FIT');
});

test('a target industry is worth twenty', () => {
  assert.equal(score({ businessType: 'barbershop' }).businessFit, 20 + 10);
  // Twenty for the industry, ten for the recurring model the industry implies.
  assert.equal(criterion(score({ businessType: 'barbershop' }), 'target_industry').awarded, 20);
});

test('a business outside the ICP earns neither the industry nor the model point', () => {
  const result = score({ businessType: 'workshop' });
  assert.equal(criterion(result, 'target_industry').awarded, 0);
  assert.equal(criterion(result, 'recurring_customer_model').awarded, 0);
  // Known and not matching, which is different from unknown.
  assert.equal(criterion(result, 'target_industry').basis, 'FACT');
});

test('the recurring-customer point is an inference about the trade, not a fact about the shop', () => {
  const result = score({ businessType: 'barbershop' });
  assert.equal(criterion(result, 'recurring_customer_model').basis, 'INFERENCE');
  assert.equal(criterion(result, 'target_industry').basis, 'FACT');
});

test('the employee-count criterion is switched off and does not appear at all', () => {
  // No source the pipeline calls reports headcount. A criterion worth zero is
  // dropped from the breakdown rather than shown as an unanswerable row, so
  // "not in the result" is the assertion, not "awarded zero".
  const result = score({ employeeCount: 6 });
  assert.equal(
    result.dimensions
      .flatMap((dimension) => dimension.criteria)
      .find((entry) => entry.key === 'employee_count'),
    undefined,
  );
  assert.ok(!result.unknowns.some((entry) => entry.includes('pessoas')));
});

test('a switched-off criterion comes back by raising its weight in the config', () => {
  // The point of zeroing rather than deleting: restoring it is a number in
  // the settings screen, not a deploy.
  const restored = scoreProspect(
    { ...UNKNOWN_SIGNALS, employeeCount: 6 },
    {
      ...config,
      businessFit: { ...config.businessFit, employeeCountInRange: 5 },
    },
    geography,
  );
  assert.equal(criterion(restored, 'employee_count').awarded, 5);
});

test('a rating is three-valued: unknown is not a bad rating', () => {
  assert.equal(criterion(score({ rating: 4.6 }), 'rating_at_least').awarded, 5);
  assert.equal(criterion(score({ rating: 4 }), 'rating_at_least').awarded, 5);
  assert.equal(criterion(score({ rating: 3.9 }), 'rating_at_least').awarded, 0);
  assert.equal(criterion(score({ rating: 3.9 }), 'rating_at_least').basis, 'FACT');
  // A shop with no reviews yet has not been rated badly.
  assert.equal(criterion(score({ rating: null }), 'rating_at_least').basis, 'UNKNOWN');
});

test('target geography is worth five, by city or by province', () => {
  assert.equal(criterion(score({ city: 'Maputo' }), 'target_geography').awarded, 5);
  assert.equal(criterion(score({ city: 'Matola' }), 'target_geography').awarded, 5);
  assert.equal(
    criterion(score({ city: 'Matola-Rio', province: 'Maputo' }), 'target_geography').awarded,
    5,
  );
  assert.equal(criterion(score({ city: 'Beira', province: 'Sofala' }), 'target_geography').awarded, 0);
});

test('business fit never exceeds its cap', () => {
  const result = score({
    businessType: 'barbershop',
    rating: 4.6,
    city: 'Maputo',
    country: 'Moçambique',
  });
  assert.equal(result.businessFit, 40);
  assert.ok(result.businessFit <= config.businessFit.max);
});

/* -------------------------------------------------------- digital presence */

test('a website is worth five', () => {
  assert.equal(criterion(score({ websiteUrl: 'https://x.test' }), 'website').awarded, 5);
});

test('having no website is a finding, not a gap in knowledge', () => {
  // Discovery looks for a website; not finding one is the answer, so this
  // criterion is never UNKNOWN.
  assert.equal(criterion(score({ websiteUrl: null }), 'website').basis, 'FACT');
});

test('the social criteria are switched off — no source reports profiles', () => {
  const result = score({ socialProfileCount: 4, websiteUrl: 'https://x.test' });
  const keys = result.dimensions.flatMap((dimension) =>
    dimension.criteria.map((entry) => entry.key),
  );
  assert.ok(!keys.includes('active_social'));
  assert.ok(!keys.includes('strong_presence'));
});

test('a contact channel is worth five', () => {
  assert.equal(criterion(score({ hasContactChannel: true }), 'contact_channel').awarded, 5);
});

test('a published timetable and photos are worth five each, three-valued', () => {
  assert.equal(criterion(score({ hasOpeningHours: true }), 'opening_hours').awarded, 5);
  assert.equal(criterion(score({ hasOpeningHours: false }), 'opening_hours').basis, 'FACT');
  assert.equal(criterion(score({ hasOpeningHours: null }), 'opening_hours').basis, 'UNKNOWN');
  assert.equal(criterion(score({ hasPhotos: true }), 'photos').awarded, 5);
});

test('digital presence caps at twenty', () => {
  const result = score({
    websiteUrl: 'https://x.test',
    hasContactChannel: true,
    hasOpeningHours: true,
    hasPhotos: true,
  });
  assert.equal(result.digitalPresence, 20);
});

/* ------------------------------------------------------ retention potential */

test('a recurring trade is worth ten and several services five more', () => {
  const result = score({ businessType: 'barbershop' });
  assert.equal(criterion(result, 'recurring_service').awarded, 10);
  assert.equal(criterion(result, 'multiple_services').awarded, 5);
  // Plus the loyalty use case, which the ICP table now answers on its own:
  // a trade that is both recurring and multi-service has one by definition.
  assert.equal(criterion(result, 'loyalty_use_case').awarded, 5);
  assert.equal(result.retentionPotential, 20);
});

test('a trade with one service earns the recurring point but not the variety point', () => {
  // A gym sells one thing, repeatedly.
  const gym = findIcpIndustry('gym');
  assert.ok(gym);
  assert.equal(gym.recurringModel, true);
  assert.equal(gym.multipleServices, false);

  const result = score({ businessType: 'gym' });
  assert.equal(criterion(result, 'recurring_service').awarded, 10);
  assert.equal(criterion(result, 'multiple_services').awarded, 0);
});

test('the promotions criterion is switched off — nothing crawls pages now', () => {
  const result = score({ runsPromotions: true });
  assert.equal(
    result.dimensions
      .flatMap((dimension) => dimension.criteria)
      .find((entry) => entry.key === 'promotions'),
    undefined,
  );
});

test('the loyalty use case is inferred from the trade, and an observation overrules it', () => {
  // Inferred: nothing looked at this shop, but the trade answers the question.
  const inferred = criterion(score({ businessType: 'barbershop' }), 'loyalty_use_case');
  assert.equal(inferred.awarded, 5);
  assert.equal(inferred.basis, 'INFERENCE');

  // A gym is recurring but sells one thing, so the table says no.
  assert.equal(criterion(score({ businessType: 'gym' }), 'loyalty_use_case').awarded, 0);

  // An explicit "no" from something that actually looked is a FACT and wins
  // over the table — `??` and not `||` is what makes this pass.
  const observed = criterion(
    score({ businessType: 'barbershop', loyaltyUseCase: false }),
    'loyalty_use_case',
  );
  assert.equal(observed.awarded, 0);
  assert.equal(observed.basis, 'FACT');

  // With no trade and no observation there is nothing to go on, and UNKNOWN
  // beats INFERENCE: `criterion` overrides the basis whenever `met` is null,
  // so an unanswered criterion cannot be dressed up as a reasoned zero.
  assert.equal(criterion(score({}), 'loyalty_use_case').basis, 'UNKNOWN');
  assert.equal(criterion(score({}), 'loyalty_use_case').awarded, 0);
});

test('review volume is worth five per threshold met', () => {
  assert.equal(criterion(score({ reviewCount: 9 }), 'review_volume_10').awarded, 0);
  assert.equal(criterion(score({ reviewCount: 10 }), 'review_volume_10').awarded, 5);
  assert.equal(criterion(score({ reviewCount: 10 }), 'review_volume_30').awarded, 0);
  assert.equal(criterion(score({ reviewCount: 30 }), 'review_volume_30').awarded, 5);
  // Traffic and quality are scored apart: many reviews, poorly rated.
  const busy = score({ reviewCount: 41, rating: 3.4 });
  assert.equal(criterion(busy, 'review_volume_30').awarded, 5);
  assert.equal(criterion(busy, 'rating_at_least').awarded, 0);
  assert.equal(criterion(score({ reviewCount: null }), 'review_volume_10').basis, 'UNKNOWN');
});

test('retention potential caps at thirty', () => {
  const result = score({
    businessType: 'barbershop',
    loyaltyUseCase: true,
    reviewCount: 120,
  });
  assert.equal(result.retentionPotential, 30);
});

/* --------------------------------------------------- commercial opportunity */

test('the decision-maker and growth criteria are switched off', () => {
  const result = score({ decisionMakerIdentified: true, growthSignal: true });
  const keys = result.dimensions.flatMap((dimension) =>
    dimension.criteria.map((entry) => entry.key),
  );
  assert.ok(!keys.includes('decision_maker'));
  assert.ok(!keys.includes('growth_signal'));
});

test('a reachable contact and a trading business are worth five each', () => {
  assert.equal(criterion(score({ reachableContact: true }), 'reachable_contact').awarded, 5);
  assert.equal(criterion(score({ isOperational: true }), 'operational').awarded, 5);
  // Closed is a finding worth zero, not an unknown, and not a disqualification.
  assert.equal(criterion(score({ isOperational: false }), 'operational').awarded, 0);
  assert.equal(criterion(score({ isOperational: false }), 'operational').basis, 'FACT');
  assert.equal(criterion(score({ isOperational: null }), 'operational').basis, 'UNKNOWN');

  const both = score({ reachableContact: true, isOperational: true });
  assert.equal(both.commercialOpportunity, 10);
});

/* ------------------------------------------------------------------ bands */

test('the bands are the ones the plan fixes', () => {
  assert.equal(bandFor(100, config), 'PRIORITY');
  assert.equal(bandFor(80, config), 'PRIORITY');
  assert.equal(bandFor(79, config), 'GOOD');
  assert.equal(bandFor(60, config), 'GOOD');
  assert.equal(bandFor(59, config), 'NURTURE');
  assert.equal(bandFor(40, config), 'NURTURE');
  assert.equal(bandFor(39, config), 'LOW_FIT');
  assert.equal(bandFor(0, config), 'LOW_FIT');
});

/**
 * The ceiling test, and the reason the weights were redistributed at all.
 *
 * Every signal here comes from one Google Places listing — no headcount, no
 * social profiles, no crawl for promotions, no people database. If this drops
 * below 100 the table has a criterion no source can feed, and `PRIORITY` at 80
 * quietly stops being reachable: leads still rank against each other, but the
 * band an operator filters on is empty forever and nobody can see why.
 */
test('a lead with everything one listing can say scores one hundred and is PRIORITY', () => {
  const result = score({
    businessType: 'barbershop',
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    rating: 4.6,
    reviewCount: 87,
    websiteUrl: 'https://barbearia.test',
    hasContactChannel: true,
    hasOpeningHours: true,
    hasPhotos: true,
    reachableContact: true,
    isOperational: true,
  });

  assert.equal(result.total, 100);
  assert.equal(result.band, 'PRIORITY');
  assert.deepEqual(result.unknowns, []);
});

test('the four dimension caps still add up to one hundred', () => {
  // A guard against a future edit that raises one dimension and forgets that
  // the bands are absolute numbers, not percentages.
  assert.equal(
    config.businessFit.max +
      config.digitalPresence.max +
      config.retentionPotential.max +
      config.commercialOpportunity.max,
    100,
  );
});

/* --------------------------------------------------------------- unknowns */

test('unknown criteria are listed rather than folded into the score', () => {
  const result = score({ businessType: 'barbershop', city: 'Maputo' });
  // The listing was never read: no rating, no review count, no timetable, no
  // photos, no trading status. Five things nobody looked at, each of which a
  // detail call would answer — which is exactly what the panel is for.
  assert.ok(result.unknowns.length >= 5);
  assert.ok(result.unknowns.some((entry) => entry.includes('Avaliação')));
  assert.ok(result.unknowns.some((entry) => entry.includes('avaliações')));
  // And nothing about a switched-off criterion, which no call can answer.
  assert.ok(!result.unknowns.some((entry) => entry.includes('pessoas')));
});

/* ------------------------------------------------------------- geography */

test('a place nothing is known about is unknown, not out of area', () => {
  assert.equal(
    isTargetGeography({ city: null, province: null, country: null }, geography),
    null,
  );
});

test('a stated country that is not the target rules the lead out', () => {
  assert.equal(
    isTargetGeography({ city: 'Maputo', province: null, country: 'Portugal' }, geography),
    false,
  );
});

test('the country code is accepted where the country name is expected', () => {
  assert.equal(
    isTargetGeography({ city: 'Maputo', province: null, country: 'MZ' }, geography),
    true,
  );
});

test('adding a city to the configuration is all it takes to sell there', () => {
  const widened = { ...geography, cities: [...geography.cities, 'Beira'] };
  assert.equal(
    isTargetGeography({ city: 'Beira', province: 'Sofala', country: 'Moçambique' }, widened),
    true,
  );
});

/* ----------------------------------------------------------- qualification */

test('a business with no name cannot be identified and is refused', () => {
  const result = qualify(
    { name: '  ', businessType: 'barbershop', city: 'Maputo', province: null, country: null },
    geography,
  );
  assert.equal(result.qualified, false);
  assert.equal(result.qualified === false && result.reason, 'NO_IDENTIFYING_DATA');
});

test('a business outside the target geography is refused', () => {
  const result = qualify(
    { name: 'Barbearia X', businessType: 'barbershop', city: 'Beira', province: 'Sofala', country: 'Moçambique' },
    geography,
  );
  assert.equal(result.qualified === false && result.reason, 'OUT_OF_GEOGRAPHY');
});

test('a stated trade outside the ICP is refused', () => {
  const result = qualify(
    { name: 'Oficina X', businessType: 'workshop', city: 'Maputo', province: null, country: null },
    geography,
  );
  assert.equal(result.qualified === false && result.reason, 'NOT_TARGET_INDUSTRY');
});

test('an unknown trade is not a refusal', () => {
  // The leads hardest to find are the ones least likely to already be
  // somebody's customer. Absence of an industry is not evidence against.
  const result = qualify(
    { name: 'Barbearia X', businessType: null, city: 'Maputo', province: null, country: null },
    geography,
  );
  assert.equal(result.qualified, true);
});
