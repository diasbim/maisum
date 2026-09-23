"use strict";
/**
 * The vocabulary of the prospecting module, in one place.
 *
 * Everything here is a stored value or a wire value: pipeline statuses that
 * land in Firestore, evidence kinds that reach a screen, provider operation
 * names that a cost row is keyed by. Changing a string in this file changes
 * stored data, so none of them is cosmetic.
 *
 * The arrangement follows `affiliate_contracts.ts`: the stored enum and the
 * Portuguese a person reads are written down together, so they cannot drift
 * apart quietly.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.JOB_BATCH_SIZE = exports.JOB_LEASE_MS = exports.CLAIMABLE_JOB_STATUSES = exports.JOB_TYPE = exports.JOB_STATUS = exports.FALLBACK_ERROR_CODES = exports.PROVIDER_ERROR_CODE = exports.PROVIDER_OPERATION = exports.EMAIL_STATUS_LABEL = exports.EMAIL_STATUS = exports.SENIORITY = exports.OUTREACH_CHANNEL_LABEL = exports.OUTREACH_CHANNEL = exports.ACTIVITY_TYPE = exports.PROSPECT_SOURCE = exports.CLAIM_TYPE = exports.ENRICHMENT_STATUS_LABEL = exports.ENRICHMENT_STATUS = exports.PROSPECT_STATUS_LABEL = exports.PROSPECT_STATUS = exports.PROSPECT_TERMINAL = exports.PROSPECT_PIPELINE = void 0;
exports.isProspectStatus = isProspectStatus;
exports.isTerminalStatus = isTerminalStatus;
exports.blocksOutreach = blocksOutreach;
exports.canTransition = canTransition;
exports.isDecisionMakerSeniority = isDecisionMakerSeniority;
exports.isReachableEmail = isReachableEmail;
/* ------------------------------------------------------------------ status */
/**
 * The pipeline, in order.
 *
 * Order is meaning here, not presentation: `canTransition` reads the index to
 * decide whether a move is forward, and the UI reads it to draw the funnel. A
 * value inserted in the middle changes what "forward" means for every lead
 * already stored, which is why a new stage goes at the end unless the change
 * is deliberate.
 */
exports.PROSPECT_PIPELINE = [
    'RAW',
    'QUALIFIED',
    'SCORED',
    'ENRICHED',
    'READY_TO_CONTACT',
    'CONTACTED',
    'REPLIED',
    'INTERESTED',
    'DEMO',
    'TRIAL',
    'CUSTOMER',
];
/**
 * Where a lead stops.
 *
 * `DO_NOT_CONTACT` and `OPTED_OUT` are the two that carry an obligation rather
 * than an opinion, and `blocksOutreach` names them. `EXISTING_CUSTOMER` is
 * here rather than in the pipeline because a business that already pays for
 * MaisUm is not a lead at any score.
 */
exports.PROSPECT_TERMINAL = [
    'NOT_A_FIT',
    'NO_CONTACT',
    'DO_NOT_CONTACT',
    'OPTED_OUT',
    'EXISTING_CUSTOMER',
    'LOST',
];
exports.PROSPECT_STATUS = [
    ...exports.PROSPECT_PIPELINE,
    ...exports.PROSPECT_TERMINAL,
];
function isProspectStatus(value) {
    return (typeof value === 'string' &&
        exports.PROSPECT_STATUS.includes(value));
}
function isTerminalStatus(status) {
    return exports.PROSPECT_TERMINAL.includes(status);
}
/**
 * The two statuses that forbid outreach, whatever else is true of the lead.
 *
 * Read by the outreach route before anything is generated, and by the store
 * before an activity of type `OUTREACH_*` is appended. Two checks rather than
 * one because generating is a different act from recording, and a module that
 * only guarded the first would still let a person log a message they should
 * never have sent.
 */
function blocksOutreach(status) {
    return status === 'DO_NOT_CONTACT' || status === 'OPTED_OUT';
}
/**
 * Whether a lead may move from one status to another.
 *
 * Three rules, and they are the whole state machine:
 *
 *   Forward only, but stages may be skipped. A lead that answers the first
 *   WhatsApp message goes straight from `READY_TO_CONTACT` to `REPLIED`
 *   without anyone having to record a `CONTACTED` that did not happen — the
 *   alternative is a salesperson inventing history to satisfy a validator.
 *
 *   Any pipeline stage may end. A lead is disqualified from wherever it stood.
 *
 *   A terminal status admits nothing. Not even back to `RAW`: reopening a
 *   `DO_NOT_CONTACT` would erase a refusal that the person who gave it has no
 *   way to give twice, and applying the same rule to `LOST` costs only a
 *   re-run of the search, which is cheap. A lead that must genuinely be
 *   reconsidered is discovered again, deduplicated onto the same company, and
 *   gets a new prospect row with its own history.
 */
function canTransition(from, to) {
    if (from === to)
        return false;
    if (isTerminalStatus(from))
        return false;
    if (isTerminalStatus(to))
        return true;
    const fromIndex = exports.PROSPECT_PIPELINE.indexOf(from);
    const toIndex = exports.PROSPECT_PIPELINE.indexOf(to);
    return fromIndex >= 0 && toIndex > fromIndex;
}
/** What an operator reads. One table, so no route invents a second wording. */
exports.PROSPECT_STATUS_LABEL = {
    RAW: 'Descoberto',
    QUALIFIED: 'Qualificado',
    SCORED: 'Pontuado',
    ENRICHED: 'Enriquecido',
    READY_TO_CONTACT: 'Pronto a contactar',
    CONTACTED: 'Contactado',
    REPLIED: 'Respondeu',
    INTERESTED: 'Interessado',
    DEMO: 'Demonstração',
    TRIAL: 'Em teste',
    CUSTOMER: 'Cliente',
    NOT_A_FIT: 'Não encaixa',
    NO_CONTACT: 'Sem contacto',
    DO_NOT_CONTACT: 'Não contactar',
    OPTED_OUT: 'Pediu para sair',
    EXISTING_CUSTOMER: 'Já é cliente',
    LOST: 'Perdido',
};
/* -------------------------------------------------------------- enrichment */
/**
 * How far paid enrichment got.
 *
 * `BUDGET_BLOCKED` is a state of its own rather than a flavour of `FAILED`,
 * because it is not a failure: nothing went wrong, the cap did its job, and
 * the lead becomes enrichable again once the budget resets without anyone
 * retrying anything. A screen that showed it as an error would send an
 * operator looking for a fault that does not exist.
 */
exports.ENRICHMENT_STATUS = [
    'NOT_STARTED',
    'BELOW_THRESHOLD',
    'IN_PROGRESS',
    'PARTIAL',
    'COMPLETE',
    'NO_RESULT',
    'BUDGET_BLOCKED',
    'FAILED',
];
exports.ENRICHMENT_STATUS_LABEL = {
    NOT_STARTED: 'Por enriquecer',
    BELOW_THRESHOLD: 'Abaixo do mínimo',
    IN_PROGRESS: 'A enriquecer',
    PARTIAL: 'Parcial',
    COMPLETE: 'Completo',
    NO_RESULT: 'Sem resultados',
    BUDGET_BLOCKED: 'Orçamento esgotado',
    FAILED: 'Falhou',
};
/* ------------------------------------------------------------ verification */
/**
 * What a claim about a business is worth.
 *
 * The module's central rule is that these three are never collapsed. A `FACT`
 * was read from a provider response or a page; an `INFERENCE` is the model's
 * reading of evidence it must name; `UNKNOWN` is the honest answer and the one
 * the UI must be able to show. A field that cannot be one of these is not
 * stored.
 */
exports.CLAIM_TYPE = ['FACT', 'INFERENCE', 'UNKNOWN'];
/* ------------------------------------------------------------------ source */
/** Where a prospect came from. Stored, so it is append-only in practice. */
exports.PROSPECT_SOURCE = [
    /** Discovered by a provider search. */
    'DISCOVERY',
    /** Typed in by the person who answered the WhatsApp inbox. */
    'MANUAL',
    /** Seeded for development. Never present in production data. */
    'SEED',
];
/* ---------------------------------------------------------------- activity */
/**
 * The timeline. Every entry is something a person or the system actually did.
 *
 * `OUTREACH_GENERATED` and `OUTREACH_SENT` are separate because the module
 * generates and never sends: the first is written by the server, the second
 * only ever by a person saying they sent it. Collapsing them would make the
 * timeline claim the product did something it is designed not to do.
 */
exports.ACTIVITY_TYPE = [
    'DISCOVERED',
    'QUALIFIED',
    'SCORED',
    'ENRICHED',
    'DECISION_MAKER_FOUND',
    'ANALYZED',
    'OUTREACH_GENERATED',
    'OUTREACH_SENT',
    'STATUS_CHANGED',
    'NOTE',
];
exports.OUTREACH_CHANNEL = ['WHATSAPP', 'EMAIL', 'SMS', 'LINKEDIN'];
exports.OUTREACH_CHANNEL_LABEL = {
    WHATSAPP: 'WhatsApp',
    EMAIL: 'Email',
    SMS: 'SMS',
    LINKEDIN: 'LinkedIn',
};
/* ------------------------------------------------------------------ people */
exports.SENIORITY = [
    'OWNER',
    'FOUNDER',
    'C_LEVEL',
    'DIRECTOR',
    'MANAGER',
    'STAFF',
    'UNKNOWN',
];
/**
 * Which roles decide whether a shop buys software.
 *
 * In an eight-person barbershop that is the owner, and nobody else. The list
 * is ordered by how directly the role decides, and this predicate cuts it
 * after `MANAGER` — a `STAFF` contact is worth storing, because they answer
 * the phone, but the UI must not present them as the person to pitch.
 */
function isDecisionMakerSeniority(seniority) {
    return (seniority === 'OWNER' ||
        seniority === 'FOUNDER' ||
        seniority === 'C_LEVEL' ||
        seniority === 'DIRECTOR' ||
        seniority === 'MANAGER');
}
/**
 * Whether an email address is known to work.
 *
 * `GUESSED` exists because providers return pattern-built addresses, and those
 * must never be shown as if they had been verified — criterion 13 is about
 * exactly this. A `GUESSED` address is stored, labelled, and excluded from the
 * "reachable contact" scoring point.
 */
exports.EMAIL_STATUS = [
    'VERIFIED',
    'GUESSED',
    'UNVERIFIED',
    'INVALID',
    'UNKNOWN',
];
exports.EMAIL_STATUS_LABEL = {
    VERIFIED: 'Verificado',
    GUESSED: 'Estimado',
    UNVERIFIED: 'Por verificar',
    INVALID: 'Inválido',
    UNKNOWN: 'Desconhecido',
};
/** Only a verified address counts as a reachable email. */
function isReachableEmail(status) {
    return status === 'VERIFIED';
}
/* --------------------------------------------------------------- providers */
/**
 * Every paid operation, named. A usage row is keyed by one of these.
 *
 * The two model calls are here beside the data providers, and they are
 * separate from one another. A model call is a paid provider call like any
 * other — a module that guarded its Apollo credits and let an operator
 * generate two hundred outreach drafts without counting them would be
 * spending silently in the one place nobody was watching.
 */
/**
 * Every operation that can cost money, as stored vocabulary.
 *
 * Append-only. `ANALYZE_LEAD` and `GENERATE_OUTREACH` are no longer emitted —
 * the analysis is not run and the outreach is templated — but usage rows
 * written before that still name them, and a reader that cannot resolve the
 * operation on a historical row cannot report last quarter's spend.
 */
exports.PROVIDER_OPERATION = [
    'SEARCH_BUSINESSES',
    'ENRICH_COMPANY',
    'FIND_DECISION_MAKERS',
    'ENRICH_PERSON',
    'RESEARCH_COMPANY',
    'ANALYZE_LEAD',
    'GENERATE_OUTREACH',
    /** The dear half of a directory listing: phone, website, timetable, photos. */
    'FETCH_LISTING_DETAILS',
];
/**
 * Why a provider call did not produce what was asked for.
 *
 * Seven codes, because the caller does something different with each: a
 * timeout is retried, a rate limit is backed off, exhausted credits pause the
 * whole provider, an invalid schema is a bug to be logged, and `NO_RESULT` is
 * not an error at all — it is the answer that this business has no findable
 * decision maker, which is worth storing so the lead is not enriched again
 * next week at the same cost.
 */
exports.PROVIDER_ERROR_CODE = [
    'UNAVAILABLE',
    'TIMEOUT',
    'RATE_LIMITED',
    'INSUFFICIENT_CREDITS',
    'INVALID_SCHEMA',
    'NOT_CONFIGURED',
    'NO_RESULT',
];
/**
 * Codes that mean "ask a different provider", rather than "stop".
 *
 * `NO_RESULT` is deliberately absent. A provider that answered "this business
 * has no decision maker I can find" has answered; asking the next one is a
 * second charge for the same question, and the fallback chain exists to route
 * around breakage, not to shop for a better answer.
 */
exports.FALLBACK_ERROR_CODES = [
    'UNAVAILABLE',
    'TIMEOUT',
    'RATE_LIMITED',
    'INSUFFICIENT_CREDITS',
    'INVALID_SCHEMA',
    'NOT_CONFIGURED',
];
/* -------------------------------------------------------------------- jobs */
exports.JOB_STATUS = [
    'QUEUED',
    'RUNNING',
    'SUCCEEDED',
    'PARTIAL',
    'FAILED',
    'CANCELLED',
];
exports.JOB_TYPE = ['DISCOVERY', 'BULK_ENRICHMENT'];
/** States a sweep may pick up. Terminal rows are never queried again. */
exports.CLAIMABLE_JOB_STATUSES = ['QUEUED', 'RUNNING'];
/**
 * How long a worker holds a job before another may take it.
 *
 * The same reasoning as `OUTBOX_LEASE_MS`: longer than any single batch should
 * take, short enough that a crashed instance does not strand a search for an
 * hour. A discovery batch calls a provider and then writes up to ten
 * companies, so this is more generous than the outbox's two minutes.
 */
exports.JOB_LEASE_MS = 300_000;
/** Businesses one invocation processes before yielding. Bounded on purpose. */
exports.JOB_BATCH_SIZE = 10;
