# Backend Bootstrap Contract

This document defines the client contract for the merchant-centric auth
bootstrap, the generic sync cutover, and the implemented affiliate/referral
routes. The Flutter app remains Firebase OTP plus Firestore by default.

**Authority rule:** Firestore remains the operational source of truth for
merchants, customers, sales, loyalty ledger entries, affiliates, codes,
attributions, rewards, events, outbox rows, and reconciliation decisions.
The REST/PostgreSQL path is an additive transport for bootstrap,
compatibility, analytics, and projections; PostgreSQL availability must never
participate in the critical sale or referral decision.

## Auth Bootstrap

### POST /auth/otp/request

Request body:

```json
{
  "phone": "+258840000000",
  "device_id": "device-123"
}
```

Response envelope:

```json
{
  "success": true,
  "message": "OTP sent",
  "data": {
    "verification_id": "otp-session-123",
    "expires_at": "2026-05-06T10:00:00Z"
  }
}
```

### POST /auth/otp/verify

Request body:

```json
{
  "phone": "+258840000000",
  "code": "123456",
  "verification_id": "otp-session-123",
  "device_id": "device-123"
}
```

### POST /auth/session/exchange

Used immediately after Firebase Phone Auth succeeds in the current mobile
flow.

Request body:

```json
{
  "firebase_id_token": "firebase-id-token",
  "phone": "+258840000000",
  "device_id": "device-123"
}
```

### POST /auth/refresh

Request body:

```json
{
  "refresh_token": "refresh-token",
  "device_id": "device-123"
}
```

### GET /auth/restore

Headers:

```text
Authorization: Bearer <token>
```

Optional query:

```text
device_id=device-123
```

### Bootstrap Session Envelope

All successful verify, exchange, refresh, and restore calls should return:

```json
{
  "success": true,
  "data": {
    "user_id": "owner-user-1",
    "app_user_id": "owner-user-1",
    "merchant_id": "merchant-1",
    "merchant_name": "Minha Loja",
    "phone": "+258840000000",
    "subscription_status": "TRIAL",
    "subscription_state": {
      "merchant_id": "merchant-1",
      "plan_code": "free",
      "plan_name": "Free",
      "plan_version": 1,
      "pricing_version": 1,
      "status": "TRIAL",
      "trial_ends_at": 1715342400000,
      "grace_ends_at": 1715947200000,
      "period_start": 1715120000000,
      "period_end": 1717798399999,
      "updated_at": 1715120000000
    },
    "entitlements": [
      {
        "id": "merchant-1_whatsapp_messages",
        "merchant_id": "merchant-1",
        "feature_key": "whatsapp_messages",
        "is_enabled": true,
        "limit_value": 200,
        "unit": "messages_per_month",
        "updated_at": 1715120000000
      }
    ],
    "feature_flags": [
      {
        "id": "merchant-1_whatsapp_campaigns",
        "merchant_id": "merchant-1",
        "flag_key": "whatsapp_campaigns",
        "is_enabled": true,
        "payload": {
          "template": "promo_v1"
        },
        "updated_at": 1715120000000
      }
    ],
    "remote_config": [
      {
        "id": "merchant-1_billing_whatsapp_price",
        "merchant_id": "merchant-1",
        "config_key": "billing_whatsapp_price",
        "payload": {
          "currency": "MZN",
          "amount": 2
        },
        "updated_at": 1715120000000
      }
    ],
    "usage_balances": [
      {
        "id": "merchant-1_whatsapp_messages_1715120000000",
        "merchant_id": "merchant-1",
        "metric_key": "whatsapp_messages",
        "window_start": 1715120000000,
        "window_end": 1717798399999,
        "used": 12,
        "limit_value": 200,
        "soft_limit": true,
        "updated_at": 1715120000000
      }
    ],
    "access_token": "backend-access-token",
    "refresh_token": "backend-refresh-token",
    "expires_at": "2026-05-06T10:00:00Z",
    "device_id": "device-123",
    "firebase_uid": "firebase-uid-1"
  }
}
```

## Merchant Auto-Creation Rules

- The backend must treat merchant phone number as globally unique.
- On first successful verify or exchange, a merchant is auto-created with
  default `merchant_name = Minha Loja`.
- The backend must create one owner `app_user` linked to the merchant.
- The client must not be required to complete an onboarding form before
  reaching the dashboard.

## Merchant Referral API (authoritative)

These endpoints are the operational contract for affiliates/referrals. They
read and write Firestore-backed facts through the Functions layer. Merchant
identity is always resolved from the authenticated token; the client must not
send a trusted `merchant_id` for these decisions.

### Role boundaries

- **Any authenticated business member** may read affiliate data, validate a
  code, commit an online sale with a code, and sync an offline referral sale.
- **Owner only** may create/edit/deactivate affiliates, create/edit/enable/
  disable codes, approve/cancel rewards, and sync an offline affiliate create.
- **Internal admin routes** (`/admin/affiliates*`,
  `/admin/merchants/:merchantId/affiliate-*`) exist for console governance and
  support, but this document stays customer/merchant oriented and does not list
  every admin response shape.

### Merchant reads

```text
GET /merchant/affiliates
GET /merchant/affiliates/:affiliateId
GET /merchant/affiliates/metrics
GET /merchant/affiliates/:affiliateId/metrics
GET /merchant/affiliate-codes
GET /merchant/affiliate-codes/:codeId
GET /merchant/referrals
GET /merchant/referrals/:attributionId
GET /merchant/affiliate-rewards
```

All list routes page with the existing envelope shape:

```json
{
  "success": true,
  "data": [],
  "paging": {
    "limit": 50,
    "offset": 0,
    "has_more": false
  },
  "total": 0,
  "truncated": false
}
```

`truncated=true` means the server capped the scan and the totals/derived rates
must be treated as partial rather than exact.

### Merchant mutations

```text
POST  /merchant/affiliates
PATCH /merchant/affiliates/:affiliateId
POST  /merchant/affiliates/:affiliateId/activate
POST  /merchant/affiliates/:affiliateId/deactivate
POST  /merchant/affiliates/sync

POST  /merchant/affiliate-codes
PATCH /merchant/affiliate-codes/:codeId
POST  /merchant/affiliate-codes/:codeId/enable
POST  /merchant/affiliate-codes/:codeId/disable

POST  /merchant/affiliate-rewards/:rewardId/approve
POST  /merchant/affiliate-rewards/:rewardId/cancel
```

Mutation failures use:

```json
{
  "success": false,
  "code": "affiliate_already_linked",
  "message": "Este afiliado já está ligado a este negócio."
}
```

Stable refusal codes include `invalid_*`, `affiliate_not_found`,
`affiliate_suspended`, `affiliate_already_linked`, `code_not_found`,
`reward_not_found`, `reward_not_pending`, `reward_paid`, `forbidden_role`,
`sale_conflict`, and `rate_limited`.

### POST /merchant/referrals/validate-code

Purpose: preview a typed referral code before a sale exists. This endpoint is
the **only** rate-limited referral endpoint.

Request body:

```json
{
  "code": "AFI-ANA-2345",
  "customer_phone": "+258841111222",
  "sale_amount": 850
}
```

Success, valid:

```json
{
  "success": true,
  "data": {
    "valid": true,
    "affiliate_id": "af_123",
    "affiliate_name": "Ana Silva",
    "affiliate_code_id": "ac_123",
    "normalized_code": "AFI-ANA-2345",
    "first_visit_only": true,
    "benefit": {
      "type": "PERCENTAGE",
      "value": 10,
      "display_text": "10% de desconto"
    },
    "validated_at": 1760000000000
  }
}
```

Success, rejected for business reasons:

```json
{
  "success": true,
  "data": {
    "valid": false,
    "reason": "CUSTOMER_NOT_ELIGIBLE",
    "message": "Este cliente não é elegível para este código.",
    "validated_at": 1760000000000
  }
}
```

Rate-limited:

```json
{
  "success": false,
  "code": "rate_limited",
  "message": "Demasiadas tentativas. Tente daqui a pouco."
}
```

with `Retry-After: <seconds>`.

### POST /merchant/referral-sales/commit

Purpose: authoritative online commit of a referred sale. The preview is
advisory only; all checks run again against Firestore and the real gross
amount.

Request body:

```json
{
  "device_id": "device-123",
  "local_sale_id": "sale-local-1",
  "customer_id": "customer-1",
  "customer_phone": "+258841111222",
  "gross_amount": 850,
  "code": "AFI-ANA-2345",
  "items": [
    {
      "id": "line-1",
      "merchant_item_id": "item-1",
      "name_snapshot": "Corte",
      "type_snapshot": "SERVICE",
      "quantity": 1,
      "unit_price": 850,
      "subtotal": 850
    }
  ]
}
```

Possible outcomes:

- `committed`: the sale, benefit, attribution, reward, events, and outbox
  rows were created.
- `replayed`: the same idempotency key was seen already; the server returns the
  same authoritative result instead of creating anything again.
- `rejected`: the code was refused; the caller should sell without a code.
- `conflict`: the same local sale id was reused with different facts.
- `customer_not_found`: the customer was not available to the server.

Example committed/replayed envelope:

```json
{
  "success": true,
  "data": {
    "outcome": "committed",
    "sale": {},
    "referral": {
      "affiliate_id": "af_123",
      "affiliate_code_id": "ac_123",
      "normalized_code": "AFI-ANA-2345",
      "benefit": {
        "type": "PERCENTAGE",
        "value": 10,
        "discount_amount": 85,
        "points_awarded": 0,
        "display_text": "10% de desconto"
      },
      "attribution_id": "aa_123",
      "attribution_status": "CONFIRMED",
      "reward": {
        "id": "ar_123",
        "type": "FIRST_QUALIFYING_SALE",
        "value": 100,
        "status": "PENDING"
      }
    },
    "idempotency_key": "sale:device-123:sale-local-1",
    "replayed": false
  }
}
```

Rejected online commit:

```json
{
  "success": true,
  "data": {
    "outcome": "rejected",
    "code": "referral_rejected",
    "reason": "CODE_EXPIRED",
    "message": "Este código já expirou."
  }
}
```

### POST /merchant/referral-sales/sync

Purpose: reconcile an offline sale that already happened on device.

The request reuses the online commit fields and adds the local fact the server
cannot infer later:

```json
{
  "merchant_id": "merchant-1",
  "device_id": "device-123",
  "local_sale_id": "sale-local-1",
  "customer_id": "customer-1",
  "customer_phone": "+258841111222",
  "gross_amount": 850,
  "code": "AFI-ANA-2345",
  "created_at": 1760000000000,
  "idempotency_key": "sale:device-123:sale-local-1",
  "offline_benefit_applied": true,
  "applied_benefit": {
    "type": "PERCENTAGE",
    "value": 10,
    "discount_amount": 85,
    "points_awarded": 0
  },
  "cached_code_id": "ac_123",
  "items": []
}
```

Possible outcomes:

- `committed` / `replayed`: the queued sale converged.
- `rejected`: the code was refused, but the sale remains recorded; if the till
  had already granted a monetary benefit, it remains recorded and no affiliate
  reward is created.
- `deferred`: the customer has not reached the server yet; retry later.
- `conflict`: the same local sale id was reused for different facts.

Offline responses also carry reconciliation metadata such as
`clock_skew_ms`, `monetary_benefit_applied`, `retroactive_discount_applied`
(always false in the current implementation), and
`points_benefit_credited`.

### POST /merchant/affiliates/sync

Purpose: reconcile an affiliate created offline by an owner.

The queue payload includes the same business fields as online create plus:

```json
{
  "local_id": "local-123",
  "local_affiliate_id": "local_local-123",
  "device_id": "device-123",
  "idempotency_key": "affiliate:device-123:local-123",
  "created_at": 1760000000000
}
```

Response:

```json
{
  "success": true,
  "data": {
    "outcome": "committed",
    "local_id": "local-123",
    "local_affiliate_id": "local_local-123",
    "affiliate": {}
  }
}
```

`replayed` means the identity/link/code already exists and should replace the
provisional local row.

## Generic Sync Endpoints

The new backend transport mirrors the current queue orchestration so the
mobile queue does not change for generic entities.

### GET /sync/{entityType}

Returns the full initial collection for bootstrap.

### GET /sync/{entityType}/changes

Query parameters:

```text
order_field=updated_at
last_value=1714980000000
last_doc_id=reward-2
limit=200
```

Returns only rows after the provided cursor.

### POST /sync/{entityType}/{entityId}

Request body:

```json
{
  "operation": "create",
  "payload": {
    "id": "sale-1",
    "merchant_id": "merchant-1",
    "device_id": "device-123"
  },
  "queued_at": "2026-05-06T10:00:00Z"
}
```

The backend must resolve tenant context from the authenticated token and
reject cross-tenant payloads.

### Sync entity types (generic pull/read path)

- `customer`, `merchant_item`, `sale`, `sale_item`
- `reward`, `redemption`, `loyalty_ledger`
- `appointment`, `retention_metric`, `customer_risk_score`
- `recovery_task`, `recovery_action`, `visit_report`
- `survey`, `survey_question`, `survey_response`, `survey_response_answer`
- `subscription_state`, `entitlement`, `feature_flag`, `remote_config`
- `usage_balance`, `usage_event`, `app_user`, `sync_tombstone`
- `return_bonus`

### Affiliate-specific sync entity types

The queue now also carries write-only affiliate operations:

- `affiliate` → POST `/merchant/affiliates/sync`
- `referral_sale` → POST `/merchant/referral-sales/sync`

These are **not** served by `GET /sync/{entityType}` and are deliberately kept
out of the generic sync writer because the referral domain owns their
idempotency, validation, and reconciliation rules.

### Queue metadata and idempotency

The affiliate rollout extends queued operations with:

- `local_id`: the device-side identity of the provisional row or sale.
- `idempotency_key`: stable replay key (`affiliate:{deviceId}:{localId}` or
  `sale:{deviceId}:{localSaleId}`).
- `last_sync_error`: latest server refusal/message recorded for operator
  review.

For offline referral sales, the payload also carries:

- `offline_benefit_applied`
- `applied_benefit`
- `cached_code_id`

The server must treat these as reconciliation facts, never as permission to
skip validation.

## Cache and Reconciliation Semantics

- `affiliate_code_lookup_cache` is a local SQLite projection refreshed from the
  merchant affiliate read API, not from direct client access to Firestore.
- The cache stores the code terms plus `affiliate_status`, `link_status`, and
  `refreshed_at`, so an offline till can distinguish “code active” from
  “affiliate/link inactive”.
- The preview is advisory only. Unknown or uncached codes must still be kept on
  the queued sale because the server may later attribute them.
- Online commit recalculates everything from Firestore. A valid preview does
  not guarantee a valid commit.
- Offline reconciliation is sale-preserving: the sale remains recorded even
  when the code is refused later.
- Firestore write success is the operational completion point. PostgreSQL
  projections and analytics may lag without invalidating the sale.

## Current Limits and Non-goals

- No automatic payout, affiliate login, or marketplace flow exists in this
  MVP.
- No WhatsApp provider is configured in-repo today. The affiliate outbox stays
  in `NOT_CONFIGURED`/queued states and batch sweeps simply recheck until an
  adapter exists; manual app sharing still works.
- Reward approval is online-only.
- The admin portal's global affiliate detail shows linked merchant ids but not
  the per-link active/inactive status inline.
- An uncached offline code never triggers a retroactive monetary discount after
  the sale. The server may still attribute the referral, but it must not
  rewrite the amount already charged.
- If an offline sale granted a local benefit and the server later rejects the
  code, the sale keeps the granted benefit recorded and the affiliate receives
  no attribution or reward.

## Usage Events

Usage is tracked offline by enqueueing `usage_event` items to the existing sync
queue. The backend aggregates usage into `usage_balance` and returns updated
balances via sync pulls or the next bootstrap.

Example payload for a queued usage event:

```json
{
  "operation": "create",
  "payload": {
    "id": "usage-1",
    "merchant_id": "merchant-1",
    "metric_key": "whatsapp_messages",
    "quantity": 1,
    "occurred_at": 1715123456789,
    "source": "campaign",
    "metadata": {
      "template": "promo_v1"
    }
  },
  "queued_at": "2026-05-06T10:00:00Z"
}
```

## Policy Versioning (grandfathered pricing)

- `plan_version` describes the current plan definition.
- `pricing_version` allows grandfathered pricing for existing merchants.
- The backend must keep historical pricing versions and emit the correct
  version in `subscription_state`.
