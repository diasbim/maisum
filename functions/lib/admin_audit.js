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
exports.AUDIT_SCAN_CAP = exports.ADMIN_AUDIT_COLLECTION = void 0;
exports.sanitizeDetails = sanitizeDetails;
exports.recordAuditEvent = recordAuditEvent;
exports.listAuditEvents = listAuditEvents;
const admin = __importStar(require("firebase-admin"));
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
exports.ADMIN_AUDIT_COLLECTION = 'admin_audit_events';
/**
 * Strips values Firestore cannot store, and anything unbounded.
 *
 * `details` carries before/after snapshots, which are whatever the caller had
 * in hand. `undefined` is rejected by Firestore outright, and an oversized blob
 * would make the audit collection expensive to read for the one field that
 * matters. Both are handled here rather than at each call site.
 */
function sanitizeDetails(details, maxBytes = 8000) {
    const cleaned = JSON.parse(JSON.stringify(details ?? {}, (_key, value) => value === undefined ? null : value));
    const encoded = JSON.stringify(cleaned);
    if (encoded.length <= maxBytes)
        return cleaned;
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
async function recordAuditEvent(actor, entry) {
    const now = Date.now();
    const id = `${now}_${Math.random().toString(36).slice(2, 10)}`;
    try {
        await admin
            .firestore()
            .collection(exports.ADMIN_AUDIT_COLLECTION)
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
    }
    catch (error) {
        console.error('admin_audit_write_failed', {
            action: entry.action,
            target_id: entry.targetId,
            message: error instanceof Error ? error.message : String(error),
        });
        return null;
    }
}
/**
 * Reads the trail, newest first.
 *
 * Filters are applied in memory over a bounded window rather than in the
 * query, so no composite index has to exist before the console works. The
 * window is generous and the trail is small by nature — it grows only when an
 * operator does something.
 */
exports.AUDIT_SCAN_CAP = 2000;
async function listAuditEvents(query) {
    const snapshot = await admin
        .firestore()
        .collection(exports.ADMIN_AUDIT_COLLECTION)
        .orderBy('created_at', 'desc')
        .limit(exports.AUDIT_SCAN_CAP + 1)
        .get();
    const truncated = snapshot.size > exports.AUDIT_SCAN_CAP;
    const docs = truncated ? snapshot.docs.slice(0, exports.AUDIT_SCAN_CAP) : snapshot.docs;
    const filtered = docs
        .map((doc) => doc.data())
        .filter((event) => {
        if (query.merchantId && event.merchant_id !== query.merchantId) {
            return false;
        }
        if (query.targetType && event.target_type !== query.targetType) {
            return false;
        }
        if (query.action && event.action !== query.action)
            return false;
        return true;
    });
    const items = filtered.slice(query.offset, query.offset + query.limit);
    return {
        items,
        hasMore: query.offset + items.length < filtered.length,
        truncated,
    };
}
