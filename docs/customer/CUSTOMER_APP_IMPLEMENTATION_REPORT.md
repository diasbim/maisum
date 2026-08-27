# Customer App Implementation Report

Date: 2026-08-27
Status: implementation complete; external QA and production rollout pending

## Delivered

- One Flutter application with explicit `merchant` and `customer` actors.
- Phone OTP customer entry, server-resolved customer session and fail-closed
  actor switching.
- Customer-only GoRouter shell for Home, Rewards, Activity, Businesses and
  Profile, plus business detail, QR, redemption and preferences routes.
- Customer-safe Cloud Functions APIs authorized by Firebase UID binding.
- Canonical phone identity linking without duplicate business customers.
- Confirmed-points read models, activity and rewards per linked business.
- Account-partitioned SQLite cache through migration 26, with offline reads,
  freshness metadata and cross-account response protection.
- Online-only, server-authoritative and idempotent customer redemption.
- Signed 30-day customer QR, offline cache, Flutter QR rendering, merchant
  camera scanner and manual-token fallback.
- Customer preferences, analytics events and allow-listed custom-scheme deep
  links (`maisum://app/customer/...`).
- Flag-gated FCM permission/token registration, refresh and removal. Message
  production/delivery is intentionally not claimed.
- Global kill switch, feature flags and optional
  `CUSTOMER_APP_ALLOWED_UIDS` pilot allow-list; all flags default to disabled.

## Backend APIs

- `GET /customer/session`
- `GET /customer/home`
- `GET /customer/businesses`
- `GET /customer/businesses/:businessId`
- `GET /customer/rewards`
- `GET /customer/activity`
- `GET /customer/profile`
- `PATCH /customer/preferences`
- `GET /customer/notifications`
- `GET /customer/deep-links`
- `POST /customer/events`
- `GET /customer/qr`
- `POST /customer/redemptions`
- `POST /customer/push-tokens`
- `POST /customer/push-tokens/remove`
- `POST /merchant/customer-qr/resolve`

Canonical identities, UID links, account documents, analytics events and push
tokens remain server-only in Firestore rules.

## Flutter and platform changes

- New feature module: `lib/features/customer_app/`.
- Auth actor persisted in secure storage and represented in `AuthSession`.
- Customer sessions never receive a synthetic `merchantId`.
- Customer sessions bypass merchant PIN/onboarding and the global PIN overlay.
- Added compatible HTTP `PATCH` support; push removal uses the existing POST
  transport convention.
- Added `qr_flutter`, `mobile_scanner`, `firebase_messaging` and `app_links`.
- Android camera permission and `maisum://app/customer/...` intent filter.

## Database migration

Migration 26 adds `customer_app_cache`, partitioned by Firebase UID and
resource key. It stores JSON payload, source update time and successful refresh
time without entering the merchant mutation/sync queue.

## Validation executed

- `functions: npm test`: 19 tests passed.
- Customer/auth/cache/migration/widget targeted Flutter tests passed.
- Full `flutter test`: passed (450+ existing and new tests).
- `flutter analyze`: no issues.
- `flutter build apk --debug`: succeeded.
- `git diff --check`: passed.

## External validation still required

- Firestore emulator integration for concurrent binding, relationship
  isolation and replay behavior (no emulator target is configured).
- FCM delivery from a real producer and notification taps on physical devices.
- Android low-end, camera, intermittent-network and airplane-mode scenarios.
- Measured startup/cache/scan/redemption performance targets.
- Production Firebase secrets, flags, allow-list, indexes and rollback drill.

These are release/pilot activities rather than unimplemented application code.
