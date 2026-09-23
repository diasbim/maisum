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
 * The guards this feature depends on, read from the files that deploy them.
 *
 * Everything else about the referral engine is proved by running it. These
 * four cannot be: `firestore.rules` and `firestore.indexes.json` are only
 * enforced by Google's infrastructure, the PostgreSQL scripts are only run by
 * `psql`, and where the routes are mounted is decided in `index.ts` rather
 * than in any handler. Without an emulator and a database in CI, the honest
 * substitute is to read the artefacts and hold them to the contract the code
 * assumes — which catches the failure that actually happens: someone adds a
 * collection, an index, a column or a route and forgets one of the four.
 *
 * This is not a claim that the rules were exercised against a live Firestore.
 * They were not. `docs/afiliados/PLAN.md` §10 documents the emulator command
 * for when one is available.
 */
const REPO = node_path_1.default.join(__dirname, '..', '..');
const FUNCTIONS = node_path_1.default.join(__dirname, '..');
function read(...segments) {
    return (0, node_fs_1.readFileSync)(node_path_1.default.join(...segments), 'utf8');
}
const RULES = read(REPO, 'firestore.rules');
const INDEXES_RAW = read(REPO, 'firestore.indexes.json');
const UP_SQL = read(FUNCTIONS, 'sql', 'migrations', '20260915_affiliates.up.sql');
const DOWN_SQL = read(FUNCTIONS, 'sql', 'migrations', '20260915_affiliates.down.sql');
const SCHEMA_SQL = read(FUNCTIONS, 'sql', 'schema.sql');
const SEED_SQL = read(FUNCTIONS, 'sql', 'seed_affiliates.sql');
const INDEX_TS = read(FUNCTIONS, 'src', 'index.ts');
const COMMIT_TS = read(FUNCTIONS, 'src', 'affiliate_sale_commit.ts');
const OFFLINE_TS = read(FUNCTIONS, 'src', 'affiliate_offline_sale.ts');
const STORE_TS = read(FUNCTIONS, 'src', 'affiliate_store.ts');
const ROUTES_TS = read(FUNCTIONS, 'src', 'affiliate_routes.ts');
const OUTBOX_FS_TS = read(FUNCTIONS, 'src', 'affiliate_outbox_firestore.ts');
const OUTBOX_TS = read(FUNCTIONS, 'src', 'affiliate_outbox.ts');
/**
 * Every server-owned collection the feature writes, under a business.
 *
 * `affiliate_code_lookup_cache` is deliberately absent: that one is SQLite on
 * the device, never Firestore.
 */
const MERCHANT_SCOPED_COLLECTIONS = [
    'affiliate_merchants',
    'affiliate_codes',
    'affiliate_attributions',
    'affiliate_rewards',
    'affiliate_events',
    'affiliate_outbox',
    'affiliate_fraud_signals',
    'affiliate_rate_limits',
];
/** The two that live at the root because they are global by definition. */
const ROOT_COLLECTIONS = ['affiliates', 'affiliate_code_lookup'];
/* ============================================================ firestore.rules */
/** The body of `match /<collection>/{...} { ... }`, wherever it appears. */
function matchBlock(collection) {
    const pattern = new RegExp(`match /${collection}/\\{[A-Za-z]+\\}\\s*\\{([\\s\\S]*?)\\n(\\s*)\\}`);
    const found = pattern.exec(RULES);
    strict_1.default.ok(found, `firestore.rules has no match block for ${collection}`);
    return found[1];
}
(0, node_test_1.default)('every merchant-scoped affiliate collection is denied to clients outright', () => {
    for (const collection of MERCHANT_SCOPED_COLLECTIONS) {
        const block = matchBlock(collection);
        strict_1.default.match(block, /allow read,\s*write:\s*if false;/, `${collection} is not denied in firestore.rules`);
        // Not "deny writes but allow reads": a reward row names who is owed what,
        // and an attribution names which customer belongs to which affiliate.
        strict_1.default.doesNotMatch(block, /allow (read|get|list)[^:]*:\s*if (?!false)/, `${collection} grants a client read`);
    }
});
(0, node_test_1.default)('the global affiliate identity and the code lookup are denied too', () => {
    for (const collection of ROOT_COLLECTIONS) {
        strict_1.default.match(matchBlock(collection), /allow read,\s*write:\s*if false;/, `${collection} is not denied in firestore.rules`);
    }
});
(0, node_test_1.default)('no affiliate collection is in the readable business allowlist', () => {
    const allowlist = /function isReadableBusinessCollection\(collectionId\) \{([\s\S]*?)\n    \}/
        .exec(RULES);
    strict_1.default.ok(allowlist, 'the readable-collection allowlist moved');
    for (const collection of MERCHANT_SCOPED_COLLECTIONS) {
        strict_1.default.ok(!allowlist[1].includes(`'${collection}'`), `${collection} is readable by any member of the business`);
    }
});
(0, node_test_1.default)('a client cannot write any referral field onto a sale', () => {
    const writable = /function saleClientWritableFields\(\) \{([\s\S]*?)\n    \}/.exec(RULES);
    const serverOwned = /function saleServerOwnedReferralFields\(\) \{([\s\S]*?)\n    \}/
        .exec(RULES);
    strict_1.default.ok(writable && serverOwned, 'the sale field lists moved');
    const fields = (block) => [...block.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
    const writableFields = new Set(fields(writable[1]));
    const serverFields = fields(serverOwned[1]);
    strict_1.default.ok(serverFields.length > 0);
    for (const field of serverFields) {
        strict_1.default.ok(!writableFields.has(field), `${field} is both server-owned and client-writable`);
    }
    // Both gates are wired in, not merely declared.
    strict_1.default.match(RULES, /saleCreateIsValid[\s\S]*?saleCarriesNoReferralClaim\(\)/);
    strict_1.default.match(RULES, /saleUpdateIsValid[\s\S]*?saleReferralFieldsUnchanged\(\)/);
});
(0, node_test_1.default)('every referral field the commit writes onto a sale is named as server-owned', () => {
    const serverOwned = /function saleServerOwnedReferralFields\(\) \{([\s\S]*?)\n    \}/
        .exec(RULES);
    strict_1.default.ok(serverOwned);
    const declared = new Set([...serverOwned[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]));
    // Read off the two places that build a sale document, so a field added to
    // either one without being declared here fails rather than becomes writable.
    const written = new Set();
    for (const source of [COMMIT_TS, OFFLINE_TS]) {
        for (const match of source.matchAll(/^\s{4}(gross_amount|referral_[a-z_]+|affiliate_(?:id|code_id)):/gm)) {
            written.add(match[1]);
        }
    }
    strict_1.default.ok(written.size >= 8, 'the sale document shape could not be read');
    for (const field of written) {
        strict_1.default.ok(declared.has(field), `${field} is written by the server but not listed in saleServerOwnedReferralFields`);
    }
});
(0, node_test_1.default)('firestore.indexes.json is valid JSON with the shape the CLI deploys', () => {
    const parsed = JSON.parse(INDEXES_RAW);
    strict_1.default.ok(Array.isArray(parsed.indexes));
    for (const entry of parsed.indexes) {
        strict_1.default.equal(typeof entry.collectionGroup, 'string');
        strict_1.default.ok(['COLLECTION', 'COLLECTION_GROUP'].includes(entry.queryScope));
        strict_1.default.ok(Array.isArray(entry.fields) && entry.fields.length > 0);
        for (const field of entry.fields) {
            strict_1.default.equal(typeof field.fieldPath, 'string');
            strict_1.default.ok(field.order !== undefined || field.arrayConfig !== undefined, `${entry.collectionGroup}.${field.fieldPath} has no order`);
        }
    }
});
function affiliateIndexes() {
    const parsed = JSON.parse(INDEXES_RAW);
    return parsed.indexes.filter((entry) => entry.collectionGroup.startsWith('affiliate'));
}
function hasIndexFor(collection, fields) {
    return affiliateIndexes().some((entry) => entry.collectionGroup === collection &&
        fields.every((field, position) => entry.fields[position]?.fieldPath === field));
}
(0, node_test_1.default)('every scoped list the store runs has an index that starts with the business', () => {
    // `readScoped` filters on merchant_id, optionally plus one more field.
    for (const collection of [
        'affiliate_merchants',
        'affiliate_codes',
        'affiliate_attributions',
        'affiliate_rewards',
    ]) {
        strict_1.default.ok(hasIndexFor(collection, ['merchant_id']), `${collection} has no merchant-scoped index`);
    }
    // The `extra` filter the routes pass is always affiliate_id.
    strict_1.default.match(STORE_TS, /query\.where\(extra\.field, '==', extra\.value\)/);
    for (const collection of [
        'affiliate_codes',
        'affiliate_attributions',
        'affiliate_rewards',
    ]) {
        strict_1.default.ok(hasIndexFor(collection, ['merchant_id', 'affiliate_id']), `${collection} has no merchant + affiliate index`);
    }
});
(0, node_test_1.default)('the outbox sweep query is indexed the way it is written', () => {
    // status IN (...) + next_attempt_at <= now, ordered by next_attempt_at.
    strict_1.default.match(OUTBOX_FS_TS, /\.where\('status', 'in'/);
    strict_1.default.match(OUTBOX_FS_TS, /\.where\('next_attempt_at', '<=', input\.now\)/);
    strict_1.default.match(OUTBOX_FS_TS, /\.orderBy\('next_attempt_at', 'asc'\)/);
    strict_1.default.ok(hasIndexFor('affiliate_outbox', ['status', 'next_attempt_at']), 'the outbox sweep would need an index Firestore does not have');
});
(0, node_test_1.default)('the only index that can cross businesses is the outbox sweep, which no client can reach', () => {
    const crossBusiness = affiliateIndexes().filter((entry) => entry.queryScope === 'COLLECTION_GROUP');
    // The sweep runs as a scheduled worker with the Admin SDK and deliberately
    // reads every business's due backlog; everything else stays inside one.
    strict_1.default.deepEqual(crossBusiness.map((entry) => entry.collectionGroup), ['affiliate_outbox']);
    strict_1.default.match(OUTBOX_FS_TS, /db\(\)\.collectionGroup\('affiliate_outbox'\)/);
    // And the rules deny that collection to every client, so the index is not a
    // way around merchant isolation.
    strict_1.default.match(matchBlock('affiliate_outbox'), /allow read,\s*write:\s*if false;/);
    // No merchant-scoped read is left without the business as its first filter.
    for (const entry of affiliateIndexes()) {
        if (entry.queryScope === 'COLLECTION_GROUP')
            continue;
        if (entry.collectionGroup === 'affiliate_outbox')
            continue;
        strict_1.default.equal(entry.fields[0]?.fieldPath, 'merchant_id', `${entry.collectionGroup} is indexed without the business first`);
    }
});
/* ============================================================ SQL migrations */
function statements(sql) {
    return sql
        .split('\n')
        .filter((line) => !line.trimStart().startsWith('--'))
        .join('\n')
        .split(';')
        .map((statement) => statement.trim())
        .filter((statement) => statement !== '');
}
function created(sql, kind) {
    const pattern = kind === 'TABLE'
        ? /CREATE TABLE IF NOT EXISTS ([a-z_]+)/g
        : /CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z_]+)/g;
    return [...sql.matchAll(pattern)].map((match) => match[1]);
}
function dropped(sql, kind) {
    const pattern = new RegExp(`DROP ${kind} IF EXISTS ([a-z_]+)`, 'g');
    return [...sql.matchAll(pattern)].map((match) => match[1]);
}
(0, node_test_1.default)('both migration scripts declare one transaction boundary', () => {
    for (const [name, sql] of [
        ['up', UP_SQL],
        ['down', DOWN_SQL],
    ]) {
        strict_1.default.match(sql, /^BEGIN;/, `${name} does not open a transaction`);
        strict_1.default.match(sql.trimEnd(), /COMMIT;$/, `${name} does not commit`);
    }
});
(0, node_test_1.default)('the down script structurally names every table the up script creates', () => {
    const createdTables = created(UP_SQL, 'TABLE');
    const droppedTables = new Set(dropped(DOWN_SQL, 'TABLE'));
    strict_1.default.ok(createdTables.length >= 9, 'the up script creates fewer tables than the plan');
    for (const table of createdTables) {
        strict_1.default.ok(droppedTables.has(table), `${table} survives the rollback`);
    }
    // And nothing else: a rollback that drops `sales` is not a rollback.
    for (const table of droppedTables) {
        strict_1.default.ok(createdTables.includes(table), `the down script drops ${table}, which it did not create`);
    }
});
(0, node_test_1.default)('the down script structurally names every legacy column and index added by up', () => {
    const addedColumns = [...UP_SQL.matchAll(/ADD COLUMN IF NOT EXISTS ([a-z_]+)/g)].map((match) => match[1]);
    const droppedColumns = new Set([...DOWN_SQL.matchAll(/DROP COLUMN IF EXISTS ([a-z_]+)/g)].map((match) => match[1]));
    strict_1.default.ok(addedColumns.length > 0, 'the up script alters no existing table');
    for (const column of addedColumns) {
        strict_1.default.ok(droppedColumns.has(column), `${column} survives the rollback`);
    }
    // Indexes on tables the down script does not drop have to be dropped by name;
    // the ones on affiliate tables go with the table.
    const affiliateTables = new Set(created(UP_SQL, 'TABLE'));
    const legacyIndexes = [...UP_SQL.matchAll(/CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z_]+)\s*\n?\s*ON ([a-z_]+)/g)]
        .filter((match) => !affiliateTables.has(match[2]))
        .map((match) => match[1]);
    const droppedIndexes = new Set(dropped(DOWN_SQL, 'INDEX'));
    for (const index of legacyIndexes) {
        strict_1.default.ok(droppedIndexes.has(index), `${index} is left behind on a legacy table`);
    }
});
(0, node_test_1.default)('the rollback declares dependency-safe reverse table order', () => {
    const createdTables = created(UP_SQL, 'TABLE');
    const droppedTables = dropped(DOWN_SQL, 'TABLE');
    // Reverse creation order is what makes a foreign key chain droppable.
    const expected = createdTables.filter((table) => droppedTables.includes(table)).reverse();
    strict_1.default.deepEqual(droppedTables, expected, 'the rollback drops tables in an order a foreign key could block');
    // Indexes before the columns they are on, columns before the tables.
    const downStatements = statements(DOWN_SQL);
    const firstTableDrop = downStatements.findIndex((s) => s.startsWith('DROP TABLE'));
    const lastIndexDrop = downStatements.map((s) => s.startsWith('DROP INDEX')).lastIndexOf(true);
    strict_1.default.ok(lastIndexDrop < firstTableDrop, 'an index is dropped after its table');
});
(0, node_test_1.default)('the up script uses idempotent DDL guards', () => {
    for (const statement of statements(UP_SQL)) {
        if (statement.startsWith('CREATE TABLE')) {
            strict_1.default.match(statement, /^CREATE TABLE IF NOT EXISTS/);
        }
        if (statement.startsWith('CREATE INDEX') || statement.startsWith('CREATE UNIQUE INDEX')) {
            strict_1.default.match(statement, /IF NOT EXISTS/);
        }
        if (statement.startsWith('ALTER TABLE')) {
            strict_1.default.match(statement, /ALTER TABLE IF EXISTS/);
            for (const line of statement.split('\n')) {
                if (line.includes('ADD COLUMN'))
                    strict_1.default.match(line, /ADD COLUMN IF NOT EXISTS/);
            }
        }
    }
});
(0, node_test_1.default)('the down script uses idempotent DDL guards', () => {
    for (const statement of statements(DOWN_SQL)) {
        if (statement.startsWith('DROP'))
            strict_1.default.match(statement, /IF EXISTS/);
        if (statement.startsWith('ALTER TABLE')) {
            strict_1.default.match(statement, /ALTER TABLE IF EXISTS/);
            for (const line of statement.split('\n')) {
                if (line.includes('DROP COLUMN'))
                    strict_1.default.match(line, /DROP COLUMN IF EXISTS/);
            }
        }
    }
});
(0, node_test_1.default)('the bootstrap schema and the migration create the same affiliate tables', () => {
    const fromMigration = new Set(created(UP_SQL, 'TABLE'));
    const fromSchema = new Set(created(SCHEMA_SQL, 'TABLE').filter((table) => table.startsWith('affiliate')));
    for (const table of fromMigration) {
        strict_1.default.ok(fromSchema.has(table), `${table} exists only in the migration, so a fresh bootstrap lacks it`);
    }
});
(0, node_test_1.default)('the uniqueness the feature depends on is enforced by the database, not by hope', () => {
    // One live attribution per customer per business, whatever a race does.
    strict_1.default.match(UP_SQL, /CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_attributions_non_rejected_customer\s*\n\s*ON affiliate_attributions\(merchant_id, customer_id\)\s*\n\s*WHERE status <> 'REJECTED';/);
    // One reward per attribution per type: the duplicate-reward conflict rule.
    strict_1.default.match(UP_SQL, /CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_rewards_attribution_type\s*\n\s*ON affiliate_rewards\(merchant_id, attribution_id, reward_type\);/);
    // One code string across every business: the key of the lookup table itself,
    // which is what makes the collision retry in `claimAffiliateCode` decidable.
    strict_1.default.match(UP_SQL, /CREATE TABLE IF NOT EXISTS affiliate_code_lookup \(\s*\n\s*normalized_code TEXT PRIMARY KEY,/);
    // One affiliate identity per phone.
    strict_1.default.match(UP_SQL, /CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliates_normalized_phone\s*\n\s*ON affiliates\(normalized_phone\);/);
    // One code per affiliate per business.
    strict_1.default.match(UP_SQL, /CREATE UNIQUE INDEX IF NOT EXISTS idx_affiliate_codes_scope\s*\n\s*ON affiliate_codes\(/);
    // Every one of them survives into the bootstrap schema too.
    for (const name of [
        'idx_affiliate_attributions_non_rejected_customer',
        'idx_affiliate_rewards_attribution_type',
        'idx_affiliates_normalized_phone',
    ]) {
        strict_1.default.ok(SCHEMA_SQL.includes(name), `${name} is missing from schema.sql`);
    }
});
(0, node_test_1.default)('the seed carries only obviously synthetic phone numbers', () => {
    // A seed row with a real number sends a real person a WhatsApp the first
    // time somebody points the worker at a dev database.
    const phones = [...SEED_SQL.matchAll(/\+?258(\d{9})/g)].map((match) => match[1]);
    strict_1.default.ok(phones.length > 0, 'the seed has no affiliates in it');
    for (const national of phones) {
        // After the operator prefix, a fixture number is either one digit repeated
        // or a run of zeros with a counter on the end. A real number is neither.
        const body = national.slice(2);
        strict_1.default.ok(/^(\d)\1*$/.test(body) || /^0{4,}\d$/.test(body), `+258${national} does not look like a reserved test number`);
    }
});
(0, node_test_1.default)('the seed is confined to a demonstrably fake business', () => {
    // Nothing in it may write into a business that could exist in production.
    strict_1.default.doesNotMatch(SEED_SQL, /DROP |TRUNCATE |DELETE FROM (?!affiliate)/);
    strict_1.default.match(SEED_SQL, /ON CONFLICT/, 'the seed is not re-runnable');
    strict_1.default.match(SEED_SQL, /merchant-affiliates-dev/);
    strict_1.default.match(SEED_SQL, /MaisUm Afiliados Demo/);
    strict_1.default.match(SEED_SQL, /merchant-affiliates-secondary/);
});
(0, node_test_1.default)('the ordinary sale trigger invokes the real referred-return command', () => {
    const start = INDEX_TS.indexOf('export const loyaltyLedgerSaleOnSaleWrite = onDocumentWritten');
    strict_1.default.ok(start > 0, 'the ordinary sale trigger is gone');
    const end = INDEX_TS.indexOf('\nexport const ', start + 1);
    const trigger = INDEX_TS.slice(start, end === -1 ? INDEX_TS.length : end);
    strict_1.default.match(trigger, /recordReferredCustomerReturnInFirestore\(\{/);
    strict_1.default.match(trigger, /merchantId,/);
    strict_1.default.match(trigger, /saleId,/);
    strict_1.default.match(trigger, /customerId,/);
    strict_1.default.match(trigger, /cancellation !== 'CANCELLED'/);
});
/* =================================================== where the routes are hung */
(0, node_test_1.default)('the referral routes are mounted on the routers that authenticate', () => {
    const registration = /registerAffiliateRoutes\(\{([\s\S]*?)\n\}\);/.exec(INDEX_TS);
    strict_1.default.ok(registration, 'registerAffiliateRoutes is no longer called from index.ts');
    strict_1.default.match(registration[1], /merchantRouter,/);
    strict_1.default.match(registration[1], /adminRouter,/);
    // The resolver and the owner predicate are handed in, not reimplemented.
    strict_1.default.match(registration[1], /requireBusiness,/);
    strict_1.default.match(registration[1], /isOwnerOrAdminRequest,/);
});
(0, node_test_1.default)('the admin router refuses anybody who is not an internal admin, before any handler', () => {
    const guard = /const adminRouter = express\.Router\(\);\s*adminRouter\.use\(\(req, res, next\) => \{([\s\S]*?)\n\}\);/
        .exec(INDEX_TS);
    strict_1.default.ok(guard, 'the admin router guard moved or was removed');
    strict_1.default.match(guard[1], /isAdminRequest\(req as AuthedRequest\)/);
    strict_1.default.match(guard[1], /status\(403\)/);
    // And it is that router, gated, which is mounted at /admin.
    strict_1.default.match(INDEX_TS, /app\.use\('\/admin', adminRouter\)/);
});
/** The source of every route registered on one router, with its handler. */
function handlersOn(router) {
    const bodies = [];
    const pattern = new RegExp(`${router}\\.(get|post|put|patch|delete)\\(`, 'g');
    for (const match of ROUTES_TS.matchAll(pattern)) {
        let depth = 0;
        let index = match.index + match[0].length - 1;
        const start = index;
        do {
            const character = ROUTES_TS[index];
            if (character === '(')
                depth++;
            else if (character === ')')
                depth--;
            index++;
        } while (depth > 0 && index < ROUTES_TS.length);
        bodies.push(ROUTES_TS.slice(start, index));
    }
    return bodies;
}
(0, node_test_1.default)('no merchant route takes the business from the request instead of resolving it', () => {
    const merchantHandlers = handlersOn('merchantRouter');
    strict_1.default.ok(merchantHandlers.length > 0, 'no merchant affiliate routes are registered');
    for (const handler of merchantHandlers) {
        // A handler that read a merchant id off the request would serve another
        // business to an authenticated caller. `requireBusiness` is the only source.
        strict_1.default.doesNotMatch(handler, /req\.(body|query|params)\.merchant_?[Ii]d|body\.merchant_?[Ii]d/, `a merchant handler reads a business id from the request:\n${handler.slice(0, 200)}`);
        strict_1.default.match(handler, /requireBusiness\(/, `a merchant handler does not resolve its business:\n${handler.slice(0, 200)}`);
    }
});
(0, node_test_1.default)('an admin route that names a business checks that the business exists', () => {
    const adminHandlers = handlersOn('adminRouter');
    strict_1.default.ok(adminHandlers.length > 0, 'no admin affiliate routes are registered');
    for (const handler of adminHandlers) {
        if (!/req\.params\.merchantId/.test(handler))
            continue;
        // The admin router is already gated on `internal_admin` in index.ts; what
        // is left is that a named business is a real one rather than a typo that
        // creates a link into a business nobody owns.
        strict_1.default.match(handler, /merchantExists\(merchantId\)/, `an admin handler trusts a business id it was handed:\n${handler.slice(0, 200)}`);
    }
});
(0, node_test_1.default)('nothing that decides money is read off the request', () => {
    // The benefit comes off the code, the reward off the business settings.
    for (const field of [
        'benefit_amount',
        'discount_amount',
        'reward_points',
        'reward_value',
        'points_awarded',
        'net_amount',
    ]) {
        strict_1.default.doesNotMatch(ROUTES_TS, new RegExp(`req\\.body\\.${field}|body\\.${field}\\b`), `${field} is taken from the caller`);
    }
    // The commit takes a gross amount and a code, and derives the rest.
    strict_1.default.match(COMMIT_TS, /const benefit = calculateBenefit\(code, input\.grossAmount\)/);
    strict_1.default.match(COMMIT_TS, /loyaltyRuleFrom\(facts\.business\)/);
});
/* ================================================= the customer's own ledger */
(0, node_test_1.default)("an affiliate's reward is never written into a customer's loyalty ledger", () => {
    // The two are different currencies owed to different people. A reward that
    // landed in the customer's ledger would be points the customer could spend
    // and the affiliate never receives, and it would move a balance the loyalty
    // engine believes it owns.
    strict_1.default.ok(!STORE_TS.includes('loyalty_ledger'), 'the reward store writes a ledger entry');
    strict_1.default.ok(!ROUTES_TS.includes('loyalty_ledger'), 'a reward route writes a ledger entry');
    // The only ledger writes in the feature are the customer's POINTS benefit,
    // in the two files that commit a sale, and both are keyed by the sale.
    for (const [name, source] of [
        ['affiliate_sale_commit.ts', COMMIT_TS],
        ['affiliate_offline_sale.ts', OFFLINE_TS],
    ]) {
        const writes = [...source.matchAll(/referralPaths\.ledgerEntry\(\s*([^;]*?)\),?\s*\n/g)];
        strict_1.default.ok(writes.length > 0, `${name} no longer writes the POINTS benefit`);
        for (const write of writes) {
            strict_1.default.match(write[1], /referralBonusLedgerEntryId\(saleId\)/, `${name} writes a ledger entry that is not the referral bonus`);
        }
    }
    strict_1.default.match(COMMIT_TS, /REFERRAL_BONUS_ENTRY_TYPE = 'REFERRAL_BONUS'/);
});
(0, node_test_1.default)('a reward decision goes through the shared state machine, and PAID is terminal', () => {
    // Route-level authorisation is asserted by running the handlers in
    // affiliate_routes.test.ts; what is asserted here is that the handler defers
    // to the shared transition table rather than comparing statuses inline.
    strict_1.default.match(ROUTES_TS, /transitionReward\(/);
    strict_1.default.doesNotMatch(ROUTES_TS, /status === 'PENDING' \?|=== 'APPROVED' \?/, 'a route decides a reward status by hand');
    const contracts = read(FUNCTIONS, 'src', 'affiliate_api_contracts.ts');
    strict_1.default.match(contracts, /export const REWARD_TRANSITIONS: Record<RewardStatus, readonly RewardStatus\[\]>/);
    // Points already handed over are not un-handed by a status change.
    strict_1.default.match(contracts, /PAID: \[\],/);
});
/* ===================================================================== logs */
(0, node_test_1.default)('no affiliate source logs a phone number without masking it', () => {
    for (const [name, source] of [
        ['affiliate_routes.ts', ROUTES_TS],
        ['affiliate_store.ts', STORE_TS],
        ['affiliate_sale_commit.ts', COMMIT_TS],
        ['affiliate_offline_sale.ts', OFFLINE_TS],
        ['affiliate_outbox_firestore.ts', OUTBOX_FS_TS],
        ['affiliate_outbox.ts', OUTBOX_TS],
    ]) {
        for (const line of source.split('\n')) {
            if (!/console\.(log|info|warn|error)/.test(line))
                continue;
            strict_1.default.doesNotMatch(line, /phone(?!_masked|Masked|_hash|Hash)/, `${name} logs a phone: ${line.trim()}`);
        }
    }
});
(0, node_test_1.default)('no affiliate source logs a token or an authorization header', () => {
    for (const source of [
        ROUTES_TS,
        STORE_TS,
        OUTBOX_FS_TS,
        OUTBOX_TS,
        COMMIT_TS,
        OFFLINE_TS,
    ]) {
        for (const line of source.split('\n')) {
            if (!/console\.(log|info|warn|error)/.test(line))
                continue;
            strict_1.default.doesNotMatch(line, /token|authorization|bearer/i, line.trim());
        }
    }
});
