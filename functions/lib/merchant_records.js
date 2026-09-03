"use strict";
/**
 * Shaping the business's own operational records for the web.
 *
 * These documents are written by the mobile app, which syncs SQLite rows
 * straight up: snake_case keys, epoch milliseconds for times, and booleans
 * stored as 0/1 integers (`is_active`, `active`, `synced`). A web client that
 * assumed JSON-shaped values would read every inactive item as active, so
 * every field goes through a normaliser here rather than being passed along
 * as it was stored.
 *
 * Kept free of firebase-admin on purpose: this is the part worth testing, and
 * `merchant_collections.ts` is the part that talks to Firestore.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.asString = asString;
exports.asNumber = asNumber;
exports.asBool = asBool;
exports.asEpoch = asEpoch;
exports.toCustomer = toCustomer;
exports.toCatalogItem = toCatalogItem;
exports.toReward = toReward;
exports.toSale = toSale;
exports.sortSales = sortSales;
exports.toStaff = toStaff;
exports.fold = fold;
exports.matchesSearch = matchesSearch;
exports.capDocuments = capDocuments;
exports.paginate = paginate;
exports.selectCustomers = selectCustomers;
exports.selectCatalog = selectCatalog;
exports.selectRewards = selectRewards;
exports.selectStaff = selectStaff;
/* --------------------------------------------------------------- normalisers */
function asString(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'string' && value.trim() !== '')
            return value.trim();
    }
    return null;
}
function asNumber(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'number' && Number.isFinite(value))
            return value;
        if (typeof value === 'string' && value.trim() !== '') {
            const parsed = Number(value);
            if (Number.isFinite(parsed))
                return parsed;
        }
    }
    return null;
}
/**
 * A flag as the app stores it.
 *
 * `1`/`0` is the SQLite spelling and by far the common case; real booleans
 * arrive from documents the backend wrote. Anything else is unknown rather
 * than false — a missing flag should not read as "disabled" on a screen that
 * lists what a business sells.
 */
function asBool(data, ...keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === 'boolean')
            return value;
        if (typeof value === 'number' && Number.isFinite(value))
            return value !== 0;
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            if (normalized === 'true' || normalized === '1')
                return true;
            if (normalized === 'false' || normalized === '0')
                return false;
        }
    }
    return null;
}
/** Epoch milliseconds, rejecting the zero the app writes for "never". */
function asEpoch(data, ...keys) {
    const value = asNumber(data, ...keys);
    return value !== null && value > 0 ? value : null;
}
function toCustomer(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        phone: asString(data, 'phone'),
        total_points: asNumber(data, 'total_points') ?? 0,
        total_visits: asNumber(data, 'total_visits') ?? 0,
        total_spent: asNumber(data, 'total_spent') ?? 0,
        average_spend: asNumber(data, 'average_spend'),
        lifecycle_stage: asString(data, 'lifecycle_stage'),
        retention_status: asString(data, 'retention_status'),
        relationship_status: asString(data, 'relationship_status'),
        first_visit_at: asEpoch(data, 'first_visit_at'),
        last_visit_at: asEpoch(data, 'last_visit_at'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
        archived_at: asEpoch(data, 'archived_at'),
    };
}
function toCatalogItem(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        type: asString(data, 'type'),
        default_price: asNumber(data, 'default_price'),
        is_active: asBool(data, 'is_active', 'active'),
        display_order: asNumber(data, 'display_order') ?? 0,
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
function toReward(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        name: asString(data, 'name'),
        description: asString(data, 'description'),
        points_required: asNumber(data, 'points_required'),
        // The app's reward model calls the flag `active`; `is_active` is the
        // spelling every other collection uses, so both are accepted.
        is_active: asBool(data, 'active', 'is_active'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
    };
}
/**
 * One sale on a customer's history.
 *
 * The two status fields are carried through rather than collapsed into a
 * single "state": a cancelled sale is still a row in this collection, and
 * dropping it would make the customer's points stop adding up while showing it
 * plainly would overstate how often they came.
 */
function toSale(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        amount: asNumber(data, 'amount'),
        points: asNumber(data, 'points'),
        created_at: asEpoch(data, 'created_at'),
        cancellation_status: asString(data, 'cancellation_status'),
        confirmation_status: asString(data, 'confirmation_status'),
    };
}
/** Newest first. A sale with no date sorts last rather than as 1970. */
function sortSales(rows) {
    return [...rows].sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0));
}
function toStaff(id, data) {
    return {
        id: asString(data, 'id') ?? id,
        phone: asString(data, 'phone'),
        role: asString(data, 'role'),
        status: asString(data, 'status'),
        created_at: asEpoch(data, 'created_at'),
        updated_at: asEpoch(data, 'updated_at'),
        last_login_at: asEpoch(data, 'last_login_at'),
    };
}
/** Case- and accent-insensitive, so "Joao" finds "João". */
function fold(value) {
    return value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim();
}
function matchesSearch(fields, search) {
    const needle = fold(search);
    if (needle === '')
        return true;
    return fields.some((value) => value !== null && fold(value).includes(needle));
}
/**
 * Cuts a read down to the cap and says whether anything was cut.
 *
 * The caller reads `cap + 1` documents so that "exactly at the cap" and "one
 * past it" are distinguishable — otherwise a business with exactly 2000
 * customers would be told its list is incomplete when it is not.
 */
function capDocuments(docs, cap) {
    const truncated = docs.length > cap;
    return { docs: truncated ? docs.slice(0, cap) : docs, truncated };
}
function paginate(rows, query) {
    const offset = Math.max(0, query.offset);
    const limit = Math.max(1, query.limit);
    const items = rows.slice(offset, offset + limit);
    return {
        items,
        hasMore: offset + items.length < rows.length,
        total: rows.length,
    };
}
/**
 * The customer list, ordered the way the counter thinks about it.
 *
 * Most recent visit first, because the question behind this screen is usually
 * "who was just here". Customers who have never visited fall to the bottom in
 * name order rather than in whatever order Firestore returned them.
 */
function selectCustomers(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.name, row.phone, row.id], search)) {
            return false;
        }
        if (status !== '') {
            // A document written before the field existed is an active customer,
            // which is what the app assumes too.
            const value = (row.relationship_status ?? 'ACTIVE').toUpperCase();
            if (value !== status)
                return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byVisit = (b.last_visit_at ?? 0) - (a.last_visit_at ?? 0);
        if (byVisit !== 0)
            return byVisit;
        return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
    });
    return paginate(sorted, query);
}
/** The catalogue, in the order the app shows it at the till. */
function selectCatalog(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.name, row.id], search))
            return false;
        if (status === 'ACTIVE' && row.is_active === false)
            return false;
        if (status === 'INACTIVE' && row.is_active !== false)
            return false;
        if (status === 'PRODUCT' || status === 'SERVICE') {
            if ((row.type ?? '').toUpperCase() !== status)
                return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byOrder = a.display_order - b.display_order;
        if (byOrder !== 0)
            return byOrder;
        return (a.name ?? a.id).localeCompare(b.name ?? b.id, 'pt');
    });
    return paginate(sorted, query);
}
/** Rewards, cheapest first: that is the one a customer reaches next. */
function selectRewards(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const filtered = rows.filter((row) => {
        if (search !== '' &&
            !matchesSearch([row.name, row.description, row.id], search)) {
            return false;
        }
        if (status === 'ACTIVE' && row.is_active === false)
            return false;
        if (status === 'INACTIVE' && row.is_active !== false)
            return false;
        return true;
    });
    const sorted = [...filtered].sort((a, b) => (a.points_required ?? 0) - (b.points_required ?? 0));
    return paginate(sorted, query);
}
/** The team: owners first, then whoever signed in most recently. */
function selectStaff(rows, query) {
    const search = (query.search ?? '').trim();
    const status = (query.status ?? '').trim().toUpperCase();
    const rank = (role) => {
        switch ((role ?? '').toUpperCase()) {
            case 'OWNER':
                return 0;
            case 'MANAGER':
                return 1;
            default:
                return 2;
        }
    };
    const filtered = rows.filter((row) => {
        if (search !== '' && !matchesSearch([row.phone, row.id, row.role], search)) {
            return false;
        }
        if (status !== '' && (row.status ?? '').toUpperCase() !== status) {
            return false;
        }
        return true;
    });
    const sorted = [...filtered].sort((a, b) => {
        const byRole = rank(a.role) - rank(b.role);
        if (byRole !== 0)
            return byRole;
        return ((b.last_login_at ?? b.updated_at ?? 0) -
            (a.last_login_at ?? a.updated_at ?? 0));
    });
    return paginate(sorted, query);
}
