"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const affiliate_whatsapp_cloud_js_1 = require("./affiliate_whatsapp_cloud.js");
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
/* ---------------------------------------------------------------- fixtures */
function message(overrides = {}) {
    return {
        idempotencyKey: 'merchant-1:affiliate_new_customer:sale-9',
        merchantId: 'merchant-1',
        template: 'affiliate_new_customer',
        toPhoneE164: '+258841234567',
        body: 'rendered elsewhere',
        variables: {
            points: 1250,
            merchantName: 'Barbearia Central',
            statusText: 'a aguardar aprovação',
        },
        ...overrides,
    };
}
function okFetch(captured = {}, id = 'wamid.ABC') {
    return (async (url, init) => {
        captured.url = String(url);
        captured.init = init;
        return new Response(JSON.stringify({ messages: [{ id }] }), { status: 200 });
    });
}
function failingFetch(status, payload) {
    return (async () => new Response(JSON.stringify(payload), { status }));
}
const adapter = (fetchImpl) => new affiliate_whatsapp_cloud_js_1.WhatsAppCloudAdapter({
    accessToken: 'token',
    phoneNumberId: '1234567890',
    fetchImpl,
});
const body = (init) => JSON.parse(String(init?.body ?? '{}'));
/* ------------------------------------------------- templates and parameters */
(0, node_test_1.default)('every local template has a parameter order read from its own text', () => {
    for (const name of affiliate_notifications_js_1.AFFILIATE_TEMPLATE) {
        const placeholders = (0, affiliate_whatsapp_cloud_js_1.templatePlaceholders)(name);
        const braces = (affiliate_notifications_js_1.AFFILIATE_TEMPLATES[name].match(/\{\w+\}/g) ?? []).length;
        strict_1.default.equal(placeholders.length, braces, `${name}: a ordem devia cobrir todos os marcadores`);
    }
});
(0, node_test_1.default)('the parameter order is the order the placeholders appear in', () => {
    // WhatsApp maps parameters by position. Swapping two sends a real message
    // to a real person with the point total where the name should be.
    strict_1.default.deepEqual((0, affiliate_whatsapp_cloud_js_1.templatePlaceholders)('affiliate_new_customer'), [
        'merchantName',
        'points',
        'statusText',
    ]);
    strict_1.default.deepEqual((0, affiliate_whatsapp_cloud_js_1.templatePlaceholders)('customer_referral_thanks'), ['points']);
});
(0, node_test_1.default)('the parameters carry the same values the body was rendered from', () => {
    const sent = message();
    const rendered = (0, affiliate_notifications_js_1.renderAffiliateMessage)(sent.template, sent.variables ?? {});
    for (const value of (0, affiliate_whatsapp_cloud_js_1.templateParameters)(sent)) {
        strict_1.default.ok(rendered.includes(value), `${value} devia aparecer no corpo renderizado: ${rendered}`);
    }
});
(0, node_test_1.default)('points are formatted the same way in both halves', () => {
    strict_1.default.deepEqual((0, affiliate_whatsapp_cloud_js_1.templateParameters)(message()), [
        'Barbearia Central',
        (1250).toLocaleString('pt-PT'),
        'a aguardar aprovação',
    ]);
});
(0, node_test_1.default)('a missing value is a permanent failure, not an empty parameter', () => {
    // "Tem  pontos a aguardar aprovação" reads like a rounding bug to whoever
    // receives it, and no bug report ever reaches anyone.
    strict_1.default.throws(() => (0, affiliate_whatsapp_cloud_js_1.templateParameters)(message({ variables: { points: 10 } })), (error) => error instanceof affiliate_whatsapp_cloud_js_1.WhatsAppSendError &&
        error.retryable === false &&
        /merchantName/.test(error.message));
});
(0, node_test_1.default)('a message built before variables existed fails clearly', () => {
    strict_1.default.throws(() => (0, affiliate_whatsapp_cloud_js_1.templateParameters)(message({ variables: undefined })), (error) => error instanceof affiliate_whatsapp_cloud_js_1.WhatsAppSendError && !error.retryable);
});
(0, node_test_1.default)('a newline inside a value is collapsed, not refused', () => {
    const params = (0, affiliate_whatsapp_cloud_js_1.templateParameters)(message({ variables: { points: 5, merchantName: 'Barbearia\nCentral', statusText: 'aprovados' } }));
    strict_1.default.equal(params[0], 'Barbearia Central');
});
/* ----------------------------------------------------------- the request */
(0, node_test_1.default)('the request is a template message, never free text', () => {
    const captured = {};
    return adapter(okFetch(captured))
        .send(message())
        .then(() => {
        const payload = body(captured.init);
        strict_1.default.equal(payload.type, 'template');
        strict_1.default.equal(payload.template.name, 'affiliate_new_customer');
        strict_1.default.equal(payload.messaging_product, 'whatsapp');
        strict_1.default.equal(payload.to, '+258841234567');
        // The rendered body must not travel: outside the 24-hour window Meta
        // rejects it, and the rejection looks like a transient fault.
        strict_1.default.ok(!JSON.stringify(payload).includes('rendered elsewhere'));
    });
});
(0, node_test_1.default)('the parameters go in the body component, in order', async () => {
    const captured = {};
    await adapter(okFetch(captured)).send(message());
    const payload = body(captured.init);
    strict_1.default.deepEqual(payload.template.components[0].parameters.map((p) => p.text), ['Barbearia Central', (1250).toLocaleString('pt-PT'), 'a aguardar aprovação']);
});
(0, node_test_1.default)('a template with no placeholders sends no components', async () => {
    const captured = {};
    await adapter(okFetch(captured)).send(message({ template: 'customer_referral_thanks', variables: { points: 40 } }));
    const payload = body(captured.init);
    strict_1.default.equal(payload.template.components.length, 1, 'tem {points}, logo tem componente');
});
(0, node_test_1.default)('the token travels in the header and the url names the sending number', async () => {
    const captured = {};
    await adapter(okFetch(captured)).send(message());
    strict_1.default.ok(captured.url?.endsWith('/1234567890/messages'));
    const headers = captured.init?.headers;
    strict_1.default.equal(headers.authorization, 'Bearer token');
    // Never in the query string: a token there lands in every access log
    // between here and Meta.
    strict_1.default.ok(!captured.url?.includes('token'));
});
(0, node_test_1.default)('the provider message id is returned', async () => {
    const result = await adapter(okFetch({}, 'wamid.XYZ')).send(message());
    strict_1.default.equal(result.providerMessageId, 'wamid.XYZ');
});
(0, node_test_1.default)('a 200 with no message id is not treated as sent', async () => {
    const fetchImpl = (async () => new Response(JSON.stringify({ messages: [] }), { status: 200 }));
    await strict_1.default.rejects(adapter(fetchImpl).send(message()), (error) => error instanceof affiliate_whatsapp_cloud_js_1.WhatsAppSendError &&
        // Not retried: it may well have been sent, and sending again is worse.
        error.retryable === false);
});
/* ------------------------------------------------------- error classification */
(0, node_test_1.default)('an unapproved template is permanent', () => {
    const error = (0, affiliate_whatsapp_cloud_js_1.errorFrom)(400, {
        error: { code: 132001, message: 'Template name does not exist' },
    });
    strict_1.default.equal(error.retryable, false);
    strict_1.default.equal(error.code, 132001);
});
(0, node_test_1.default)('a parameter count mismatch is permanent', () => {
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(400, { error: { code: 132000 } }).retryable, false);
});
(0, node_test_1.default)('a recipient who is not on WhatsApp is permanent', () => {
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(400, { error: { code: 131026 } }).retryable, false);
});
(0, node_test_1.default)('a rate limit is retryable', () => {
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(400, { error: { code: 130429 } }).retryable, true);
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(429, {}).retryable, true);
});
(0, node_test_1.default)('Meta failing on its own side is retryable', () => {
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(500, {}).retryable, true);
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(503, {}).retryable, true);
});
(0, node_test_1.default)('refused credentials are permanent, so the log line is readable', () => {
    // A queue retrying a bad token every five minutes buries the one line that
    // says the token is bad under thousands that say nothing.
    const error = (0, affiliate_whatsapp_cloud_js_1.errorFrom)(401, { error: { message: 'Invalid OAuth access token' } });
    strict_1.default.equal(error.retryable, false);
    strict_1.default.match(error.message, /credenciais/);
});
(0, node_test_1.default)('an unrecognised 400 is retried rather than dropped on a guess', () => {
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.errorFrom)(400, { error: { code: 999999 } }).retryable, true);
});
(0, node_test_1.default)('the body is read before the status is judged', async () => {
    // A 429 carrying an unapproved-template code is the template's fault, and
    // retrying it forever would never start working.
    const error = (0, affiliate_whatsapp_cloud_js_1.errorFrom)(429, { error: { code: 132016 } });
    strict_1.default.equal(error.retryable, false);
});
(0, node_test_1.default)('a network failure is retryable', async () => {
    const fetchImpl = (async () => {
        throw new Error('ECONNRESET');
    });
    await strict_1.default.rejects(adapter(fetchImpl).send(message()), (error) => error instanceof affiliate_whatsapp_cloud_js_1.WhatsAppSendError && error.retryable);
});
/* ------------------------------------------------- the delivery boundary */
(0, node_test_1.default)('a permanent adapter failure is not retried by the outbox', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: {
            send: async () => {
                throw new affiliate_whatsapp_cloud_js_1.WhatsAppSendError({ message: 'template disabled', retryable: false });
            },
        },
        notificationsEnabled: true,
    });
    strict_1.default.equal(outcome.status, 'failed');
    strict_1.default.equal(outcome.status === 'failed' && outcome.retryable, false);
});
(0, node_test_1.default)('an adapter that classifies nothing still gets the retrying default', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: {
            send: async () => {
                throw new Error('boom');
            },
        },
        notificationsEnabled: true,
    });
    strict_1.default.equal(outcome.status === 'failed' && outcome.retryable, true);
});
(0, node_test_1.default)('a sent message reports the provider id', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: adapter(okFetch({}, 'wamid.OK')),
        notificationsEnabled: true,
    });
    strict_1.default.equal(outcome.status, 'sent');
    strict_1.default.equal(outcome.status === 'sent' && outcome.providerMessageId, 'wamid.OK');
});
/* --------------------------------------------------------- construction */
(0, node_test_1.default)('half a configuration is no configuration', () => {
    // Half-configured would throw on every row and burn the whole backlog's
    // retry budget; null keeps the outbox answering not_configured.
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: 'x', phoneNumberId: undefined }), null);
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: undefined, phoneNumberId: 'y' }), null);
    strict_1.default.equal((0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: '  ', phoneNumberId: 'y' }), null);
    strict_1.default.notEqual((0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: 'x', phoneNumberId: 'y' }), null);
});
(0, node_test_1.default)('an unconfigured provider still answers not_configured, not failed', async () => {
    const outcome = await (0, affiliate_notifications_js_1.deliverAffiliateMessage)(message(), {
        adapter: (0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: undefined, phoneNumberId: undefined }),
        notificationsEnabled: true,
    });
    strict_1.default.equal(outcome.status, 'not_configured');
});
(0, node_test_1.default)('the template language defaults to the one the templates are written in', async () => {
    const captured = {};
    const built = (0, affiliate_whatsapp_cloud_js_1.cloudAdapterFrom)({ accessToken: 'x', phoneNumberId: '1' });
    strict_1.default.ok(built !== null);
    await new affiliate_whatsapp_cloud_js_1.WhatsAppCloudAdapter({
        accessToken: 'x',
        phoneNumberId: '1',
        fetchImpl: okFetch(captured),
    }).send(message());
    strict_1.default.equal(body(captured.init).template.language.code, 'pt_PT');
});
