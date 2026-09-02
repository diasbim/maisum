import * as admin from 'firebase-admin';

/**
 * The administrative audit trail.
 *
 * This was the one thing the console needed that had no home in Firestore: it
 * was written only to PostgreSQL, which was never connected. Without it there
 * is no record of who changed what — and the whole reason the portal forwards
 * each operator's own token, rather than holding a credential of its own, is so
 * that record can name a person.
 *
 * Top-level collection rather than per-business: an entry may concern no
 * business at all (a plan edit), and "everything an operator did" has to be
 * answerable without walking every business.
 */

export const ADMIN_AUDIT_COLLECTION = 'admin_audit_events';

export type AuditActor = {
  appUserId: string | null;
  firebaseUid: string | null;
  role: string | null;
};

export type AuditEntry = {
  action: string;
  targetType: string;
  targetId: string | null;
  merchantId: string | null;
  details: Record<string, unknown>;
};

/**
 * Strips values Firestore cannot store, and anything unbounded.
 *
 * `details` carries before/after snapshots, which are whatever the caller had
 * in hand. `undefined` is rejected by Firestore outright, and an oversized blob
 * would make the audit collection expensive to read for the one field that
 * matters. Both are handled here rather than at each call site.
 */
export function sanitizeDetails(
  details: Record<string, unknown>,
  maxBytes = 8000,
): Record<string, unknown> {
  const cleaned = JSON.parse(
    JSON.stringify(details ?? {}, (_key, value: unknown) =>
      value === undefined ? null : value,
    ),
  ) as Record<string, unknown>;

  const encoded = JSON.stringify(cleaned);
  if (encoded.length <= maxBytes) return cleaned;

  return {
    truncated: true,
    reason: `Detalhe com ${encoded.length} bytes excedeu o limite de ${maxBytes}.`,
    preview: encoded.slice(0, 1000),
  };
}

/**
 * Records one administrative action.
 *
 * Deliberately never throws. An audit write failing must not roll back the
 * change it describes — the operator would see an error, retry, and apply the
 * change twice. A failure here is logged loudly instead, which is the
 * behaviour that keeps the console honest without making it fragile.
 */
export async function recordAuditEvent(
  actor: AuditActor,
  entry: AuditEntry,
): Promise<string | null> {
  const now = Date.now();
  const id = `${now}_${Math.random().toString(36).slice(2, 10)}`;

  try {
    await admin
      .firestore()
      .collection(ADMIN_AUDIT_COLLECTION)
      .doc(id)
      .set({
        id,
        action: entry.action,
        target_type: entry.targetType,
        target_id: entry.targetId,
        merchant_id: entry.merchantId,
        actor_app_user_id: actor.appUserId,
        actor_firebase_uid: actor.firebaseUid,
        actor_role: actor.role,
        details: sanitizeDetails(entry.details),
        created_at: now,
      });
    return id;
  } catch (error) {
    console.error('admin_audit_write_failed', {
      action: entry.action,
      target_id: entry.targetId,
      message: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

export type AuditQuery = {
  merchantId?: string;
  targetType?: string;
  action?: string;
  limit: number;
  offset: number;
};

/**
 * Reads the trail, newest first.
 *
 * Filters are applied in memory over a bounded window rather than in the
 * query, so no composite index has to exist before the console works. The
 * window is generous and the trail is small by nature — it grows only when an
 * operator does something.
 */
export const AUDIT_SCAN_CAP = 2000;

export async function listAuditEvents(
  query: AuditQuery,
): Promise<{
  items: Array<Record<string, unknown>>;
  hasMore: boolean;
  truncated: boolean;
}> {
  const snapshot = await admin
    .firestore()
    .collection(ADMIN_AUDIT_COLLECTION)
    .orderBy('created_at', 'desc')
    .limit(AUDIT_SCAN_CAP + 1)
    .get();

  const truncated = snapshot.size > AUDIT_SCAN_CAP;
  const docs = truncated ? snapshot.docs.slice(0, AUDIT_SCAN_CAP) : snapshot.docs;

  const filtered = docs
    .map((doc) => doc.data() as Record<string, unknown>)
    .filter((event) => {
      if (query.merchantId && event.merchant_id !== query.merchantId) {
        return false;
      }
      if (query.targetType && event.target_type !== query.targetType) {
        return false;
      }
      if (query.action && event.action !== query.action) return false;
      return true;
    });

  const items = filtered.slice(query.offset, query.offset + query.limit);
  return {
    items,
    hasMore: query.offset + items.length < filtered.length,
    truncated,
  };
}
