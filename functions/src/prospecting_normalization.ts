/**
 * Turning what a provider said into something two records can be compared on.
 *
 * Deduplication is the module's most consequential rule — criterion 9 is a
 * test that no company is ever stored twice — and every one of its five match
 * keys is a normalisation. So the normalisers live here, pure and alone, and
 * the store does nothing but look up what these functions return.
 *
 * A note on the phone normaliser, because there is already one in the product.
 * `tryNormalizeMozambiquePhoneToE164` in index.ts accepts mobile prefixes
 * 82–87 and nothing else, which is correct for its job: it identifies a
 * customer, and a customer of a barbershop has a mobile. A business has a
 * landline, and `+258 21 xxx xxx` is exactly the number printed on a salon's
 * window. Sending a business number through the customer normaliser would
 * return null and cost the module its third match key, so this one is
 * deliberately wider — it normalises rather than validates a subscriber, and
 * it takes the country code from configuration rather than assuming
 * Mozambique.
 */

/* ----------------------------------------------------------------- domain */

/**
 * The host, and only the host.
 *
 * `https://Barbearia-X.co.mz/?utm_source=ig` and
 * `http://www.barbearia-x.co.mz` are the same company, so the scheme, the
 * `www.`, the port, the path, the query and the fragment all go. What stays is
 * lowercase and punycode-free enough to be a document id.
 *
 * Returns null rather than a best effort for anything that is not a host: an
 * empty string would collide every company that has no website onto one
 * lookup document, which is the one failure mode that would merge unrelated
 * businesses rather than merely miss a duplicate.
 */
export function normalizeDomain(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  let value = raw.trim().toLowerCase();
  if (value === '') return null;

  // A bare domain has no scheme, and URL() refuses it. Adding one is cheaper
  // than hand-parsing, and it is what makes "barbearia-x.co.mz" and
  // "https://barbearia-x.co.mz/sobre" fold to the same string.
  if (!/^[a-z][a-z0-9+.-]*:\/\//.test(value)) value = `https://${value}`;

  let host: string;
  try {
    host = new URL(value).hostname;
  } catch {
    return null;
  }

  host = host.replace(/^www\./, '').replace(/\.$/, '');
  if (host === '') return null;

  // A host has at least one dot and no spaces. "localhost" and a stray label
  // typed into the website field are not domains, and treating them as ones
  // would give every such company the same match key.
  if (!/^[a-z0-9.-]+\.[a-z]{2,}$/.test(host)) return null;

  return host;
}

/* ------------------------------------------------------------------ phone */

/**
 * E.164, using the configured country code for a local number.
 *
 * Everything that is not a digit or a leading plus is dropped first, so
 * `+258 84 123 4567`, `084 123 4567` and `(+258) 84-123-4567` all land on
 * `+258841234567`. A number that already carries a country code keeps it: a
 * Portuguese owner's `+351` number is not rewritten to Mozambique just because
 * that is where the shop is.
 *
 * The leading zero of a local number is a trunk prefix, not part of the
 * subscriber number, and is dropped before the country code is applied.
 */
export function normalizePhone(
  raw: unknown,
  countryCode: string,
): string | null {
  if (typeof raw !== 'string') return null;

  const trimmed = raw.trim();
  if (trimmed === '') return null;

  // `00` is the other way of writing `+`, and it is how a number is printed on
  // a sign in Maputo as often as not.
  const international = /^(\+|00)/.test(trimmed);
  const digits = trimmed.replace(/\D/g, '');
  if (digits === '') return null;

  const cc = countryCode.replace(/\D/g, '');
  if (cc === '') return null;

  let subscriber: string;
  if (international) {
    subscriber = digits.replace(/^00/, '');
  } else if (digits.startsWith(cc) && digits.length > cc.length + 5) {
    // Written without a plus but with the country code — common when a number
    // is copied out of a spreadsheet. The length guard keeps a local number
    // that merely begins with the same digits from being mistaken for one.
    subscriber = digits;
  } else {
    subscriber = `${cc}${digits.replace(/^0+/, '')}`;
  }

  // Shorter than this is a short code or a typo, longer than this is not a
  // phone number at all. E.164 caps the whole thing at 15 digits.
  if (subscriber.length < 8 || subscriber.length > 15) return null;

  return `+${subscriber}`;
}

/* ------------------------------------------------------------------- name */

/**
 * Legal forms, which say nothing about which business this is.
 *
 * Mozambique uses the Portuguese set. `EI` is the sole-trader form and is
 * short enough to appear inside a real name, so it is only stripped as a whole
 * word at the end, like the rest.
 *
 * "E Filhos" and "E Irmãos" are deliberately absent. They read like legal
 * forms and are not: "Silva & Filhos" is the name of the business, and a
 * normaliser that stripped them would fold it onto "Silva" — and onto every
 * other Silva in Maputo with it. The test for the ampersand is the one that
 * catches this if anyone adds them back.
 */
const LEGAL_SUFFIXES = [
  'lda',
  'limitada',
  'sa',
  'sarl',
  'ei',
  'eirl',
  'unipessoal',
  'sociedade unipessoal',
];

/**
 * A company name, folded to what makes it that company.
 *
 * Accents go, because a provider writes "Salao Beleza" and a person writes
 * "Salão Beleza". Punctuation goes. Legal suffixes go, repeatedly — "Barbearia
 * X, Lda. Unipessoal" has two. Runs of whitespace collapse.
 *
 * Returns an empty string for a name that folds to nothing, and callers treat
 * that as "no name key" rather than as a key. The store never builds a lookup
 * document from an empty value, for the same reason the domain normaliser
 * refuses one.
 */
export function normalizeCompanyName(raw: unknown): string {
  if (typeof raw !== 'string') return '';

  let value = raw
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    // Ampersand is a word in a name; the rest of the punctuation is not.
    .replace(/&/g, ' e ')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Repeatedly, because a name can carry more than one suffix, and because
  // stripping "lda" off "barbearia x lda unipessoal" only helps if the pass
  // runs again afterwards.
  let changed = true;
  while (changed) {
    changed = false;
    for (const suffix of LEGAL_SUFFIXES) {
      if (value === suffix) {
        // The whole name was a legal form. There is nothing left to match on,
        // and returning "" is more honest than returning the suffix.
        return '';
      }
      if (value.endsWith(` ${suffix}`)) {
        value = value.slice(0, -(suffix.length + 1)).trim();
        changed = true;
      }
    }
  }

  return value;
}

/**
 * Words that describe the trade rather than name the business.
 *
 * Dropped only when comparing two listings. "Tsemeta Barbershop" and
 * "Tsemeta Barber Shop" are one business written two ways, and the trade word
 * is the part that varies.
 */
export const GENERIC_NAME_TOKENS: readonly string[] = [
  'barber',
  'barbers',
  'barbershop',
  'barbearia',
  'shop',
  'studio',
  'salon',
  'salao',
  'hair',
  'cabeleireiro',
  'spa',
  'clinic',
  'clinica',
];

/**
 * A company name folded down to what distinguishes it from its neighbours.
 *
 * Built on `normalizeCompanyName`, which already strips accents, punctuation
 * and legal suffixes — and, as a consequence, already collapses every
 * apostrophe variant, since `'`, `’`, `´` and `` ` `` are all punctuation to
 * it. This adds two things.
 *
 * NFKD rather than NFD, so compatibility forms fold too: a provider that
 * returns a ligature or a fullwidth letter should not read as a different
 * business.
 *
 * The trade words go, because they are the part that varies between two
 * writings of one shop. That makes matching looser, which is why the caller
 * must also require the two listings to be close together — this string on
 * its own would merge every unrelated "Barbearia Central" in the city.
 *
 * Returns `''` when a name is nothing but trade words. The caller treats that
 * as "no comparison key" and falls back to the full folded name, because
 * merging every shop called "Barber Shop" into one lead would be a bug that
 * silently costs the operator real businesses.
 */
export function normalizeMatchName(raw: unknown): string {
  if (typeof raw !== 'string') return '';

  const folded = normalizeCompanyName(
    raw.normalize('NFKD').replace(/\p{M}/gu, ''),
  );
  if (folded === '') return '';

  const kept = folded
    .split(' ')
    .filter((token) => token !== '' && !GENERIC_NAME_TOKENS.includes(token));

  return kept.join(' ');
}

/** The name key is only distinguishing together with a place. */
export function normalizeCity(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/* ------------------------------------------------------------------ social */

/**
 * A social profile, reduced to the network and the handle.
 *
 * Instagram alone serves the same profile at four URLs — with and without
 * `www.`, with and without a trailing slash, with a query string appended by
 * whatever shared it, and under `/p/` for a post rather than the profile. Only
 * the first path segment identifies the account, so that is what is kept.
 *
 * Returns null for a URL with no path, which is a link to the network rather
 * than to anyone on it.
 */
export function normalizeSocialUrl(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  let value = raw.trim().toLowerCase();
  if (value === '') return null;
  if (!/^[a-z][a-z0-9+.-]*:\/\//.test(value)) value = `https://${value}`;

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }

  const host = url.hostname.replace(/^www\./, '');
  const segments = url.pathname.split('/').filter((part) => part !== '');
  if (segments.length === 0) return null;

  // LinkedIn company pages live at /company/<slug>; everything else worth
  // matching on is at the root. Keeping two segments for LinkedIn and one
  // elsewhere is the difference between matching a company and matching the
  // word "company".
  const handle =
    host.endsWith('linkedin.com') && segments.length >= 2
      ? `${segments[0]}/${segments[1]}`
      : segments[0];

  return `${host}/${handle}`;
}

/* -------------------------------------------------------------- match keys */

/**
 * The five ways two records can be the same company, in the order they are
 * tried.
 *
 * Order is confidence. A provider's own organisation id is the provider saying
 * these are one record; a domain is near-certain; a phone is strong but a
 * shared switchboard exists; a name plus a city is a guess that is right often
 * enough to be worth making and wrong often enough to be last but one; a
 * social profile catches the shop that has Instagram and nothing else.
 */
export const MATCH_KIND = [
  'PROVIDER_ORG',
  'DOMAIN',
  'PHONE',
  'NAME_CITY',
  'SOCIAL',
] as const;
export type MatchKind = (typeof MATCH_KIND)[number];

export type MatchKey = { kind: MatchKind; value: string };

export type CompanyIdentity = {
  name?: string | null;
  city?: string | null;
  domain?: string | null;
  website?: string | null;
  phone?: string | null;
  whatsapp?: string | null;
  providerOrgId?: string | null;
  provider?: string | null;
  linkedinUrl?: string | null;
  instagramUrl?: string | null;
  facebookUrl?: string | null;
};

/**
 * Every key a company can be matched on, strongest first.
 *
 * Absent inputs produce no key rather than an empty one — a company with no
 * website contributes no `DOMAIN` key, and so cannot collide with another
 * company that has no website either. That is the single most important
 * property of this function: **a missing value never matches a missing value.**
 *
 * The provider id is namespaced by the provider, because Apollo's org id and
 * some other provider's are different identifier spaces that would otherwise
 * be compared as strings.
 */
export function buildMatchKeys(
  identity: CompanyIdentity,
  phoneCountryCode: string,
): MatchKey[] {
  const keys: MatchKey[] = [];
  const seen = new Set<string>();

  const push = (kind: MatchKind, value: string | null) => {
    if (value === null || value === '') return;
    const composed = `${kind}:${value}`;
    if (seen.has(composed)) return;
    seen.add(composed);
    keys.push({ kind, value });
  };

  const provider = (identity.provider ?? '').trim().toLowerCase();
  const orgId = (identity.providerOrgId ?? '').trim();
  if (provider !== '' && orgId !== '') push('PROVIDER_ORG', `${provider}/${orgId}`);

  push('DOMAIN', normalizeDomain(identity.domain ?? identity.website ?? null));

  push('PHONE', normalizePhone(identity.phone, phoneCountryCode));
  push('PHONE', normalizePhone(identity.whatsapp, phoneCountryCode));

  const name = normalizeCompanyName(identity.name);
  const city = normalizeCity(identity.city);
  // Both halves are required. A name with no city is not distinguishing in a
  // dataset that will eventually hold every barbershop in the country, and a
  // city with no name is not a company at all.
  if (name !== '' && city !== '') push('NAME_CITY', `${name}@${city}`);

  push('SOCIAL', normalizeSocialUrl(identity.linkedinUrl));
  push('SOCIAL', normalizeSocialUrl(identity.instagramUrl));
  push('SOCIAL', normalizeSocialUrl(identity.facebookUrl));

  return keys;
}

/**
 * The document id a match key is stored under.
 *
 * Firestore has no unique index, so uniqueness is a property of a document id
 * that two writers would collide on — the same device `affiliate_code_lookup`
 * uses. The key is hashed rather than used raw because a normalised value can
 * contain a slash, which is a path separator, and because a document id is
 * capped at 1 500 bytes while a URL is not.
 */
export function matchKeyDocId(key: MatchKey): string {
  return `${key.kind.toLowerCase()}_${fnv1a(key.value)}`;
}

/**
 * A short, stable, non-cryptographic digest.
 *
 * FNV-1a rather than SHA-256 because this is a lookup id, not a secret: it
 * never protects anything, and a 64-bit digest written in base36 is short
 * enough to read in a Firestore console while collisions across even a
 * national dataset stay vanishingly unlikely. The store reads the stored
 * `value` back and compares it, so a collision would be caught rather than
 * silently merging two companies.
 */
export function fnv1a(value: string): string {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (let index = 0; index < value.length; index++) {
    hash = (hash ^ BigInt(value.charCodeAt(index))) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toString(36);
}
