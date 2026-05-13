# Backend Bootstrap Contract

This document defines the client contract for the merchant-centric auth bootstrap and sync cutover. The Flutter app remains Firebase OTP plus Firestore by default, but these endpoints are the contract for the new backend path behind feature flags.

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

Used immediately after Firebase Phone Auth succeeds in the current mobile flow.

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
Authorization: Bearer <access-token>
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
        "payload": {"template": "promo_v1"},
        "updated_at": 1715120000000
      }
    ],
    "remote_config": [
      {
        "id": "merchant-1_billing_whatsapp_price",
        "merchant_id": "merchant-1",
        "config_key": "billing_whatsapp_price",
        "payload": {"currency": "MZN", "amount": 2},
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
- On first successful verify or exchange, a merchant is auto-created with default `merchant_name = Minha Loja`.
- The backend must create one owner `app_user` linked to the merchant.
- The client must not be required to complete an onboarding form before reaching the dashboard.

## Sync Endpoints

The new backend transport mirrors the current queue orchestration so the mobile queue does not change.

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

The backend must resolve tenant context from the authenticated token and reject cross-tenant payloads.

### Sync entity types (v1)

- `customer`, `sale`, `reward`, `redemption`
- `subscription_state` (single document per merchant)
- `entitlement`
- `feature_flag`
- `remote_config`
- `usage_balance`
- `usage_event` (write-only via queue; aggregated into usage balances by backend)

## Usage Events

Usage is tracked offline by enqueueing `usage_event` items to the existing sync queue. The backend must aggregate usage into `usage_balance` and return updated balances via sync pulls or the next bootstrap.

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
    "metadata": {"template": "promo_v1"}
  },
  "queued_at": "2026-05-06T10:00:00Z"
}
```

## Policy Versioning (grandfathered pricing)

- `plan_version` describes the current plan definition.
- `pricing_version` allows grandfathered pricing for existing merchants.
- The backend must keep historical pricing versions and emit the correct version in `subscription_state`.