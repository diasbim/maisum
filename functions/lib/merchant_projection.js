"use strict";
/**
 * Projects a Firestore `businesses/{merchantId}` document onto the PostgreSQL
 * `merchants` read model.
 *
 * Firestore is authoritative — it is what the mobile app writes and what the
 * onboarding flow creates. The `merchants` table existed with no writer at all,
 * which is why every read surface built on it came back empty. This is that
 * missing writer.
 *
 * The mapping is not a rename. Three things differ between the two sides and
 * each can make a document unprojectable:
 *
 *  - the name lives under `merchant_name` in Firestore and `name` in SQL;
 *  - `merchants.phone` is `NOT NULL UNIQUE`, while a Firestore business may
 *    carry no phone at all, and two may carry the same one;
 *  - `merchants.name` is `NOT NULL`, while onboarding can save a draft before
 *    the business has been named.
 *
 * Deciding all of that here, as a pure function, keeps it testable and keeps
 * the trigger and the backfill from drifting into two different answers.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SKIP_EXPLANATIONS = void 0;
exports.projectBusinessToMerchant = projectBusinessToMerchant;
function readString(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string') {
            const trimmed = value.trim();
            if (trimmed.length > 0)
                return trimmed;
        }
    }
    return null;
}
function readNumber(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
        if (typeof value === 'string') {
            const parsed = Number(value.trim());
            if (Number.isFinite(parsed))
                return parsed;
        }
    }
    return null;
}
/**
 * Builds the row for one business document, or explains why it cannot be built.
 *
 * `now` is injected so the caller decides the fallback timestamp; a projection
 * run must not invent a different `created_at` on every retry.
 */
function projectBusinessToMerchant(merchantId, data, now) {
    const id = typeof merchantId === 'string' ? merchantId.trim() : '';
    if (id.length === 0) {
        return {
            status: 'skipped',
            reason: 'missing_merchant_id',
            detail: 'The document path carries no merchant id.',
        };
    }
    const record = data ?? {};
    // Firestore names this `merchant_name`. Falling back to `name` covers
    // documents written before that field settled.
    const name = readString(record, 'merchant_name', 'name');
    if (name == null) {
        return {
            status: 'skipped',
            reason: 'missing_name',
            detail: 'Business has no name yet; merchants.name is NOT NULL.',
        };
    }
    // A business saved mid-onboarding may have no phone. The column is NOT NULL
    // and UNIQUE, so there is nothing sensible to substitute — a placeholder
    // would collide with the next such business and claim the row.
    const phone = readString(record, 'phone');
    if (phone == null) {
        return {
            status: 'skipped',
            reason: 'missing_phone',
            detail: 'Business has no phone; merchants.phone is NOT NULL UNIQUE.',
        };
    }
    const createdAt = readNumber(record, 'created_at') ?? now;
    const updatedAt = readNumber(record, 'updated_at') ?? createdAt;
    return {
        status: 'ready',
        row: {
            id,
            name,
            phone,
            created_at: createdAt,
            // A row that has never been updated still needs a sortable timestamp;
            // the merchant list orders by this column.
            updated_at: updatedAt,
        },
    };
}
/**
 * Human-readable summary of why a document was skipped, for the backfill
 * report. The operator running it needs to know whether a missing business is
 * a bug or just an unfinished sign-up.
 */
exports.SKIP_EXPLANATIONS = {
    missing_merchant_id: 'Documento sem identificador.',
    missing_name: 'Negócio ainda sem nome — registo incompleto.',
    missing_phone: 'Negócio sem telefone — registo incompleto.',
};
