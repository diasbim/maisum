# MaisUm

MaisUm is an offline-first Customer Retention Platform for small businesses:
**turn customers into regulars**. The existing Business Owner application is
the operational core; loyalty, rewards, engagement, and future customer
interfaces all build on one Customer Core.

## Product Governance

Future features are evaluated through a strict decision framework before they enter the roadmap. See `docs/feature_decision_framework.md`.

App-wide module decisions are tracked in `docs/app_feature_decision_register.md`.

Validate register coverage locally:

```bash
dart run tool/check_feature_decision_register.dart
```

## GitHub Pages Deployment

This repository deploys the static landing page from `docs/` to GitHub Pages via GitHub Actions.

1. In repository settings, enable GitHub Pages and set Source to GitHub Actions.
2. Push changes to `main` that touch `docs/` (or run `.github/workflows/deploy.yml` manually).
3. The workflow uploads `docs/` and publishes it to the `github-pages` environment.

## Quick Start

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d android --dart-define=API_BASE_URL=https://your-api.example.com
```

## Stack

| Layer | Package |
|---|---|
| State management | hooks_riverpod ^2.6.1 |
| Navigation | go_router ^14.6.3 |
| HTTP | dio ^5.7.0 |
| Local DB | sqflite ^2.3.3 |
| Models | freezed_annotation + json_annotation |
| Auth storage | flutter_secure_storage ^9.2.4 |
| Connectivity | connectivity_plus ^6.1.4 |
| Deep links | url_launcher ^6.3.1 |

## Project Structure

```
lib/
  app/           # App entry, router, all Riverpod providers
  core/          # Shared: constants, theme, errors, DB, network, storage, widgets
  features/
    auth/        # Splash → Login → OTP flow
    dashboard/   # Stats + quick-action buttons
    sales/       # New sale (3-tap flow)
    customers/   # List, search, detail, WhatsApp link
    rewards/     # Rewards list + create
    sync/        # Background sync engine + status indicator
    settings/    # Points ratio display, logout
```

Each feature follows `domain/` → `data/` → `presentation/` layering.

## Environment

Pass at build time via `--dart-define`:

| Variable | Default | Description |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:3000` | Backend base URL |
| `CLOUD_FUNCTIONS_API_BASE_URL` | `https://us-central1-loyaltyos-fc4dd.cloudfunctions.net/api` | Cloud Functions HTTP API base URL for non-sync endpoints (for example engage/notifications) |

Read in `AppConstants`:
```dart
static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000');
```

### Customer redemption pilot

Keep `CUSTOMER_REDEMPTION_ENABLED=true` behind both allow-lists during a
controlled pilot:

| Functions environment variable | Description |
|---|---|
| `CUSTOMER_REDEMPTION_ALLOWED_UIDS` | Comma-separated Firebase UIDs allowed to redeem |
| `CUSTOMER_REDEMPTION_ALLOWED_MERCHANT_IDS` | Comma-separated business IDs allowed to validate and consume |

When either allow-list is configured, an identifier that is missing from it is
denied. Omit both only after the pilot is approved for broad rollout.

Redemption lifecycle events are emitted to Cloud Logging as structured records
with `event="customer_redemption_lifecycle"`. They contain operational IDs,
state, surface, and rejection reason only; QR codes and customer contact data
are excluded.

## Points Calculation

```
points = floor(amount_mzn / 100)
```

Configured by the active business profile, with a default of 1 point per 100 MZN. A 200 MZN sale earns 2 points with that default.

## Offline Behaviour

1. Customer creation, visits, sales, and points earning go to SQLite first.
2. A `SyncItem` is enqueued in `sync_queue`.
3. `SyncService.processQueue()` runs when:
   - App returns to foreground
   - Connectivity changes from offline → online
4. Max 3 retries per item. Failed items are marked `status='failed'` and left for manual review.
5. The dashboard shows a pending-sync count badge on the sync indicator.

Final reward redemption is intentionally online-only. It is confirmed by a
server transaction against the canonical loyalty ledger so two devices cannot
overspend the same balance. Notification delivery is never part of the loyalty
transaction.

## Auth (MVP)

- Phone number → 6-digit OTP screen.
- **Offline mode**: any 6 digits are accepted and an offline session is created with a 30-day expiry.
- Token stored with `flutter_secure_storage` (Android encrypted shared preferences).
- Router guard redirects unauthenticated users to `/login` on every navigation.

## API Contract

### Auth

```
POST /auth/otp/request   { phone }
POST /auth/otp/verify    { phone, code } → { token, userId }
```

### Sync

Sync writes are enqueued locally and then applied as direct Firestore upserts
under `businesses/{businessUid}/{collection}/{entityId}` using merge semantics.
Deletes are mapped to Firestore document deletes.

### Customer Core and Retention

Authenticated business commands use:

```
POST /customer-core/identities/lookup
POST /customer-core/business-customers/link
POST /customer-core/business-customers/backfill
POST /loyalty/ledger/backfill
POST /loyalty/ledger/reconcile
POST /loyalty/redemptions
POST /retention/policies
POST /retention/classifications/scan
```

Firestore is authoritative for canonical identities, loyalty ledger entries,
domain events, lifecycle transitions, policies, and recommendations. Immutable
domain events are projected asynchronously and idempotently into PostgreSQL
`retention_domain_events` for analytics; PostgreSQL availability never
participates in the canonical customer or loyalty transaction.

## Android Build

```bash
# Debug
flutter build apk --debug --dart-define=API_BASE_URL=https://api.example.com

# Release (requires keystore)
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

- `applicationId`: `com.loyaltyos.loyaltyos`
- `minSdk`: 26 (Android 8.0)
- `targetSdk`: 34
- ProGuard enabled in release; keep rules in `android/app/proguard-rules.pro`

### Release Signing Setup

1. Generate an upload keystore once:

```bash
keytool -genkeypair -v -keystore keystore/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Copy `android/key.properties.example` to `android/key.properties`.

3. Fill in `android/key.properties` with your passwords, alias, and keystore path. The provided example assumes the keystore is stored at `keystore/upload-keystore.jks` from the project root.

4. Build the release APK:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

The signed APK will be generated at `build/app/outputs/flutter-apk/app-release.apk`.

## iOS Build

```bash
flutter build ios --release --dart-define=API_BASE_URL=https://api.example.com
```

- Deployment target: iOS 14.0
- Bundle ID: `com.loyaltyos.loyaltyos`
- WhatsApp deep links require `whatsapp` in `LSApplicationQueriesSchemes` (already in `Info.plist`)

## Database

SQLite schema version 25 is migrated additively. The existing merchant-scoped
`customers` table is the offline BusinessCustomer projection and links to a
canonical Firestore customer identity. Sales remain offline-first; confirmed
balances are projected from the server-owned `loyalty_ledger`. Legacy
`total_points` remains a compatibility projection during rollout.

## Testing

```bash
flutter test                  # widget smoke test
flutter analyze --no-fatal-infos  # must return "No issues found!"
```

## WhatsApp Integration

Customer detail screen includes a "Enviar WhatsApp" button that opens:
```
https://wa.me/258{phone}?text=Olá%20{name}%2C...
```

No API key is required for business-assisted delivery through `url_launcher`.
WhatsApp actions require recorded customer consent and are attributed as
retention actions. Offline messages use an idempotent customer-scoped queue;
the server rechecks tenant access, consent, and the customer phone before
accepting delivery.
