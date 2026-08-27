# Customer App Architecture Audit

Date: 2026-08-27
Repository: `diasbim/maisum`
Scope: customer app plan validation before implementation

## Executive summary

MaisUm is one Flutter application with a mature merchant experience. The
repository already contains the important customer-domain foundations:
canonical phone identity, per-business customer relationships, loyalty ledger,
confirmed balance projection, assisted redemption, SQLite, Firestore and
Riverpod/GoRouter infrastructure.

The missing boundary is the customer actor. Authentication, local session,
authorization, routing, data access and sync currently assume `merchantId`.
Customer UI must not be built on top of that assumption because it would grant
the wrong tenant context and could expose merchant-only behavior.

Implementation must start with a server-authoritative Firebase UID to canonical
customer binding and customer-owned read contracts. Only then can Flutter
session, routes, cache and screens be added safely.

## Repository map

| Area | Existing implementation | Reusable? | Required change |
|---|---|---:|---|
| Entry point | `lib/main.dart` | Yes | No second app or entry point |
| Routing | `lib/app/router.dart`, flat merchant/admin routes | Partial | Add actor-aware redirects and `/customer/*` shell without rewriting merchant routes |
| Auth | `AuthRepository`, `AuthSession`, Firebase Phone OTP | Partial | Add customer actor/session resolution before merchant provisioning |
| Post-auth | `post_auth_navigation.dart` | Partial | Route by explicit actor; customer must not enter merchant onboarding |
| Providers | `lib/app/providers.dart` | Partial | Add customer APIs/repositories/providers without `activeMerchantIdProvider` |
| Customer relationship | `Customer` and `CustomerDao`, scoped by merchant | Yes | Keep as business relationship, not the global account |
| Canonical identity | `customer_identities` in `functions/src/index.ts` | Yes | Bind authenticated UID atomically and idempotently |
| Business links | Existing bidirectional canonical/business link collections | Yes | Read only links owned by the authenticated canonical identity |
| Phone normalization | `MozPhoneUtils` and backend normalization | Yes | Keep equivalent acceptance tests on both boundaries |
| Loyalty | Ledger/projection and `confirmed_points` | Yes | Customer contracts expose confirmed values only |
| Rewards | Merchant reward model/repository | Partial | Add a customer-safe read DTO/projection |
| Redemption | Assisted endpoint and atomic ledger mutation | Partial | Add distinct customer authorization and server-issued code |
| SQLite | `AppDatabase`, DAOs and migrations | Partial | Add customer-partitioned read cache and freshness metadata |
| Sync | `SyncService`, `SyncDao`, `FirestoreSyncService` | Partial | Reuse primitives only; current queue and scope are merchant writes |
| Connectivity | Current sync/connectivity providers | Yes | Reuse for refresh and online-only actions |
| Feature flags | Merchant-scoped flags/remote config | Partial | Add a global/customer-account rollout decision |
| Design system | Theme and `MaisUm*` components | Yes | Reuse; extract only for a real second consumer |
| QR | No package or implementation | No | Add signed/opaque customer token in a later phase |
| Notifications | Merchant engagement support; no FCM client | Partial | Add customer preferences/push after MVP reads |
| Deep links | No package or route handling | No | Add after stable customer routes |
| Firestore rules | Business membership/owner access; canonical collections denied | Partial | Keep canonical data server-only and test isolation through APIs |
| Tests | Dart tests plus limited Functions tests | Yes | Extend with identity/authorization and actor/routing/cache tests |

## Confirmed constraints

1. `AuthSession.resolvedMerchantId` falls back to Firebase UID. It cannot
   represent a customer safely without an actor discriminator.
2. `AuthRepository` restores or creates merchant context after Firebase
   sign-in. Customer resolution must branch before that provisioning path.
3. Functions authentication resolves Firebase UID as a merchant fallback.
   `/customer/*` needs an explicit customer boundary that ignores this fallback
   and authorizes by canonical identity.
4. Firestore rules intentionally prevent direct client access to canonical
   identity/link collections. Customer data should initially use authenticated
   Functions endpoints, not relaxed client rules.
5. Merchant write sync and conflict handling are tenant-scoped. Customer
   offline support is a read cache with refresh/reconciliation, not a parallel
   mutation queue.
6. The attached `file_sync_service.dart` is equivalent to
   `lib/features/sync/sync_service.dart`; it contributes no logic to merge.

## Existing capabilities to preserve

- Owner/staff authentication, PIN and onboarding redirects.
- Merchant ID isolation and Firestore access checks.
- Canonical customer linking triggered by business customer writes.
- Ledger-backed confirmed points and reconciliation.
- Idempotent, atomic assisted redemption.
- Existing SQLite migrations and merchant sync queue.
- Existing feature entitlements and merchant UI behavior.

## Gaps in dependency order

1. Customer account binding and customer request authorization.
2. Customer session/read DTOs and API endpoints.
3. Flutter actor-aware auth/session and route guards.
4. Customer-partitioned read cache and freshness metadata.
5. Read-only MVP screens.
6. Customer redemption authorization.
7. QR identification and merchant scanning.
8. Push, deep links and analytics.

## First implementation slice

Backend identity/session foundation:

- authenticated `GET /customer/session`;
- phone sourced from the verified Firebase token, never request payload;
- deterministic canonical identity resolution using the current HMAC scheme;
- atomic and idempotent UID-to-canonical binding;
- conflict when one canonical identity is already owned by another UID;
- existing business links returned without exposing canonical collections;
- canonical HMAC identifier retained server-side and omitted from the response;
- no merchant/customer relationship created during customer sign-in;
- no merchant scope accepted from the customer request.

Acceptance:

- local and E.164 forms resolve consistently at the canonical boundary;
- repeated calls produce the same account and links;
- an authenticated UID cannot request another phone/canonical identity;
- customer access does not imply merchant access;
- existing merchant authentication and routes remain unchanged;
- Functions TypeScript build and targeted tests pass.

## Backend implementation update

The backend now provides UID-bound customer read contracts for session, home,
businesses, business detail, rewards, activity and profile; it exposes only
`confirmed_points` as a balance. Customer redemption selects an already linked
business from the reward ID, uses the existing atomic ledger path and returns a
server-issued code. Customer QR values are signed, opaque account subjects with
an expiry and are resolved only by an authorized merchant endpoint.

All customer flags (`CUSTOMER_APP_ENABLED`, `CUSTOMER_REDEMPTION_ENABLED`,
`CUSTOMER_QR_ENABLED`, `CUSTOMER_PUSH_ENABLED` and
`CUSTOMER_DEEP_LINKS_ENABLED`) default to disabled. Preferences, analytics and
deep-link route contracts are server-side; push delivery and Flutter handling
remain deliberately out of scope.
