"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
function message(overrides = {}) {
    return {
        idempotencyKey: 'aff_reward:ar_1',
        merchantId: 'merchant-1',
        template: 'affiliate_new_customer',
        toPhoneE164: '+258840000001',
        body: 'corpo',
        ...overrides,
    };
}
/* -------------------------------------------------------------- the words */
(0, node_test_1.default)('a pending reward is never described as approved', () => {
    // The affiliate would count on points the merchant has not agreed to, and
    // the correction is worse than the wait.
    strict_1.default.equal((0, affiliate_notifications_js_1.rewardStatusText)('PENDING'), 'a aguardar aprovação');
    strict_1.default.equal((0, affiliate_notifications_js_1.rewardStatusText)('APPROVED'), 'aprovados');
});
(0, node_test_1.default)('anything that is not approved reads as waiting', () => {
    for (const status of ['PENDING', 'CANCELLED', 'PAID', '', 'something new']) {
        strict_1.default.equal((0, affiliate_notifications_js_1.rewardStatusText)(status), 'a aguardar aprovação', status);
    }
});
(0, node_test_1.default)('the status text is matched regardless of case or padding', () => {
    strict_1.default.equal((0, affiliate_notifications_js_1.rewardStatusText)('  approved '), 'aprovados');
});
(0, node_test_1.default)('every template renders with no placeholder left behind', () => {
    for (const template of affiliate_notifications_js_1.AFFILIATE_TEMPLATE) {
        const rendered = (0, affiliate_notifications_js_1.renderAffiliateMessage)(template, {
            points: 150,
            merchantName: 'Café Central',
            statusText: (0, affiliate_notifications_js_1.rewardStatusText)('PENDING'),
        });
        strict_1.default.ok(!/\{\w+\}/.test(rendered), `${template} left a placeholder`);
        strict_1.default.ok(rendered.length > 0);
    }
});
(0, node_test_1.default)('the affiliate message names the shop and the reward', () => {
    const rendered = (0, affiliate_notifications_js_1.renderAffiliateMessage)('affiliate_new_customer', {
        points: 150,
        merchantName: 'Café Central',
        statusText: (0, affiliate_notifications_js_1.rewardStatusText)('PENDING'),
    });
    strict_1.default.match(rendered, /Café Central/);
    strict_1.default.match(rendered, /150 pontos de recompensa a aguardar aprovação/);
});
(0, node_test_1.default)('an unknown placeholder is left visible rather than blanked', () => {
    // "Tem  pontos" looks like a rounding bug and gets ignored; "Tem {points}
    // pontos" is obviously broken and gets reported.
    const rendered = (0, affiliate_notifications_js_1.renderAffiliateMessage)('affiliate_new_customer', {
        merchantName: 'Café Central',
        statusText: 'aprovados',
    });
    strict_1.default.match(rendered, /\{points\}/);
});
(0, node_test_1.default)('a blank shop name does not leave a gap in the sentence', () => {
    const rendered = (0, affiliate_notifications_js_1.renderAffiliateMessage)('affiliate_new_customer', {
        points: 10,
        merchantName: '   ',
        statusText: 'aprovados',
    });
    strict_1.default.match(rendered, /\{merchantName\}/);
});
(0, node_test_1.default)('points are whole and never negative', () => {
    strict_1.default.match((0, affiliate_notifications_js_1.renderAffiliateMessage)('customer_referral_thanks', { points: 12.7 }), /12 pontos/);
    strict_1.default.match((0, affiliate_notifications_js_1.renderAffiliateMessage)('customer_referral_thanks', { points: -5 }), /0 pontos/);
});
(0, node_test_1.default)('the templates stay editable strings with braced variables', () => {
    for (const template of affiliate_notifications_js_1.AFFILIATE_TEMPLATE) {
        strict_1.default.match(affiliate_notifications_js_1.AFFILIATE_TEMPLATES[template], /\{\w+\}/, `${template} has no variables and was probably hard-coded`);
    }
});
/* ----------------------------------------------------------- the delivery */
(0, node_test_1.default)('with no provider, nothing is sent and nothing is claimed', async () => {
    // The whole point: a stub returning success would mark every message
    // delivered and lose the lot.
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: null,
        notificationsEnabled: true,
    });
    strict_1.default.deepEqual(outcome, { status: 'not_configured' });
});
(0, node_test_1.default)('not configured is not a failure and does not burn a retry', () => {
    const outcome = { status: 'not_configured' };
    strict_1.default.equal((0, affiliate_notifications_js_1.isTerminalDelivery)(outcome, affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS + 10), false);
});
(0, node_test_1.default)('a merchant who turned notifications off is not messaged', async () => {
    let called = false;
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: {
            async send() {
                called = true;
                return { providerMessageId: 'x' };
            },
        },
        notificationsEnabled: false,
    });
    strict_1.default.deepEqual(outcome, { status: 'skipped', reason: 'notifications_disabled' });
    strict_1.default.equal(called, false, 'the adapter was reached anyway');
});
(0, node_test_1.default)('a recipient with no number is skipped, not retried forever', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message({ toPhoneE164: '  ' }), {
        adapter: { async send() { return { providerMessageId: 'x' }; } },
        notificationsEnabled: true,
    });
    strict_1.default.deepEqual(outcome, { status: 'skipped', reason: 'no_phone' });
    strict_1.default.equal((0, affiliate_notifications_js_1.isTerminalDelivery)(outcome, 1), true);
});
(0, node_test_1.default)('a working provider reports what it sent', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: { async send() { return { providerMessageId: 'wamid.1' }; } },
        notificationsEnabled: true,
    });
    strict_1.default.deepEqual(outcome, { status: 'sent', providerMessageId: 'wamid.1' });
    strict_1.default.equal((0, affiliate_notifications_js_1.isTerminalDelivery)(outcome, 1), true);
});
(0, node_test_1.default)('a throwing provider is a failure, not a crash', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: { async send() { throw new Error('502 from provider'); } },
        notificationsEnabled: true,
    });
    strict_1.default.equal(outcome.status, 'failed');
    strict_1.default.match(outcome.error, /502/);
});
(0, node_test_1.default)('a failure retries up to the cap and then stops', () => {
    const failure = { status: 'failed', retryable: true, error: 'boom' };
    for (let attempt = 1; attempt < affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS; attempt++) {
        strict_1.default.equal((0, affiliate_notifications_js_1.isTerminalDelivery)(failure, attempt), false, `attempt ${attempt}`);
    }
    strict_1.default.equal((0, affiliate_notifications_js_1.isTerminalDelivery)(failure, affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS), true);
});
/* ------------------------------------------------------------- the timing */
(0, node_test_1.default)('backoff grows, then stops growing', () => {
    strict_1.default.equal((0, affiliate_notifications_js_1.nextAttemptDelayMs)(1), 30000);
    strict_1.default.equal((0, affiliate_notifications_js_1.nextAttemptDelayMs)(2), 60000);
    strict_1.default.equal((0, affiliate_notifications_js_1.nextAttemptDelayMs)(3), 120000);
});
(0, node_test_1.default)('the last retry is still the same day', () => {
    // Uncapped doubling puts it days out, by which point congratulating someone
    // on a sale is strange rather than late.
    const last = (0, affiliate_notifications_js_1.nextAttemptDelayMs)(affiliate_notifications_js_1.MAX_DELIVERY_ATTEMPTS);
    strict_1.default.ok(last <= 3600000, `${last}ms is longer than an hour`);
});
(0, node_test_1.default)('a nonsense attempt number does not produce a nonsense delay', () => {
    strict_1.default.ok((0, affiliate_notifications_js_1.nextAttemptDelayMs)(0) > 0);
    strict_1.default.ok((0, affiliate_notifications_js_1.nextAttemptDelayMs)(-3) > 0);
});
/* --------------------------------------------------------------- the logs */
(0, node_test_1.default)('a logged number identifies a recipient without reaching them', () => {
    strict_1.default.equal((0, affiliate_notifications_js_1.maskPhone)('+258840000001'), '***0001');
    strict_1.default.notEqual((0, affiliate_notifications_js_1.maskPhone)('+258840000001'), (0, affiliate_notifications_js_1.maskPhone)('+258840000002'));
});
(0, node_test_1.default)('a number too short to mask is hidden entirely', () => {
    strict_1.default.equal((0, affiliate_notifications_js_1.maskPhone)('12'), '***');
    strict_1.default.equal((0, affiliate_notifications_js_1.maskPhone)(''), '***');
});
