# MaisUm — CUSTOMER_APP_IMPLEMENTATION_PLAN.md

Version: 1.1
Status: Repository-validated / Implementation in progress
Validated against repository: 2026-08-27
Platform: Flutter / Android-first
Product: MaisUm — Customer Retention Platform
Core Loop: Register Sale → Assign Points → Engage Customer → Customer Returns

---

## 0. EXECUTION CONTRACT

This document is an implementation specification for Codex/Claude Code.

### Primary objective

Add the MaisUm Customer App experience to the existing Flutter application while maximizing reuse of the existing Business Owner App.

### Non-negotiable rules

1. Do NOT create a second Flutter codebase.
2. Do NOT duplicate Customer, Business, Loyalty, Reward, Redemption, Auth, SQLite, sync, formatting, or design-system implementations.
3. Extract reusable merchant components before creating customer-specific duplicates.
4. Preserve current merchant functionality and behavior.
5. Customer loyalty balances and redemption authorization are server-authoritative.
6. Customer App is offline-tolerant; reward redemption requires connectivity.
7. Phone number is the primary customer identity.
8. Existing merchant customer records must link to a customer account instead of creating duplicates.
9. Maximum simplicity: large controls, minimal text, one-hand operation.
10. Every feature must reinforce:
   Register Sale → Assign Points → Engage Customer → Customer Returns.
11. Do not turn the Customer App into a marketplace, social network, or analytics dashboard.
12. Do not introduce a new architecture or infrastructure layer when an existing shared implementation can be reused.

### Source alignment

Repository validation on 2026-08-27 corrected the assumptions in this
section. The application currently has Riverpod, GoRouter, Firebase Phone OTP,
Firestore, SQLite, canonical customer identity, business/customer links,
loyalty projections and server-authoritative assisted redemption. It does
**not** yet have separate customer/merchant shells, a customer actor/session,
customer APIs, a customer cache and QR. Customer FCM token registration and
custom-scheme deep-link routing are now present behind their customer flags;
push delivery and real-device validation remain unimplemented.

Validated source paths:
- `lib/main.dart`
- `lib/app/router.dart`
- `lib/app/providers.dart`
- `lib/features/auth/`
- `lib/features/customers/`
- `lib/features/loyalty/`
- `lib/features/rewards/`
- `lib/features/sync/`
- `lib/core/database/`
- `functions/src/index.ts`
- `firestore.rules`
- `pubspec.yaml`

The detailed audit is in
`docs/customer/CUSTOMER_APP_ARCHITECTURE_AUDIT.md`. Its findings override any
generic current-state claim below; unimplemented items remain target
capabilities.

Previously supplied external source references were not repository paths and
are intentionally superseded by the validated sources above.

Legacy source references:
- Customer Core and app architecture: fileciteturn2file14
- Customer lifecycle / optional customer app: fileciteturn2file5
- Loyalty / retention architecture: fileciteturn2file7
- Existing platform architecture: fileciteturn2file18
- Offline / sync direction: fileciteturn2file12

---

# 1. BEFORE CODING: REPOSITORY AUDIT

Codex MUST inspect the current repository before changing code.

## 1.1 Audit objectives

Identify:

- current Flutter entry point;
- flavor/environment configuration;
- current route tree;
- authentication implementation;
- merchant route shell;
- Riverpod providers;
- repository interfaces;
- Firestore repositories;
- SQLite/local database;
- synchronization engine;
- network/connectivity service;
- existing design system;
- existing reusable widgets;
- Customer model;
- Business model;
- Sale model;
- SaleItem model;
- Loyalty model;
- Reward model;
- Redemption model;
- Notification model;
- Business Profile;
- phone normalization;
- QR scanner;
- QR generator, if any;
- analytics;
- error handling;
- localization;
- existing tests.

## 1.2 Required audit deliverable

Create:

`docs/customer/CUSTOMER_APP_ARCHITECTURE_AUDIT.md`

Include:

| Area | Existing implementation | Reusable? | Required change |
|---|---|---:|---|
| Auth | ... | Yes/No | ... |
| Routing | ... | Yes/No | ... |
| Theme | ... | Yes/No | ... |
| Customer | ... | Yes/No | ... |
| Loyalty | ... | Yes/No | ... |
| Rewards | ... | Yes/No | ... |
| Redemption | ... | Yes/No | ... |
| SQLite | ... | Yes/No | ... |
| Sync | ... | Yes/No | ... |
| QR | ... | Yes/No | ... |
| Notifications | ... | Yes/No | ... |

Do not proceed to broad implementation until this audit is complete.

## 1.3 Validated baseline

The audit was completed on 2026-08-27.

| Area | Current implementation | Decision |
|---|---|---|
| Auth | Phone OTP exists, but `AuthSession` and post-auth assume a merchant | Add explicit actor context; never synthesize a merchant for a customer |
| Routing | Flat merchant/admin `GoRoute` tree | Add `/customer/*` incrementally; do not refactor all merchant routes first |
| Customer Core | Canonical identity and bidirectional business links exist in Functions | Reuse them and add UID-to-canonical account binding |
| Loyalty | Ledger and confirmed points are server-owned | Customer reads only confirmed projections |
| Redemption | Assisted merchant flow exists | Add a distinct customer-authorized endpoint; do not reuse local random codes |
| SQLite/sync | Shared database primitives, but write sync is merchant-scoped | Reuse primitives; add a customer read cache, not a second write sync engine |
| Feature flags | Existing flags are merchant-scoped | Add a customer actor rollout gate before customer routing is enabled |
| QR/push/deep links | QR is implemented; FCM registration and custom-scheme routing are flag-gated | Delivery and real-device validation remain pending |
| Attached sync service | Equivalent to `lib/features/sync/sync_service.dart` | No integration or replacement required |

Broad UI implementation is blocked until customer identity, authorization and
read contracts are implemented and tested.

---

# 2. TARGET ARCHITECTURE

Use the existing Flutter application and feature-first structure. The end
state has a customer shell alongside the current merchant/admin experience. A
merchant shell refactor is not a prerequisite for the MVP.

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   ├── theme/
│   └── config/
│
├── core/
│   ├── auth/
│   ├── database/
│   ├── network/
│   ├── sync/
│   ├── analytics/
│   ├── errors/
│   ├── formatting/
│   └── permissions/
│
├── shared/
│   ├── design_system/
│   ├── widgets/
│   ├── components/
│   ├── models/
│   └── services/
│
├── features/
│   ├── customers/
│   ├── loyalty/
│   ├── rewards/
│   ├── businesses/
│   ├── activity/
│   ├── notifications/
│   └── retention/
│
├── merchant/
│   ├── navigation/
│   ├── screens/
│   └── providers/
│
└── customer/
    ├── navigation/
    ├── screens/
    ├── providers/
    └── widgets/
```

The diagram is conceptual only. New customer code belongs under
`lib/features/customer_app/` with domain/data/presentation subdirectories, in
line with the current feature-first convention. Shared primitives stay in
their current `lib/core/` or feature locations and are extracted only when a
concrete second consumer exists. Do not move the merchant tree merely to match
the diagram.

---

# 3. SHARED COMPONENT REUSE AND EXTRACTION

Do not perform a broad extraction phase before customer contracts exist.
Search for and reuse current components first. Extract only when customer code
becomes a second real consumer and merchant regression coverage protects the
move.

Before building Customer UI, identify reusable merchant components. Extract
only the components that would otherwise be duplicated.

## 3.1 Design system

Create/reuse:

- MaisUmButton
- MaisUmSecondaryButton
- MaisUmIconButton
- MaisUmCard
- MaisUmText
- MaisUmBadge
- MaisUmAvatar
- MaisUmProgressBar
- MaisUmBottomSheet
- MaisUmDialog
- MaisUmLoadingState
- MaisUmEmptyState
- MaisUmErrorState
- MaisUmOfflineBanner
- MaisUmLastUpdated

Do not change the merchant visual behavior unnecessarily.

## 3.2 Shared loyalty components

Create/reuse:

- PointsBalanceCard
- RewardCard
- RewardProgress
- PointsTransactionTile
- RedemptionConfirmation
- RedemptionSuccess

## 3.3 Shared customer components

Create/reuse:

- CustomerAvatar
- CustomerIdentity
- CustomerQr
- CustomerActivityTile
- CustomerBusinessCard

## 3.4 Shared business components

Create/reuse:

- BusinessAvatar
- BusinessHeader
- BusinessCard
- BusinessContactActions

## 3.5 Shared services

Reuse/extract:

- CurrencyFormatter
- PhoneFormatter
- DateFormatter
- PhoneNormalizer
- ConnectivityService
- AnalyticsService
- ErrorHandler
- NotificationService
- QRService
- AuthService

## 3.6 Refactoring acceptance criterion

After extraction:

- Merchant App compiles.
- Existing merchant tests pass.
- Existing merchant flows behave as before.
- No customer-specific dependency is introduced into merchant-only UI.
- No duplicated component exists merely because the Customer App needs it.

---

# 4. CUSTOMER DOMAIN MODEL

The Customer App uses the existing Customer Core.

Validated conceptual model:

```text
Firebase User
    │ 1:1
    ↓
CustomerAccount
    │ 1:1
    ↓
CanonicalCustomerIdentity
    │
    ├── BusinessCustomerLink → Customer in Business A
    ├── BusinessCustomerLink → Customer in Business B
    └── BusinessCustomerLink → Customer in Business C
```

In the current codebase, `Customer` is the per-business relationship stored at
`businesses/{merchantId}/customers/{customerId}`. It is not the global customer
account. The canonical identity remains server-owned.

## 4.1 Canonical customer identity

Must support:

- canonical customer id;
- normalized E.164 phone and masked last four digits;
- account linkage state;
- createdAt;
- updatedAt.

Do not expose the HMAC lookup key or full canonical collection directly through
Firestore rules. Customer APIs return only customer-owned DTO fields.

## 4.2 Business customer relationship

Must support:

- business customer id;
- canonical customer id;
- merchant/business id;
- loyalty relationship;
- lifecycle/retention state where already supported;
- joinedAt;
- status.

## 4.3 Customer account

Must atomically associate Firebase Auth UID with the canonical identity.
Account binding uses the verified `phone_number` claim, never a phone supplied
by the client request. Repeated binding is idempotent; a conflicting UID is
rejected and audited.

## 4.4 Customer consent

Reuse the existing consent model if available.

Do not introduce a second consent system.

---

# 5. AUTHENTICATION

## 5.1 Primary authentication

Phone number + OTP.

No email requirement.

Customer-intent flow:

```text
Welcome
  ↓
Phone
  ↓
OTP
  ↓
GET /customer/session
  ↓
Existing customer?
 ├── Yes → Link/open existing profile
 └── No  → Create canonical account without inventing a business relationship
```

The existing merchant OTP/PIN/onboarding behavior remains unchanged. Customer
intent must be explicit (customer entry route or future deep link) before OTP
completion so `AuthRepository` does not provision a synthetic merchant. A
Firebase user may have merchant access and a customer account; the active actor
is a session/navigation context, not an exclusive global role claim.

## 5.2 Existing customer linking

This is mandatory.

Example:

Merchant already has:

```text
Carlos
+258 84 XXX XXXX
850 points
12 visits
```

Carlos installs MaisUm.

The app must resolve the existing canonical customer.

Never create:

```text
Carlos #1
Carlos #2
```

## 5.3 Account linking acceptance criteria

- Existing phone match resolves to canonical customer.
- Existing loyalty history is preserved.
- Existing business relationships are preserved.
- New Auth account does not create a duplicate Customer.
- Duplicate phone normalization is handled consistently.

---

# 6. CUSTOMER ROUTING

Create a separate Customer route shell.

Add it incrementally to the existing `lib/app/router.dart`. Do not make a
merchant shell refactor a prerequisite. Customer redirects must be pure/tested
actor decisions before they are wired into the current asynchronous PIN and
merchant-onboarding guards.

Recommended routes:

```text
/customer
/customer/home
/customer/rewards
/customer/activity
/customer/businesses
/customer/business/:businessId
/customer/qr
/customer/redeem/:rewardId
/customer/profile
```

The exact route naming may follow existing conventions.

## 6.1 Route guards

Customer routes require:

- authenticated Firebase user;
- customer role/account;
- valid customer relationship.

Merchant routes must not become accessible through customer navigation.

Server authorization remains authoritative.

---

# 7. CUSTOMER NAVIGATION

Initial navigation:

```text
Home
Rewards
Activity
Businesses
Profile
```

Keep navigation shallow.

Avoid nested navigation unless necessary.

---

# 8. CUSTOMER HOME

## Objective

Answer immediately:

1. How many points do I have?
2. What reward am I working toward?
3. What should I do next?

## Target layout

```text
Olá, Carlos 👋

┌─────────────────────────────┐
│        850 PONTOS           │
│                             │
│ ███████████████░░░          │
│                             │
│ Faltam 150 pontos           │
│ para a tua recompensa       │
└─────────────────────────────┘

Próxima recompensa

✂️ Corte grátis
1.000 pontos

Última visita
Hoje · Barbearia X
```

## Home requirements

Display:

- customer first name;
- current business context if selected;
- points balance;
- next reward;
- reward progress;
- recent visit/activity;
- last sync state when relevant.

## Performance

Home should render cached data immediately.

Target:

- cached render <300ms after data is available;
- network refresh non-blocking.

---

# 9. MULTI-BUSINESS CUSTOMER EXPERIENCE

A customer can belong to multiple businesses.

Example:

```text
Carlos
├── Barbearia X — 850 points
├── Café Y — 120 points
└── Restaurante Z — 430 points
```

## Businesses screen

Show:

- business name;
- business logo/avatar;
- customer points at that business;
- next reward;
- last visit.

Do not build a marketplace.

Do not rank businesses.

Do not introduce social features.

---

# 10. BUSINESS DETAIL

Display:

- business name;
- logo;
- basic profile;
- customer points;
- next reward;
- progress;
- last visit;
- rewards;
- WhatsApp action, where supported;
- location/directions, where supported by current business profile.

Use existing Business Profile data.

Do not duplicate business profile fields in Customer-specific storage.

---

# 11. REWARDS

Customer reward UI is read-focused.

Display:

- reward name;
- description;
- required points;
- current points;
- progress;
- eligibility;
- expiration if supported.

Example:

```text
Corte grátis
1.000 pontos

850 / 1.000

Faltam 150 pontos
```

Available reward:

```text
100 MT desconto
500 pontos

DISPONÍVEL

[ Resgatar ]
```

Reuse the existing Reward model and loyalty configuration.

---

# 12. REWARD REDEMPTION

Redemption requires connectivity.

Do not allow offline redemption.

Flow:

```text
Reward
  ↓
Tap Resgatar
  ↓
Confirmation
  ↓
Online server validation
  ↓
Atomic redemption
  ↓
Updated balance
  ↓
Success
```

## Confirmation

```text
Resgatar recompensa?

Corte grátis

1.000 pontos

[ Cancelar ] [ Resgatar ]
```

## Success

```text
✓ Recompensa resgatada

Corte grátis

Código:
483921

Mostra este código
na barbearia.

[ Fechar ]
```

Use the existing redemption domain if available.

## Security

The server must verify:

- authenticated customer;
- reward belongs to authorized business/customer context;
- reward is currently redeemable;
- sufficient balance;
- no duplicate redemption;
- atomic balance update.

Never trust client-calculated balances.

---

# 13. CUSTOMER QR

Customer QR is the bridge to the Merchant App.

## Customer

```text
Meu QR

[ QR CODE ]

Carlos
+258 84 XXX XXXX

Mostra este código
no balcão.
```

## Merchant

```text
Register Sale
  ↓
Scan Customer QR
  ↓
Resolve customer
  ↓
Amount
  ↓
Sale
  ↓
Points
```

## QR security

QR must NOT encode:

- points;
- balance;
- private profile data;
- authentication credentials.

Use an opaque customer public identifier plus secure token/signature as supported by the backend.

QR resolution must be authorized server-side where required.

QR display should work offline.

---

# 14. ACTIVITY

Customer activity is read-only.

Example:

```text
Actividade

Hoje
+100 pontos
Visita · Barbearia X

20 Ago
+100 pontos
Visita · Barbearia X

12 Ago
-500 pontos
Recompensa resgatada
```

Display customer-relevant activity only.

Do not expose:

- merchant internal notes;
- merchant margins;
- internal transaction metadata;
- other customers;
- staff-only information.

---

# 15. PROFILE

Keep minimal.

```text
Perfil

Carlos Manuel
+258 84 XXX XXXX

Notificações
Privacidade
Negócios ligados
Ajuda

Terminar sessão
```

Do not add complex settings in MVP.

---

# 16. NOTIFICATIONS

Reuse the existing notification infrastructure.

Supported event examples:

- POINTS_EARNED
- REWARD_UNLOCKED
- REWARD_EXPIRING
- CUSTOMER_RETURNED
- SPECIAL_OFFER

Push is supplementary.

Loyalty transactions must not depend on push delivery.

Implemented registration contract (not delivery):

- Flutter requests notification permission only for an authenticated customer
  when `customer_push_enabled` is returned by `/customer/session`.
- It registers, refreshes and best-effort removes an FCM token through
  authenticated `/customer/push-tokens` endpoints. The backend derives the UID
  from the verified token, validates only `platform` and `token`, and stores
  tokens in a server-only Firestore collection.
- There is deliberately no FCM send trigger/producer in this repository.
  Delivery, FCM credentials and real-device notification verification remain
  pending.

## Notification copy

Keep short and action-oriented.

Examples:

```text
🎉 Ganhaste 100 pontos na Barbearia X.

✂️ Já podes resgatar o teu corte grátis.

👋 Sentimos a tua falta. Que tal voltar?
```

---

# 17. WHATSAPP / DEEP LINKS

WhatsApp remains a primary engagement channel.

Customer App should complement it.

Deep-link examples:

```text
WhatsApp
  ↓
"Já tens 850 pontos. Faltam 150..."
  ↓
MaisUm
  ↓
Home / reward detail
```

```text
WhatsApp
  ↓
"Já podes resgatar a tua recompensa."
  ↓
MaisUm
  ↓
Reward detail
```

Implement deep links only after core navigation is stable.

Implemented custom-scheme contract:

- Android accepts only `maisum://app/customer/...`; no HTTPS app/universal link
  is configured because no verified domain was supplied.
- The app allow-lists customer home, rewards, activity, businesses, profile,
  QR, preferences, and parameterized business/redeem routes. Merchant and
  admin routes, external origins, query strings and fragments are rejected.
- Notification tap payloads use the same allow-list through
  `customer_route`; foreground receipt is recorded without rendering an
  untrusted notification UI.

---

# 18. OFFLINE-FIRST CUSTOMER BEHAVIOR

Customer App should be offline-tolerant.

Cache:

- customer profile;
- business relationships;
- points balance;
- rewards;
- recent activity;
- QR identity;
- business profile.

When offline:

```text
You're offline
Last updated: Today, 10:32
```

The app must remain usable for viewing cached information.

## Offline restrictions

Do NOT permit:

- reward redemption;
- authoritative balance mutation;
- profile mutation that requires server validation.

QR display remains available offline.

---

# 19. SHARED OFFLINE INFRASTRUCTURE

Do not create separate:

```text
MerchantOfflineService
CustomerOfflineService
```

Use shared:

```text
OfflineRepository
LocalCache
ConnectivityService
SyncQueue
SyncEngine
```

These names are conceptual; the repository does not currently expose all of
them as generic abstractions. Reuse `AppDatabase`, connectivity and existing
serialization/error patterns. Do not route customer reads through merchant
`SyncService` because its queue, conflict handling and scope require a
`merchantId`.

Implement a customer-partitioned read-through cache keyed by the authenticated
customer account/Firebase UID, with `updatedAt`/`lastSuccessfulRefreshAt`
metadata and account-safe clearing on logout. The canonical HMAC identifier
remains server-only.

Customer App should primarily perform read/cache/refresh operations.

---

# 20. CUSTOMER HOME READ MODEL

Prefer an optimized customer-home read model instead of many sequential requests.

Conceptually:

```text
CustomerHome
├── customer
├── businesses
├── balances
├── nextReward
├── recentActivity
├── notifications
└── syncMetadata
```

Possible API:

```http
GET /customer/home
GET /customer/businesses
GET /customer/businesses/:businessId
GET /customer/loyalty
GET /customer/rewards
GET /customer/activity
GET /customer/qr
POST /customer/redemptions
GET /customer/notifications
PATCH /customer/preferences
```

Adapt endpoint names to the existing backend conventions.

Do not create parallel APIs if equivalent endpoints already exist.

---

# 21. SERVER-AUTHORITATIVE LOYALTY

Never calculate authoritative loyalty balances in Flutter.

Correct:

```text
Merchant Sale
   ↓
Backend
   ↓
Loyalty Engine
   ↓
Points Ledger
   ↓
Customer Read Model
   ↓
Customer App
```

Customer App displays the server result.

Any locally displayed optimistic state must be clearly non-authoritative and reconciled with server state.

---

# 22. CUSTOMER PERMISSIONS

Customer can:

- view own profile;
- view own businesses;
- view own points;
- view own rewards;
- view own activity;
- redeem eligible rewards;
- show own QR;
- manage own notification preferences.

Customer cannot:

- create rewards;
- change loyalty rules;
- register sales;
- edit merchant customers;
- access merchant analytics;
- access other customers;
- modify points;
- modify redemptions;
- access staff functions.

Enforce permissions server-side.

---

# 23. SHARED DATA CONTRACTS

Reuse generated models where possible.

Do not create:

```text
CustomerAppCustomer
MerchantAppCustomer
```

if one canonical `Customer` model is sufficient.

Likewise avoid duplicate:

```text
CustomerReward
MerchantReward
CustomerBusiness
MerchantBusiness
```

unless the domain genuinely requires separate DTO/read models.

DTOs are acceptable when API boundaries require them, but map them into shared domain concepts.

---

# 24. ANALYTICS

Track only product-useful metrics.

Required:

- customer app installs;
- successful phone verification;
- account-link success;
- customer home opens;
- reward views;
- reward unlocks;
- reward redemptions;
- QR views;
- notification opens;
- deep-link opens;
- active customers.

Do not build a complex customer analytics dashboard.

Merchant-facing analytics remain in the Business Owner Portal/App.

---

# 25. FEATURE FLAGS

Use the existing flag conventions where their scope fits. Current flags are
merchant-scoped, so they cannot decide pre-merchant customer access by
themselves.

Suggested:

```text
customer_app_enabled
customer_qr_enabled
customer_redemption_enabled
customer_push_enabled
customer_deep_links_enabled
customer_app_allowed_uids
```

Default strategy:

- Customer App can be enabled for pilot users.
- Redemption can be separately controlled.
- Push/deep links can be rolled out independently.
- The initial customer actor gate is evaluated server-side and returned by the
  customer session endpoint.
- Do not silently treat a missing merchant flag as customer access.

Use the existing configuration/feature-flag system if one exists.

Do not introduce a new remote-config platform just for this.

---

# 26. TEST PLAN

The Customer App implementation is incomplete until all existing project QA requirements are extended to it.

## 26.1 Unit tests

Cover:

- phone normalization;
- customer identity resolution;
- account linking;
- duplicate prevention;
- points display;
- reward progress;
- reward eligibility;
- customer permissions;
- QR token handling;
- notification preferences;
- cached read model mapping.

## 26.2 Integration tests

Cover:

```text
Auth → Customer
Auth → Existing Customer
Merchant Customer → Customer Account
Sale → Points → Customer
Reward → Redemption
QR → Merchant Customer Identification
Offline Cache → Online Refresh
Notification → Deep Link
```

## 26.3 E2E scenario: existing customer

```text
Merchant creates customer
↓
Customer receives WhatsApp
↓
Customer opens MaisUm
↓
OTP
↓
Existing customer resolved
↓
Existing points/history shown
```

## 26.4 E2E scenario: sale

```text
Customer shows QR
↓
Merchant scans
↓
Merchant registers sale
↓
Loyalty engine awards points
↓
Customer balance updates
↓
Customer sees reward progress
```

## 26.5 E2E scenario: redemption

```text
Customer reaches reward
↓
Reward becomes available
↓
Customer taps Resgatar
↓
Server validates
↓
Redemption created
↓
Balance updated
↓
Merchant can verify redemption
```

---

# 27. OFFLINE QA

Mandatory scenarios:

1. Open Customer App offline.
2. Home renders cached data.
3. Rewards render cached data.
4. Activity renders cached data.
5. Business list renders cached data.
6. QR displays offline.
7. Network returns.
8. Data refreshes.
9. Customer attempts redemption offline.
10. Redemption is blocked.
11. No points are deducted.
12. No duplicate redemption is created.
13. App survives sync failure.

---

# 28. SECURITY QA

Verify:

- Customer A cannot read Customer B.
- Customer cannot access merchant endpoints.
- Customer cannot modify points.
- Customer cannot modify rewards.
- Customer cannot redeem another customer's reward.
- Customer cannot forge QR identity.
- Customer cannot bypass reward eligibility.
- Customer cannot replay a redemption request.
- Unauthorized business data is rejected.
- Firestore/API rules enforce actor and tenant isolation.

---

# 29. PERFORMANCE QA

Targets:

| Operation | Target |
|---|---:|
| Warm app launch | <2 sec |
| Cached Home | <300ms |
| Cached Rewards | <500ms |
| Cached Activity | <500ms |
| QR display | <300ms |
| QR scan | <1 sec |
| Online redemption | <3 sec |
| Local reads | <100ms where practical |

Avoid blocking the UI on network refresh.

---

# 30. LOW-END AND REAL-DEVICE QA

Test on:

- low-end Android;
- Android 8+ where supported by the existing app;
- poor network;
- intermittent network;
- airplane mode;
- app restart while offline;
- background/foreground transitions;
- small screens;
- one-handed usage;
- high-noise real-world environments.

---

# 31. UX RULES

Every Customer App screen must follow:

- large touch targets;
- short text;
- strong hierarchy;
- one primary action;
- minimal forms;
- minimal typing;
- obvious status;
- clear offline state;
- no unnecessary confirmation dialogs;
- no complex charts;
- no dense tables.

The customer should understand the screen in approximately one glance.

---

# 32. MVP SCREEN CHECKLIST

## Authentication

- [x] Welcome
- [x] Phone
- [x] OTP
- [x] Existing account linking
- [x] New customer creation

## Core

- [x] Home
- [x] Rewards
- [x] Activity
- [x] Businesses
- [x] Business detail
- [x] Customer QR
- [x] Reward redemption
- [x] Profile

## Platform

- [x] Offline cache
- [x] Connectivity state
- [x] Notifications
- [x] Deep links
- [x] Analytics
- [x] Feature flags

---

# 33. EXPLICIT NON-GOALS

Do not build in this implementation:

- marketplace;
- social feed;
- comments;
- followers;
- customer-to-customer messaging;
- public customer profiles;
- reviews;
- leaderboards;
- advanced gamification;
- AI assistant;
- paid membership;
- complex offers;
- multi-level membership;
- customer analytics dashboard.

---

# 34. IMPLEMENTATION ORDER

Execute vertical slices in this dependency order. Tests and merchant
regressions belong to every phase rather than a final QA-only phase.

## Phase 0 — Repository validation

- [x] Inspect repository and attached sync service.
- [x] Produce `docs/customer/CUSTOMER_APP_ARCHITECTURE_AUDIT.md`.
- [x] Map reusable code and gaps.
- [x] Correct this plan to match the feature-first codebase.

## Phase 1 — Customer identity and authorization

- [x] Add authenticated `GET /customer/session`.
- [x] Bind Firebase UID to canonical customer identity atomically.
- [x] Resolve canonical identity only from the verified token phone.
- [x] Return existing business links without creating duplicates.
- [x] Reject UID/canonical ownership conflicts.
- [x] Add customer request authorization helpers and tests.
- [x] Keep canonical/account Firestore collections server-only.
- [ ] Add Firestore emulator integration coverage for concurrent binding and
  business-link projection.

Deterministic transaction-contract coverage exercises the competing binding
retry path. Firestore emulator coverage remains pending because this repository
does not configure an emulator test target.

Exit criterion: identity binding is idempotent, tenant-safe and does not create
or grant merchant scope.

## Phase 2 — Actor-aware Flutter session and routing

- [x] Add an explicit merchant/customer actor type to auth state.
- [x] Preserve the current merchant OTP, PIN and onboarding path.
- [x] Add customer API/repository/providers without `activeMerchantIdProvider`.
- [x] Add `/customer/*` shell, navigation and actor guards.
- [x] Add a rollout-disabled customer placeholder state.
- [x] Test owner/staff/customer redirects.

Exit criterion: a customer reaches only `/customer/*`; owner/staff behavior is
unchanged.

## Phase 3 — Customer read model and offline cache

- [x] Define customer-safe session/home/business/reward/activity DTOs.
- [x] Add optimized customer home/read endpoints authorized by bound UID.
- [x] Expose confirmed points only.
- [x] Add customer-partitioned SQLite read cache and freshness metadata.
- [x] Implement cache-first rendering plus online refresh/reconciliation.
- [x] Clear or switch cache safely when the authenticated UID changes.

Exit criterion: authorized cached data opens offline and refreshes without any
merchant write-sync mutation.

## Phase 4 — Read-only MVP UI

- [x] Home.
- [x] Rewards and progress based on confirmed balance.
- [x] Activity.
- [x] Businesses.
- [x] Business detail.
- [x] Profile (read-only initially).
- [x] Offline/freshness/error states.

Exit criterion: the read-only MVP completes its unit/widget/integration tests
and merchant regressions.

## Phase 5 — Customer redemption

- [x] Add a customer-authorized redemption endpoint.
- [x] Reuse the ledger transaction/idempotency rules.
- [x] Issue the redemption code/token on the server.
- [x] Block offline redemption before request creation.
- [x] Refresh balance/activity after successful redemption.
- [ ] Verify redemption replay/concurrency with the Firestore emulator.

## Phase 6 — Customer QR and merchant scan

- [x] Add opaque or signed rotating/static token contract after threat review.
- [x] Cache only the safe display token needed offline.
- [x] Add customer QR display.
- [x] Add merchant scanner/resolution behind a separate flag.
- [x] Verify QR signature forgery and expiry with unit tests.
- [ ] Verify customer/business QR isolation with the Firestore emulator.

## Phase 7 — Engagement

- [x] Customer notification preferences.
- [x] FCM token registration/removal, permission and refresh handling behind
  `customer_push_enabled`; delivery producer remains intentionally absent.
- [x] Stable customer deep links.
- [x] Allow-listed `maisum://app/customer/...` links suitable for WhatsApp
  transport to Home/Reward/Business.
- [x] Customer-safe analytics events.
- [ ] Verify FCM delivery and notification/deep-link behavior on real devices.

## Phase 8 — Pilot and release QA

- [x] Full available unit, widget and integration test suite.
- [ ] Device-driven E2E suite.
- [ ] Offline, security and performance scenarios.
- [ ] Low-end/real-device testing.
- [x] Merchant regression suite through the full Flutter test run.
- [x] Pilot allow-list and fail-safe feature gates.
- [ ] Production rollback drill.

---

# 35. DEFINITION OF DONE

The Customer App MVP is complete only when:

## Architecture

- [x] Same Flutter repository.
- [x] Shared design system.
- [x] Shared domain concepts with API-boundary customer DTOs.
- [x] Shared auth with explicit actor context.
- [x] Shared Firestore infrastructure.
- [x] Shared SQLite infrastructure with customer read cache.
- [x] No parallel customer write-sync engine.
- [x] No duplicated canonical Customer.
- [x] No duplicated loyalty calculation.

## Customer

- [x] Phone authentication.
- [x] Existing customer linking.
- [x] Home.
- [x] Points.
- [x] Rewards.
- [x] Activity.
- [x] Businesses.
- [x] Business detail.
- [x] Customer QR.
- [x] Redemption.
- [x] Profile.

## Merchant integration

- [x] Merchant identifies customer through QR.
- [x] Merchant registers sale through the preserved existing flow.
- [x] Loyalty updates through the existing ledger projection.
- [x] Customer refreshes the confirmed balance.
- [x] Reward progress uses confirmed points.
- [x] Reward can be redeemed online.
- [x] Merchant receives a server-verifiable redemption code.

## Reliability

- [x] Cached home works offline.
- [x] Cached rewards work offline.
- [x] Cached activity works offline.
- [x] Non-expired QR works offline.
- [x] Redemption is blocked offline.
- [x] Refresh works after reconnect.
- [x] Duplicate account creation is prevented.

## Security

- [x] Customer API authorization derives identity from Firebase UID.
- [x] Merchant/customer route and request-scope isolation.
- [x] Server-authoritative points.
- [x] Server-authoritative redemption.
- [x] QR is signed, opaque and rejects forged/expired tokens.
- [x] Tenant/business access is checked through canonical relationship links.

## QA

- [x] Unit tests pass.
- [x] Available integration tests pass.
- [ ] E2E tests pass.
- [x] Deterministic cache/offline tests pass.
- [x] Available authorization, flag and token security tests pass.
- [ ] Performance targets pass.
- [x] Merchant regression suite passes.

---

# 36. FINAL PRODUCT LOOP

The implementation must preserve this complete system:

```text
CUSTOMER
   │
   │ shows QR / phone
   ↓
MERCHANT APP
   │
   │ registers sale
   ↓
LOYALTY ENGINE
   │
   │ awards points
   ↓
CUSTOMER APP
   │
   │ sees progress
   ↓
REWARD
   │
   │ becomes available
   ↓
WHATSAPP / PUSH
   │
   │ brings customer back
   ↓
CUSTOMER
   │
   │ returns
   ↓
MERCHANT
   │
   └── registers another sale
```

The Customer App is successful when it strengthens this loop, not when it accumulates features.

---

# 37. CODEx IMPLEMENTATION COMMAND

When executing this plan, Codex should follow this behavior:

1. Inspect before modifying.
2. Reuse before creating.
3. Extract shared code before duplicating.
4. Make the smallest safe change.
5. Keep merchant behavior stable.
6. Add tests with every domain change.
7. Run formatting and static analysis.
8. Run merchant regression tests after shared refactors.
9. Run customer tests after each feature.
10. Do not invent APIs/models when existing equivalents are available.
11. Do not add dependencies without first checking whether the repository already provides equivalent functionality.
12. Do not implement non-goals.
13. Stop and document blockers rather than silently changing architecture.

Required final implementation report:

```text
CUSTOMER_APP_IMPLEMENTATION_REPORT.md

Include:
- files changed;
- files created;
- shared components extracted;
- APIs added/changed;
- database migrations;
- Firestore rule changes;
- routes added;
- tests added;
- tests executed;
- known limitations;
- remaining TODOs;
- rollout/feature-flag status.
```

---

# 38. SUCCESS CRITERION

The implementation is successful when MaisUm feels like:

**one platform with two simple experiences**

—not:

**two apps sharing a database.**

The merchant builds the habit of registering sales.

The customer builds the habit of returning.

Everything else is secondary.
