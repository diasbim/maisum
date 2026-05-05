# LoyaltyOS

Offline-first loyalty app for barbershops in Maputo, Mozambique. Barbers register sales in under 5 seconds, on low-end Android devices, with or without internet.

## Product Governance

Future features are evaluated through a strict decision framework before they enter the roadmap. See `docs/feature_decision_framework.md`.

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

Read in `AppConstants`:
```dart
static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000');
```

## Points Calculation

```
points = floor(amount_mzn / 100)
```

Configurable via `AppConstants.pointsPerMzn = 100`. 200 MZN haircut → 2 points.

## Offline Behaviour

1. Every write goes to SQLite first (immediate, always succeeds).
2. A `SyncItem` is enqueued in `sync_queue`.
3. `SyncService.processQueue()` runs when:
   - App returns to foreground
   - Connectivity changes from offline → online
4. Max 3 retries per item. Failed items are marked `status='failed'` and left for manual review.
5. The dashboard shows a pending-sync count badge on the sync indicator.

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

```
POST /sync
{
  id, operation, entityType, entityId, payload, createdAt
}
→ { success: true }
```

The backend is responsible for idempotent upserts using `entityId`.

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

## iOS Build

```bash
flutter build ios --release --dart-define=API_BASE_URL=https://api.example.com
```

- Deployment target: iOS 14.0
- Bundle ID: `com.loyaltyos.loyaltyos`
- WhatsApp deep links require `whatsapp` in `LSApplicationQueriesSchemes` (already in `Info.plist`)

## Database

SQLite version 2. Tables: `customers`, `sales`, `rewards`, `sync_queue`.

**Migration from v1**: `onUpgrade` drops and recreates the `customers` table (renames `nome→name`, `telefone→phone`) and creates the new tables.

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

No API key required — uses `url_launcher` deep link.
