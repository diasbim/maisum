"use strict";
/**
 * The WhatsApp provider, at last: Meta's Cloud API.
 *
 * `affiliate_outbox_firestore.ts` left this boundary deliberately empty, and
 * said what filling it would take. This is that — one `WhatsAppAdapter`, no
 * change to the outbox, the queue, the retry schedule or the stored rows.
 *
 * ── Why template messages and not the rendered body ─────────────────────────
 *
 * Every message this product sends is **business-initiated**: an affiliate
 * learns a referral converted, a customer is thanked for a code they used.
 * Nobody messaged the business first. WhatsApp allows free text only inside a
 * 24-hour window opened by the *customer* writing in, and outside it accepts
 * nothing but a pre-approved template, sent as a name plus ordered
 * parameters.
 *
 * So `message.body` — already rendered, and still carried for logs, previews
 * and the manual share sheet — cannot be what goes on the wire. Posting it as
 * `type: "text"` would be rejected for every recipient who had not written in
 * first, which is all of them, and the rejection (131047) looks like a
 * transient provider fault rather than a design mistake.
 *
 * ── Why the parameters are derived, not listed ──────────────────────────────
 *
 * The order comes from reading `{placeholders}` out of the same
 * `AFFILIATE_TEMPLATES` string the body was rendered from. A second
 * hand-written list would be a copy to keep in step, and the failure when it
 * drifted would be silent in the worst way: Meta maps parameters by position,
 * so a swapped pair sends a real message, to a real person, with the point
 * total where the merchant's name should be.
 *
 * ── What must exist on Meta's side ─────────────────────────────────────────
 *
 * One approved template per entry in `AFFILIATE_TEMPLATE`, named exactly that,
 * in the language this adapter is configured with, whose body has the same
 * number of `{{n}}` placeholders in the same order as the local string. A
 * mismatch is error 132000, and it is reported as permanent rather than
 * retried, because retrying an unapproved template never starts working.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.WhatsAppCloudAdapter = exports.WhatsAppSendError = void 0;
exports.templatePlaceholders = templatePlaceholders;
exports.templateParameters = templateParameters;
exports.errorFrom = errorFrom;
exports.cloudAdapterFrom = cloudAdapterFrom;
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
const DEFAULT_BASE_URL = 'https://graph.facebook.com/v21.0';
const DEFAULT_LANGUAGE = 'pt_PT';
const DEFAULT_TIMEOUT_MS = 10000;
/**
 * A parameter WhatsApp will not accept.
 *
 * Newlines, tabs and runs of four or more spaces are rejected inside a
 * template parameter — the template owns the layout, the parameter is a value.
 * Collapsed rather than refused: a merchant who typed a line break into their
 * business name should not silently stop receiving notifications.
 */
const collapseWhitespace = (value) => value.replace(/[\r\n\t]+/g, ' ').replace(/\s{2,}/g, ' ').trim();
/* --------------------------------------------------------------- the error */
/**
 * A send that failed, and whether trying again could help.
 *
 * The outbox already distinguishes retryable from terminal; before this
 * adapter existed there was no error taxonomy to populate it with, so
 * `deliverAffiliateMessage` assumed everything was worth retrying. That
 * assumption is wrong in one expensive direction: an unapproved template or a
 * number that is not on WhatsApp fails identically every time, and retrying
 * it spends quota and keeps a dead row in the queue.
 */
class WhatsAppSendError extends Error {
    constructor(input) {
        super(input.message);
        this.name = 'WhatsAppSendError';
        this.retryable = input.retryable;
        this.code = input.code ?? null;
        this.httpStatus = input.httpStatus ?? null;
    }
}
exports.WhatsAppSendError = WhatsAppSendError;
/**
 * Meta error codes that fail the same way however often they are retried.
 *
 * Everything not listed is treated as retryable, which is the safe default
 * for a queue with a bounded attempt count: a permanent failure retried a few
 * times is cheap, a transient one dropped is a message somebody never gets.
 */
const PERMANENT_CODES = new Set([
    131026, // recipient is not a WhatsApp user, or cannot receive messages
    131047, // re-engagement: free text outside the 24h window
    131051, // unsupported message type
    131052, // media download error
    132000, // parameter count does not match the approved template
    132001, // template does not exist in this language
    132005, // translated text too long
    132007, // parameter format does not match the template
    132012, // parameter format error
    132015, // template paused for quality
    132016, // template disabled
    132068, // flow is blocked
    133010, // sending phone number not registered
]);
/** Codes that are explicitly worth another attempt, for readability. */
const RETRYABLE_CODES = new Set([
    368, // temporarily blocked for policy violations — lifts on its own
    130429, // API throughput limit
    131000, // generic internal error on Meta's side
    131048, // spam rate limit
    131056, // pair rate limit between this business and this recipient
]);
/* ---------------------------------------------------------- the parameters */
/**
 * The placeholders of a local template, in the order they appear.
 *
 * Exported because the test asserts the local strings and the approved
 * templates agree on arity, and because an operator submitting a template to
 * Meta needs to know what `{{1}}` is supposed to be.
 */
function templatePlaceholders(template) {
    const found = [];
    const pattern = /\{(\w+)\}/g;
    let match = pattern.exec(affiliate_notifications_js_1.AFFILIATE_TEMPLATES[template]);
    while (match !== null) {
        found.push(match[1]);
        match = pattern.exec(affiliate_notifications_js_1.AFFILIATE_TEMPLATES[template]);
    }
    return found;
}
/**
 * The ordered parameter values for one message.
 *
 * Throws permanently when a value the template needs is missing. The
 * alternative — sending an empty string — produces a message reading "Tem
 * pontos a aguardar aprovação" that looks like a product bug to the person
 * who receives it, and no bug report ever reaches anyone.
 */
function templateParameters(message) {
    const values = {
        points: message.variables?.points === undefined
            ? undefined
            : Math.max(0, Math.floor(message.variables.points)).toLocaleString('pt-PT'),
        merchantName: message.variables?.merchantName,
        statusText: message.variables?.statusText,
    };
    return templatePlaceholders(message.template).map((name) => {
        const raw = values[name];
        const value = typeof raw === 'string' ? collapseWhitespace(raw) : raw;
        if (value === undefined || value === '') {
            throw new WhatsAppSendError({
                message: `template ${message.template} needs ${name}, which this message does not carry`,
                retryable: false,
            });
        }
        return value;
    });
}
class WhatsAppCloudAdapter {
    constructor(options) {
        this.options = options;
    }
    async send(message) {
        const parameters = templateParameters(message);
        const fetchImpl = this.options.fetchImpl ?? fetch;
        const baseUrl = (this.options.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, '');
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
        let response;
        try {
            response = await fetchImpl(`${baseUrl}/${this.options.phoneNumberId}/messages`, {
                method: 'POST',
                headers: {
                    // Bearer, and never logged. The outbox masks the phone number for
                    // the same reason: a log line is read by more people than a message.
                    authorization: `Bearer ${this.options.accessToken}`,
                    'content-type': 'application/json',
                },
                body: JSON.stringify({
                    messaging_product: 'whatsapp',
                    recipient_type: 'individual',
                    to: message.toPhoneE164,
                    type: 'template',
                    template: {
                        name: message.template,
                        language: { code: this.options.language ?? DEFAULT_LANGUAGE },
                        components: parameters.length === 0
                            ? []
                            : [
                                {
                                    type: 'body',
                                    parameters: parameters.map((text) => ({ type: 'text', text })),
                                },
                            ],
                    },
                }),
                signal: controller.signal,
            });
        }
        catch (error) {
            const aborted = error instanceof Error &&
                (error.name === 'AbortError' || error.name === 'TimeoutError');
            throw new WhatsAppSendError({
                message: aborted ? 'request timed out' : 'network error',
                retryable: true,
            });
        }
        finally {
            clearTimeout(timer);
        }
        let payload = null;
        try {
            payload = await response.json();
        }
        catch {
            payload = null;
        }
        if (!response.ok)
            throw errorFrom(response.status, payload);
        const id = firstMessageId(payload);
        if (id === null) {
            // A 200 with no message id is a contract this adapter does not
            // understand. Not retried: the message may well have been sent, and
            // sending it again is worse than failing loudly once.
            throw new WhatsAppSendError({
                message: 'accepted without a message id',
                retryable: false,
                httpStatus: response.status,
            });
        }
        return { providerMessageId: id };
    }
}
exports.WhatsAppCloudAdapter = WhatsAppCloudAdapter;
/* ------------------------------------------------------------- the mapping */
function asRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? value
        : null;
}
/** The id Meta assigned, from `messages[0].id`. */
function firstMessageId(payload) {
    const messages = asRecord(payload)?.messages;
    if (!Array.isArray(messages) || messages.length === 0)
        return null;
    const id = asRecord(messages[0])?.id;
    return typeof id === 'string' && id.trim() !== '' ? id : null;
}
/**
 * An HTTP failure, turned into a typed one.
 *
 * The body is read before the status is judged, for the same reason the Places
 * adapter does it: Meta reports a rate limit and an unapproved template with
 * overlapping statuses, and judging the status alone would retry the template
 * forever while giving up on the rate limit.
 */
function errorFrom(httpStatus, payload) {
    const error = asRecord(asRecord(payload)?.error);
    const code = typeof error?.code === 'number' ? error.code : null;
    const detail = (typeof error?.message === 'string' ? error.message : null) ??
        `HTTP ${httpStatus}`;
    if (code !== null && PERMANENT_CODES.has(code)) {
        return new WhatsAppSendError({ message: detail, retryable: false, code, httpStatus });
    }
    if (code !== null && RETRYABLE_CODES.has(code)) {
        return new WhatsAppSendError({ message: detail, retryable: true, code, httpStatus });
    }
    // An expired or wrong token. Permanent on purpose: it is a configuration
    // fault, and a queue that retries it every five minutes buries the one log
    // line that says so under thousands that say nothing.
    if (httpStatus === 401 || httpStatus === 403) {
        return new WhatsAppSendError({
            message: `credenciais recusadas: ${detail}`,
            retryable: false,
            code,
            httpStatus,
        });
    }
    if (httpStatus === 429 || httpStatus >= 500) {
        return new WhatsAppSendError({ message: detail, retryable: true, code, httpStatus });
    }
    // A 400 this adapter has no code for. Retryable, because the alternative is
    // dropping a message on a guess, and the attempt count bounds the cost.
    return new WhatsAppSendError({ message: detail, retryable: true, code, httpStatus });
}
/* ------------------------------------------------------------ construction */
/**
 * The adapter, when both halves of its configuration exist.
 *
 * Null when either is missing, so the outbox keeps answering
 * `not_configured` — a half-configured provider that throws on every row
 * would burn the retry budget of the whole backlog.
 */
function cloudAdapterFrom(env) {
    const accessToken = env.accessToken?.trim() ?? '';
    const phoneNumberId = env.phoneNumberId?.trim() ?? '';
    if (accessToken === '' || phoneNumberId === '')
        return null;
    return new WhatsAppCloudAdapter({
        accessToken,
        phoneNumberId,
        language: env.language?.trim() === '' || env.language === undefined
            ? DEFAULT_LANGUAGE
            : env.language.trim(),
    });
}
