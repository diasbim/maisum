"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_test_1 = __importDefault(require("node:test"));
const sync_backend_js_1 = require("./sync_backend.js");
(0, node_test_1.default)('customer archive mutation uses the authenticated actor and supports restore', () => {
    const archiveMutation = (0, sync_backend_js_1.resolveCustomerArchiveMutation)({
        archived_at: 123,
        archived_by_app_user_id: 'client-supplied',
    }, 'server-actor');
    strict_1.default.deepEqual(archiveMutation, {
        touched: true,
        archivedAt: 123,
        archivedByAppUserId: 'server-actor',
    });
    strict_1.default.deepEqual((0, sync_backend_js_1.buildCustomerArchiveFirestorePatch)(archiveMutation, 456), {
        archived_at: 123,
        archived_by_app_user_id: 'server-actor',
        updated_at: 456,
    });
    const restoreMutation = (0, sync_backend_js_1.resolveCustomerArchiveMutation)({ archivedAt: null }, 'server-actor');
    strict_1.default.deepEqual(restoreMutation, {
        touched: true,
        archivedAt: null,
        archivedByAppUserId: null,
    });
    strict_1.default.deepEqual((0, sync_backend_js_1.buildCustomerArchiveFirestorePatch)(restoreMutation, 789), {
        archived_at: null,
        archived_by_app_user_id: null,
        updated_at: 789,
    });
});
(0, node_test_1.default)('sale cancellation request requires a reason and rejects self-replacement', () => {
    strict_1.default.throws(() => (0, sync_backend_js_1.resolveSaleCancellationRequest)({}, 'user-1', 1000, 'sale-1'), /cancellation_reason is required/i);
    strict_1.default.throws(() => (0, sync_backend_js_1.resolveSaleCancellationRequest)({
        cancellation_reason: 'duplicate',
        replacement_sale_id: 'sale-1',
    }, 'user-1', 1000, 'sale-1'), /replacement_sale_id must reference a different sale/i);
});
(0, node_test_1.default)('sale cancellation replay compatibility is strict but idempotent', () => {
    const request = (0, sync_backend_js_1.resolveSaleCancellationRequest)({
        cancellation_reason: 'customer refunded',
        replacement_sale_id: 'sale-2',
    }, 'user-1', 1000, 'sale-1');
    strict_1.default.equal((0, sync_backend_js_1.normalizeSaleCancellationStatus)('canceled'), 'CANCELLED');
    strict_1.default.equal((0, sync_backend_js_1.isCompatibleRepeatedSaleCancellation)({
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: 'sale-2',
    }, request), true);
    strict_1.default.equal((0, sync_backend_js_1.isCompatibleRepeatedSaleCancellation)({
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'other reason',
        replacementSaleId: 'sale-2',
    }, request), false);
    strict_1.default.equal((0, sync_backend_js_1.shouldPersistReplacementSaleLinkOnReplay)({
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: null,
    }, request), true);
    strict_1.default.equal((0, sync_backend_js_1.shouldPersistReplacementSaleLinkOnReplay)({
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: 'sale-2',
    }, request), false);
});
(0, node_test_1.default)('sale create payload rejects forged cancellation metadata and keeps authorship authoritative', () => {
    strict_1.default.doesNotThrow(() => (0, sync_backend_js_1.assertValidAuthoritativeSaleCreatePayload)({}));
    strict_1.default.doesNotThrow(() => (0, sync_backend_js_1.assertValidAuthoritativeSaleCreatePayload)({
        cancellation_status: 'ACTIVE',
        cancelled_at: null,
        cancellation_reason: '',
        replacement_sale_id: null,
    }));
    strict_1.default.throws(() => (0, sync_backend_js_1.assertValidAuthoritativeSaleCreatePayload)({ cancellation_status: 'CANCELLED' }), /cancellation_status is server-managed/i);
    strict_1.default.throws(() => (0, sync_backend_js_1.assertValidAuthoritativeSaleCreatePayload)({ cancellation_reason: 'forged' }), /cancellation_reason is server-managed/i);
    strict_1.default.deepEqual((0, sync_backend_js_1.resolveAuthoritativeSaleAuthorship)({
        created_by_app_user_id: 'client-created',
        updated_by_app_user_id: 'client-updated',
    }, 'server-actor'), {
        createdByAppUserId: 'server-actor',
        updatedByAppUserId: 'server-actor',
    });
    strict_1.default.deepEqual((0, sync_backend_js_1.resolveAuthoritativeSaleAuthorship)({ created_by_app_user_id: 'client-created' }, null), {
        createdByAppUserId: 'client-created',
        updatedByAppUserId: 'client-created',
    });
});
(0, node_test_1.default)('sale create replays are idempotent only when immutable fields match', () => {
    strict_1.default.equal((0, sync_backend_js_1.isCompatibleRepeatedSaleCreate)({
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
    }, {
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
    }), true);
    strict_1.default.equal((0, sync_backend_js_1.isCompatibleRepeatedSaleCreate)({
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
    }, {
        customerId: 'customer-1',
        amount: 200,
        points: 5,
        createdAt: 123,
    }), false);
});
(0, node_test_1.default)('customer hard-delete checks cover all relevant sync tables', () => {
    strict_1.default.deepEqual(sync_backend_js_1.CUSTOMER_DELETE_DEPENDENCY_CHECKS.map((item) => item.label), [
        'sales',
        'redemptions',
        'appointments',
        'retention_metrics',
        'customer_risk_scores',
        'recovery_tasks',
        'recovery_actions',
        'visit_reports',
        'survey_responses',
    ]);
    strict_1.default.deepEqual((0, sync_backend_js_1.buildCustomerDeleteDependencyChecks)(['loyalty_ledger', 'redemption_requests']).map((item) => item.label), [
        'sales',
        'redemptions',
        'appointments',
        'retention_metrics',
        'customer_risk_scores',
        'recovery_tasks',
        'recovery_actions',
        'visit_reports',
        'survey_responses',
        'loyalty_ledger',
        'redemption_requests',
    ]);
});
(0, node_test_1.default)('sale cancellation keeps the original ledger entry and applies a single immutable reversal', () => {
    const originalSaleEntry = {
        id: 'sale_sale-1',
        merchant_id: 'merchant-1',
        customer_id: 'customer-1',
        entry_type: 'SALE',
        source_type: 'sale',
        source_id: 'sale-1',
        occurred_at: 100,
        points_delta: 10,
        policy_version: 3,
        balance_after: 0,
        canonical_customer_id: 'canonical-1',
        amount_mzn: 200,
        reward_id: null,
        idempotency_key: null,
        created_at: 100,
        updated_at: 100,
    };
    const secondSaleEntry = {
        ...originalSaleEntry,
        id: 'sale_sale-2',
        source_id: 'sale-2',
        occurred_at: 200,
        amount_mzn: 120,
        created_at: 200,
        updated_at: 200,
    };
    const reversalEntry = (0, sync_backend_js_1.buildSaleReversalLoyaltyLedgerEntry)({
        id: 'sale_reversal_sale-1',
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        canonicalCustomerId: 'canonical-1',
        saleId: 'sale-1',
        originalSaleEntry,
        cancellationReason: 'refund requested',
        cancelledAt: 300,
        createdAt: 300,
        updatedAt: 300,
    });
    strict_1.default.deepEqual(reversalEntry, {
        id: 'sale_reversal_sale-1',
        merchant_id: 'merchant-1',
        customer_id: 'customer-1',
        entry_type: 'SALE_REVERSAL',
        source_type: 'sale_cancellation',
        source_id: 'sale-1',
        occurred_at: 300,
        points_delta: -10,
        policy_version: 3,
        balance_after: 0,
        canonical_customer_id: 'canonical-1',
        amount_mzn: -200,
        reward_id: null,
        idempotency_key: null,
        reversal_of_entry_id: 'sale_sale-1',
        reversal_reason: 'refund requested',
        created_at: 300,
        updated_at: 300,
    });
    const balancedEntries = (0, sync_backend_js_1.computeLoyaltyLedgerEntriesWithBalances)([
        secondSaleEntry,
        reversalEntry,
        originalSaleEntry,
    ]);
    strict_1.default.deepEqual(balancedEntries.map((entry) => ({
        id: entry.id,
        balance_after: entry.balance_after,
    })), [
        { id: 'sale_sale-1', balance_after: 10 },
        { id: 'sale_sale-2', balance_after: 20 },
        { id: 'sale_reversal_sale-1', balance_after: 10 },
    ]);
    const projection = (0, sync_backend_js_1.computeCustomerProjectionFromLoyaltyLedgerEntries)([
        originalSaleEntry,
        secondSaleEntry,
        reversalEntry,
    ]);
    strict_1.default.deepEqual(projection, {
        confirmedPoints: 10,
        firstVisitAt: 200,
        lastVisitAt: 200,
        totalVisits: 1,
        totalSpent: 120,
        averageSpend: 120,
        averageVisitIntervalDays: 0,
        lastLedgerEntryAt: 300,
    });
});
(0, node_test_1.default)('sync tombstone payload matches the generic contract exactly', () => {
    strict_1.default.deepEqual((0, sync_backend_js_1.buildSyncTombstonePayload)('ts_1', 'merchant-1', 'customer', 'customer-1', 1234), {
        id: 'ts_1',
        merchant_id: 'merchant-1',
        entity_type: 'customer',
        entity_id: 'customer-1',
        deleted_at: 1234,
    });
});
(0, node_test_1.default)('authoritative corrections use Firestore and expose tombstones', () => {
    const schema = (0, node_fs_1.readFileSync)((0, node_path_1.resolve)(process.cwd(), 'sql/schema.sql'), 'utf8');
    const source = (0, node_fs_1.readFileSync)((0, node_path_1.resolve)(process.cwd(), 'src/index.ts'), 'utf8');
    const archiveHandler = source.slice(source.indexOf('async function archiveCustomerViaSync'), source.indexOf('async function upsertCustomer'));
    const cancellationHandler = source.slice(source.indexOf('async function cancelSaleViaSync'), source.indexOf('async function applySaleCancellationToLoyaltyState'));
    const cancellationTransaction = source.slice(source.indexOf('async function applySaleCancellationToLoyaltyState'), source.indexOf('async function permanentlyDeleteCustomer'));
    const deletionHandler = source.slice(source.indexOf('async function permanentlyDeleteCustomer'), source.indexOf('function customerFirestoreDependencyQueries'));
    const hardDeleteTransaction = source.slice(source.indexOf('async function applyCustomerFirestoreHardDelete'), source.indexOf('async function resolveSqlCustomerDeleteDependencyChecks'));
    strict_1.default.match(schema, /CREATE TABLE IF NOT EXISTS sync_tombstones/i);
    strict_1.default.match(schema, /CREATE TABLE IF NOT EXISTS sync_tombstones \(\s*id TEXT PRIMARY KEY,\s*merchant_id TEXT NOT NULL REFERENCES merchants\(id\),\s*entity_type TEXT NOT NULL,\s*entity_id TEXT NOT NULL,\s*deleted_at BIGINT NOT NULL\s*\);/s);
    strict_1.default.match(schema, /ADD COLUMN IF NOT EXISTS archived_at BIGINT/i);
    strict_1.default.match(schema, /ADD COLUMN IF NOT EXISTS cancellation_status TEXT NOT NULL DEFAULT 'ACTIVE'/i);
    strict_1.default.match(source, /sale:\s*\{\s*table:\s*'sales',\s*orderField:\s*'updated_at'/s);
    strict_1.default.match(source, /sync_tombstone:\s*\{\s*table:\s*'sync_tombstones',\s*orderField:\s*'deleted_at',\s*idField:\s*'id',\s*selectSql:\s*'id, merchant_id, entity_type, entity_id, deleted_at'/s);
    strict_1.default.match(source, /operation === 'cancel'/);
    strict_1.default.match(source, /operation === 'update'[\s\S]*sale_update_forbidden/s);
    strict_1.default.match(source, /operation === 'create'[\s\S]*upsertSale\(merchantId, payload, entityId, authedReq\)/s);
    strict_1.default.match(source, /sale only supports operation="create" or operation="cancel"/);
    strict_1.default.match(source, /sale_delete_forbidden/);
    strict_1.default.match(source, /assertValidAuthoritativeSaleCreatePayload\(payload\)/);
    strict_1.default.match(source, /VALUES \(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,'ACTIVE',NULL,NULL,NULL,NULL\)/);
    strict_1.default.match(source, /ON CONFLICT \(id\) DO NOTHING/);
    strict_1.default.match(source, /isCompatibleRepeatedSaleCreate/);
    strict_1.default.match(source, /replacement_sale_link_persisted/);
    strict_1.default.match(source, /SALE_REVERSAL/);
    strict_1.default.match(source, /sale_cancellation/);
    strict_1.default.match(source, /buildSaleReversalLoyaltyLedgerEntry/);
    strict_1.default.doesNotMatch(source, /transaction\.delete\(ledgerRef\)/);
    strict_1.default.match(source, /SELECT deleted_at\s+FROM sync_tombstones[\s\S]*entity_type = 'customer'[\s\S]*entity_id = \$2/s);
    strict_1.default.match(source, /customer_deleted_tombstone_conflict/);
    strict_1.default.doesNotMatch(source, /DELETE FROM sync_tombstones[\s\S]*entity_type = 'customer'/s);
    strict_1.default.match(source, /buildCustomerArchiveFirestorePatch\(archiveMutation, updatedAt\)/);
    strict_1.default.match(source, /businessCustomerRef\(merchantId, id\)\.set\(/);
    strict_1.default.match(archiveHandler, /admin\.firestore\(\)\.runTransaction/);
    strict_1.default.match(archiveHandler, /\.\.\.customerPatch/);
    strict_1.default.doesNotMatch(archiveHandler, /pool\.(query|connect)/);
    strict_1.default.match(cancellationHandler, /applySaleCancellationToLoyaltyState/);
    strict_1.default.match(source, /cancelled_at: currentCancelledAt \?\? params\.cancelledAt/);
    strict_1.default.match(cancellationTransaction, /cancelledAt: currentCancelledAt \?\? params\.cancelledAt/);
    strict_1.default.match(cancellationTransaction, /balance_after:[\s\S]*pickNumber\(reversalLedgerData, 'balance_after'\)/);
    strict_1.default.doesNotMatch(cancellationHandler, /pool\.(query|connect)/);
    strict_1.default.match(deletionHandler, /applyCustomerFirestoreHardDelete/);
    strict_1.default.doesNotMatch(deletionHandler, /pool\.(query|connect)/);
    strict_1.default.match(source, /customer_delete_requires_archive/);
    strict_1.default.match(hardDeleteTransaction, /customerSnapshot\.exists[\s\S]*archived_at[\s\S]*customer_delete_requires_archive/);
    strict_1.default.match(hardDeleteTransaction, /transaction\.get\(tombstoneRef\)[\s\S]*existingTombstoneSnapshot/);
    for (const collection of [
        'sales',
        'redemptions',
        'appointments',
        'retention_metrics',
        'customer_risk_scores',
        'recovery_tasks',
        'recovery_actions',
        'visit_reports',
        'survey_responses',
        'loyalty_ledger',
        'redemption_requests',
    ]) {
        strict_1.default.match(source, new RegExp(`'${collection}'`));
    }
    strict_1.default.match(source, /const SYNC_TOMBSTONE_COLLECTION = 'sync_tombstones'/);
    strict_1.default.match(source, /collection\(SYNC_TOMBSTONE_COLLECTION\)/);
    strict_1.default.match(source, /const deletedAt =[\s\S]*pickNumber\(existingTombstone, 'deleted_at'\)/);
    strict_1.default.match(source, /transaction\.set\(tombstoneRef,[\s\S]*deleted_at: deletedAt/);
});
