/**
 * Response contracts for the `/admin/*` API.
 *
 * These endpoints previously returned `data: result.rows` — raw PostgreSQL
 * rows. Nothing described or checked their shape, so every client mirrored a
 * SQL SELECT list by hand and a renamed column broke them silently at runtime.
 *
 * Two things this normalizes at the boundary, which callers previously had to
 * guess at:
 *
 *  - `node-pg` returns `BIGINT` columns as **strings** (it will not risk
 *    precision loss on int8). Every timestamp column in this schema is
 *    `BIGINT` epoch-millis, so `created_at` arrived as `"1730000000000"`.
 *    Here it is always a `number | null`.
 *  - Absent columns and SQL `NULL` both become `null`, never `undefined`, so
 *    JSON serialization keeps the key.
 *
 * Widening a field is safe for the existing Flutter client: its readers already
 * accept both strings and numbers. Renaming or removing one is not.
 */

// --- Envelopes ---------------------------------------------------------------

export type AdminPagingDto = {
  limit: number;
  offset: number;
  has_more: boolean;
};

export type AdminListResponse<T> = {
  success: true;
  data: T[];
  paging: AdminPagingDto;
};

export type AdminItemResponse<T> = {
  success: true;
  data: T;
};

// --- Merchants ---------------------------------------------------------------

export type AdminMerchantSummaryDto = {
  id: string;
  name: string;
  phone: string | null;
  created_at: number | null;
  updated_at: number | null;
  plan_code: string | null;
  plan_name: string | null;
  subscription_status: string | null;
  staff_count: number;
  active_staff_count: number;
  usage_balance_count: number;
  last_operational_update_at: number | null;
};

export type AdminMerchantDetailDto = AdminMerchantSummaryDto & {
  plan_version: number | null;
  pricing_version: number | null;
  trial_ends_at: number | null;
  grace_ends_at: number | null;
  period_start: number | null;
  period_end: number | null;
  subscription_updated_at: number | null;
  last_staff_login_at: number | null;
  usage_used_total: number;
  usage_updated_at: number | null;
  usage_event_count: number;
  last_usage_event_at: number | null;
  entitlement_count: number;
  feature_flag_count: number;
  remote_config_count: number;
};

// --- Audit trail -------------------------------------------------------------

export type AdminAuditEventDto = {
  id: string;
  action: string;
  target_type: string;
  target_id: string | null;
  merchant_id: string | null;
  actor_app_user_id: string | null;
  actor_firebase_uid: string | null;
  actor_role: string | null;
  details: Record<string, unknown>;
  created_at: number | null;
};

// --- Plan catalog ------------------------------------------------------------

export type AdminPlanPriceDto = {
  pricing_version: number | null;
  currency: string | null;
  amount: number | null;
  billing_period: string | null;
  is_active: boolean;
  created_at: number | null;
  updated_at: number | null;
};

export type AdminPlanFeatureDto = {
  feature_key: string;
  is_enabled: boolean;
  limit_value: number | null;
  unit: string | null;
  updated_at: number | null;
};

export type AdminPlanDto = {
  plan_code: string;
  version: number | null;
  name: string | null;
  is_active: boolean;
  created_at: number | null;
  updated_at: number | null;
  prices: AdminPlanPriceDto[];
  features: AdminPlanFeatureDto[];
};

// --- Operations summary ------------------------------------------------------

export type AdminOperationsSummaryDto = {
  merchant_count: number;
  active_subscription_count: number;
  trial_subscription_count: number;
  attention_subscription_count: number;
  active_staff_count: number;
  usage_events_24h: number;
  open_recovery_task_count: number;
  visit_reports_24h: number;
  survey_responses_24h: number;
  admin_audit_events_24h: number;
  last_admin_audit_at: number | null;
  last_usage_event_at: number | null;
};

// --- Readers -----------------------------------------------------------------

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

/** Trimmed string, or `null` when absent, blank, or not a string. */
export function readNullableString(
  row: Record<string, unknown>,
  key: string,
): string | null {
  const value = row[key];
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** Trimmed string, falling back to `fallback` when absent or blank. */
export function readString(
  row: Record<string, unknown>,
  key: string,
  fallback = '',
): string {
  return readNullableString(row, key) ?? fallback;
}

/**
 * Numeric column as a `number`, tolerating the string form that `node-pg`
 * returns for `BIGINT`. Non-finite and unparseable values become `null`.
 */
export function readNullableNumber(
  row: Record<string, unknown>,
  key: string,
): number | null {
  const value = row[key];
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'bigint') return Number(value);
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length === 0) return null;
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

/** Counter column, defaulting to `0` rather than `null`. */
export function readCount(row: Record<string, unknown>, key: string): number {
  return readNullableNumber(row, key) ?? 0;
}

/** Boolean column, tolerating the `'t'`/`'f'` and `0`/`1` spellings. */
export function readBoolean(
  row: Record<string, unknown>,
  key: string,
  fallback = false,
): boolean {
  const value = row[key];
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', 't', 'yes', 'y', '1'].includes(normalized)) return true;
    if (['false', 'f', 'no', 'n', '0'].includes(normalized)) return false;
  }
  return fallback;
}

/** `jsonb` column as an object, tolerating a JSON string. */
export function readJsonObject(
  row: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const value = row[key];
  if (typeof value === 'string') {
    try {
      return asRecord(JSON.parse(value));
    } catch {
      return {};
    }
  }
  return asRecord(value);
}

function readArray(row: Record<string, unknown>, key: string): unknown[] {
  const value = row[key];
  if (Array.isArray(value)) return value;
  if (typeof value === 'string') {
    try {
      const parsed: unknown = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

// --- Mappers -----------------------------------------------------------------

export function toAdminMerchantSummary(
  raw: unknown,
): AdminMerchantSummaryDto {
  const row = asRecord(raw);
  return {
    id: readString(row, 'id'),
    name: readString(row, 'name'),
    phone: readNullableString(row, 'phone'),
    created_at: readNullableNumber(row, 'created_at'),
    updated_at: readNullableNumber(row, 'updated_at'),
    plan_code: readNullableString(row, 'plan_code'),
    plan_name: readNullableString(row, 'plan_name'),
    subscription_status: readNullableString(row, 'subscription_status'),
    staff_count: readCount(row, 'staff_count'),
    active_staff_count: readCount(row, 'active_staff_count'),
    usage_balance_count: readCount(row, 'usage_balance_count'),
    last_operational_update_at: readNullableNumber(
      row,
      'last_operational_update_at',
    ),
  };
}

export function toAdminMerchantDetail(raw: unknown): AdminMerchantDetailDto {
  const row = asRecord(raw);
  return {
    ...toAdminMerchantSummary(row),
    plan_version: readNullableNumber(row, 'plan_version'),
    pricing_version: readNullableNumber(row, 'pricing_version'),
    trial_ends_at: readNullableNumber(row, 'trial_ends_at'),
    grace_ends_at: readNullableNumber(row, 'grace_ends_at'),
    period_start: readNullableNumber(row, 'period_start'),
    period_end: readNullableNumber(row, 'period_end'),
    subscription_updated_at: readNullableNumber(row, 'subscription_updated_at'),
    last_staff_login_at: readNullableNumber(row, 'last_staff_login_at'),
    usage_used_total: readCount(row, 'usage_used_total'),
    usage_updated_at: readNullableNumber(row, 'usage_updated_at'),
    usage_event_count: readCount(row, 'usage_event_count'),
    last_usage_event_at: readNullableNumber(row, 'last_usage_event_at'),
    entitlement_count: readCount(row, 'entitlement_count'),
    feature_flag_count: readCount(row, 'feature_flag_count'),
    remote_config_count: readCount(row, 'remote_config_count'),
  };
}

export function toAdminAuditEvent(raw: unknown): AdminAuditEventDto {
  const row = asRecord(raw);
  return {
    id: readString(row, 'id'),
    action: readString(row, 'action', 'admin.event'),
    target_type: readString(row, 'target_type', 'unknown'),
    target_id: readNullableString(row, 'target_id'),
    merchant_id: readNullableString(row, 'merchant_id'),
    actor_app_user_id: readNullableString(row, 'actor_app_user_id'),
    actor_firebase_uid: readNullableString(row, 'actor_firebase_uid'),
    actor_role: readNullableString(row, 'actor_role'),
    details: readJsonObject(row, 'details'),
    created_at: readNullableNumber(row, 'created_at'),
  };
}

export function toAdminPlanPrice(raw: unknown): AdminPlanPriceDto {
  const row = asRecord(raw);
  return {
    pricing_version: readNullableNumber(row, 'pricing_version'),
    currency: readNullableString(row, 'currency'),
    amount: readNullableNumber(row, 'amount'),
    billing_period: readNullableString(row, 'billing_period'),
    is_active: readBoolean(row, 'is_active'),
    created_at: readNullableNumber(row, 'created_at'),
    updated_at: readNullableNumber(row, 'updated_at'),
  };
}

export function toAdminPlanFeature(raw: unknown): AdminPlanFeatureDto {
  const row = asRecord(raw);
  return {
    feature_key: readString(row, 'feature_key'),
    is_enabled: readBoolean(row, 'is_enabled'),
    limit_value: readNullableNumber(row, 'limit_value'),
    unit: readNullableString(row, 'unit'),
    updated_at: readNullableNumber(row, 'updated_at'),
  };
}

export function toAdminPlan(raw: unknown): AdminPlanDto {
  const row = asRecord(raw);
  return {
    plan_code: readString(row, 'plan_code'),
    version: readNullableNumber(row, 'version'),
    name: readNullableString(row, 'name'),
    is_active: readBoolean(row, 'is_active'),
    created_at: readNullableNumber(row, 'created_at'),
    updated_at: readNullableNumber(row, 'updated_at'),
    prices: readArray(row, 'prices').map(toAdminPlanPrice),
    features: readArray(row, 'features')
      .map(toAdminPlanFeature)
      // `jsonb_agg(... ) FILTER` can still emit a null-keyed object for plans
      // with no features; drop entries that carry no key.
      .filter((feature) => feature.feature_key.length > 0),
  };
}

export function toAdminOperationsSummary(
  raw: unknown,
): AdminOperationsSummaryDto {
  const row = asRecord(raw);
  return {
    merchant_count: readCount(row, 'merchant_count'),
    active_subscription_count: readCount(row, 'active_subscription_count'),
    trial_subscription_count: readCount(row, 'trial_subscription_count'),
    attention_subscription_count: readCount(
      row,
      'attention_subscription_count',
    ),
    active_staff_count: readCount(row, 'active_staff_count'),
    usage_events_24h: readCount(row, 'usage_events_24h'),
    open_recovery_task_count: readCount(row, 'open_recovery_task_count'),
    visit_reports_24h: readCount(row, 'visit_reports_24h'),
    survey_responses_24h: readCount(row, 'survey_responses_24h'),
    admin_audit_events_24h: readCount(row, 'admin_audit_events_24h'),
    last_admin_audit_at: readNullableNumber(row, 'last_admin_audit_at'),
    last_usage_event_at: readNullableNumber(row, 'last_usage_event_at'),
  };
}

/** Builds the paging envelope shared by the admin list endpoints. */
export function toAdminPaging(
  limit: number,
  offset: number,
  returnedRows: number,
): AdminPagingDto {
  return {
    limit,
    offset,
    has_more: returnedRows === limit,
  };
}

// --- Entitlements, staff and cards -------------------------------------------

/**
 * One entitlement override in force for a merchant.
 *
 * `limit_value` is nullable and that nullability is load-bearing: `null` means
 * unmetered, `0` means denied. Anything that collapses the two would read as
 * "no limit" on a merchant who has been cut off, or the reverse.
 */
export type AdminEntitlementDto = {
  id: string;
  merchant_id: string;
  feature_key: string;
  is_enabled: boolean;
  limit_value: number | null;
  unit: string | null;
  updated_at: number | null;
};

export function toAdminEntitlement(raw: unknown): AdminEntitlementDto {
  const row = asRecord(raw);
  return {
    id: readString(row, 'id'),
    merchant_id: readString(row, 'merchant_id'),
    feature_key: readString(row, 'feature_key'),
    is_enabled: readBoolean(row, 'is_enabled'),
    limit_value: readNullableNumber(row, 'limit_value'),
    unit: readNullableString(row, 'unit'),
    updated_at: readNullableNumber(row, 'updated_at'),
  };
}

/** A staff account, with the merchant it belongs to resolved to a name. */
export type AdminStaffUserDto = {
  id: string;
  merchant_id: string;
  merchant_name: string | null;
  phone: string;
  role: string;
  status: string;
  invited_at: number | null;
  accepted_at: number | null;
  deactivated_at: number | null;
  last_login_at: number | null;
  created_at: number | null;
  updated_at: number | null;
};

export function toAdminStaffUser(raw: unknown): AdminStaffUserDto {
  const row = asRecord(raw);
  return {
    id: readString(row, 'id'),
    merchant_id: readString(row, 'merchant_id'),
    merchant_name: readNullableString(row, 'merchant_name'),
    phone: readString(row, 'phone'),
    role: readString(row, 'role', 'UNKNOWN'),
    status: readString(row, 'status', 'UNKNOWN'),
    invited_at: readNullableNumber(row, 'invited_at'),
    accepted_at: readNullableNumber(row, 'accepted_at'),
    deactivated_at: readNullableNumber(row, 'deactivated_at'),
    last_login_at: readNullableNumber(row, 'last_login_at'),
    created_at: readNullableNumber(row, 'created_at'),
    updated_at: readNullableNumber(row, 'updated_at'),
  };
}

/**
 * An NFC card as the console may see it.
 *
 * The full UID never leaves the server. A UID is what a reader sends to
 * identify a customer, so a console that prints them turns a support screen
 * into a source of working credentials; the last four are enough to confirm
 * which card someone is holding.
 */
export type AdminNfcCardDto = {
  card_uid_last4: string;
  canonical_customer_id: string | null;
  status: string;
  source: string | null;
  linked_by: string | null;
  linked_by_merchant_id: string | null;
  created_at: number | null;
  updated_at: number | null;
};

export function toAdminNfcCard(
  cardUid: string,
  raw: unknown,
): AdminNfcCardDto {
  const row = asRecord(raw);
  const uid = readString(row, 'card_uid', cardUid);
  return {
    card_uid_last4: uid.length <= 4 ? uid : uid.slice(-4),
    canonical_customer_id: readNullableString(row, 'canonical_customer_id'),
    status: readString(row, 'status', 'UNKNOWN'),
    source: readNullableString(row, 'source'),
    linked_by: readNullableString(row, 'linked_by'),
    linked_by_merchant_id: readNullableString(row, 'linked_by_merchant_id'),
    created_at: readNullableNumber(row, 'created_at'),
    updated_at: readNullableNumber(row, 'updated_at'),
  };
}

/** A business a customer is known to, and the id that business uses for them. */
export type AdminCustomerBusinessDto = {
  merchant_id: string;
  business_customer_id: string;
  linked_at: number | null;
};

/** The result of a customer lookup. Never carries a full phone number. */
export type AdminCustomerLookupDto = {
  canonical_customer_id: string;
  phone_last4: string | null;
  account_state: string;
  account_linked: boolean;
  created_at: number | null;
  updated_at: number | null;
  created_by_merchant_id: string | null;
  last_linked_merchant_id: string | null;
  businesses: AdminCustomerBusinessDto[];
  cards: Array<{
    card_uid_last4: string;
    status: string;
    source: string | null;
    linked_by_merchant_id: string | null;
    created_at: number | null;
    updated_at: number | null;
  }>;
};

/** One entry in a customer's points ledger at one business. */
export type AdminLedgerEntryDto = {
  id: string;
  entry_type: string;
  source_type: string;
  source_id: string;
  points_delta: number;
  balance_after: number;
  amount_mzn: number;
  reward_id: string | null;
  reversal_of_entry_id: string | null;
  reversal_reason: string | null;
  occurred_at: number;
  created_at: number;
};

export type AdminLedgerDto = {
  canonical_customer_id: string;
  merchant_id: string;
  entry_count: number;
  net_points: number;
  entries: AdminLedgerEntryDto[];
};

/** A person holding an administrator claim, and which claim grants it. */
export type AdminDirectoryEntryDto = {
  uid: string;
  email: string | null;
  display_name: string | null;
  disabled: boolean;
  claims: string[];
  last_sign_in_at: number | null;
  created_at: number | null;
};
