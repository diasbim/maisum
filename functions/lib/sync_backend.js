"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OPTIONAL_CUSTOMER_DELETE_DEPENDENCY_CHECKS = exports.CUSTOMER_DELETE_DEPENDENCY_CHECKS = void 0;
exports.resolveCustomerArchiveMutation = resolveCustomerArchiveMutation;
exports.normalizeSaleCancellationStatus = normalizeSaleCancellationStatus;
exports.assertValidAuthoritativeSaleCreatePayload = assertValidAuthoritativeSaleCreatePayload;
exports.resolveSaleCancellationRequest = resolveSaleCancellationRequest;
exports.isCompatibleRepeatedSaleCancellation = isCompatibleRepeatedSaleCancellation;
exports.shouldPersistReplacementSaleLinkOnReplay = shouldPersistReplacementSaleLinkOnReplay;
exports.isCompatibleRepeatedSaleCreate = isCompatibleRepeatedSaleCreate;
exports.resolveAuthoritativeSaleAuthorship = resolveAuthoritativeSaleAuthorship;
exports.buildSyncTombstonePayload = buildSyncTombstonePayload;
exports.buildCustomerArchiveFirestorePatch = buildCustomerArchiveFirestorePatch;
exports.buildCustomerDeleteDependencyChecks = buildCustomerDeleteDependencyChecks;
exports.computeLoyaltyLedgerEntriesWithBalances = computeLoyaltyLedgerEntriesWithBalances;
exports.computeCustomerProjectionFromLoyaltyLedgerEntries = computeCustomerProjectionFromLoyaltyLedgerEntries;
exports.buildSaleReversalLoyaltyLedgerEntry = buildSaleReversalLoyaltyLedgerEntry;
exports.CUSTOMER_DELETE_DEPENDENCY_CHECKS = [
    {
        label: 'sales',
        tableName: 'sales',
        sql: 'SELECT 1 FROM sales WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'redemptions',
        tableName: 'redemptions',
        sql: 'SELECT 1 FROM redemptions WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'appointments',
        tableName: 'appointments',
        sql: 'SELECT 1 FROM appointments WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'retention_metrics',
        tableName: 'retention_metrics',
        sql: 'SELECT 1 FROM retention_metrics WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'customer_risk_scores',
        tableName: 'customer_risk_scores',
        sql: 'SELECT 1 FROM customer_risk_scores WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'recovery_tasks',
        tableName: 'recovery_tasks',
        sql: 'SELECT 1 FROM recovery_tasks WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'recovery_actions',
        tableName: 'recovery_actions',
        sql: 'SELECT 1 FROM recovery_actions WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'visit_reports',
        tableName: 'visit_reports',
        sql: 'SELECT 1 FROM visit_reports WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'survey_responses',
        tableName: 'survey_responses',
        sql: 'SELECT 1 FROM survey_responses WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
];
exports.OPTIONAL_CUSTOMER_DELETE_DEPENDENCY_CHECKS = [
    {
        label: 'loyalty_ledger',
        tableName: 'loyalty_ledger',
        sql: 'SELECT 1 FROM loyalty_ledger WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
    {
        label: 'redemption_requests',
        tableName: 'redemption_requests',
        sql: 'SELECT 1 FROM redemption_requests WHERE merchant_id = $1 AND customer_id = $2 LIMIT 1',
    },
];
function orderLoyaltyLedgerEntries(entries) {
    return [...entries].sort((left, right) => {
        const byOccurredAt = left.occurred_at - right.occurred_at;
        if (byOccurredAt !== 0)
            return byOccurredAt;
        const byCreatedAt = left.created_at - right.created_at;
        if (byCreatedAt !== 0)
            return byCreatedAt;
        return left.id.localeCompare(right.id);
    });
}
function collectReversedSaleIds(entries) {
    return new Set(entries
        .filter((entry) => entry.entry_type === 'SALE_REVERSAL')
        .map((entry) => entry.source_id));
}
function hasOwnKey(payload, key) {
    return Object.prototype.hasOwnProperty.call(payload, key);
}
function parseFiniteNumber(value) {
    if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
    }
    if (typeof value === 'string' && value.trim().length > 0) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}
function pickNonEmptyString(payload, ...keys) {
    for (const key of keys) {
        const value = payload[key];
        if (typeof value === 'string' && value.trim().length > 0) {
            return value.trim();
        }
    }
    return null;
}
function fieldIsExplicitlySet(value) {
    if (value == null) {
        return false;
    }
    if (typeof value === 'string') {
        return value.trim().length > 0;
    }
    return true;
}
function readNullableNumberField(payload, ...keys) {
    const touched = keys.some((key) => hasOwnKey(payload, key));
    if (!touched) {
        return { touched: false, value: null };
    }
    for (const key of keys) {
        if (!hasOwnKey(payload, key)) {
            continue;
        }
        const raw = payload[key];
        if (raw == null || raw === '') {
            return { touched: true, value: null };
        }
        const parsed = parseFiniteNumber(raw);
        if (parsed != null) {
            return { touched: true, value: parsed };
        }
    }
    throw new Error(`Invalid numeric field: ${keys[0]}.`);
}
function resolveCustomerArchiveMutation(payload, actorAppUserId) {
    const archivedAt = readNullableNumberField(payload, 'archived_at', 'archivedAt');
    if (!archivedAt.touched) {
        return {
            touched: false,
            archivedAt: null,
            archivedByAppUserId: null,
        };
    }
    return {
        touched: true,
        archivedAt: archivedAt.value,
        archivedByAppUserId: archivedAt.value == null ? null : actorAppUserId,
    };
}
function normalizeSaleCancellationStatus(value) {
    if (typeof value !== 'string') {
        return null;
    }
    const normalized = value.trim().toUpperCase();
    if (normalized === 'CANCELLED' || normalized === 'CANCELED') {
        return 'CANCELLED';
    }
    return null;
}
function assertValidAuthoritativeSaleCreatePayload(payload) {
    const requestedCancellationStatus = pickNonEmptyString(payload, 'cancellation_status', 'cancellationStatus');
    if (requestedCancellationStatus && requestedCancellationStatus.trim().toUpperCase() !== 'ACTIVE') {
        throw new Error('cancellation_status is server-managed for sale create.');
    }
    const forbiddenFields = [
        { keys: ['cancelled_at', 'cancelledAt'], label: 'cancelled_at' },
        {
            keys: ['cancelled_by_app_user_id', 'cancelledByAppUserId'],
            label: 'cancelled_by_app_user_id',
        },
        { keys: ['cancellation_reason', 'cancellationReason'], label: 'cancellation_reason' },
        { keys: ['replacement_sale_id', 'replacementSaleId'], label: 'replacement_sale_id' },
    ];
    for (const field of forbiddenFields) {
        for (const key of field.keys) {
            if (hasOwnKey(payload, key) && fieldIsExplicitlySet(payload[key])) {
                throw new Error(`${field.label} is server-managed for sale create.`);
            }
        }
    }
}
function resolveSaleCancellationRequest(payload, actorAppUserId, now, saleId) {
    const cancellationReason = pickNonEmptyString(payload, 'cancellation_reason', 'cancellationReason');
    if (!cancellationReason) {
        throw new Error('cancellation_reason is required.');
    }
    const replacementSaleId = pickNonEmptyString(payload, 'replacement_sale_id', 'replacementSaleId');
    if (replacementSaleId != null && replacementSaleId === saleId) {
        throw new Error('replacement_sale_id must reference a different sale.');
    }
    return {
        cancellationReason,
        replacementSaleId,
        cancelledAt: now,
        cancelledByAppUserId: actorAppUserId,
    };
}
function isCompatibleRepeatedSaleCancellation(existing, request) {
    if (normalizeSaleCancellationStatus(existing.cancellationStatus) !== 'CANCELLED') {
        return false;
    }
    const existingReason = typeof existing.cancellationReason === 'string' && existing.cancellationReason.trim().length > 0
        ? existing.cancellationReason.trim()
        : null;
    const existingReplacement = typeof existing.replacementSaleId === 'string' && existing.replacementSaleId.trim().length > 0
        ? existing.replacementSaleId.trim()
        : null;
    if (existingReason != null && existingReason !== request.cancellationReason) {
        return false;
    }
    if (existingReplacement != null &&
        request.replacementSaleId != null &&
        existingReplacement !== request.replacementSaleId) {
        return false;
    }
    return true;
}
function shouldPersistReplacementSaleLinkOnReplay(existing, request) {
    if (!isCompatibleRepeatedSaleCancellation(existing, request)) {
        return false;
    }
    const existingReplacement = typeof existing.replacementSaleId === 'string' && existing.replacementSaleId.trim().length > 0
        ? existing.replacementSaleId.trim()
        : null;
    return existingReplacement == null && request.replacementSaleId != null;
}
function isCompatibleRepeatedSaleCreate(existing, request) {
    return (pickNonEmptyString(existing, 'customerId') === request.customerId ||
        pickNonEmptyString(existing, 'customer_id') === request.customerId) &&
        parseFiniteNumber(existing.amount) === request.amount &&
        parseFiniteNumber(existing.points) === request.points &&
        (parseFiniteNumber(existing.createdAt) === request.createdAt ||
            parseFiniteNumber(existing.created_at) === request.createdAt);
}
function resolveAuthoritativeSaleAuthorship(payload, actorAppUserId) {
    const payloadCreatedBy = pickNonEmptyString(payload, 'created_by_app_user_id', 'createdByAppUserId');
    const payloadUpdatedBy = pickNonEmptyString(payload, 'updated_by_app_user_id', 'updatedByAppUserId');
    const authoritativeActor = actorAppUserId?.trim() ? actorAppUserId.trim() : null;
    const createdByAppUserId = authoritativeActor ?? payloadCreatedBy;
    const updatedByAppUserId = authoritativeActor ?? payloadUpdatedBy ?? createdByAppUserId;
    return {
        createdByAppUserId,
        updatedByAppUserId,
    };
}
function buildSyncTombstonePayload(id, merchantId, entityType, entityId, deletedAt) {
    return {
        id,
        merchant_id: merchantId,
        entity_type: entityType,
        entity_id: entityId,
        deleted_at: deletedAt,
    };
}
function buildCustomerArchiveFirestorePatch(mutation, updatedAt) {
    return {
        archived_at: mutation.archivedAt,
        archived_by_app_user_id: mutation.archivedByAppUserId,
        updated_at: updatedAt,
    };
}
function buildCustomerDeleteDependencyChecks(existingTableNames) {
    const checks = [...exports.CUSTOMER_DELETE_DEPENDENCY_CHECKS];
    if (!existingTableNames) {
        return checks;
    }
    const normalizedTables = new Set([...existingTableNames].map((tableName) => tableName.trim().toLowerCase()));
    for (const check of exports.OPTIONAL_CUSTOMER_DELETE_DEPENDENCY_CHECKS) {
        if (normalizedTables.has(check.tableName.toLowerCase())) {
            checks.push(check);
        }
    }
    return checks;
}
function computeLoyaltyLedgerEntriesWithBalances(entries) {
    const ordered = orderLoyaltyLedgerEntries(entries);
    let runningBalance = 0;
    return ordered.map((entry) => {
        runningBalance += entry.points_delta;
        return {
            ...entry,
            balance_after: runningBalance,
        };
    });
}
function computeCustomerProjectionFromLoyaltyLedgerEntries(entries) {
    const balancedEntries = computeLoyaltyLedgerEntriesWithBalances(entries);
    const confirmedPoints = balancedEntries.reduce((sum, entry) => sum + entry.points_delta, 0);
    const reversedSaleIds = collectReversedSaleIds(balancedEntries);
    const activeSaleEntries = balancedEntries
        .filter((entry) => entry.entry_type === 'SALE' && !reversedSaleIds.has(entry.source_id))
        .sort((left, right) => left.occurred_at - right.occurred_at);
    const totalVisits = activeSaleEntries.length;
    const totalSpent = activeSaleEntries.reduce((sum, entry) => sum + (entry.amount_mzn ?? 0), 0);
    const firstVisitAt = totalVisits > 0 ? activeSaleEntries[0].occurred_at : null;
    const lastVisitAt = totalVisits > 0
        ? activeSaleEntries[totalVisits - 1].occurred_at
        : null;
    const averageSpend = totalVisits > 0 ? totalSpent / totalVisits : 0;
    const intervals = [];
    for (let index = 1; index < activeSaleEntries.length; index += 1) {
        intervals.push(activeSaleEntries[index].occurred_at - activeSaleEntries[index - 1].occurred_at);
    }
    const averageVisitIntervalDays = intervals.length > 0
        ? Math.round(intervals.reduce((sum, value) => sum + value, 0) /
            intervals.length /
            (24 * 60 * 60 * 1000))
        : 0;
    const lastLedgerEntryAt = balancedEntries.reduce((latest, entry) => {
        if (latest == null || entry.occurred_at > latest) {
            return entry.occurred_at;
        }
        return latest;
    }, null);
    return {
        confirmedPoints,
        firstVisitAt,
        lastVisitAt,
        totalVisits,
        totalSpent,
        averageSpend,
        averageVisitIntervalDays,
        lastLedgerEntryAt,
    };
}
function buildSaleReversalLoyaltyLedgerEntry(params) {
    const originalAmount = Math.abs(parseFiniteNumber(params.originalSaleEntry.amount_mzn) ?? 0);
    return {
        id: params.id,
        merchant_id: params.merchantId,
        customer_id: params.customerId,
        entry_type: 'SALE_REVERSAL',
        source_type: 'sale_cancellation',
        source_id: params.saleId,
        occurred_at: params.cancelledAt,
        points_delta: -Math.abs(params.originalSaleEntry.points_delta),
        policy_version: params.originalSaleEntry.policy_version,
        balance_after: 0,
        canonical_customer_id: params.canonicalCustomerId ?? params.originalSaleEntry.canonical_customer_id,
        amount_mzn: originalAmount > 0 ? -originalAmount : 0,
        reward_id: null,
        idempotency_key: null,
        reversal_of_entry_id: params.originalSaleEntry.id,
        reversal_reason: params.cancellationReason,
        created_at: params.createdAt,
        updated_at: params.updatedAt,
    };
}
