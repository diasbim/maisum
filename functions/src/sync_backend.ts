export type CustomerArchiveMutation = {
  touched: boolean;
  archivedAt: number | null;
  archivedByAppUserId: string | null;
};

export type SaleCancellationRequest = {
  cancellationReason: string;
  replacementSaleId: string | null;
  cancelledAt: number;
  cancelledByAppUserId: string;
};

export type ExistingSaleCancellationState = {
  cancellationStatus?: unknown;
  cancellationReason?: unknown;
  replacementSaleId?: unknown;
};

export type ExistingSaleCreateState = {
  customerId?: unknown;
  amount?: unknown;
  points?: unknown;
  createdAt?: unknown;
};

export type RequestedSaleCreateState = {
  customerId: string;
  amount: number;
  points: number;
  createdAt: number;
};

export type AuthoritativeSaleAuthorship = {
  createdByAppUserId: string | null;
  updatedByAppUserId: string | null;
};

export type SyncTombstonePayload = {
  id: string;
  merchant_id: string;
  entity_type: string;
  entity_id: string;
  deleted_at: number;
};

export type CustomerArchiveFirestorePatch = {
  archived_at: number | null;
  archived_by_app_user_id: string | null;
  updated_at: number;
};

export type CustomerDeleteDependencyCheck = {
  label: string;
  tableName: string;
  sql: string;
};

export type SharedLoyaltyLedgerEntryType = 'SALE' | 'SALE_REVERSAL' | 'REDEMPTION';

export type SharedLoyaltyLedgerSourceType = 'sale' | 'sale_cancellation' | 'redemption';

export type SharedLoyaltyLedgerEntryRecord = {
  id: string;
  merchant_id: string;
  customer_id: string;
  entry_type: SharedLoyaltyLedgerEntryType;
  source_type: SharedLoyaltyLedgerSourceType;
  source_id: string;
  occurred_at: number;
  points_delta: number;
  policy_version: number;
  balance_after: number;
  canonical_customer_id?: string;
  amount_mzn?: number;
  reward_id?: string | null;
  idempotency_key?: string | null;
  reversal_of_entry_id?: string | null;
  reversal_reason?: string | null;
  created_at: number;
  updated_at: number;
};

export type SharedLoyaltyCustomerProjection = {
  confirmedPoints: number;
  firstVisitAt: number | null;
  lastVisitAt: number | null;
  totalVisits: number;
  totalSpent: number;
  averageSpend: number;
  averageVisitIntervalDays: number;
  lastLedgerEntryAt: number | null;
};

export const CUSTOMER_DELETE_DEPENDENCY_CHECKS: CustomerDeleteDependencyCheck[] = [
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
] ;

export const OPTIONAL_CUSTOMER_DELETE_DEPENDENCY_CHECKS: CustomerDeleteDependencyCheck[] = [
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

function orderLoyaltyLedgerEntries(
  entries: SharedLoyaltyLedgerEntryRecord[],
): SharedLoyaltyLedgerEntryRecord[] {
  return [...entries].sort((left, right) => {
    const byOccurredAt = left.occurred_at - right.occurred_at;
    if (byOccurredAt !== 0) return byOccurredAt;
    const byCreatedAt = left.created_at - right.created_at;
    if (byCreatedAt !== 0) return byCreatedAt;
    return left.id.localeCompare(right.id);
  });
}

function collectReversedSaleIds(entries: SharedLoyaltyLedgerEntryRecord[]): Set<string> {
  return new Set(
    entries
      .filter((entry) => entry.entry_type === 'SALE_REVERSAL')
      .map((entry) => entry.source_id),
  );
}

function hasOwnKey(payload: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(payload, key);
}

function parseFiniteNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function pickNonEmptyString(
  payload: Record<string, unknown>,
  ...keys: string[]
): string | null {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function fieldIsExplicitlySet(value: unknown): boolean {
  if (value == null) {
    return false;
  }
  if (typeof value === 'string') {
    return value.trim().length > 0;
  }
  return true;
}

function readNullableNumberField(
  payload: Record<string, unknown>,
  ...keys: string[]
): { touched: boolean; value: number | null; } {
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

export function resolveCustomerArchiveMutation(
  payload: Record<string, unknown>,
  actorAppUserId: string,
): CustomerArchiveMutation {
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

export function normalizeSaleCancellationStatus(value: unknown): 'CANCELLED' | null {
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim().toUpperCase();
  if (normalized === 'CANCELLED' || normalized === 'CANCELED') {
    return 'CANCELLED';
  }
  return null;
}

export function assertValidAuthoritativeSaleCreatePayload(
  payload: Record<string, unknown>,
): void {
  const requestedCancellationStatus = pickNonEmptyString(
    payload,
    'cancellation_status',
    'cancellationStatus',
  );
  if (requestedCancellationStatus && requestedCancellationStatus.trim().toUpperCase() !== 'ACTIVE') {
    throw new Error('cancellation_status is server-managed for sale create.');
  }

  const forbiddenFields: Array<{ keys: string[]; label: string; }> = [
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

export function resolveSaleCancellationRequest(
  payload: Record<string, unknown>,
  actorAppUserId: string,
  now: number,
  saleId: string,
): SaleCancellationRequest {
  const cancellationReason = pickNonEmptyString(
    payload,
    'cancellation_reason',
    'cancellationReason',
  );
  if (!cancellationReason) {
    throw new Error('cancellation_reason is required.');
  }
  const replacementSaleId = pickNonEmptyString(
    payload,
    'replacement_sale_id',
    'replacementSaleId',
  );
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

export function isCompatibleRepeatedSaleCancellation(
  existing: ExistingSaleCancellationState,
  request: SaleCancellationRequest,
): boolean {
  if (normalizeSaleCancellationStatus(existing.cancellationStatus) !== 'CANCELLED') {
    return false;
  }
  const existingReason =
    typeof existing.cancellationReason === 'string' && existing.cancellationReason.trim().length > 0
      ? existing.cancellationReason.trim()
      : null;
  const existingReplacement =
    typeof existing.replacementSaleId === 'string' && existing.replacementSaleId.trim().length > 0
      ? existing.replacementSaleId.trim()
      : null;

  if (existingReason != null && existingReason !== request.cancellationReason) {
    return false;
  }
  if (
    existingReplacement != null &&
    request.replacementSaleId != null &&
    existingReplacement !== request.replacementSaleId
  ) {
    return false;
  }
  return true;
}

export function shouldPersistReplacementSaleLinkOnReplay(
  existing: ExistingSaleCancellationState,
  request: SaleCancellationRequest,
): boolean {
  if (!isCompatibleRepeatedSaleCancellation(existing, request)) {
    return false;
  }
  const existingReplacement =
    typeof existing.replacementSaleId === 'string' && existing.replacementSaleId.trim().length > 0
      ? existing.replacementSaleId.trim()
      : null;
  return existingReplacement == null && request.replacementSaleId != null;
}

export function isCompatibleRepeatedSaleCreate(
  existing: ExistingSaleCreateState,
  request: RequestedSaleCreateState,
): boolean {
  return (
    pickNonEmptyString(existing as Record<string, unknown>, 'customerId') === request.customerId ||
    pickNonEmptyString(existing as Record<string, unknown>, 'customer_id') === request.customerId
  ) &&
    parseFiniteNumber(existing.amount) === request.amount &&
    parseFiniteNumber(existing.points) === request.points &&
    (
      parseFiniteNumber(existing.createdAt) === request.createdAt ||
      parseFiniteNumber((existing as Record<string, unknown>).created_at) === request.createdAt
    );
}

export function resolveAuthoritativeSaleAuthorship(
  payload: Record<string, unknown>,
  actorAppUserId?: string | null,
): AuthoritativeSaleAuthorship {
  const payloadCreatedBy =
    pickNonEmptyString(payload, 'created_by_app_user_id', 'createdByAppUserId');
  const payloadUpdatedBy =
    pickNonEmptyString(payload, 'updated_by_app_user_id', 'updatedByAppUserId');
  const authoritativeActor = actorAppUserId?.trim() ? actorAppUserId.trim() : null;
  const createdByAppUserId = authoritativeActor ?? payloadCreatedBy;
  const updatedByAppUserId = authoritativeActor ?? payloadUpdatedBy ?? createdByAppUserId;
  return {
    createdByAppUserId,
    updatedByAppUserId,
  };
}

export function buildSyncTombstonePayload(
  id: string,
  merchantId: string,
  entityType: string,
  entityId: string,
  deletedAt: number,
): SyncTombstonePayload {
  return {
    id,
    merchant_id: merchantId,
    entity_type: entityType,
    entity_id: entityId,
    deleted_at: deletedAt,
  };
}

export function buildCustomerArchiveFirestorePatch(
  mutation: CustomerArchiveMutation,
  updatedAt: number,
): CustomerArchiveFirestorePatch {
  return {
    archived_at: mutation.archivedAt,
    archived_by_app_user_id: mutation.archivedByAppUserId,
    updated_at: updatedAt,
  };
}

export function buildCustomerDeleteDependencyChecks(
  existingTableNames?: Iterable<string>,
): CustomerDeleteDependencyCheck[] {
  const checks = [...CUSTOMER_DELETE_DEPENDENCY_CHECKS];
  if (!existingTableNames) {
    return checks;
  }
  const normalizedTables = new Set(
    [...existingTableNames].map((tableName) => tableName.trim().toLowerCase()),
  );
  for (const check of OPTIONAL_CUSTOMER_DELETE_DEPENDENCY_CHECKS) {
    if (normalizedTables.has(check.tableName.toLowerCase())) {
      checks.push(check);
    }
  }
  return checks;
}

export function computeLoyaltyLedgerEntriesWithBalances(
  entries: SharedLoyaltyLedgerEntryRecord[],
): SharedLoyaltyLedgerEntryRecord[] {
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

export function computeCustomerProjectionFromLoyaltyLedgerEntries(
  entries: SharedLoyaltyLedgerEntryRecord[],
): SharedLoyaltyCustomerProjection {
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
  const intervals: number[] = [];
  for (let index = 1; index < activeSaleEntries.length; index += 1) {
    intervals.push(activeSaleEntries[index].occurred_at - activeSaleEntries[index - 1].occurred_at);
  }
  const averageVisitIntervalDays = intervals.length > 0
    ? Math.round(
      intervals.reduce((sum, value) => sum + value, 0) /
          intervals.length /
          (24 * 60 * 60 * 1000),
    )
    : 0;
  const lastLedgerEntryAt = balancedEntries.reduce<number | null>((latest, entry) => {
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

export function buildSaleReversalLoyaltyLedgerEntry(params: {
  id: string;
  merchantId: string;
  customerId: string;
  canonicalCustomerId?: string | null;
  saleId: string;
  originalSaleEntry: SharedLoyaltyLedgerEntryRecord;
  cancellationReason: string;
  cancelledAt: number;
  createdAt: number;
  updatedAt: number;
}): SharedLoyaltyLedgerEntryRecord {
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
