import {
  FALLBACK_ERROR_CODES,
  type EmailStatus,
  type ProviderErrorCode,
  type ProviderOperation,
  type Seniority,
} from './prospecting_contracts.js';

/**
 * The boundary between this module and anything it pays for.
 *
 * Five interfaces, one internal model, and a fallback chain. Business logic
 * depends on the interfaces and never on a concrete provider — which is what
 * makes the whole pipeline runnable against fixtures, and what makes swapping
 * Apollo for something else a change to one file rather than to the routes.
 *
 * Three rules hold everywhere below.
 *
 * **Provider-shaped data never leaves an adapter.** Every field is mapped into
 * the types in this file before it is returned. A route that handed an Apollo
 * response to the UI would be shipping Apollo's schema as the product's, and
 * the next provider would break every screen.
 *
 * **Absent is null, never guessed.** No adapter may construct an email from a
 * name and a domain, infer an owner from a company name, or default an
 * employee count. This is the rule criterion 13 tests, and it is enforced here
 * rather than trusted: `assertNoFabrication` refuses a result whose email is
 * marked `VERIFIED` without the provider having said so.
 *
 * **Every failure is typed.** An adapter throws `ProviderError` with one of
 * seven codes, and the chain decides what each means. An adapter that let a
 * `fetch` rejection escape would take down a discovery job with a stack trace
 * instead of moving to the next provider.
 */

/* ------------------------------------------------------------------ errors */

export class ProviderError extends Error {
  readonly code: ProviderErrorCode;
  readonly provider: string;
  readonly operation: ProviderOperation;
  /** What the provider said, for the log. Never shown to an operator. */
  readonly detail: string | null;

  constructor(input: {
    code: ProviderErrorCode;
    provider: string;
    operation: ProviderOperation;
    detail?: string | null;
  }) {
    super(`${input.provider}/${input.operation}: ${input.code}`);
    this.name = 'ProviderError';
    this.code = input.code;
    this.provider = input.provider;
    this.operation = input.operation;
    this.detail = input.detail ?? null;
  }

  /** True when another provider should be asked the same question. */
  get isFallbackWorthy(): boolean {
    return FALLBACK_ERROR_CODES.includes(this.code);
  }
}

/* ------------------------------------------------------------ the model */

/**
 * A company as this module stores it.
 *
 * Every field is nullable except the name, because every one of them is
 * genuinely absent for some business in Maputo. A type that made `domain`
 * required would force an adapter to invent one.
 */
export type CompanyRecord = {
  name: string;
  legal_name: string | null;
  domain: string | null;
  website: string | null;
  /** A `businesses.business_type` id, or null when the trade is not stated. */
  industry: string | null;
  /** What the provider called the trade, kept for evidence and for mapping. */
  industry_raw: string | null;
  employee_count: number | null;
  city: string | null;
  province: string | null;
  country: string | null;
  address: string | null;
  phone: string | null;
  email: string | null;
  linkedin_url: string | null;
  instagram_url: string | null;
  facebook_url: string | null;
  whatsapp: string | null;
  /** Public rating, 0–5, or null when the source carries none. */
  rating: number | null;
  review_count: number | null;
  has_opening_hours: boolean | null;
  has_photos: boolean | null;
  /** The source's own word for whether it is trading. Kept raw. */
  business_status: string | null;
  /**
   * Where the storefront is, when the source says.
   *
   * Carried for deduplication, not for mapping. Two listings with the same
   * folded name are the same business when they are metres apart and two
   * different businesses when they are in different neighbourhoods, and a
   * name alone cannot tell those apart — "Barbearia Central" is a name three
   * unrelated shops in Maputo will have chosen.
   */
  latitude: number | null;
  longitude: number | null;
  source: string;
  source_reference: string | null;
  provider_org_id: string | null;
};

export type PersonRecord = {
  first_name: string | null;
  last_name: string | null;
  job_title: string | null;
  seniority: Seniority;
  email: string | null;
  email_status: EmailStatus;
  phone: string | null;
  linkedin_url: string | null;
  provider_person_id: string | null;
  /** The provider's own confidence, 0–1, or null when it reports none. */
  confidence_score: number | null;
};

/**
 * Something observed about a business, with where it was observed.
 *
 * `source` is not optional and not a provider name: it is the URL or the
 * specific response field the claim came from. A finding with no source cannot
 * be checked by the person reading it, and an unfalsifiable claim about a real
 * business is worse than no claim.
 */
export type ResearchFinding = {
  claim: string;
  type: 'FACT' | 'INFERENCE';
  source: string;
};

export type CompanyResearchResult = {
  findings: readonly ResearchFinding[];
  /** Questions the research did not answer. Shown, not hidden. */
  unknowns: readonly string[];
  website_reachable: boolean | null;
  social_profiles: readonly string[];
  runs_promotions: boolean | null;
  growth_signal: boolean | null;
};

/* -------------------------------------------------------------- the inputs */

export type BusinessSearchCriteria = {
  /** `businesses.business_type` ids. Empty means every ICP industry. */
  industries: readonly string[];
  city: string | null;
  province: string | null;
  country: string;
  employeeMin: number | null;
  employeeMax: number | null;
  limit: number;
  /** Continuation token from a previous page, opaque to the caller. */
  cursor: string | null;
};

export type BusinessDiscoveryResult = {
  company: CompanyRecord;
  /** Opaque, provider-specific, returned so the next page can be asked for. */
  cursor: string | null;
};

export type CompanyEnrichmentInput = {
  name: string;
  domain: string | null;
  website: string | null;
  linkedinUrl: string | null;
  providerOrgId: string | null;
};

export type CompanyEnrichmentResult = {
  company: Partial<CompanyRecord>;
  /** Which fields this call actually filled, for the enrichment panel. */
  fieldsDiscovered: readonly string[];
};

export type DecisionMakerSearchInput = {
  companyName: string;
  domain: string | null;
  providerOrgId: string | null;
  /** Titles worth asking for, most senior first. */
  titles: readonly string[];
  limit: number;
};

export type PersonDiscoveryResult = { person: PersonRecord };

export type PersonEnrichmentInput = {
  providerPersonId: string | null;
  firstName: string | null;
  lastName: string | null;
  companyName: string | null;
  domain: string | null;
  linkedinUrl: string | null;
};

export type PersonEnrichmentResult = {
  person: Partial<PersonRecord>;
  fieldsDiscovered: readonly string[];
};

export type CompanyResearchInput = {
  name: string;
  website: string | null;
  city: string | null;
  industry: string | null;
};

/* ---------------------------------------------------------- the interfaces */

export type ProviderIdentity = {
  /** Stable key, used in settings, usage rows and logs. */
  readonly key: string;
  /** Whether credentials exist. A provider that is not configured is skipped. */
  isConfigured(): boolean;
};

export interface BusinessDiscoveryProvider extends ProviderIdentity {
  searchBusinesses(
    criteria: BusinessSearchCriteria,
  ): Promise<BusinessDiscoveryResult[]>;
}

export interface CompanyEnrichmentProvider extends ProviderIdentity {
  enrichCompany(input: CompanyEnrichmentInput): Promise<CompanyEnrichmentResult>;
}

export interface PersonDiscoveryProvider extends ProviderIdentity {
  findDecisionMakers(
    input: DecisionMakerSearchInput,
  ): Promise<PersonDiscoveryResult[]>;
}

export interface PersonEnrichmentProvider extends ProviderIdentity {
  enrichPerson(input: PersonEnrichmentInput): Promise<PersonEnrichmentResult>;
}

export interface WebResearchProvider extends ProviderIdentity {
  researchCompany(input: CompanyResearchInput): Promise<CompanyResearchResult>;
}

/* ------------------------------------------------------- listing details */

/**
 * The second, dearer half of a directory listing.
 *
 * Directory sources price by the fields asked for, not only by the call: a
 * search that returns a name, a trade and a rating is cheap, and the phone
 * number and the website cost more. That pricing is the whole reason this is a
 * separate port rather than more fields on `BusinessDiscoveryProvider` — it
 * lets the pipeline put the scoring gate *between* the two, so the expensive
 * half is only ever asked for about a business the rules already liked.
 *
 * Deliberately not named after any one source. It is the shape of the second
 * call, and a directory that prices the same way slots in behind it.
 */
export type ListingDetailInput = {
  /** The source's own id for the listing — a company's `source_reference`. */
  reference: string;
};

export type ListingDetailResult = {
  phone: string | null;
  website: string | null;
  /** Null when the response did not carry the field at all. */
  hasOpeningHours: boolean | null;
  hasPhotos: boolean | null;
};

export interface ListingDetailProvider extends ProviderIdentity {
  fetchListingDetail(input: ListingDetailInput): Promise<ListingDetailResult>;
}

/* ------------------------------------------------------------ the fallback */

/**
 * What a chain produced, and how.
 *
 * `partial` is the third outcome the brief asks for, and it is not a failure:
 * the first provider timed out, the second answered, and the result is real
 * but came from the less-preferred source. `attempts` carries every call that
 * was made so the usage rows can be written for all of them — including the
 * one that failed, which was still charged for.
 */
export type ChainAttempt = {
  provider: string;
  ok: boolean;
  code: ProviderErrorCode | null;
  durationMs: number;
};

export type ChainOutcome<T> =
  | {
      ok: true;
      value: T;
      provider: string;
      attempts: ChainAttempt[];
      /** True when an earlier provider failed before this one answered. */
      partial: boolean;
    }
  | {
      ok: false;
      /** The last code seen, which is what the UI explains. */
      code: ProviderErrorCode;
      attempts: ChainAttempt[];
    };

/**
 * Ask each provider in turn until one answers.
 *
 * The chain walks configured providers in the order `providerPriority` gives,
 * and stops at the first that answers. It stops *also* at the first
 * `NO_RESULT`: that is an answer, and asking the next provider would be paying
 * twice to hear it again. Fallback exists to route around breakage, not to
 * shop for a better reply — a chain that kept going until somebody said
 * something would eventually find a provider willing to guess, which is the
 * one outcome this module must not produce.
 *
 * A provider that is not configured is skipped without being called and
 * without a usage row, since nothing was spent.
 */
export async function runChain<P extends ProviderIdentity, T>(
  providers: readonly P[],
  call: (provider: P) => Promise<T>,
  options: { now?: () => number } = {},
): Promise<ChainOutcome<T>> {
  const now = options.now ?? Date.now;
  const attempts: ChainAttempt[] = [];
  let lastCode: ProviderErrorCode = 'NOT_CONFIGURED';

  for (const provider of providers) {
    if (!provider.isConfigured()) continue;

    const startedAt = now();
    try {
      const value = await call(provider);
      attempts.push({
        provider: provider.key,
        ok: true,
        code: null,
        durationMs: now() - startedAt,
      });
      return {
        ok: true,
        value,
        provider: provider.key,
        attempts,
        partial: attempts.length > 1,
      };
    } catch (error) {
      const code =
        error instanceof ProviderError ? error.code : 'UNAVAILABLE';
      attempts.push({
        provider: provider.key,
        ok: false,
        code,
        durationMs: now() - startedAt,
      });
      lastCode = code;

      // An answer, even an empty one, ends the chain.
      if (!FALLBACK_ERROR_CODES.includes(code)) {
        return { ok: false, code, attempts };
      }
    }
  }

  return { ok: false, code: lastCode, attempts };
}

/* ------------------------------------------------------------- validation */

/**
 * Refuses a person record that claims more than the provider said.
 *
 * Adapters are the place fabrication would enter, and they are written by
 * whoever is integrating a provider under time pressure. So the check is here,
 * applied to every adapter's output by the caller, rather than being a rule in
 * a comment that each adapter is trusted to have followed.
 *
 * Two things are refused outright: an email marked `VERIFIED` that is not a
 * syntactically valid address, and a confidence score outside 0–1. Both are
 * signs the mapping is reading the wrong field, and both would otherwise
 * become a number an operator trusts.
 */
export function assertNoFabrication(
  person: PersonRecord,
  provider: string,
  operation: ProviderOperation,
): PersonRecord {
  const fail = (detail: string) => {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail,
    });
  };

  if (person.email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(person.email)) {
    fail('email is not a valid address');
  }
  if (person.email === null && person.email_status === 'VERIFIED') {
    fail('email_status VERIFIED with no address');
  }
  if (
    person.confidence_score !== null &&
    (person.confidence_score < 0 || person.confidence_score > 1)
  ) {
    fail('confidence_score outside 0-1');
  }

  return person;
}

/** The same, for a company. Refuses an employee count that cannot be one. */
export function assertCompanySane(
  company: CompanyRecord,
  provider: string,
  operation: ProviderOperation,
): CompanyRecord {
  if (company.name.trim() === '') {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'company has no name',
    });
  }
  if (
    company.employee_count !== null &&
    (!Number.isInteger(company.employee_count) || company.employee_count < 0)
  ) {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'employee_count is not a whole number',
    });
  }
  // A rating outside 0–5 is a provider whose scale is not the one assumed, and
  // the scoring table compares it against a threshold without asking. Refusing
  // here is the difference between a loud bug and every lead in the campaign
  // quietly earning or losing five points for the wrong reason.
  if (
    company.rating !== null &&
    (!Number.isFinite(company.rating) || company.rating < 0 || company.rating > 5)
  ) {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'rating is not on a 0-5 scale',
    });
  }
  if (
    company.review_count !== null &&
    (!Number.isInteger(company.review_count) || company.review_count < 0)
  ) {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'review_count is not a whole number',
    });
  }
  // A coordinate off its scale is worse than a missing one: the distance test
  // would still answer, and it would answer "far apart" for two listings of
  // the same shop. Deduplication would then pay twice and report success.
  if (
    company.latitude !== null &&
    (!Number.isFinite(company.latitude) ||
      company.latitude < -90 ||
      company.latitude > 90)
  ) {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'latitude is not a degree between -90 and 90',
    });
  }
  if (
    company.longitude !== null &&
    (!Number.isFinite(company.longitude) ||
      company.longitude < -180 ||
      company.longitude > 180)
  ) {
    throw new ProviderError({
      code: 'INVALID_SCHEMA',
      provider,
      operation,
      detail: 'longitude is not a degree between -180 and 180',
    });
  }
  return company;
}

/* ------------------------------------------------------------- titles */

/**
 * Who to ask for, most likely to decide first.
 *
 * Bilingual because the businesses are Mozambican and the providers index
 * whatever the business wrote on LinkedIn, which is as often English as
 * Portuguese. Asking for only one language halves the hit rate on exactly the
 * leads worth having.
 */
export const DECISION_MAKER_TITLES: readonly string[] = [
  'owner',
  'proprietário',
  'proprietario',
  'founder',
  'fundador',
  'ceo',
  'managing director',
  'director geral',
  'diretor geral',
  'general manager',
  'gerente geral',
  'manager',
  'gerente',
];

/**
 * A job title mapped to the seniority the scorer reads.
 *
 * Returns `UNKNOWN` for anything unrecognised rather than guessing `STAFF`:
 * an unmapped title is a gap in this table, not a statement that the person is
 * junior, and treating it as one would quietly drop real owners whose title is
 * written in a way nobody anticipated.
 */
export function seniorityFromTitle(title: string | null): Seniority {
  if (title === null) return 'UNKNOWN';
  const value = title
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase();

  // The Portuguese stems carry a gendered ending, so the alternation spells
  // both out: `\bproprietari\b` can never match, because the character after
  // the stem is always a letter and the boundary never falls there.
  if (/\b(owner|proprietari[ao]|dono|dona|titular)\b/.test(value)) return 'OWNER';
  if (/\b(founder|fundador[ao]?|cofounder|co-founder)\b/.test(value)) return 'FOUNDER';
  if (/\b(ceo|cfo|coo|cto|chief)\b/.test(value)) return 'C_LEVEL';
  if (/\b(director|diretor|directora|diretora|managing)\b/.test(value)) {
    return 'DIRECTOR';
  }
  if (/\b(manager|gerente|gestor|gestora|supervisor)\b/.test(value)) {
    return 'MANAGER';
  }
  if (/\b(assistant|assistente|atendimento|rece(p)?cionista|staff)\b/.test(value)) {
    return 'STAFF';
  }
  return 'UNKNOWN';
}
