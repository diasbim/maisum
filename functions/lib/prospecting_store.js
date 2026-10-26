"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.TransitionError = exports.SCAN_CAP = exports.prospectingRefs = exports.SUBCOLLECTIONS = exports.COLLECTIONS = void 0;
exports.claimCompany = claimCompany;
exports.matchExistingCustomer = matchExistingCustomer;
exports.createProspectForCompany = createProspectForCompany;
exports.getProspect = getProspect;
exports.getCompany = getCompany;
exports.setProspectStatus = setProspectStatus;
exports.saveScores = saveScores;
exports.updateCompanyListing = updateCompanyListing;
exports.recordOutreachTemplate = recordOutreachTemplate;
exports.readFunnelCounts = readFunnelCounts;
exports.saveContact = saveContact;
exports.listContacts = listContacts;
exports.appendActivity = appendActivity;
exports.listActivities = listActivities;
exports.saveAnalysis = saveAnalysis;
exports.latestAnalysis = latestAnalysis;
exports.readSpend = readSpend;
exports.recordUsage = recordUsage;
exports.listUsage = listUsage;
exports.readSettings = readSettings;
exports.writeSettings = writeSettings;
exports.listProspects = listProspects;
const crypto_1 = require("crypto");
const admin = __importStar(require("firebase-admin"));
/**
 * `FieldValue` and `FieldPath` are imported from the subpath, not reached for
 * as `admin.firestore.FieldValue`.
 *
 * Under this project's module resolution the namespace form is `undefined` at
 * runtime — `admin.firestore()` is callable, but the statics hanging off it
 * are not there — so `FieldValue.increment(...)` throws
 * "Cannot read properties of undefined". It type-checks, which is what makes
 * it dangerous: the failure only appears when the line actually runs.
 *
 * This is the same trap the console hit with `FieldPath` (see the v0.6 note in
 * `docs/web_admin_portal_code_plan.md`, where it broke all five paginated
 * handlers under the emulator), and it was found here the same way: by running
 * the code rather than by compiling it.
 */
const firestore_1 = require("firebase-admin/firestore");
const prospecting_budget_js_1 = require("./prospecting_budget.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_funnel_js_1 = require("./prospecting_funnel.js");
const prospecting_normalization_js_1 = require("./prospecting_normalization.js");
/**
 * Where prospecting data lives, and the two writes that cannot be expressed as
 * a plain set: claiming a company, and consuming budget.
 *
 * Firestore has no unique index, so "this company is stored once" cannot be a
 * constraint — it has to be a property of a document id that two concurrent
 * writers would collide on. That is the device `affiliate_code_lookup` already
 * uses for codes, and `claimCompany` below is the same shape applied to five
 * match keys instead of one.
 *
 * The collections are top-level rather than under `businesses/{merchantId}`,
 * because a prospect belongs to MaisUm and not to any merchant — it is a
 * business that might one day *become* one. Every one of them is closed to
 * clients in `firestore.rules`; the only reader is this API, through the Admin
 * SDK, behind the admin claim.
 */
const db = () => admin.firestore();
exports.COLLECTIONS = {
    companies: 'prospect_companies',
    companyLookup: 'prospect_company_lookup',
    prospects: 'prospects',
    usage: 'prospecting_usage',
    spend: 'prospecting_spend',
    settings: 'prospecting_settings',
    jobs: 'prospecting_jobs',
};
/** Subcollections of one prospect. */
exports.SUBCOLLECTIONS = {
    contacts: 'contacts',
    activities: 'activities',
    analyses: 'analyses',
};
exports.prospectingRefs = {
    company: (companyId) => db().collection(exports.COLLECTIONS.companies).doc(companyId),
    /**
     * The document that makes a company unique.
     *
     * Keyed by the hash of a normalised match key, so "is this business already
     * stored?" is a `get` on a known id rather than a query — which means it can
     * be read inside a transaction, and a query cannot.
     */
    companyLookup: (key) => db().collection(exports.COLLECTIONS.companyLookup).doc((0, prospecting_normalization_js_1.matchKeyDocId)(key)),
    prospect: (prospectId) => db().collection(exports.COLLECTIONS.prospects).doc(prospectId),
    contacts: (prospectId) => db().collection(exports.COLLECTIONS.prospects).doc(prospectId).collection(exports.SUBCOLLECTIONS.contacts),
    activities: (prospectId) => db().collection(exports.COLLECTIONS.prospects).doc(prospectId).collection(exports.SUBCOLLECTIONS.activities),
    analyses: (prospectId) => db().collection(exports.COLLECTIONS.prospects).doc(prospectId).collection(exports.SUBCOLLECTIONS.analyses),
    usage: (usageId) => db().collection(exports.COLLECTIONS.usage).doc(usageId),
    /** One counter document per period, so a budget check is one read. */
    spend: (periodKey) => db().collection(exports.COLLECTIONS.spend).doc(periodKey),
    settings: () => db().collection(exports.COLLECTIONS.settings).doc('default'),
    job: (jobId) => db().collection(exports.COLLECTIONS.jobs).doc(jobId),
};
/** How many documents a scan pulls before it answers "truncated" instead. */
exports.SCAN_CAP = 2000;
/**
 * Stores a company, or returns the one it duplicates.
 *
 * The whole transaction is: read every lookup document this company would
 * claim, and if any already points at a company, that is the company. The
 * order of `buildMatchKeys` is the order of confidence, so the first hit wins
 * and the rest are backfilled to point at the same id — a company discovered
 * by domain on Monday and by phone on Tuesday ends up with both keys claimed,
 * and the Wednesday discovery by either one finds it.
 *
 * Two writers racing on the same business both read "unclaimed", both write,
 * and Firestore fails one of them — which the caller retries, and the retry
 * reads the winner's claim. That is the property a query-based check cannot
 * have, and it is why the keys are document ids rather than fields.
 *
 * The stored `value` is read back and compared rather than trusted, so a hash
 * collision surfaces as a missed match rather than as two businesses silently
 * merged into one record.
 */
async function claimCompany(input) {
    const keys = (0, prospecting_normalization_js_1.buildMatchKeys)(toIdentity(input.company), input.phoneCountryCode);
    if (keys.length === 0) {
        // Nothing to match on at all. Stored without claims rather than refused:
        // the qualifier has already established it has a name, and a company that
        // can never be matched is still a company somebody can be shown.
        const companyId = (0, crypto_1.randomUUID)();
        await exports.prospectingRefs.company(companyId).set(toCompanyDocument(input.company, companyId, input.now));
        return { companyId, created: true, matchedOn: null };
    }
    return db().runTransaction(async (transaction) => {
        const snapshots = await Promise.all(keys.map((key) => transaction.get(exports.prospectingRefs.companyLookup(key))));
        let existingId = null;
        let matchedOn = null;
        for (let index = 0; index < snapshots.length; index++) {
            const snapshot = snapshots[index];
            if (!snapshot.exists)
                continue;
            const data = (snapshot.data() ?? {});
            // The value is compared, not assumed: a digest collision must show up as
            // a missed match, never as two businesses merged into one record.
            if (data.value !== keys[index].value)
                continue;
            const companyId = typeof data.company_id === 'string' ? data.company_id : '';
            if (companyId === '')
                continue;
            existingId = companyId;
            matchedOn = keys[index];
            break;
        }
        const companyId = existingId ?? (0, crypto_1.randomUUID)();
        // Every key this company carries now points at it, including the ones a
        // previous discovery did not know about.
        for (const key of keys) {
            transaction.set(exports.prospectingRefs.companyLookup(key), {
                kind: key.kind,
                value: key.value,
                company_id: companyId,
                created_at: input.now,
            }, { merge: true });
        }
        if (existingId === null) {
            transaction.set(exports.prospectingRefs.company(companyId), toCompanyDocument(input.company, companyId, input.now));
        }
        else {
            // A second sighting fills gaps; it never overwrites what is already
            // known with a null, which is what a plain merge of the new record would
            // do to a company whose phone this provider did not return.
            transaction.set(exports.prospectingRefs.company(companyId), { ...definedFields(input.company), updated_at: input.now }, { merge: true });
        }
        return { companyId, created: existingId === null, matchedOn };
    });
}
function toIdentity(company) {
    return {
        name: company.name,
        city: company.city,
        domain: company.domain,
        website: company.website,
        phone: company.phone,
        whatsapp: company.whatsapp,
        providerOrgId: company.provider_org_id,
        provider: company.source,
        linkedinUrl: company.linkedin_url,
        instagramUrl: company.instagram_url,
        facebookUrl: company.facebook_url,
    };
}
function toCompanyDocument(company, companyId, now) {
    return { ...company, id: companyId, created_at: now, updated_at: now };
}
/** Only the fields this sighting actually filled, so a merge adds nothing null. */
function definedFields(company) {
    const out = {};
    for (const [field, value] of Object.entries(company)) {
        if (value !== null && value !== undefined)
            out[field] = value;
    }
    return out;
}
/**
 * Whether this business is already a MaisUm merchant.
 *
 * Criterion 10, and the reason it is not a single comparison: the `businesses`
 * documents store `merchant_name` and `phone` and nothing else that identifies
 * a company. There is no domain, no email and no city on them, so three of the
 * five match keys have nothing on the MaisUm side to match against.
 *
 * What that leaves is two signals of very different strength, and they are
 * answered differently on purpose:
 *
 *   A **phone** match is the same normalised E.164 number. That is the same
 *   business, and the prospect becomes `EXISTING_CUSTOMER` without anyone
 *   being asked.
 *
 *   A **name** match is an exact fold of the whole trading name, with no city
 *   to disambiguate it. Two unrelated "Barbearia Central" is a thing that
 *   happens. So it is recorded on the prospect as `suspected_merchant_id`,
 *   shown at the top of the lead detail with the merchant it resembles, and
 *   left for a person to confirm — because `EXISTING_CUSTOMER` is terminal and
 *   terminal is irreversible, and a name collision must not be able to kill a
 *   real lead permanently.
 *
 * The scan is capped and reads only the fields it needs. At pilot scale this
 * is a few hundred documents; past that it wants a lookup collection of its
 * own, written by the same trigger that creates a business.
 */
async function matchExistingCustomer(input) {
    const phone = (0, prospecting_normalization_js_1.normalizePhone)(input.company.phone, input.phoneCountryCode);
    const whatsapp = (0, prospecting_normalization_js_1.normalizePhone)(input.company.whatsapp, input.phoneCountryCode);
    const name = (0, prospecting_normalization_js_1.normalizeCompanyName)(input.company.name);
    const snapshot = await db().collection('businesses').limit(exports.SCAN_CAP).get();
    let nameMatch = null;
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const merchantName = typeof data.merchant_name === 'string'
            ? data.merchant_name
            : typeof data.name === 'string'
                ? data.name
                : null;
        const merchantPhone = (0, prospecting_normalization_js_1.normalizePhone)(data.phone, input.phoneCountryCode);
        if (merchantPhone !== null && (merchantPhone === phone || merchantPhone === whatsapp)) {
            return { kind: 'PHONE', merchantId: doc.id, merchantName };
        }
        // Kept rather than returned: a phone match anywhere in the scan outranks a
        // name match found earlier in it.
        if (nameMatch === null &&
            name !== '' &&
            merchantName !== null &&
            (0, prospecting_normalization_js_1.normalizeCompanyName)(merchantName) === name) {
            nameMatch = { kind: 'NAME', merchantId: doc.id, merchantName };
        }
    }
    return nameMatch ?? { kind: 'NONE' };
}
/**
 * Creates the prospect for a company, or returns the one that exists.
 *
 * Keyed by the company id rather than by a random one, which makes "one live
 * prospect per company" a property of the key. Re-running the same search next
 * week finds the company, finds its prospect, and adds nothing — which is what
 * makes discovery idempotent and safe to retry.
 */
async function createProspectForCompany(input) {
    const prospectId = input.companyId;
    const ref = exports.prospectingRefs.prospect(prospectId);
    return db().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (snapshot.exists) {
            return { prospect: snapshot.data(), created: false };
        }
        const prospect = {
            id: prospectId,
            company_id: input.companyId,
            status: input.status,
            source: input.source,
            source_reference: input.sourceReference,
            lead_score: null,
            business_fit_score: null,
            digital_presence_score: null,
            retention_potential_score: null,
            commercial_opportunity_score: null,
            band: null,
            scoring_version: null,
            furthest_stage: (0, prospecting_funnel_js_1.raiseStage)(null, input.status),
            outreach_template_id: null,
            ai_summary: null,
            ai_reasoning: null,
            recommended_pitch: null,
            recommended_channel: null,
            enrichment_status: 'NOT_STARTED',
            last_enriched_at: null,
            spend_usd: 0,
            decision_maker_count: 0,
            has_reachable_contact: false,
            suspected_merchant_id: input.suspectedMerchantId ?? null,
            disqualify_reason: input.disqualifyReason ?? null,
            status_source: 'system',
            status_changed_at: input.now,
            last_activity_at: input.now,
            created_at: input.now,
            updated_at: input.now,
        };
        transaction.set(ref, prospect);
        return { prospect, created: true };
    });
}
async function getProspect(prospectId) {
    const snapshot = await exports.prospectingRefs.prospect(prospectId).get();
    return snapshot.exists ? snapshot.data() : null;
}
async function getCompany(companyId) {
    const snapshot = await exports.prospectingRefs.company(companyId).get();
    return snapshot.exists ? snapshot.data() : null;
}
class TransitionError extends Error {
    constructor(from, to) {
        super(`cannot move a prospect from ${from} to ${to}`);
        this.name = 'TransitionError';
        this.from = from;
        this.to = to;
    }
}
exports.TransitionError = TransitionError;
/**
 * Moves a prospect, in a transaction, through the one validator.
 *
 * The check is inside the transaction and reads the stored status rather than
 * one the caller passed in. Otherwise two operators looking at the same lead
 * could both see `CONTACTED`, both be told the move is legal, and one of them
 * write a transition from a status that had already changed underneath them.
 */
async function setProspectStatus(input) {
    const ref = exports.prospectingRefs.prospect(input.prospectId);
    const updated = await db().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw new Error('prospect not found');
        const prospect = snapshot.data();
        const from = (0, prospecting_contracts_js_1.isProspectStatus)(prospect.status) ? prospect.status : 'RAW';
        if (!(0, prospecting_contracts_js_1.canTransition)(from, input.to))
            throw new TransitionError(from, input.to);
        const patch = {
            status: input.to,
            status_source: input.actor,
            status_changed_at: input.now,
            last_activity_at: input.now,
            updated_at: input.now,
            /**
             * The high-water mark, raised here and nowhere else.
             *
             * In the same transaction as the status so the two cannot disagree, and
             * never lowered: a lead that reached `DEMO` and then went to `LOST` has
             * still been through every stage up to `DEMO`, and the funnel is only
             * true if it says so. Counting a funnel from `status` alone reports zero
             * contacted leads the moment they all convert.
             */
            furthest_stage: (0, prospecting_funnel_js_1.raiseStage)(prospect.furthest_stage ?? null, input.to),
            ...(input.reason === undefined ? {} : { disqualify_reason: input.reason }),
        };
        transaction.set(ref, patch, { merge: true });
        transaction.set(exports.prospectingRefs.activities(input.prospectId).doc((0, crypto_1.randomUUID)()), {
            id: (0, crypto_1.randomUUID)(),
            prospect_id: input.prospectId,
            type: 'STATUS_CHANGED',
            channel: null,
            description: `${from} → ${input.to}`,
            metadata: { from, to: input.to, reason: input.reason ?? null },
            created_at: input.now,
            created_by: input.actor,
        });
        return { ...prospect, ...patch };
    });
    return updated;
}
/** Applies a scoring result to the prospect. Never moves the status by itself. */
async function saveScores(input) {
    await exports.prospectingRefs.prospect(input.prospectId).set({
        lead_score: input.total,
        business_fit_score: input.businessFit,
        digital_presence_score: input.digitalPresence,
        retention_potential_score: input.retentionPotential,
        commercial_opportunity_score: input.commercialOpportunity,
        band: input.band,
        scoring_version: prospecting_config_js_1.SCORING_VERSION,
        updated_at: input.now,
    }, { merge: true });
}
/**
 * Writes back the fields the dear half of a listing answered.
 *
 * Narrow by design: five fields, never the whole record. A detail response is
 * a partial view of a place — it carries no name and no address — and merging
 * it wholesale would blank what the search found.
 *
 * The two kinds of field are treated differently, and the difference is the
 * three-valued discipline again. A null phone or website means the response
 * did not carry one, which must not erase a number discovered some other way,
 * so those are only written when present. `hasOpeningHours` and `hasPhotos`
 * are written even when false, because the field mask asked for them: false
 * there is an answer, and leaving the previous null in place would keep
 * claiming nobody looked.
 */
async function updateCompanyListing(input) {
    const patch = {
        has_opening_hours: input.hasOpeningHours,
        has_photos: input.hasPhotos,
        updated_at: input.now,
    };
    if (input.phone !== null)
        patch.phone = input.phone;
    if (input.website !== null)
        patch.website = input.website;
    await exports.prospectingRefs.company(input.companyId).set(patch, { merge: true });
}
/**
 * Records which template a lead was actually written to with. Once.
 *
 * A transaction rather than a merge, because "set only if unset" is a
 * read-then-write and two operators sending from two tabs would otherwise
 * race — with the loser silently reassigning an A/B arm. Returns what the
 * lead ended up attributed to, which is not always what was passed.
 */
async function recordOutreachTemplate(input) {
    const ref = exports.prospectingRefs.prospect(input.prospectId);
    return db().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists)
            throw new Error('prospect not found');
        const existing = snapshot.data().outreach_template_id;
        if (typeof existing === 'string' && existing.trim() !== '')
            return existing;
        transaction.set(ref, { outreach_template_id: input.templateId, updated_at: input.now }, { merge: true });
        return input.templateId;
    });
}
/**
 * The funnel's raw counts.
 *
 * Aggregation queries rather than reading the documents: a count over ten
 * thousand prospects costs a fraction of a read here and ten thousand reads
 * the other way, and the funnel is a screen somebody refreshes.
 *
 * Runs `PROSPECT_PIPELINE.length` counts on `furthest_stage` and one per
 * terminal status, all in parallel. The arithmetic — the accumulating, the
 * rates — is `buildFunnel`'s, which is pure and tested without an emulator.
 */
async function readFunnelCounts(input) {
    const prospects = db().collection(exports.COLLECTIONS.prospects);
    const countOf = async (query) => (await query.count().get()).data().count;
    const stages = await Promise.all(prospecting_contracts_js_1.PROSPECT_PIPELINE.map(async (_status, stage) => ({
        stage,
        count: await countOf(prospects.where('furthest_stage', '==', stage)),
    })));
    const exits = await Promise.all(prospecting_contracts_js_1.PROSPECT_TERMINAL.map(async (status) => ({
        status,
        count: await countOf(prospects.where('status', '==', status)),
    })));
    // Only the two bands the decision rule compares. Counting all four would be
    // four more round trips for a number nothing reads.
    const bands = await Promise.all(['PRIORITY', 'NURTURE'].map(async (band) => ({
        band,
        total: await countOf(prospects.where('band', '==', band)),
        customers: await countOf(prospects.where('band', '==', band).where('status', '==', 'CUSTOMER')),
    })));
    /**
     * Sent and replied, per template.
     *
     * `replied` is `furthest_stage >= REPLIED`, not `status == 'REPLIED'` — a
     * lead that replied and then became a customer replied. Counting current
     * status here would make the best template look like the worst.
     *
     * Only the templates the caller names are counted: Firestore cannot group
     * by a field, so each is two queries, and asking about templates nobody has
     * configured would be round trips for guaranteed zeros.
     */
    const repliedStage = prospecting_funnel_js_1.STAGE_OF.REPLIED ?? 6;
    const templates = await Promise.all((input?.templateIds ?? []).map(async (templateId) => {
        const scoped = prospects.where('outreach_template_id', '==', templateId);
        return {
            templateId,
            sent: await countOf(scoped),
            replied: await countOf(scoped.where('furthest_stage', '>=', repliedStage)),
        };
    }));
    return {
        reachedByStage: Object.fromEntries(stages.map((entry) => [entry.stage, entry.count])),
        byTemplate: Object.fromEntries(templates.map((entry) => [
            entry.templateId,
            { sent: entry.sent, replied: entry.replied },
        ])),
        exitsByStatus: Object.fromEntries(exits.map((entry) => [entry.status, entry.count])),
        byBand: Object.fromEntries(bands.map((entry) => [
            entry.band,
            { total: entry.total, customers: entry.customers },
        ])),
    };
}
/* ---------------------------------------------------------------- contacts */
/**
 * Stores a contact, keyed by the provider's person id where there is one.
 *
 * Without the key, finding decision makers twice would store the same person
 * twice, and the "decision maker identified" scoring point would be earned by
 * a duplicate.
 */
async function saveContact(input) {
    const contactId = input.person.provider_person_id ??
        `local_${(0, prospecting_normalization_js_1.matchKeyDocId)({
            kind: 'NAME_CITY',
            value: `${input.person.first_name ?? ''}|${input.person.job_title ?? ''}`,
        })}`;
    const contact = {
        ...input.person,
        id: contactId,
        prospect_id: input.prospectId,
        is_decision_maker: input.isDecisionMaker,
        created_at: input.now,
        updated_at: input.now,
    };
    await exports.prospectingRefs.contacts(input.prospectId).doc(contactId).set(contact, { merge: true });
    return contact;
}
async function listContacts(prospectId) {
    const snapshot = await exports.prospectingRefs.contacts(prospectId).limit(50).get();
    return snapshot.docs.map((doc) => doc.data());
}
/* -------------------------------------------------------------- activities */
async function appendActivity(input) {
    const id = (0, crypto_1.randomUUID)();
    const activity = {
        id,
        prospect_id: input.prospectId,
        type: input.type,
        channel: input.channel ?? null,
        description: input.description,
        metadata: input.metadata ?? {},
        created_at: input.now,
        created_by: input.actor,
    };
    await exports.prospectingRefs.activities(input.prospectId).doc(id).set(activity);
    await exports.prospectingRefs
        .prospect(input.prospectId)
        .set({ last_activity_at: input.now, updated_at: input.now }, { merge: true });
    return activity;
}
async function listActivities(prospectId, limit = 50) {
    const snapshot = await exports.prospectingRefs
        .activities(prospectId)
        .orderBy('created_at', 'desc')
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) => doc.data());
}
async function saveAnalysis(input) {
    await exports.prospectingRefs.analyses(input.prospect_id).doc(input.id).set(input);
}
/** The newest analysis, which is the only one the cache consults. */
async function latestAnalysis(prospectId) {
    const snapshot = await exports.prospectingRefs
        .analyses(prospectId)
        .orderBy('created_at', 'desc')
        .limit(1)
        .get();
    return snapshot.empty ? null : snapshot.docs[0].data();
}
/**
 * What has been spent, in two reads rather than a scan of the usage log.
 *
 * The counters are the authority for the budget decision; the usage rows are
 * the authority for what was actually bought. They are written in one
 * transaction, so a counter cannot advance without a row explaining it.
 */
async function readSpend(input) {
    const [month, day, prospect] = await Promise.all([
        exports.prospectingRefs.spend((0, prospecting_budget_js_1.monthKey)(input.now)).get(),
        exports.prospectingRefs.spend((0, prospecting_budget_js_1.dayKey)(input.now)).get(),
        input.prospectId === null
            ? Promise.resolve(null)
            : exports.prospectingRefs.prospect(input.prospectId).get(),
    ]);
    const total = (snapshot) => {
        if (snapshot === null || !snapshot.exists)
            return 0;
        const value = (snapshot.data() ?? {}).total_usd;
        return typeof value === 'number' && Number.isFinite(value) ? value : 0;
    };
    const leadSpend = prospect !== null && prospect.exists
        ? (prospect.data() ?? {}).spend_usd ?? 0
        : 0;
    return {
        monthUsd: total(month),
        dayUsd: total(day),
        leadUsd: typeof leadSpend === 'number' && Number.isFinite(leadSpend) ? leadSpend : 0,
    };
}
/**
 * Writes the usage row and advances every counter it belongs to, atomically.
 *
 * A failed call is recorded exactly like a successful one, because providers
 * charge for calls that return nothing and a log that only recorded successes
 * would understate the month by precisely the amount nobody expected to be
 * spending.
 */
async function recordUsage(input) {
    const id = (0, crypto_1.randomUUID)();
    const charged = input.actualCostUsd ?? input.estimatedCostUsd;
    const row = {
        id,
        provider: input.provider,
        operation: input.operation,
        prospect_id: input.prospectId,
        estimated_cost: (0, prospecting_budget_js_1.round)(input.estimatedCostUsd),
        actual_cost: input.actualCostUsd === null ? null : (0, prospecting_budget_js_1.round)(input.actualCostUsd),
        credits_used: input.creditsUsed,
        success: input.success,
        error_code: input.errorCode,
        correlation_id: input.correlationId,
        month_key: (0, prospecting_budget_js_1.monthKey)(input.now),
        day_key: (0, prospecting_budget_js_1.dayKey)(input.now),
        created_at: input.now,
    };
    const batch = db().batch();
    batch.set(exports.prospectingRefs.usage(id), row);
    batch.set(exports.prospectingRefs.spend(row.month_key), {
        period: row.month_key,
        kind: 'month',
        total_usd: firestore_1.FieldValue.increment((0, prospecting_budget_js_1.round)(charged)),
        calls: firestore_1.FieldValue.increment(1),
        updated_at: input.now,
    }, { merge: true });
    batch.set(exports.prospectingRefs.spend(row.day_key), {
        period: row.day_key,
        kind: 'day',
        total_usd: firestore_1.FieldValue.increment((0, prospecting_budget_js_1.round)(charged)),
        calls: firestore_1.FieldValue.increment(1),
        updated_at: input.now,
    }, { merge: true });
    if (input.prospectId !== null) {
        batch.set(exports.prospectingRefs.prospect(input.prospectId), {
            spend_usd: firestore_1.FieldValue.increment((0, prospecting_budget_js_1.round)(charged)),
            updated_at: input.now,
        }, { merge: true });
    }
    await batch.commit();
    return row;
}
/** The usage log for a period, newest first. */
async function listUsage(input) {
    let query = db()
        .collection(exports.COLLECTIONS.usage)
        .orderBy('created_at', 'desc');
    if (input.monthKey !== undefined) {
        query = db()
            .collection(exports.COLLECTIONS.usage)
            .where('month_key', '==', input.monthKey)
            .orderBy('created_at', 'desc');
    }
    const snapshot = await query.offset(input.offset).limit(input.limit + 1).get();
    const docs = snapshot.docs.slice(0, input.limit);
    return {
        rows: docs.map((doc) => doc.data()),
        hasMore: snapshot.size > input.limit,
    };
}
/* ---------------------------------------------------------------- settings */
/**
 * The stored settings, over the defaults.
 *
 * A field absent from the document takes its default, so adding one to
 * `DEFAULT_SETTINGS` needs no migration and an operator who has never opened
 * the settings screen is governed by the same numbers as the code.
 */
async function readSettings() {
    const snapshot = await exports.prospectingRefs.settings().get();
    if (!snapshot.exists)
        return prospecting_config_js_1.DEFAULT_SETTINGS;
    const stored = (snapshot.data() ?? {});
    return {
        ...prospecting_config_js_1.DEFAULT_SETTINGS,
        ...stored,
        geography: { ...prospecting_config_js_1.DEFAULT_SETTINGS.geography, ...(stored.geography ?? {}) },
        scoring: { ...prospecting_config_js_1.DEFAULT_SETTINGS.scoring, ...(stored.scoring ?? {}) },
    };
}
async function writeSettings(input) {
    await exports.prospectingRefs.settings().set({ ...input.patch, updated_at: input.now, updated_by: input.actor }, { merge: true });
    return readSettings();
}
/**
 * A page of leads.
 *
 * One equality filter goes to Firestore — the most selective the caller gave,
 * in a fixed priority — and the rest are applied in memory over a capped scan.
 * The alternative is a composite index for every combination of seven filters
 * and four sorts, which is a few hundred indexes for a screen that will be
 * used by four people.
 *
 * The cap is reported rather than hidden: past it the page would be wrong, and
 * a console that quietly showed the first two thousand of a larger set is how
 * an operator concludes a lead does not exist.
 */
async function listProspects(query) {
    const sortField = query.sort === 'newest'
        ? 'created_at'
        : query.sort === 'enriched'
            ? 'last_enriched_at'
            : query.sort === 'contacted'
                ? 'last_activity_at'
                : 'lead_score';
    let firestoreQuery = db().collection(exports.COLLECTIONS.prospects);
    // Priority order: the most selective filter an operator is likely to set.
    if (query.status !== undefined && query.status !== '') {
        firestoreQuery = firestoreQuery.where('status', '==', query.status);
    }
    else if (query.band !== undefined && query.band !== '') {
        firestoreQuery = firestoreQuery.where('band', '==', query.band);
    }
    else if (query.enrichmentStatus !== undefined && query.enrichmentStatus !== '') {
        firestoreQuery = firestoreQuery.where('enrichment_status', '==', query.enrichmentStatus);
    }
    else if (query.source !== undefined && query.source !== '') {
        firestoreQuery = firestoreQuery.where('source', '==', query.source);
    }
    const snapshot = await firestoreQuery
        .orderBy(sortField, 'desc')
        .limit(exports.SCAN_CAP + 1)
        .get();
    const truncated = snapshot.size > exports.SCAN_CAP;
    const docs = truncated ? snapshot.docs.slice(0, exports.SCAN_CAP) : snapshot.docs;
    const prospects = docs.map((doc) => doc.data());
    // The company is needed for the name, the industry and the city, all of
    // which the list shows and two of which it filters on.
    const companies = await loadCompanies(prospects.map((prospect) => prospect.company_id));
    const rows = prospects
        .map((prospect) => ({
        prospect,
        company: companies.get(prospect.company_id) ?? null,
    }))
        .filter((row) => matchesInMemory(row, query));
    const page = rows.slice(query.offset, query.offset + query.limit);
    return {
        rows: page,
        total: rows.length,
        hasMore: query.offset + page.length < rows.length,
        truncated,
    };
}
function matchesInMemory(row, query) {
    const { prospect, company } = row;
    if (query.status && prospect.status !== query.status)
        return false;
    if (query.band && prospect.band !== query.band)
        return false;
    if (query.source && prospect.source !== query.source)
        return false;
    if (query.enrichmentStatus && prospect.enrichment_status !== query.enrichmentStatus) {
        return false;
    }
    if (query.industry && (company?.industry ?? null) !== query.industry)
        return false;
    if (query.city && (0, prospecting_normalization_js_1.normalizeCompanyName)(company?.city ?? '') !== (0, prospecting_normalization_js_1.normalizeCompanyName)(query.city)) {
        return false;
    }
    if (query.contact === 'with' && prospect.decision_maker_count === 0)
        return false;
    if (query.contact === 'without' && prospect.decision_maker_count > 0)
        return false;
    if (query.search !== undefined && query.search.trim() !== '') {
        const needle = (0, prospecting_normalization_js_1.normalizeCompanyName)(query.search);
        const haystack = (0, prospecting_normalization_js_1.normalizeCompanyName)(company?.name ?? '');
        if (needle !== '' && !haystack.includes(needle))
            return false;
    }
    return true;
}
/** Firestore takes at most thirty ids per `in`, so the reads are chunked. */
async function loadCompanies(ids) {
    const unique = [...new Set(ids)].filter((id) => id !== '');
    const found = new Map();
    for (let index = 0; index < unique.length; index += 30) {
        const chunk = unique.slice(index, index + 30);
        const snapshot = await db()
            .collection(exports.COLLECTIONS.companies)
            .where(firestore_1.FieldPath.documentId(), 'in', chunk)
            .get();
        for (const doc of snapshot.docs) {
            found.set(doc.id, doc.data());
        }
    }
    return found;
}
