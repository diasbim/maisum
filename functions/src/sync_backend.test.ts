import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import {
  assertValidAuthoritativeSaleCreatePayload,
  buildCustomerArchiveFirestorePatch,
  buildSaleReversalLoyaltyLedgerEntry,
  buildSyncTombstonePayload,
  buildCustomerDeleteDependencyChecks,
  computeCustomerProjectionFromLoyaltyLedgerEntries,
  CUSTOMER_DELETE_DEPENDENCY_CHECKS,
  computeLoyaltyLedgerEntriesWithBalances,
  isCompatibleRepeatedSaleCreate,
  isCompatibleRepeatedSaleCancellation,
  normalizeSaleCancellationStatus,
  resolveAuthoritativeSaleAuthorship,
  resolveCustomerArchiveMutation,
  resolveSaleCancellationRequest,
  shouldPersistReplacementSaleLinkOnReplay,
} from './sync_backend.js';

test('customer archive mutation uses the authenticated actor and supports restore', () => {
  const archiveMutation = resolveCustomerArchiveMutation(
    {
      archived_at: 123,
      archived_by_app_user_id: 'client-supplied',
    },
    'server-actor',
  );
  assert.deepEqual(archiveMutation, {
    touched: true,
    archivedAt: 123,
    archivedByAppUserId: 'server-actor',
  });
  assert.deepEqual(buildCustomerArchiveFirestorePatch(archiveMutation, 456), {
    archived_at: 123,
    archived_by_app_user_id: 'server-actor',
    updated_at: 456,
  });

  const restoreMutation = resolveCustomerArchiveMutation(
    { archivedAt: null },
    'server-actor',
  );
  assert.deepEqual(restoreMutation, {
    touched: true,
    archivedAt: null,
    archivedByAppUserId: null,
  });
  assert.deepEqual(buildCustomerArchiveFirestorePatch(restoreMutation, 789), {
    archived_at: null,
    archived_by_app_user_id: null,
    updated_at: 789,
  });
});

test('sale cancellation request requires a reason and rejects self-replacement', () => {
  assert.throws(
    () => resolveSaleCancellationRequest({}, 'user-1', 1000, 'sale-1'),
    /cancellation_reason is required/i,
  );
  assert.throws(
    () =>
      resolveSaleCancellationRequest(
        {
          cancellation_reason: 'duplicate',
          replacement_sale_id: 'sale-1',
        },
        'user-1',
        1000,
        'sale-1',
      ),
    /replacement_sale_id must reference a different sale/i,
  );
});

test('sale cancellation replay compatibility is strict but idempotent', () => {
  const request = resolveSaleCancellationRequest(
    {
      cancellation_reason: 'customer refunded',
      replacement_sale_id: 'sale-2',
    },
    'user-1',
    1000,
    'sale-1',
  );

  assert.equal(normalizeSaleCancellationStatus('canceled'), 'CANCELLED');
  assert.equal(
    isCompatibleRepeatedSaleCancellation(
      {
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: 'sale-2',
      },
      request,
    ),
    true,
  );
  assert.equal(
    isCompatibleRepeatedSaleCancellation(
      {
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'other reason',
        replacementSaleId: 'sale-2',
      },
      request,
    ),
    false,
  );
  assert.equal(
    shouldPersistReplacementSaleLinkOnReplay(
      {
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: null,
      },
      request,
    ),
    true,
  );
  assert.equal(
    shouldPersistReplacementSaleLinkOnReplay(
      {
        cancellationStatus: 'CANCELLED',
        cancellationReason: 'customer refunded',
        replacementSaleId: 'sale-2',
      },
      request,
    ),
    false,
  );
});

test('sale create payload rejects forged cancellation metadata and keeps authorship authoritative', () => {
  assert.doesNotThrow(() => assertValidAuthoritativeSaleCreatePayload({}));
  assert.doesNotThrow(() =>
    assertValidAuthoritativeSaleCreatePayload({
      cancellation_status: 'ACTIVE',
      cancelled_at: null,
      cancellation_reason: '',
      replacement_sale_id: null,
    }));
  assert.throws(
    () => assertValidAuthoritativeSaleCreatePayload({ cancellation_status: 'CANCELLED' }),
    /cancellation_status is server-managed/i,
  );
  assert.throws(
    () => assertValidAuthoritativeSaleCreatePayload({ cancellation_reason: 'forged' }),
    /cancellation_reason is server-managed/i,
  );
  assert.deepEqual(
    resolveAuthoritativeSaleAuthorship(
      {
        created_by_app_user_id: 'client-created',
        updated_by_app_user_id: 'client-updated',
      },
      'server-actor',
    ),
    {
      createdByAppUserId: 'server-actor',
      updatedByAppUserId: 'server-actor',
    },
  );
  assert.deepEqual(
    resolveAuthoritativeSaleAuthorship(
      { created_by_app_user_id: 'client-created' },
      null,
    ),
    {
      createdByAppUserId: 'client-created',
      updatedByAppUserId: 'client-created',
    },
  );
});

test('sale create replays are idempotent only when immutable fields match', () => {
  assert.equal(
    isCompatibleRepeatedSaleCreate(
      {
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
      },
      {
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
      },
    ),
    true,
  );
  assert.equal(
    isCompatibleRepeatedSaleCreate(
      {
        customerId: 'customer-1',
        amount: 100,
        points: 5,
        createdAt: 123,
      },
      {
        customerId: 'customer-1',
        amount: 200,
        points: 5,
        createdAt: 123,
      },
    ),
    false,
  );
});

test('customer hard-delete checks cover all relevant sync tables', () => {
  assert.deepEqual(
    CUSTOMER_DELETE_DEPENDENCY_CHECKS.map((item) => item.label),
    [
      'sales',
      'redemptions',
      'appointments',
      'retention_metrics',
      'customer_risk_scores',
      'recovery_tasks',
      'recovery_actions',
      'visit_reports',
      'survey_responses',
    ],
  );
  assert.deepEqual(
    buildCustomerDeleteDependencyChecks(['loyalty_ledger', 'redemption_requests']).map(
      (item) => item.label,
    ),
    [
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
    ],
  );
});

test('sale cancellation keeps the original ledger entry and applies a single immutable reversal', () => {
  const originalSaleEntry = {
    id: 'sale_sale-1',
    merchant_id: 'merchant-1',
    customer_id: 'customer-1',
    entry_type: 'SALE' as const,
    source_type: 'sale' as const,
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
  const reversalEntry = buildSaleReversalLoyaltyLedgerEntry({
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

  assert.deepEqual(reversalEntry, {
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

  const balancedEntries = computeLoyaltyLedgerEntriesWithBalances([
    secondSaleEntry,
    reversalEntry,
    originalSaleEntry,
  ]);
  assert.deepEqual(
    balancedEntries.map((entry) => ({
      id: entry.id,
      balance_after: entry.balance_after,
    })),
    [
      { id: 'sale_sale-1', balance_after: 10 },
      { id: 'sale_sale-2', balance_after: 20 },
      { id: 'sale_reversal_sale-1', balance_after: 10 },
    ],
  );

  const projection = computeCustomerProjectionFromLoyaltyLedgerEntries([
    originalSaleEntry,
    secondSaleEntry,
    reversalEntry,
  ]);
  assert.deepEqual(projection, {
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

test('sync tombstone payload matches the generic contract exactly', () => {
  assert.deepEqual(
    buildSyncTombstonePayload('ts_1', 'merchant-1', 'customer', 'customer-1', 1234),
    {
      id: 'ts_1',
      merchant_id: 'merchant-1',
      entity_type: 'customer',
      entity_id: 'customer-1',
      deleted_at: 1234,
    },
  );
});

test('authoritative corrections use Firestore and expose tombstones', () => {
  const schema = readFileSync(resolve(process.cwd(), 'sql/schema.sql'), 'utf8');
  const source = readFileSync(resolve(process.cwd(), 'src/index.ts'), 'utf8');
  const archiveHandler = source.slice(
    source.indexOf('async function archiveCustomerViaSync'),
    source.indexOf('async function upsertCustomer'),
  );
  const cancellationHandler = source.slice(
    source.indexOf('async function cancelSaleViaSync'),
    source.indexOf('async function applySaleCancellationToLoyaltyState'),
  );
  const cancellationTransaction = source.slice(
    source.indexOf('async function applySaleCancellationToLoyaltyState'),
    source.indexOf('async function permanentlyDeleteCustomer'),
  );
  const deletionHandler = source.slice(
    source.indexOf('async function permanentlyDeleteCustomer'),
    source.indexOf('function customerFirestoreDependencyQueries'),
  );
  const hardDeleteTransaction = source.slice(
    source.indexOf('async function applyCustomerFirestoreHardDelete'),
    source.indexOf('async function resolveSqlCustomerDeleteDependencyChecks'),
  );

  assert.match(schema, /CREATE TABLE IF NOT EXISTS sync_tombstones/i);
  assert.match(
    schema,
    /CREATE TABLE IF NOT EXISTS sync_tombstones \(\s*id TEXT PRIMARY KEY,\s*merchant_id TEXT NOT NULL REFERENCES merchants\(id\),\s*entity_type TEXT NOT NULL,\s*entity_id TEXT NOT NULL,\s*deleted_at BIGINT NOT NULL\s*\);/s,
  );
  assert.match(schema, /ADD COLUMN IF NOT EXISTS archived_at BIGINT/i);
  assert.match(schema, /ADD COLUMN IF NOT EXISTS cancellation_status TEXT NOT NULL DEFAULT 'ACTIVE'/i);
  assert.match(source, /sale:\s*\{\s*table:\s*'sales',\s*orderField:\s*'updated_at'/s);
  assert.match(
    source,
    /sync_tombstone:\s*\{\s*table:\s*'sync_tombstones',\s*orderField:\s*'deleted_at',\s*idField:\s*'id',\s*selectSql:\s*'id, merchant_id, entity_type, entity_id, deleted_at'/s,
  );
  assert.match(source, /operation === 'cancel'/);
  assert.match(source, /operation === 'update'[\s\S]*sale_update_forbidden/s);
  assert.match(source, /operation === 'create'[\s\S]*upsertSale\(merchantId, payload, entityId, authedReq\)/s);
  assert.match(source, /sale only supports operation="create" or operation="cancel"/);
  assert.match(source, /sale_delete_forbidden/);
  assert.match(source, /assertValidAuthoritativeSaleCreatePayload\(payload\)/);
  assert.match(source, /VALUES \(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,'ACTIVE',NULL,NULL,NULL,NULL\)/);
  assert.match(source, /ON CONFLICT \(id\) DO NOTHING/);
  assert.match(source, /isCompatibleRepeatedSaleCreate/);
  assert.match(source, /replacement_sale_link_persisted/);
  assert.match(source, /SALE_REVERSAL/);
  assert.match(source, /sale_cancellation/);
  assert.match(source, /buildSaleReversalLoyaltyLedgerEntry/);
  assert.doesNotMatch(source, /transaction\.delete\(ledgerRef\)/);
  assert.match(source, /SELECT deleted_at\s+FROM sync_tombstones[\s\S]*entity_type = 'customer'[\s\S]*entity_id = \$2/s);
  assert.match(source, /customer_deleted_tombstone_conflict/);
  assert.doesNotMatch(source, /DELETE FROM sync_tombstones[\s\S]*entity_type = 'customer'/s);
  assert.match(source, /buildCustomerArchiveFirestorePatch\(archiveMutation, updatedAt\)/);
  assert.match(source, /businessCustomerRef\(merchantId, id\)\.set\(/);
  assert.match(archiveHandler, /admin\.firestore\(\)\.runTransaction/);
  assert.match(archiveHandler, /\.\.\.customerPatch/);
  assert.doesNotMatch(archiveHandler, /pool\.(query|connect)/);
  assert.match(cancellationHandler, /applySaleCancellationToLoyaltyState/);
  assert.match(
    source,
    /cancelled_at: currentCancelledAt \?\? params\.cancelledAt/,
  );
  assert.match(
    cancellationTransaction,
    /cancelledAt: currentCancelledAt \?\? params\.cancelledAt/,
  );
  assert.match(
    cancellationTransaction,
    /balance_after:[\s\S]*pickNumber\(reversalLedgerData, 'balance_after'\)/,
  );
  assert.doesNotMatch(cancellationHandler, /pool\.(query|connect)/);
  assert.match(deletionHandler, /applyCustomerFirestoreHardDelete/);
  assert.doesNotMatch(deletionHandler, /pool\.(query|connect)/);
  assert.match(source, /customer_delete_requires_archive/);
  assert.match(
    hardDeleteTransaction,
    /customerSnapshot\.exists[\s\S]*archived_at[\s\S]*customer_delete_requires_archive/,
  );
  assert.match(
    hardDeleteTransaction,
    /transaction\.get\(tombstoneRef\)[\s\S]*existingTombstoneSnapshot/,
  );
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
    assert.match(source, new RegExp(`'${collection}'`));
  }
  assert.match(source, /const SYNC_TOMBSTONE_COLLECTION = 'sync_tombstones'/);
  assert.match(source, /collection\(SYNC_TOMBSTONE_COLLECTION\)/);
  assert.match(
    source,
    /const deletedAt =[\s\S]*pickNumber\(existingTombstone, 'deleted_at'\)/,
  );
  assert.match(
    source,
    /transaction\.set\(tombstoneRef,[\s\S]*deleted_at: deletedAt/,
  );
});
