/**
 * One business, once — before anyone pays for its details.
 *
 * A real run for "barbershop em Maputo" discovered the same shop three times,
 * written with three different apostrophes, and paid the dear second-stage
 * call for all three. Three of five paid calls bought one phone number. The
 * money is the visible half of the damage; the invisible half is that those
 * three slots were taken from businesses that were never contacted.
 *
 * So this runs between discovery and the spend gate, and nowhere else. After
 * the gate is too late — the calls are already made — and inside the scoring
 * engine is the wrong place, because a duplicate is not a low-quality lead.
 * It is the same lead.
 *
 * Two listings are the same business when their source reference matches, or
 * when their folded names match *and* they stand within a short walk of each
 * other. Name alone is not enough: "Barbearia Central" is a name several
 * unrelated shops choose. Distance alone is not enough either — a barbershop
 * and a pharmacy share a building.
 */

import { normalizeMatchName, normalizeCompanyName } from './prospecting_normalization.js';

/* ------------------------------------------------------------------ types */

/** What deduplication needs to know about a candidate. Deliberately little. */
export type DedupCandidate = {
  /** The provider's own id. An exact match here is decisive. */
  sourceReference: string | null;
  name: string;
  reviewCount: number | null;
  latitude: number | null;
  longitude: number | null;
};

export const DUPLICATE_REASON = [
  'SAME_SOURCE_REFERENCE',
  'SAME_NAME_NEARBY',
  'SAME_NAME_NO_LOCATION',
] as const;

export type DuplicateReason = (typeof DUPLICATE_REASON)[number];

export const DUPLICATE_REASON_LABEL: Record<DuplicateReason, string> = {
  SAME_SOURCE_REFERENCE: 'mesma referência do fornecedor',
  SAME_NAME_NEARBY: 'mesmo nome, a poucos metros',
  SAME_NAME_NO_LOCATION: 'mesmo nome, sem coordenadas para confirmar',
};

export type DuplicateRecord<T> = {
  candidate: T;
  /** The candidate that was kept instead. */
  duplicateOf: T;
  reason: DuplicateReason;
};

export type DedupResult<T> = {
  kept: readonly T[];
  duplicates: readonly DuplicateRecord<T>[];
};

/** Metres. A storefront and its own second listing are not further than this. */
export const DEFAULT_DEDUP_RADIUS_METRES = 150;

/* --------------------------------------------------------------- distance */

const EARTH_RADIUS_METRES = 6_371_000;

const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;

/**
 * Great-circle distance, in metres.
 *
 * Haversine rather than a flat approximation. Not for the accuracy at 150 m,
 * where either would do, but because a flat approximation needs a latitude
 * correction that is easy to forget and fails quietly far from the equator.
 */
export function distanceMetres(
  from: { latitude: number; longitude: number },
  to: { latitude: number; longitude: number },
): number {
  const deltaLat = toRadians(to.latitude - from.latitude);
  const deltaLon = toRadians(to.longitude - from.longitude);
  const a =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(toRadians(from.latitude)) *
      Math.cos(toRadians(to.latitude)) *
      Math.sin(deltaLon / 2) ** 2;
  return 2 * EARTH_RADIUS_METRES * Math.asin(Math.min(1, Math.sqrt(a)));
}

/* ------------------------------------------------------------ the folding */

/**
 * The key two listings must share to be considered the same business.
 *
 * Falls back to the full folded name when the trade-word-stripped form is
 * empty, so a shop called nothing but "Barber Shop" keeps a key of its own
 * instead of merging with every other shop called "Barber Shop".
 */
export function matchName(name: string): string {
  const stripped = normalizeMatchName(name);
  return stripped !== '' ? stripped : normalizeCompanyName(name);
}

/** A candidate's position, or null when either half is missing. */
function pointOf(
  candidate: DedupCandidate,
): { latitude: number; longitude: number } | null {
  const { latitude, longitude } = candidate;
  if (latitude === null || longitude === null) return null;
  return { latitude, longitude };
}

/* ------------------------------------------------------------------ dedup */

/**
 * Which of two listings of one business to keep.
 *
 * The one with more reviews. Not the first: the API's order is not a ranking
 * anyone chose, and in the run that prompted this it put the least-reviewed
 * copy first. A listing with a review count beats one with none, because
 * `null` here means the source said nothing, not that the shop has no
 * reviews.
 */
function betterOf<T extends DedupCandidate>(left: T, right: T): T {
  const leftCount = left.reviewCount ?? -1;
  const rightCount = right.reviewCount ?? -1;
  if (leftCount !== rightCount) return leftCount > rightCount ? left : right;
  // Stable on ties, so two runs over the same page keep the same one.
  return left;
}

/**
 * Collapse listings of the same business, keeping the best-evidenced one.
 *
 * `reason` is carried out rather than logged away, because the operator
 * looking at a shorter list than the one the provider returned is owed the
 * arithmetic — and because `SAME_NAME_NO_LOCATION` is a weaker claim than the
 * other two and should be visible as such.
 */
export function dedupeCandidates<T extends DedupCandidate>(
  candidates: readonly T[],
  options: { radiusMetres?: number } = {},
): DedupResult<T> {
  const radius = options.radiusMetres ?? DEFAULT_DEDUP_RADIUS_METRES;

  const kept: T[] = [];
  const duplicates: DuplicateRecord<T>[] = [];

  for (const candidate of candidates) {
    const key = matchName(candidate.name);

    let matchedIndex = -1;
    let reason: DuplicateReason | null = null;

    for (let index = 0; index < kept.length; index++) {
      const existing = kept[index];

      if (
        candidate.sourceReference !== null &&
        existing.sourceReference !== null &&
        candidate.sourceReference === existing.sourceReference
      ) {
        matchedIndex = index;
        reason = 'SAME_SOURCE_REFERENCE';
        break;
      }

      if (key === '' || matchName(existing.name) !== key) continue;

      const here = pointOf(candidate);
      const there = pointOf(existing);

      if (here === null || there === null) {
        // Name alone. Weaker, and named as such so the report can say so.
        matchedIndex = index;
        reason = 'SAME_NAME_NO_LOCATION';
        break;
      }

      const apart = distanceMetres(here, there);
      if (apart <= radius) {
        matchedIndex = index;
        reason = 'SAME_NAME_NEARBY';
        break;
      }
    }

    if (matchedIndex === -1 || reason === null) {
      kept.push(candidate);
      continue;
    }

    const existing = kept[matchedIndex];
    const winner = betterOf(existing, candidate);
    const loser = winner === existing ? candidate : existing;
    kept[matchedIndex] = winner;
    duplicates.push({ candidate: loser, duplicateOf: winner, reason });
  }

  return { kept, duplicates };
}

/* ------------------------------------------- the second pass, after detail */

/**
 * What a paid detail call revealed, folded to a comparison key.
 *
 * The first pass works on names and coordinates because that is all the cheap
 * search returns. A chain that lists each branch under its own name and one
 * central phone number survives it, and is only detectable once the dear call
 * has been made. That call cannot be un-bought — but the *next* one can be
 * spent on a different business instead, which is what the caller does with
 * this.
 */
export type ContactFingerprint = {
  phone: string | null;
  domain: string | null;
};

export class SeenContacts {
  private readonly phones = new Set<string>();
  private readonly domains = new Set<string>();

  /**
   * Records the fingerprint and says whether it had been seen before.
   *
   * Records either way. A second sighting is still a sighting, and a caller
   * that skipped the recording would let a third copy through.
   */
  observe(fingerprint: ContactFingerprint): {
    duplicate: boolean;
    by: 'phone' | 'domain' | null;
  } {
    const phone = fingerprint.phone;
    const domain = fingerprint.domain;

    const phoneSeen = phone !== null && this.phones.has(phone);
    const domainSeen = domain !== null && this.domains.has(domain);

    if (phone !== null) this.phones.add(phone);
    if (domain !== null) this.domains.add(domain);

    if (phoneSeen) return { duplicate: true, by: 'phone' };
    if (domainSeen) return { duplicate: true, by: 'domain' };
    return { duplicate: false, by: null };
  }
}
