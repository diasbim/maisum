import { randomUUID } from 'crypto';

import * as admin from 'firebase-admin';
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
import { FieldPath, FieldValue } from 'firebase-admin/firestore';

import {
  dayKey,
  monthKey,
  round,
  type EnrichmentUsage,
} from './prospecting_budget.js';
import {
  DEFAULT_SETTINGS,
  SCORING_VERSION,
  type ProspectingSettings,
} from './prospecting_config.js';
import {
  canTransition,
  isProspectStatus,
  PROSPECT_PIPELINE,
  PROSPECT_TERMINAL,
  type ActivityType,
  type EnrichmentStatus,
  type ProspectSource,
  type ProspectStatus,
  type ProviderOperation,
} from './prospecting_contracts.js';
import { raiseStage, STAGE_OF } from './prospecting_funnel.js';
import {
  buildMatchKeys,
  matchKeyDocId,
  normalizeCompanyName,
  normalizePhone,
  type CompanyIdentity,
  type MatchKey,
} from './prospecting_normalization.js';
import type { CompanyRecord, PersonRecord } from './prospecting_providers.js';

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

export const COLLECTIONS = {
  companies: 'prospect_companies',
  companyLookup: 'prospect_company_lookup',
  prospects: 'prospects',
  usage: 'prospecting_usage',
  spend: 'prospecting_spend',
  settings: 'prospecting_settings',
  jobs: 'prospecting_jobs',
} as const;

/** Subcollections of one prospect. */
export const SUBCOLLECTIONS = {
  contacts: 'contacts',
  activities: 'activities',
  analyses: 'analyses',
} as const;

export const prospectingRefs = {
  company: (companyId: string) => db().collection(COLLECTIONS.companies).doc(companyId),

  /**
   * The document that makes a company unique.
   *
   * Keyed by the hash of a normalised match key, so "is this business already
   * stored?" is a `get` on a known id rather than a query — which means it can
   * be read inside a transaction, and a query cannot.
   */
  companyLookup: (key: MatchKey) =>
    db().collection(COLLECTIONS.companyLookup).doc(matchKeyDocId(key)),

  prospect: (prospectId: string) => db().collection(COLLECTIONS.prospects).doc(prospectId),

  contacts: (prospectId: string) =>
    db().collection(COLLECTIONS.prospects).doc(prospectId).collection(SUBCOLLECTIONS.contacts),

  activities: (prospectId: string) =>
    db().collection(COLLECTIONS.prospects).doc(prospectId).collection(SUBCOLLECTIONS.activities),

  analyses: (prospectId: string) =>
    db().collection(COLLECTIONS.prospects).doc(prospectId).collection(SUBCOLLECTIONS.analyses),

  usage: (usageId: string) => db().collection(COLLECTIONS.usage).doc(usageId),

  /** One counter document per period, so a budget check is one read. */
  spend: (periodKey: string) => db().collection(COLLECTIONS.spend).doc(periodKey),

  settings: () => db().collection(COLLECTIONS.settings).doc('default'),

  job: (jobId: string) => db().collection(COLLECTIONS.jobs).doc(jobId),
};

/** How many documents a scan pulls before it answers "truncated" instead. */
export const SCAN_CAP = 2000;

/* ------------------------------------------------------------ the records */

export type StoredCompany = CompanyRecord & {
  id: string;
  created_at: number;
  updated_at: number;
};

export type StoredProspect = {
  id: string;
  company_id: string;
  status: ProspectStatus;
  source: ProspectSource;
  source_reference: string | null;
  lead_score: number | null;
  business_fit_score: number | null;
  digital_presence_score: number | null;
  retention_potential_score: number | null;
  commercial_opportunity_score: number | null;
  band: string | null;
  /**
   * The weighting the score above was produced by. Null for anything scored
   * before versioning existed, which is read as version 1.
   */
  scoring_version: number | null;
  /**
   * The furthest pipeline stage this lead has ever reached. Never lowered.
   * Null for prospects written before the funnel existed, read as stage 0.
   */
  furthest_stage: number | null;
  /**
   * The template of the first message actually sent to this lead.
   *
   * Written on send, not on generate: an operator may draft three versions and
   * send one, and only the one that went out can have earned a reply. Set once
   * and never overwritten, so a follow-up in a different template cannot take
   * credit for a reply the first message won.
   */
  outreach_template_id: string | null;
  ai_summary: string | null;
  ai_reasoning: string | null;
  recommended_pitch: string | null;
  recommended_channel: string | null;
  enrichment_status: EnrichmentStatus;
  last_enriched_at: number | null;
  /** What this one lead has cost so far, so the per-lead cap is one read. */
  spend_usd: number;
  decision_maker_count: number;
  has_reachable_contact: boolean;
  /**
   * A business whose name matches an existing MaisUm merchant, but only by
   * name. Not terminal on its own — see `matchExistingCustomer`.
   */
  suspected_merchant_id: string | null;
  /** Why the lead was disqualified, when it was. */
  disqualify_reason: string | null;
  status_source: string | null;
  status_changed_at: number | null;
  last_activity_at: number | null;
  created_at: number;
  updated_at: number;
};

export type StoredContact = PersonRecord & {
  id: string;
  prospect_id: string;
  is_decision_maker: boolean;
  created_at: number;
  updated_at: number;
};

export type StoredActivity = {
  id: string;
  prospect_id: string;
  type: ActivityType;
  channel: string | null;
  description: string;
  metadata: Record<string, unknown>;
  created_at: number;
  created_by: string | null;
};

/* --------------------------------------------------- claiming a company */

export type ClaimOutcome = {
  companyId: string;
  /** False when an existing company was matched instead of a new one written. */
  created: boolean;
  /** Which key matched, for the activity log and for the dedup test. */
  matchedOn: MatchKey | null;
};

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
export async function claimCompany(input: {
  company: CompanyRecord;
  phoneCountryCode: string;
  now: number;
}): Promise<ClaimOutcome> {
  const keys = buildMatchKeys(toIdentity(input.company), input.phoneCountryCode);

  if (keys.length === 0) {
    // Nothing to match on at all. Stored without claims rather than refused:
    // the qualifier has already established it has a name, and a company that
    // can never be matched is still a company somebody can be shown.
    const companyId = randomUUID();
    await prospectingRefs.company(companyId).set(
      toCompanyDocument(input.company, companyId, input.now),
    );
    return { companyId, created: true, matchedOn: null };
  }

  return db().runTransaction(async (transaction) => {
    const snapshots = await Promise.all(
      keys.map((key) => transaction.get(prospectingRefs.companyLookup(key))),
    );

    let existingId: string | null = null;
    let matchedOn: MatchKey | null = null;

    for (let index = 0; index < snapshots.length; index++) {
      const snapshot = snapshots[index];
      if (!snapshot.exists) continue;

      const data = (snapshot.data() ?? {}) as Record<string, unknown>;
      // The value is compared, not assumed: a digest collision must show up as
      // a missed match, never as two businesses merged into one record.
      if (data.value !== keys[index].value) continue;

      const companyId = typeof data.company_id === 'string' ? data.company_id : '';
      if (companyId === '') continue;

      existingId = companyId;
      matchedOn = keys[index];
      break;
    }

    const companyId = existingId ?? randomUUID();

    // Every key this company carries now points at it, including the ones a
    // previous discovery did not know about.
    for (const key of keys) {
      transaction.set(
        prospectingRefs.companyLookup(key),
        {
          kind: key.kind,
          value: key.value,
          company_id: companyId,
          created_at: input.now,
        },
        { merge: true },
      );
    }

    if (existingId === null) {
      transaction.set(
        prospectingRefs.company(companyId),
        toCompanyDocument(input.company, companyId, input.now),
      );
    } else {
      // A second sighting fills gaps; it never overwrites what is already
      // known with a null, which is what a plain merge of the new record would
      // do to a company whose phone this provider did not return.
      transaction.set(
        prospectingRefs.company(companyId),
        { ...definedFields(input.company), updated_at: input.now },
        { merge: true },
      );
    }

    return { companyId, created: existingId === null, matchedOn };
  });
}

function toIdentity(company: CompanyRecord): CompanyIdentity {
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

function toCompanyDocument(
  company: CompanyRecord,
  companyId: string,
  now: number,
): StoredCompany {
  return { ...company, id: companyId, created_at: now, updated_at: now };
}

/** Only the fields this sighting actually filled, so a merge adds nothing null. */
function definedFields(company: CompanyRecord): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [field, value] of Object.entries(company)) {
    if (value !== null && value !== undefined) out[field] = value;
  }
  return out;
}

/* ----------------------------------------------------- existing customers */

export type CustomerMatch =
  | { kind: 'NONE' }
  | { kind: 'PHONE'; merchantId: string; merchantName: string | null }
  | { kind: 'NAME'; merchantId: string; merchantName: string | null };

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
export async function matchExistingCustomer(input: {
  company: CompanyRecord;
  phoneCountryCode: string;
}): Promise<CustomerMatch> {
  const phone = normalizePhone(input.company.phone, input.phoneCountryCode);
  const whatsapp = normalizePhone(input.company.whatsapp, input.phoneCountryCode);
  const name = normalizeCompanyName(input.company.name);

  const snapshot = await db().collection('businesses').limit(SCAN_CAP).get();

  let nameMatch: CustomerMatch | null = null;

  for (const doc of snapshot.docs) {
    const data = doc.data() as Record<string, unknown>;
    const merchantName =
      typeof data.merchant_name === 'string'
        ? data.merchant_name
        : typeof data.name === 'string'
          ? data.name
          : null;

    const merchantPhone = normalizePhone(data.phone, input.phoneCountryCode);
    if (merchantPhone !== null && (merchantPhone === phone || merchantPhone === whatsapp)) {
      return { kind: 'PHONE', merchantId: doc.id, merchantName };
    }

    // Kept rather than returned: a phone match anywhere in the scan outranks a
    // name match found earlier in it.
    if (
      nameMatch === null &&
      name !== '' &&
      merchantName !== null &&
      normalizeCompanyName(merchantName) === name
    ) {
      nameMatch = { kind: 'NAME', merchantId: doc.id, merchantName };
    }
  }

  return nameMatch ?? { kind: 'NONE' };
}

/* ---------------------------------------------------------- the prospect */

export type CreateProspectInput = {
  companyId: string;
  source: ProspectSource;
  sourceReference: string | null;
  status: ProspectStatus;
  now: number;
  suspectedMerchantId?: string | null;
  disqualifyReason?: string | null;
};

/**
 * Creates the prospect for a company, or returns the one that exists.
 *
 * Keyed by the company id rather than by a random one, which makes "one live
 * prospect per company" a property of the key. Re-running the same search next
 * week finds the company, finds its prospect, and adds nothing — which is what
 * makes discovery idempotent and safe to retry.
 */
export async function createProspectForCompany(
  input: CreateProspectInput,
): Promise<{ prospect: StoredProspect; created: boolean }> {
  const prospectId = input.companyId;
  const ref = prospectingRefs.prospect(prospectId);

  return db().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      return { prospect: snapshot.data() as StoredProspect, created: false };
    }

    const prospect: StoredProspect = {
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
      furthest_stage: raiseStage(null, input.status),
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

export async function getProspect(prospectId: string): Promise<StoredProspect | null> {
  const snapshot = await prospectingRefs.prospect(prospectId).get();
  return snapshot.exists ? (snapshot.data() as StoredProspect) : null;
}

export async function getCompany(companyId: string): Promise<StoredCompany | null> {
  const snapshot = await prospectingRefs.company(companyId).get();
  return snapshot.exists ? (snapshot.data() as StoredCompany) : null;
}

export class TransitionError extends Error {
  readonly from: ProspectStatus;
  readonly to: ProspectStatus;

  constructor(from: ProspectStatus, to: ProspectStatus) {
    super(`cannot move a prospect from ${from} to ${to}`);
    this.name = 'TransitionError';
    this.from = from;
    this.to = to;
  }
}

/**
 * Moves a prospect, in a transaction, through the one validator.
 *
 * The check is inside the transaction and reads the stored status rather than
 * one the caller passed in. Otherwise two operators looking at the same lead
 * could both see `CONTACTED`, both be told the move is legal, and one of them
 * write a transition from a status that had already changed underneath them.
 */
export async function setProspectStatus(input: {
  prospectId: string;
  to: ProspectStatus;
  actor: string;
  reason?: string | null;
  now: number;
}): Promise<StoredProspect> {
  const ref = prospectingRefs.prospect(input.prospectId);

  const updated = await db().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new Error('prospect not found');

    const prospect = snapshot.data() as StoredProspect;
    const from = isProspectStatus(prospect.status) ? prospect.status : 'RAW';

    if (!canTransition(from, input.to)) throw new TransitionError(from, input.to);

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
      furthest_stage: raiseStage(prospect.furthest_stage ?? null, input.to),
      ...(input.reason === undefined ? {} : { disqualify_reason: input.reason }),
    };

    transaction.set(ref, patch, { merge: true });
    transaction.set(prospectingRefs.activities(input.prospectId).doc(randomUUID()), {
      id: randomUUID(),
      prospect_id: input.prospectId,
      type: 'STATUS_CHANGED' satisfies ActivityType,
      channel: null,
      description: `${from} → ${input.to}`,
      metadata: { from, to: input.to, reason: input.reason ?? null },
      created_at: input.now,
      created_by: input.actor,
    });

    return { ...prospect, ...patch } as StoredProspect;
  });

  return updated;
}

/** Applies a scoring result to the prospect. Never moves the status by itself. */
export async function saveScores(input: {
  prospectId: string;
  total: number;
  businessFit: number;
  digitalPresence: number;
  retentionPotential: number;
  commercialOpportunity: number;
  band: string;
  now: number;
}): Promise<void> {
  await prospectingRefs.prospect(input.prospectId).set(
    {
      lead_score: input.total,
      business_fit_score: input.businessFit,
      digital_presence_score: input.digitalPresence,
      retention_potential_score: input.retentionPotential,
      commercial_opportunity_score: input.commercialOpportunity,
      band: input.band,
      scoring_version: SCORING_VERSION,
      updated_at: input.now,
    },
    { merge: true },
  );
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
export async function updateCompanyListing(input: {
  companyId: string;
  phone: string | null;
  website: string | null;
  hasOpeningHours: boolean | null;
  hasPhotos: boolean | null;
  now: number;
}): Promise<void> {
  const patch: Record<string, unknown> = {
    has_opening_hours: input.hasOpeningHours,
    has_photos: input.hasPhotos,
    updated_at: input.now,
  };
  if (input.phone !== null) patch.phone = input.phone;
  if (input.website !== null) patch.website = input.website;

  await prospectingRefs.company(input.companyId).set(patch, { merge: true });
}

/**
 * Records which template a lead was actually written to with. Once.
 *
 * A transaction rather than a merge, because "set only if unset" is a
 * read-then-write and two operators sending from two tabs would otherwise
 * race — with the loser silently reassigning an A/B arm. Returns what the
 * lead ended up attributed to, which is not always what was passed.
 */
export async function recordOutreachTemplate(input: {
  prospectId: string;
  templateId: string;
  now: number;
}): Promise<string> {
  const ref = prospectingRefs.prospect(input.prospectId);

  return db().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new Error('prospect not found');

    const existing = (snapshot.data() as StoredProspect).outreach_template_id;
    if (typeof existing === 'string' && existing.trim() !== '') return existing;

    transaction.set(
      ref,
      { outreach_template_id: input.templateId, updated_at: input.now },
      { merge: true },
    );
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
export async function readFunnelCounts(input?: {
  /** The templates to count, from the settings document. */
  templateIds?: readonly string[];
}): Promise<{
  reachedByStage: Record<number, number>;
  exitsByStatus: Partial<Record<ProspectStatus, number>>;
  byBand: Record<string, { total: number; customers: number }>;
  byTemplate: Record<string, { sent: number; replied: number }>;
}> {
  const prospects = db().collection(COLLECTIONS.prospects);
  const countOf = async (query: FirebaseFirestore.Query): Promise<number> =>
    (await query.count().get()).data().count;

  const stages = await Promise.all(
    PROSPECT_PIPELINE.map(async (_status, stage) => ({
      stage,
      count: await countOf(prospects.where('furthest_stage', '==', stage)),
    })),
  );

  const exits = await Promise.all(
    PROSPECT_TERMINAL.map(async (status) => ({
      status,
      count: await countOf(prospects.where('status', '==', status)),
    })),
  );

  // Only the two bands the decision rule compares. Counting all four would be
  // four more round trips for a number nothing reads.
  const bands = await Promise.all(
    (['PRIORITY', 'NURTURE'] as const).map(async (band) => ({
      band,
      total: await countOf(prospects.where('band', '==', band)),
      customers: await countOf(
        prospects.where('band', '==', band).where('status', '==', 'CUSTOMER'),
      ),
    })),
  );

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
  const repliedStage = STAGE_OF.REPLIED ?? 6;
  const templates = await Promise.all(
    (input?.templateIds ?? []).map(async (templateId) => {
      const scoped = prospects.where('outreach_template_id', '==', templateId);
      return {
        templateId,
        sent: await countOf(scoped),
        replied: await countOf(scoped.where('furthest_stage', '>=', repliedStage)),
      };
    }),
  );

  return {
    reachedByStage: Object.fromEntries(
      stages.map((entry) => [entry.stage, entry.count]),
    ),
    byTemplate: Object.fromEntries(
      templates.map((entry) => [
        entry.templateId,
        { sent: entry.sent, replied: entry.replied },
      ]),
    ),
    exitsByStatus: Object.fromEntries(
      exits.map((entry) => [entry.status, entry.count]),
    ) as Partial<Record<ProspectStatus, number>>,
    byBand: Object.fromEntries(
      bands.map((entry) => [
        entry.band,
        { total: entry.total, customers: entry.customers },
      ]),
    ),
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
export async function saveContact(input: {
  prospectId: string;
  person: PersonRecord;
  isDecisionMaker: boolean;
  now: number;
}): Promise<StoredContact> {
  const contactId =
    input.person.provider_person_id ??
    `local_${matchKeyDocId({
      kind: 'NAME_CITY',
      value: `${input.person.first_name ?? ''}|${input.person.job_title ?? ''}`,
    })}`;

  const contact: StoredContact = {
    ...input.person,
    id: contactId,
    prospect_id: input.prospectId,
    is_decision_maker: input.isDecisionMaker,
    created_at: input.now,
    updated_at: input.now,
  };

  await prospectingRefs.contacts(input.prospectId).doc(contactId).set(contact, { merge: true });
  return contact;
}

export async function listContacts(prospectId: string): Promise<StoredContact[]> {
  const snapshot = await prospectingRefs.contacts(prospectId).limit(50).get();
  return snapshot.docs.map((doc) => doc.data() as StoredContact);
}

/* -------------------------------------------------------------- activities */

export async function appendActivity(input: {
  prospectId: string;
  type: ActivityType;
  description: string;
  channel?: string | null;
  metadata?: Record<string, unknown>;
  actor: string | null;
  now: number;
}): Promise<StoredActivity> {
  const id = randomUUID();
  const activity: StoredActivity = {
    id,
    prospect_id: input.prospectId,
    type: input.type,
    channel: input.channel ?? null,
    description: input.description,
    metadata: input.metadata ?? {},
    created_at: input.now,
    created_by: input.actor,
  };

  await prospectingRefs.activities(input.prospectId).doc(id).set(activity);
  await prospectingRefs
    .prospect(input.prospectId)
    .set({ last_activity_at: input.now, updated_at: input.now }, { merge: true });

  return activity;
}

export async function listActivities(
  prospectId: string,
  limit = 50,
): Promise<StoredActivity[]> {
  const snapshot = await prospectingRefs
    .activities(prospectId)
    .orderBy('created_at', 'desc')
    .limit(limit)
    .get();
  return snapshot.docs.map((doc) => doc.data() as StoredActivity);
}

/* ---------------------------------------------------------------- analyses */

export type StoredAnalysis = {
  id: string;
  prospect_id: string;
  model: string;
  prompt_version: number;
  data_hash: string;
  scores: Record<string, number>;
  analysis: Record<string, unknown>;
  recommended_pitch: string;
  recommended_channel: string;
  created_at: number;
};

export async function saveAnalysis(input: StoredAnalysis): Promise<void> {
  await prospectingRefs.analyses(input.prospect_id).doc(input.id).set(input);
}

/** The newest analysis, which is the only one the cache consults. */
export async function latestAnalysis(prospectId: string): Promise<StoredAnalysis | null> {
  const snapshot = await prospectingRefs
    .analyses(prospectId)
    .orderBy('created_at', 'desc')
    .limit(1)
    .get();
  return snapshot.empty ? null : (snapshot.docs[0].data() as StoredAnalysis);
}

/* ------------------------------------------------------------------- spend */

export type SpendSnapshot = {
  monthUsd: number;
  dayUsd: number;
  leadUsd: number;
};

/**
 * What has been spent, in two reads rather than a scan of the usage log.
 *
 * The counters are the authority for the budget decision; the usage rows are
 * the authority for what was actually bought. They are written in one
 * transaction, so a counter cannot advance without a row explaining it.
 */
export async function readSpend(input: {
  now: number;
  prospectId: string | null;
}): Promise<SpendSnapshot> {
  const [month, day, prospect] = await Promise.all([
    prospectingRefs.spend(monthKey(input.now)).get(),
    prospectingRefs.spend(dayKey(input.now)).get(),
    input.prospectId === null
      ? Promise.resolve(null)
      : prospectingRefs.prospect(input.prospectId).get(),
  ]);

  const total = (snapshot: FirebaseFirestore.DocumentSnapshot | null): number => {
    if (snapshot === null || !snapshot.exists) return 0;
    const value = (snapshot.data() ?? {}).total_usd;
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  };

  const leadSpend =
    prospect !== null && prospect.exists
      ? ((prospect.data() ?? {}).spend_usd as number | undefined) ?? 0
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
export async function recordUsage(input: {
  provider: string;
  operation: ProviderOperation;
  prospectId: string | null;
  estimatedCostUsd: number;
  actualCostUsd: number | null;
  creditsUsed: number | null;
  success: boolean;
  errorCode: string | null;
  correlationId: string;
  now: number;
}): Promise<EnrichmentUsage> {
  const id = randomUUID();
  const charged = input.actualCostUsd ?? input.estimatedCostUsd;

  const row: EnrichmentUsage = {
    id,
    provider: input.provider,
    operation: input.operation,
    prospect_id: input.prospectId,
    estimated_cost: round(input.estimatedCostUsd),
    actual_cost: input.actualCostUsd === null ? null : round(input.actualCostUsd),
    credits_used: input.creditsUsed,
    success: input.success,
    error_code: input.errorCode,
    correlation_id: input.correlationId,
    month_key: monthKey(input.now),
    day_key: dayKey(input.now),
    created_at: input.now,
  };

  const batch = db().batch();
  batch.set(prospectingRefs.usage(id), row);
  batch.set(
    prospectingRefs.spend(row.month_key),
    {
      period: row.month_key,
      kind: 'month',
      total_usd: FieldValue.increment(round(charged)),
      calls: FieldValue.increment(1),
      updated_at: input.now,
    },
    { merge: true },
  );
  batch.set(
    prospectingRefs.spend(row.day_key),
    {
      period: row.day_key,
      kind: 'day',
      total_usd: FieldValue.increment(round(charged)),
      calls: FieldValue.increment(1),
      updated_at: input.now,
    },
    { merge: true },
  );

  if (input.prospectId !== null) {
    batch.set(
      prospectingRefs.prospect(input.prospectId),
      {
        spend_usd: FieldValue.increment(round(charged)),
        updated_at: input.now,
      },
      { merge: true },
    );
  }

  await batch.commit();
  return row;
}

/** The usage log for a period, newest first. */
export async function listUsage(input: {
  monthKey?: string;
  limit: number;
  offset: number;
}): Promise<{ rows: EnrichmentUsage[]; hasMore: boolean }> {
  let query = db()
    .collection(COLLECTIONS.usage)
    .orderBy('created_at', 'desc') as FirebaseFirestore.Query;

  if (input.monthKey !== undefined) {
    query = db()
      .collection(COLLECTIONS.usage)
      .where('month_key', '==', input.monthKey)
      .orderBy('created_at', 'desc');
  }

  const snapshot = await query.offset(input.offset).limit(input.limit + 1).get();
  const docs = snapshot.docs.slice(0, input.limit);

  return {
    rows: docs.map((doc) => doc.data() as EnrichmentUsage),
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
export async function readSettings(): Promise<ProspectingSettings> {
  const snapshot = await prospectingRefs.settings().get();
  if (!snapshot.exists) return DEFAULT_SETTINGS;

  const stored = (snapshot.data() ?? {}) as Partial<ProspectingSettings>;
  return {
    ...DEFAULT_SETTINGS,
    ...stored,
    geography: { ...DEFAULT_SETTINGS.geography, ...(stored.geography ?? {}) },
    scoring: { ...DEFAULT_SETTINGS.scoring, ...(stored.scoring ?? {}) },
  };
}

export async function writeSettings(input: {
  patch: Partial<ProspectingSettings>;
  actor: string;
  now: number;
}): Promise<ProspectingSettings> {
  await prospectingRefs.settings().set(
    { ...input.patch, updated_at: input.now, updated_by: input.actor },
    { merge: true },
  );
  return readSettings();
}

/* ----------------------------------------------------------------- listing */

export type ProspectQuery = {
  status?: string;
  band?: string;
  industry?: string;
  city?: string;
  source?: string;
  enrichmentStatus?: string;
  /** 'with' or 'without' a decision maker. */
  contact?: string;
  search?: string;
  sort: 'score' | 'newest' | 'enriched' | 'contacted';
  limit: number;
  offset: number;
};

export type ProspectListRow = {
  prospect: StoredProspect;
  company: StoredCompany | null;
};

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
export async function listProspects(
  query: ProspectQuery,
): Promise<{ rows: ProspectListRow[]; total: number; hasMore: boolean; truncated: boolean }> {
  const sortField =
    query.sort === 'newest'
      ? 'created_at'
      : query.sort === 'enriched'
        ? 'last_enriched_at'
        : query.sort === 'contacted'
          ? 'last_activity_at'
          : 'lead_score';

  let firestoreQuery = db().collection(COLLECTIONS.prospects) as FirebaseFirestore.Query;

  // Priority order: the most selective filter an operator is likely to set.
  if (query.status !== undefined && query.status !== '') {
    firestoreQuery = firestoreQuery.where('status', '==', query.status);
  } else if (query.band !== undefined && query.band !== '') {
    firestoreQuery = firestoreQuery.where('band', '==', query.band);
  } else if (query.enrichmentStatus !== undefined && query.enrichmentStatus !== '') {
    firestoreQuery = firestoreQuery.where('enrichment_status', '==', query.enrichmentStatus);
  } else if (query.source !== undefined && query.source !== '') {
    firestoreQuery = firestoreQuery.where('source', '==', query.source);
  }

  const snapshot = await firestoreQuery
    .orderBy(sortField, 'desc')
    .limit(SCAN_CAP + 1)
    .get();

  const truncated = snapshot.size > SCAN_CAP;
  const docs = truncated ? snapshot.docs.slice(0, SCAN_CAP) : snapshot.docs;
  const prospects = docs.map((doc) => doc.data() as StoredProspect);

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

function matchesInMemory(row: ProspectListRow, query: ProspectQuery): boolean {
  const { prospect, company } = row;

  if (query.status && prospect.status !== query.status) return false;
  if (query.band && prospect.band !== query.band) return false;
  if (query.source && prospect.source !== query.source) return false;
  if (query.enrichmentStatus && prospect.enrichment_status !== query.enrichmentStatus) {
    return false;
  }
  if (query.industry && (company?.industry ?? null) !== query.industry) return false;
  if (query.city && normalizeCompanyName(company?.city ?? '') !== normalizeCompanyName(query.city)) {
    return false;
  }
  if (query.contact === 'with' && prospect.decision_maker_count === 0) return false;
  if (query.contact === 'without' && prospect.decision_maker_count > 0) return false;

  if (query.search !== undefined && query.search.trim() !== '') {
    const needle = normalizeCompanyName(query.search);
    const haystack = normalizeCompanyName(company?.name ?? '');
    if (needle !== '' && !haystack.includes(needle)) return false;
  }

  return true;
}

/** Firestore takes at most thirty ids per `in`, so the reads are chunked. */
async function loadCompanies(ids: string[]): Promise<Map<string, StoredCompany>> {
  const unique = [...new Set(ids)].filter((id) => id !== '');
  const found = new Map<string, StoredCompany>();

  for (let index = 0; index < unique.length; index += 30) {
    const chunk = unique.slice(index, index + 30);
    const snapshot = await db()
      .collection(COLLECTIONS.companies)
      .where(FieldPath.documentId(), 'in', chunk)
      .get();
    for (const doc of snapshot.docs) {
      found.set(doc.id, doc.data() as StoredCompany);
    }
  }

  return found;
}
