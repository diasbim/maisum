"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
/**
 * What guards `/merchant/*`, checked against the source rather than trusted.
 *
 * These endpoints run with the Admin SDK, which bypasses `firestore.rules`
 * entirely, so the only thing standing between a caller and someone else's
 * customer list is the resolve step at the top of each handler. That is a
 * property of how the routes are written, and nothing in a unit test of the
 * data layer would notice it going missing — a route added in a hurry, with
 * the `merchantId` read straight off the query string, would pass every other
 * test in this suite.
 *
 * So this reads index.ts and asserts the shape holds. It is a lint with a
 * reason, and it fails loudly the day someone adds route number six.
 */
const SOURCE = (0, node_fs_1.readFileSync)(node_path_1.default.join(__dirname, '..', 'src', 'index.ts'), 'utf8');
/** The body of every `merchantRouter.<verb>('<path>', ...)` handler. */
function merchantRoutes() {
    const pattern = /merchantRouter\.(get|post|put|patch|delete)\(\s*'([^']+)'/g;
    const found = [];
    for (const match of SOURCE.matchAll(pattern)) {
        const start = match.index ?? 0;
        // Up to the start of the next route, or to where the router is mounted.
        pattern.lastIndex = start + match[0].length;
        const next = new RegExp(/merchantRouter\.(?:get|post|put|patch|delete)\(|app\.use\('\/merchant'/).exec(SOURCE.slice(pattern.lastIndex));
        const end = next === null ? SOURCE.length : pattern.lastIndex + (next.index ?? 0);
        found.push({ route: match[2], body: SOURCE.slice(start, end) });
    }
    return found;
}
(0, node_test_1.default)('the merchant router still has routes to check', () => {
    // Guards the guard: a rename that made the pattern match nothing would turn
    // every assertion below into a vacuous pass.
    const routes = merchantRoutes();
    strict_1.default.ok(routes.length >= 5, `found only ${routes.length} merchant routes`);
    strict_1.default.ok(routes.some((route) => route.route === '/customers'));
});
(0, node_test_1.default)('every merchant route resolves its business before reading anything', () => {
    for (const { route, body } of merchantRoutes()) {
        const resolves = body.includes('requireBusiness(') ||
            body.includes('businessForRequest(') ||
            // /businesses is the one that answers "which are you" and so cannot
            // resolve a business first; it asks for the caller's identity instead.
            body.includes('merchantIdentityFrom(');
        strict_1.default.ok(resolves, `merchantRouter '${route}' does not resolve a business before reading`);
    }
});
(0, node_test_1.default)('no merchant route reads a merchant id straight from the request', () => {
    // `businessForRequest` honours `?merchant_id=` only after `authorizeBusiness`
    // confirms it. A handler reaching for the parameter itself would skip that.
    for (const { route, body } of merchantRoutes()) {
        strict_1.default.ok(!/req\.query\.merchant_id/.test(body), `merchantRouter '${route}' reads merchant_id from the query directly`);
        strict_1.default.ok(!/req\.params\.merchantId/.test(body), `merchantRouter '${route}' reads a merchant id from the path`);
    }
});
(0, node_test_1.default)('a denied resolve returns, rather than falling through', () => {
    // `requireBusiness` answers the request and returns null. A handler that
    // ignored the null would serve the first business it could find.
    for (const { route, body } of merchantRoutes()) {
        if (!body.includes('requireBusiness('))
            continue;
        strict_1.default.ok(/if \(!business\) return/.test(body), `merchantRouter '${route}' does not stop when the business is denied`);
    }
});
/* ------------------------------------------------------- the bypasses above */
(0, node_test_1.default)('the request bypasses cannot reach merchant data', () => {
    // Two paths through the global middleware admit a request with no ID token:
    // the admin API key, and ALLOW_DEV_AUTH with an x-merchant-id header. Both
    // leave `req.auth` unset, and `merchantIdentityFrom` returns null without it
    // — so they answer 401 rather than acting as a business.
    const assignments = SOURCE.match(/authedReq\.auth = /g) ?? [];
    strict_1.default.equal(assignments.length, 1, 'req.auth is assigned in more than one place; the merchant guard assumes ' +
        'it is set only after verifyIdToken');
    const identity = /function merchantIdentityFrom\(([\s\S]*?)\n}/.exec(SOURCE);
    strict_1.default.ok(identity, 'merchantIdentityFrom is no longer a named function');
    strict_1.default.ok(identity[1].includes('req.auth'), 'merchantIdentityFrom no longer derives the caller from the verified token');
    strict_1.default.ok(/if \(!decoded\?\.uid\) return null/.test(identity[1]), 'merchantIdentityFrom no longer refuses a request with no verified uid');
});
/**
 * Which merchant routes may change anything.
 *
 * The business side of the portal is a reading surface: a sale, a redemption
 * and a visit report all happen with the customer standing there, and belong
 * to the app. Closing a recovery task is bookkeeping about work already done,
 * which is why it is the exception.
 *
 * "The portal writes when it needs to" is a real decision, and this list is
 * where it is recorded. Adding a route here should be a deliberate act with a
 * reason, not something that arrives with a feature — so a new write fails
 * this test until someone writes it down.
 */
const ESCRITAS_PERMITIDAS = new Set(['/recovery-tasks/:taskId/complete']);
function mutatingMerchantRoutes() {
    const pattern = /merchantRouter\.(post|put|patch|delete)\(\s*'([^']+)'/g;
    return [...SOURCE.matchAll(pattern)].map((match) => match[2]);
}
(0, node_test_1.default)('the only merchant writes are the ones we decided on', () => {
    for (const route of mutatingMerchantRoutes()) {
        strict_1.default.ok(ESCRITAS_PERMITIDAS.has(route), `${route} changes business data. Add it to ESCRITAS_PERMITIDAS with a reason, or make it a GET.`);
    }
});
(0, node_test_1.default)('every allowed write is actually still there', () => {
    // Guards the guard the other way: a route removed or renamed leaves a stale
    // entry above, and the next reader would trust a list that describes nothing.
    const found = new Set(mutatingMerchantRoutes());
    for (const route of ESCRITAS_PERMITIDAS) {
        strict_1.default.ok(found.has(route), `${route} is in the allow-list but no longer exists`);
    }
});
(0, node_test_1.default)('a write scopes itself by the resolved business, not by its own path', () => {
    // A read that forgets the scope shows the wrong data; a write that forgets it
    // changes someone else's.
    for (const { route, body } of merchantRoutes()) {
        if (!/merchantRouter\.(post|put|patch|delete)/.test(body))
            continue;
        strict_1.default.ok(/business\.id/.test(body), `${route} writes without passing business.id`);
    }
});
