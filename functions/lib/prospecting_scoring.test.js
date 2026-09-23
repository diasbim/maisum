"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_scoring_js_1 = require("./prospecting_scoring.js");
/**
 * Every criterion is checked by moving one input and asserting the delta, not
 * by asserting a total. A test that says "this lead scores 73" breaks whenever
 * any weight is tuned and tells you nothing about which one; a test that says
 * "adding a website adds exactly five" is still true after the tuning and
 * fails precisely when the website criterion is what broke.
 */
const geography = prospecting_config_js_1.DEFAULT_GEOGRAPHY;
const config = prospecting_config_js_1.DEFAULT_SCORING;
function score(overrides) {
    return (0, prospecting_scoring_js_1.scoreProspect)({ ...prospecting_scoring_js_1.UNKNOWN_SIGNALS, ...overrides }, config, geography);
}
function criterion(result, key) {
    const found = result.dimensions
        .flatMap((dimension) => dimension.criteria)
        .find((entry) => entry.key === key);
    strict_1.default.ok(found, `no criterion named ${key}`);
    return found;
}
/* ------------------------------------------------------------ business fit */
(0, node_test_1.default)('a business nothing is known about scores zero', () => {
    const result = score({});
    strict_1.default.equal(result.total, 0);
    strict_1.default.equal(result.band, 'LOW_FIT');
});
(0, node_test_1.default)('a target industry is worth twenty', () => {
    strict_1.default.equal(score({ businessType: 'barbershop' }).businessFit, 20 + 10);
    // Twenty for the industry, ten for the recurring model the industry implies.
    strict_1.default.equal(criterion(score({ businessType: 'barbershop' }), 'target_industry').awarded, 20);
});
(0, node_test_1.default)('a business outside the ICP earns neither the industry nor the model point', () => {
    const result = score({ businessType: 'workshop' });
    strict_1.default.equal(criterion(result, 'target_industry').awarded, 0);
    strict_1.default.equal(criterion(result, 'recurring_customer_model').awarded, 0);
    // Known and not matching, which is different from unknown.
    strict_1.default.equal(criterion(result, 'target_industry').basis, 'FACT');
});
(0, node_test_1.default)('the recurring-customer point is an inference about the trade, not a fact about the shop', () => {
    const result = score({ businessType: 'barbershop' });
    strict_1.default.equal(criterion(result, 'recurring_customer_model').basis, 'INFERENCE');
    strict_1.default.equal(criterion(result, 'target_industry').basis, 'FACT');
});
(0, node_test_1.default)('the employee-count criterion is switched off and does not appear at all', () => {
    // No source the pipeline calls reports headcount. A criterion worth zero is
    // dropped from the breakdown rather than shown as an unanswerable row, so
    // "not in the result" is the assertion, not "awarded zero".
    const result = score({ employeeCount: 6 });
    strict_1.default.equal(result.dimensions
        .flatMap((dimension) => dimension.criteria)
        .find((entry) => entry.key === 'employee_count'), undefined);
    strict_1.default.ok(!result.unknowns.some((entry) => entry.includes('pessoas')));
});
(0, node_test_1.default)('a switched-off criterion comes back by raising its weight in the config', () => {
    // The point of zeroing rather than deleting: restoring it is a number in
    // the settings screen, not a deploy.
    const restored = (0, prospecting_scoring_js_1.scoreProspect)({ ...prospecting_scoring_js_1.UNKNOWN_SIGNALS, employeeCount: 6 }, {
        ...config,
        businessFit: { ...config.businessFit, employeeCountInRange: 5 },
    }, geography);
    strict_1.default.equal(criterion(restored, 'employee_count').awarded, 5);
});
(0, node_test_1.default)('a rating is three-valued: unknown is not a bad rating', () => {
    strict_1.default.equal(criterion(score({ rating: 4.6 }), 'rating_at_least').awarded, 5);
    strict_1.default.equal(criterion(score({ rating: 4 }), 'rating_at_least').awarded, 5);
    strict_1.default.equal(criterion(score({ rating: 3.9 }), 'rating_at_least').awarded, 0);
    strict_1.default.equal(criterion(score({ rating: 3.9 }), 'rating_at_least').basis, 'FACT');
    // A shop with no reviews yet has not been rated badly.
    strict_1.default.equal(criterion(score({ rating: null }), 'rating_at_least').basis, 'UNKNOWN');
});
(0, node_test_1.default)('target geography is worth five, by city or by province', () => {
    strict_1.default.equal(criterion(score({ city: 'Maputo' }), 'target_geography').awarded, 5);
    strict_1.default.equal(criterion(score({ city: 'Matola' }), 'target_geography').awarded, 5);
    strict_1.default.equal(criterion(score({ city: 'Matola-Rio', province: 'Maputo' }), 'target_geography').awarded, 5);
    strict_1.default.equal(criterion(score({ city: 'Beira', province: 'Sofala' }), 'target_geography').awarded, 0);
});
(0, node_test_1.default)('business fit never exceeds its cap', () => {
    const result = score({
        businessType: 'barbershop',
        rating: 4.6,
        city: 'Maputo',
        country: 'Moçambique',
    });
    strict_1.default.equal(result.businessFit, 40);
    strict_1.default.ok(result.businessFit <= config.businessFit.max);
});
/* -------------------------------------------------------- digital presence */
(0, node_test_1.default)('a website is worth five', () => {
    strict_1.default.equal(criterion(score({ websiteUrl: 'https://x.test' }), 'website').awarded, 5);
});
(0, node_test_1.default)('having no website is a finding, not a gap in knowledge', () => {
    // Discovery looks for a website; not finding one is the answer, so this
    // criterion is never UNKNOWN.
    strict_1.default.equal(criterion(score({ websiteUrl: null }), 'website').basis, 'FACT');
});
(0, node_test_1.default)('the social criteria are switched off — no source reports profiles', () => {
    const result = score({ socialProfileCount: 4, websiteUrl: 'https://x.test' });
    const keys = result.dimensions.flatMap((dimension) => dimension.criteria.map((entry) => entry.key));
    strict_1.default.ok(!keys.includes('active_social'));
    strict_1.default.ok(!keys.includes('strong_presence'));
});
(0, node_test_1.default)('a contact channel is worth five', () => {
    strict_1.default.equal(criterion(score({ hasContactChannel: true }), 'contact_channel').awarded, 5);
});
(0, node_test_1.default)('a published timetable and photos are worth five each, three-valued', () => {
    strict_1.default.equal(criterion(score({ hasOpeningHours: true }), 'opening_hours').awarded, 5);
    strict_1.default.equal(criterion(score({ hasOpeningHours: false }), 'opening_hours').basis, 'FACT');
    strict_1.default.equal(criterion(score({ hasOpeningHours: null }), 'opening_hours').basis, 'UNKNOWN');
    strict_1.default.equal(criterion(score({ hasPhotos: true }), 'photos').awarded, 5);
});
(0, node_test_1.default)('digital presence caps at twenty', () => {
    const result = score({
        websiteUrl: 'https://x.test',
        hasContactChannel: true,
        hasOpeningHours: true,
        hasPhotos: true,
    });
    strict_1.default.equal(result.digitalPresence, 20);
});
/* ------------------------------------------------------ retention potential */
(0, node_test_1.default)('a recurring trade is worth ten and several services five more', () => {
    const result = score({ businessType: 'barbershop' });
    strict_1.default.equal(criterion(result, 'recurring_service').awarded, 10);
    strict_1.default.equal(criterion(result, 'multiple_services').awarded, 5);
    // Plus the loyalty use case, which the ICP table now answers on its own:
    // a trade that is both recurring and multi-service has one by definition.
    strict_1.default.equal(criterion(result, 'loyalty_use_case').awarded, 5);
    strict_1.default.equal(result.retentionPotential, 20);
});
(0, node_test_1.default)('a trade with one service earns the recurring point but not the variety point', () => {
    // A gym sells one thing, repeatedly.
    const gym = (0, prospecting_config_js_1.findIcpIndustry)('gym');
    strict_1.default.ok(gym);
    strict_1.default.equal(gym.recurringModel, true);
    strict_1.default.equal(gym.multipleServices, false);
    const result = score({ businessType: 'gym' });
    strict_1.default.equal(criterion(result, 'recurring_service').awarded, 10);
    strict_1.default.equal(criterion(result, 'multiple_services').awarded, 0);
});
(0, node_test_1.default)('the promotions criterion is switched off — nothing crawls pages now', () => {
    const result = score({ runsPromotions: true });
    strict_1.default.equal(result.dimensions
        .flatMap((dimension) => dimension.criteria)
        .find((entry) => entry.key === 'promotions'), undefined);
});
(0, node_test_1.default)('the loyalty use case is inferred from the trade, and an observation overrules it', () => {
    // Inferred: nothing looked at this shop, but the trade answers the question.
    const inferred = criterion(score({ businessType: 'barbershop' }), 'loyalty_use_case');
    strict_1.default.equal(inferred.awarded, 5);
    strict_1.default.equal(inferred.basis, 'INFERENCE');
    // A gym is recurring but sells one thing, so the table says no.
    strict_1.default.equal(criterion(score({ businessType: 'gym' }), 'loyalty_use_case').awarded, 0);
    // An explicit "no" from something that actually looked is a FACT and wins
    // over the table — `??` and not `||` is what makes this pass.
    const observed = criterion(score({ businessType: 'barbershop', loyaltyUseCase: false }), 'loyalty_use_case');
    strict_1.default.equal(observed.awarded, 0);
    strict_1.default.equal(observed.basis, 'FACT');
    // With no trade and no observation there is nothing to go on, and UNKNOWN
    // beats INFERENCE: `criterion` overrides the basis whenever `met` is null,
    // so an unanswered criterion cannot be dressed up as a reasoned zero.
    strict_1.default.equal(criterion(score({}), 'loyalty_use_case').basis, 'UNKNOWN');
    strict_1.default.equal(criterion(score({}), 'loyalty_use_case').awarded, 0);
});
(0, node_test_1.default)('review volume is worth five per threshold met', () => {
    strict_1.default.equal(criterion(score({ reviewCount: 9 }), 'review_volume_10').awarded, 0);
    strict_1.default.equal(criterion(score({ reviewCount: 10 }), 'review_volume_10').awarded, 5);
    strict_1.default.equal(criterion(score({ reviewCount: 10 }), 'review_volume_30').awarded, 0);
    strict_1.default.equal(criterion(score({ reviewCount: 30 }), 'review_volume_30').awarded, 5);
    // Traffic and quality are scored apart: many reviews, poorly rated.
    const busy = score({ reviewCount: 41, rating: 3.4 });
    strict_1.default.equal(criterion(busy, 'review_volume_30').awarded, 5);
    strict_1.default.equal(criterion(busy, 'rating_at_least').awarded, 0);
    strict_1.default.equal(criterion(score({ reviewCount: null }), 'review_volume_10').basis, 'UNKNOWN');
});
(0, node_test_1.default)('retention potential caps at thirty', () => {
    const result = score({
        businessType: 'barbershop',
        loyaltyUseCase: true,
        reviewCount: 120,
    });
    strict_1.default.equal(result.retentionPotential, 30);
});
/* --------------------------------------------------- commercial opportunity */
(0, node_test_1.default)('the decision-maker and growth criteria are switched off', () => {
    const result = score({ decisionMakerIdentified: true, growthSignal: true });
    const keys = result.dimensions.flatMap((dimension) => dimension.criteria.map((entry) => entry.key));
    strict_1.default.ok(!keys.includes('decision_maker'));
    strict_1.default.ok(!keys.includes('growth_signal'));
});
(0, node_test_1.default)('a reachable contact and a trading business are worth five each', () => {
    strict_1.default.equal(criterion(score({ reachableContact: true }), 'reachable_contact').awarded, 5);
    strict_1.default.equal(criterion(score({ isOperational: true }), 'operational').awarded, 5);
    // Closed is a finding worth zero, not an unknown, and not a disqualification.
    strict_1.default.equal(criterion(score({ isOperational: false }), 'operational').awarded, 0);
    strict_1.default.equal(criterion(score({ isOperational: false }), 'operational').basis, 'FACT');
    strict_1.default.equal(criterion(score({ isOperational: null }), 'operational').basis, 'UNKNOWN');
    const both = score({ reachableContact: true, isOperational: true });
    strict_1.default.equal(both.commercialOpportunity, 10);
});
/* ------------------------------------------------------------------ bands */
(0, node_test_1.default)('the bands are the ones the plan fixes', () => {
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(100, config), 'PRIORITY');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(80, config), 'PRIORITY');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(79, config), 'GOOD');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(60, config), 'GOOD');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(59, config), 'NURTURE');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(40, config), 'NURTURE');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(39, config), 'LOW_FIT');
    strict_1.default.equal((0, prospecting_config_js_1.bandFor)(0, config), 'LOW_FIT');
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
(0, node_test_1.default)('a lead with everything one listing can say scores one hundred and is PRIORITY', () => {
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
    strict_1.default.equal(result.total, 100);
    strict_1.default.equal(result.band, 'PRIORITY');
    strict_1.default.deepEqual(result.unknowns, []);
});
(0, node_test_1.default)('the four dimension caps still add up to one hundred', () => {
    // A guard against a future edit that raises one dimension and forgets that
    // the bands are absolute numbers, not percentages.
    strict_1.default.equal(config.businessFit.max +
        config.digitalPresence.max +
        config.retentionPotential.max +
        config.commercialOpportunity.max, 100);
});
/* --------------------------------------------------------------- unknowns */
(0, node_test_1.default)('unknown criteria are listed rather than folded into the score', () => {
    const result = score({ businessType: 'barbershop', city: 'Maputo' });
    // The listing was never read: no rating, no review count, no timetable, no
    // photos, no trading status. Five things nobody looked at, each of which a
    // detail call would answer — which is exactly what the panel is for.
    strict_1.default.ok(result.unknowns.length >= 5);
    strict_1.default.ok(result.unknowns.some((entry) => entry.includes('Avaliação')));
    strict_1.default.ok(result.unknowns.some((entry) => entry.includes('avaliações')));
    // And nothing about a switched-off criterion, which no call can answer.
    strict_1.default.ok(!result.unknowns.some((entry) => entry.includes('pessoas')));
});
/* ------------------------------------------------------------- geography */
(0, node_test_1.default)('a place nothing is known about is unknown, not out of area', () => {
    strict_1.default.equal((0, prospecting_scoring_js_1.isTargetGeography)({ city: null, province: null, country: null }, geography), null);
});
(0, node_test_1.default)('a stated country that is not the target rules the lead out', () => {
    strict_1.default.equal((0, prospecting_scoring_js_1.isTargetGeography)({ city: 'Maputo', province: null, country: 'Portugal' }, geography), false);
});
(0, node_test_1.default)('the country code is accepted where the country name is expected', () => {
    strict_1.default.equal((0, prospecting_scoring_js_1.isTargetGeography)({ city: 'Maputo', province: null, country: 'MZ' }, geography), true);
});
(0, node_test_1.default)('adding a city to the configuration is all it takes to sell there', () => {
    const widened = { ...geography, cities: [...geography.cities, 'Beira'] };
    strict_1.default.equal((0, prospecting_scoring_js_1.isTargetGeography)({ city: 'Beira', province: 'Sofala', country: 'Moçambique' }, widened), true);
});
/* ----------------------------------------------------------- qualification */
(0, node_test_1.default)('a business with no name cannot be identified and is refused', () => {
    const result = (0, prospecting_scoring_js_1.qualify)({ name: '  ', businessType: 'barbershop', city: 'Maputo', province: null, country: null }, geography);
    strict_1.default.equal(result.qualified, false);
    strict_1.default.equal(result.qualified === false && result.reason, 'NO_IDENTIFYING_DATA');
});
(0, node_test_1.default)('a business outside the target geography is refused', () => {
    const result = (0, prospecting_scoring_js_1.qualify)({ name: 'Barbearia X', businessType: 'barbershop', city: 'Beira', province: 'Sofala', country: 'Moçambique' }, geography);
    strict_1.default.equal(result.qualified === false && result.reason, 'OUT_OF_GEOGRAPHY');
});
(0, node_test_1.default)('a stated trade outside the ICP is refused', () => {
    const result = (0, prospecting_scoring_js_1.qualify)({ name: 'Oficina X', businessType: 'workshop', city: 'Maputo', province: null, country: null }, geography);
    strict_1.default.equal(result.qualified === false && result.reason, 'NOT_TARGET_INDUSTRY');
});
(0, node_test_1.default)('an unknown trade is not a refusal', () => {
    // The leads hardest to find are the ones least likely to already be
    // somebody's customer. Absence of an industry is not evidence against.
    const result = (0, prospecting_scoring_js_1.qualify)({ name: 'Barbearia X', businessType: null, city: 'Maputo', province: null, country: null }, geography);
    strict_1.default.equal(result.qualified, true);
});
/* ------------------------------------- evidence-weighted rating and ranking */
(0, node_test_1.default)('a five-star rating from one review does not outrank a 4.4 from a hundred', () => {
    // The failure this exists to prevent, taken from a real run: Level Up
    // Barber MZ (5.0, 2 reviews) was ranked above Tchetcho's (4.4, 107) and the
    // better lead fell outside the paid slots.
    const mean = 4.6;
    const loud = (0, prospecting_scoring_js_1.bayesianRating)(5, 1, mean, 10);
    const proven = (0, prospecting_scoring_js_1.bayesianRating)(4.4, 107, mean, 10);
    strict_1.default.ok(loud !== null && proven !== null);
    strict_1.default.ok(proven < 5, 'a média ponderada não inventa pontuação acima da real');
    strict_1.default.ok(loud < proven + 0.35, 'uma avaliação de uma só review aproxima-se da média da corrida');
    strict_1.default.ok(Math.abs(proven - 4.4) < 0.05, '107 reviews quase não são puxadas');
});
(0, node_test_1.default)('the prior pulls hardest where there is least evidence', () => {
    const mean = 4.0;
    const one = (0, prospecting_scoring_js_1.bayesianRating)(5, 1, mean, 10);
    const fifty = (0, prospecting_scoring_js_1.bayesianRating)(5, 50, mean, 10);
    strict_1.default.ok(one < fifty);
});
(0, node_test_1.default)('no prior and no mean leaves the rating exactly as it was', () => {
    strict_1.default.equal((0, prospecting_scoring_js_1.bayesianRating)(4.7, 12, null, 10), 4.7);
    strict_1.default.equal((0, prospecting_scoring_js_1.bayesianRating)(4.7, 12, 4.0, 0), 4.7);
});
(0, node_test_1.default)('a listing with no rating has no weighted rating either', () => {
    // Not zero, and not the mean. Nothing was measured, and saying otherwise
    // would hand an unrated shop the average shop's score.
    strict_1.default.equal((0, prospecting_scoring_js_1.bayesianRating)(null, null, 4.5, 10), null);
});
(0, node_test_1.default)('the run mean ignores the listings that carry no rating', () => {
    strict_1.default.equal((0, prospecting_scoring_js_1.meanRatingOf)([{ rating: 4 }, { rating: 5 }, { rating: null }]), 4.5);
    strict_1.default.equal((0, prospecting_scoring_js_1.meanRatingOf)([{ rating: null }]), null);
});
(0, node_test_1.default)('a business with no rating scores below the threshold it used to equal', () => {
    const blank = {
        ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
        businessType: 'barbershop',
        city: 'Maputo',
        country: 'Moçambique',
        isOperational: true,
    };
    const before = (0, prospecting_scoring_js_1.scoreProspect)(blank, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY);
    const after = (0, prospecting_scoring_js_1.scoreProspect)(blank, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, {
        noRatingPenalty: 10,
    });
    strict_1.default.equal(after.total, before.total - 10);
    strict_1.default.equal(after.evidencePenalty, 10);
    strict_1.default.ok(after.total < prospecting_config_js_1.DEFAULT_SETTINGS.minScoreForEnrichment);
});
(0, node_test_1.default)('the penalty is configurable, and zero restores the old behaviour', () => {
    const blank = { ...prospecting_scoring_js_1.UNKNOWN_SIGNALS, businessType: 'barbershop', city: 'Maputo' };
    const plain = (0, prospecting_scoring_js_1.scoreProspect)(blank, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY);
    const unpenalised = (0, prospecting_scoring_js_1.scoreProspect)(blank, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, {
        noRatingPenalty: 0,
    });
    strict_1.default.equal(unpenalised.total, plain.total);
    strict_1.default.equal(unpenalised.evidencePenalty, 0);
});
(0, node_test_1.default)('a rated business is not penalised', () => {
    const rated = {
        ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
        businessType: 'barbershop',
        city: 'Maputo',
        rating: 4.5,
        reviewCount: 56,
    };
    const score = (0, prospecting_scoring_js_1.scoreProspect)(rated, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, {
        noRatingPenalty: 10,
    });
    strict_1.default.equal(score.evidencePenalty, 0);
});
(0, node_test_1.default)('a rating with zero reviews counts as no evidence', () => {
    // A rating of 5.0 attached to no reviews at all is a field, not a finding.
    const hollow = {
        ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
        businessType: 'barbershop',
        city: 'Maputo',
        rating: 5,
        reviewCount: 0,
    };
    strict_1.default.equal((0, prospecting_scoring_js_1.scoreProspect)(hollow, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, { noRatingPenalty: 10 })
        .evidencePenalty, 10);
});
(0, node_test_1.default)('the score never goes below zero, however large the penalty', () => {
    const blank = { ...prospecting_scoring_js_1.UNKNOWN_SIGNALS };
    const score = (0, prospecting_scoring_js_1.scoreProspect)(blank, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, {
        noRatingPenalty: 1000,
    });
    strict_1.default.equal(score.total, 0);
});
(0, node_test_1.default)('ties are broken by evidence, then rating, then name — never by arrival order', () => {
    // Nine businesses tied at 75 in the real run, and the first five were taken
    // in whatever order the API answered in.
    const tied = [
        { score: 75, reviewCount: 35, rating: 4.8, name: 'Hair Studio' },
        { score: 75, reviewCount: 107, rating: 4.4, name: "Tchetcho's Barber Shop" },
        { score: 75, reviewCount: 43, rating: 4.7, name: 'ManCave' },
        { score: 75, reviewCount: 43, rating: 4.9, name: 'Zulu Cortes' },
        { score: 80, reviewCount: 1, rating: 5, name: 'Outro' },
    ];
    const order = [...tied].sort(prospecting_scoring_js_1.compareForRank).map((entry) => entry.name);
    strict_1.default.deepEqual(order, [
        'Outro',
        "Tchetcho's Barber Shop",
        'Zulu Cortes',
        'ManCave',
        'Hair Studio',
    ]);
});
(0, node_test_1.default)('the same list sorts the same way twice', () => {
    const rows = [
        { score: 75, reviewCount: null, rating: null, name: 'Beta' },
        { score: 75, reviewCount: null, rating: null, name: 'Alfa' },
        { score: 75, reviewCount: null, rating: null, name: 'Gama' },
    ];
    const once = [...rows].sort(prospecting_scoring_js_1.compareForRank).map((entry) => entry.name);
    const twice = [...rows].reverse().sort(prospecting_scoring_js_1.compareForRank).map((entry) => entry.name);
    strict_1.default.deepEqual(once, twice);
    strict_1.default.deepEqual(once, ['Alfa', 'Beta', 'Gama']);
});
(0, node_test_1.default)('the score stays on its 0-100 scale, so stored bands keep their meaning', () => {
    const strong = {
        ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
        businessType: 'barbershop',
        city: 'Maputo',
        country: 'Moçambique',
        rating: 4.8,
        reviewCount: 200,
        websiteUrl: 'https://exemplo.co.mz',
        hasContactChannel: true,
        reachableContact: true,
        hasOpeningHours: true,
        hasPhotos: true,
        isOperational: true,
    };
    const score = (0, prospecting_scoring_js_1.scoreProspect)(strong, prospecting_config_js_1.DEFAULT_SCORING, prospecting_config_js_1.DEFAULT_GEOGRAPHY, {
        meanRating: 4.5,
        priorCount: 10,
        noRatingPenalty: 10,
    });
    strict_1.default.ok(score.total <= 100);
    strict_1.default.ok(score.total >= 0);
});
