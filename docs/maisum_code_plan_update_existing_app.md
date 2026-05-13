# CODE_PLAN.md
# MaisUm — Existing App Upgrade Implementation Plan

Version: 1.0  
Status: Execution Ready  
Platform: Flutter + Riverpod + SQLite + Spring Boot  
Product: MaisUm  
Primary KPI: Sales registered per day per merchant

---

# 1. CONTEXT

This document defines the engineering execution plan to upgrade the existing MaisUm mobile app into:

- a behaviour-driven loyalty operating system,
- an offline-first merchant tool,
- and a semi-automatic sale registration engine using M-Pesa/eMola SMS detection.

The implementation follows the existing strategic, UX and offline-first architecture already defined in the project documents. fileciteturn1file1L1-L20 fileciteturn1file2L1-L20 fileciteturn1file4L1-L40 fileciteturn1file5L1-L40 fileciteturn1file6L1-L40 fileciteturn1file7L1-L20 fileciteturn1file8L1-L40

Core Loop:

Register Sale → Assign Points → Bring Customer Back

Every implementation MUST reinforce this loop.

---

# 2. TARGET ARCHITECTURE

## Mobile

- Flutter 3.x
- Riverpod
- GoRouter
- SQLite (sqflite)
- Workmanager
- flutter_local_notifications
- permission_handler
- telephony / sms_advanced
- connectivity_plus
- flutter_secure_storage

---

## Backend

- Spring Boot 3
- PostgreSQL
- JWT Auth
- REST API
- Flyway migrations
- Redis (optional)
- WhatsApp provider integration

---

## Infrastructure

- Docker
- GitHub Actions
- Firebase Crashlytics
- Firebase Analytics
- Play Store Internal Testing

---

# 3. HIGH LEVEL IMPLEMENTATION PHASES

| Phase | Goal |
|---|---|
| Phase 1 | Behaviour Engine |
| Phase 2 | Quick Sale Optimization |
| Phase 3 | Offline Sync Hardening |
| Phase 4 | SMS Detection Infrastructure |
| Phase 5 | Smart Sale Suggestions |
| Phase 6 | WhatsApp Reinforcement |
| Phase 7 | Analytics + Monitoring |
| Phase 8 | Play Store Compliance |

---

# 4. PHASE 1 — BEHAVIOUR ENGINE

# Goal

Transform sale registration into merchant habit.

---

# 4.1 Dashboard Upgrade

## Tasks

### Mobile

- Refactor DashboardScreen
- Add DailySalesCard
- Add MerchantStreakCard
- Add ReturningCustomersCard
- Add OfflineStatusBanner
- Add SyncStatusChip

---

## UI Requirements

Dashboard MUST show:

- vendas do dia
- clientes recorrentes
- streak diária
- estado online/offline
- sincronização pendente

---

## Performance Requirements

Dashboard initial render:

< 500ms

---

# 4.2 Sale Success Feedback

## Create Components

```text
lib/features/sales/presentation/widgets/
    sale_success_card.dart
    reward_progress_bar.dart
    sale_success_overlay.dart
```

---

## Behaviour

After successful sale:

- green success state
- haptic feedback
- short success sound
- reward progress
- WhatsApp queue state

---

## Acceptance Criteria

- feedback visible in <300ms
- auto-dismiss in 1.2s
- no blocking modal

---

# 4.3 Reward Progress Engine

## Backend Tasks

Add endpoint:

```http
GET /customers/{id}/reward-progress
```

Response:

```json
{
  "currentPoints": 35,
  "nextReward": "Corte Grátis",
  "pointsRemaining": 15,
  "progressPercentage": 70
}
```

---

## Mobile Tasks

- create RewardProgressModel
- create RewardProgressProvider
- render progress in:
  - dashboard
  - customer details
  - success state
  - WhatsApp preview

---

# 4.4 Merchant Streak System

## Database Changes

### SQLite

```sql
ALTER TABLE merchants
ADD COLUMN streak_days INTEGER DEFAULT 0;
```

### PostgreSQL

```sql
ALTER TABLE merchants
ADD COLUMN streak_days INTEGER DEFAULT 0;
```

---

## Logic

Track:

- consecutive active days
- grace period
- sales/day

---

## Services

```text
lib/core/services/streak/
    streak_service.dart
    streak_calculator.dart
```

---

# 5. PHASE 2 — QUICK SALE OPTIMIZATION

# Goal

Reduce average sale registration to ≤ 3 seconds.

---

# 5.1 New Sale Flow Refactor

## Replace current flow with:

```text
Dashboard
   ↓
Quick Sale
   ↓
Success Overlay
   ↓
Dashboard
```

---

# 5.2 Quick Amount Buttons

## Add

- 100 MT
- 200 MT
- 300 MT
- 500 MT
- Último valor

---

# 5.3 Recent Customers

## Add

```text
RecentCustomersHorizontalList
```

Logic:

- show last 10 customers
- prioritize recurring customers

---

# 5.4 One-Hand UX Optimization

## Constraints

- thumb reachable actions
- bottom aligned CTA
- large tap areas
- minimum typing

Reference UX requirements already defined. fileciteturn1file2L1-L80

---

# 6. PHASE 3 — OFFLINE-FIRST HARDENING

# Goal

Guarantee full app operation without internet.

---

# 6.1 Local Queue Engine

## Create

```text
lib/core/sync/
    sync_queue.dart
    sync_worker.dart
    sync_retry_policy.dart
    sync_conflict_resolver.dart
```

---

# 6.2 SQLite Tables

```sql
CREATE TABLE sync_queue (
    id TEXT PRIMARY KEY,
    entity_type TEXT,
    entity_id TEXT,
    payload TEXT,
    retry_count INTEGER,
    status TEXT,
    created_at INTEGER
);
```

---

# 6.3 Sync Worker

## Responsibilities

- retry failed sync
- exponential backoff
- background sync
- network recovery sync
- deduplication

---

# 6.4 Workmanager Jobs

## Add

```dart
Workmanager().registerPeriodicTask(
  'sync-task',
  'background-sync',
  frequency: Duration(minutes: 15),
);
```

---

# 6.5 Offline Visual States

## UI

Show:

- Offline
- Sincronizando
- Sincronizado
- Falha na sincronização

---

# 7. PHASE 4 — SMS DETECTION INFRASTRUCTURE

# Goal

Semi-automatic sale registration using payment confirmations.

---

# 7.1 Android Permissions

## Add

```xml
<uses-permission android:name="android.permission.RECEIVE_SMS"/>
<uses-permission android:name="android.permission.READ_SMS"/>
```

---

# 7.2 SMS Listener

## Create

```text
android/app/src/main/kotlin/.../
    SmsReceiver.kt
```

---

## Flutter Bridge

```text
lib/core/sms/
    sms_listener_service.dart
    sms_channel_bridge.dart
```

---

# 7.3 SMS Parsing Engine

## Create

```text
lib/core/sms/parsers/
    mpesa_parser.dart
    emola_parser.dart
    parser_registry.dart
```

---

## Extract Fields

- amount
- sender phone
- transaction id
- timestamp
- reference

---

## Regex Example

```dart
final amountRegex = RegExp(r'(\\d+[.,]?\\d*)\\s?MT');
```

---

# 7.4 Transaction Validation

## Create

```text
lib/core/sms/validation/
    transaction_validator.dart
    duplicate_detector.dart
```

---

## Duplicate Hash

```dart
sha256(provider + transactionId + amount + timestamp)
```

---

# 7.5 SMS Storage Rules

## MUST NOT

- upload full SMS inbox
- store unrelated messages
- store personal SMS history

Only payment confirmation metadata allowed.

---

# 8. PHASE 5 — SMART SALE SUGGESTIONS

# Goal

Transform SMS detection into one-tap sale registration.

---

# 8.1 Customer Match Engine

## Create

```text
lib/core/matching/
    customer_match_engine.dart
```

---

## Matching Priority

1. exact phone
2. recent customer
3. manual fallback

---

# 8.2 Suggested Sale Popup

## Component

```text
SuggestedSaleBottomSheet
```

---

## UX

```text
Recebido 500 MT de Carlos
Adicionar 5 pontos?
```

Buttons:

- Confirmar
- Ignorar

---

## Constraints

- non-blocking
- dismissible
- fast confirmation

---

# 8.3 Auto-Fill Sale Flow

## Behaviour

If merchant confirms:

- create sale automatically
- assign points
- queue WhatsApp
- show success overlay

---

# 9. PHASE 6 — WHATSAPP REINFORCEMENT

# Goal

Turn WhatsApp into customer return engine.

---

# 9.1 WhatsApp Templates

## Create templates

### Sale Confirmation

```text
Obrigado 🙌
Ganhou 5 pontos ⭐
Faltam 10 para corte grátis ✂️
```

---

### Inactive Customer

```text
Sentimos sua falta 😄
Tem pontos acumulados.
Volte esta semana ✂️
```

---

# 9.2 WhatsApp Queue

## Backend

Create:

```text
NotificationQueueService
```

---

## Responsibilities

- retry failed messages
- delayed sends
- offline retry
- delivery status

---

# 9.3 Merchant Completion Feedback

## UI

Show:

- WhatsApp enviado ✅
- Será enviado quando online

This reinforces behavioural completion.

---

# 10. PHASE 7 — ANALYTICS + MONITORING

# Goal

Measure behaviour loops.

---

# 10.1 Mandatory Metrics

Track:

- sales/day
- avg sale registration time
- daily active merchants
- suggestion acceptance rate
- repeat customers
- streak participation
- WhatsApp delivery rate
- sync failures
- offline usage rate

---

# 10.2 Firebase Analytics

## Events

```text
sale_registered
sale_suggested
sale_suggestion_accepted
whatsapp_sent
reward_redeemed
merchant_streak_updated
```

---

# 10.3 Crash Monitoring

## Integrate

- Firebase Crashlytics
- Sentry (optional)

---

# 11. PHASE 8 — PLAY STORE COMPLIANCE

# Goal

Pass Google Play review for SMS permissions.

---

# 11.1 Permission Onboarding Screen

## Explain clearly:

```text
MaisUm usa SMS apenas para detectar pagamentos M-Pesa/eMola
para acelerar o registo de vendas.

Nenhuma mensagem pessoal será lida.
```

---

# 11.2 Privacy Policy Update

## MUST INCLUDE

- SMS usage justification
- payment-only processing
- local-only processing
- no personal message collection

---

# 11.3 Play Store Declarations

## Required

- SMS permissions form
- core functionality justification
- demo video

---

# 12. BACKEND IMPLEMENTATION PLAN (SPRING BOOT)

# 12.1 New Modules

```text
src/main/java/com/maisum/
    sales/
    rewards/
    streaks/
    notifications/
    analytics/
```

---

# 12.2 New APIs

| Method | Endpoint |
|---|---|
| POST | /sales |
| GET | /customers/{id}/reward-progress |
| GET | /dashboard/summary |
| POST | /notifications/whatsapp |
| POST | /sales/sync |
| GET | /analytics/merchant |
|

---

# 12.3 Idempotency

Every sale MUST include:

```json
{
  "localId": "uuid"
}
```

Prevent duplicate sync.

---

# 12.4 Database Migrations

## Flyway

Create migrations for:

- streaks
- reward progress
- notification queue
- analytics events
- sync metadata

---

# 13. FILE STRUCTURE TARGET

```text
lib/
 ├── core/
 │   ├── analytics/
 │   ├── sms/
 │   ├── sync/
 │   ├── notifications/
 │   ├── services/
 │   ├── database/
 │   └── widgets/
 │
 ├── features/
 │   ├── auth/
 │   ├── dashboard/
 │   ├── customers/
 │   ├── rewards/
 │   ├── sales/
 │   ├── streaks/
 │   └── onboarding/
 │
 └── shared/
```

---

# 14. QA PLAN

# 14.1 Unit Tests

## MUST COVER

- points calculation
- streak engine
- parser engine
- duplicate detector
- sync retry logic
- customer matcher

---

# 14.2 Integration Tests

## MUST COVER

- sale registration
- offline sync
- SMS detection flow
- WhatsApp queue
- reward progress updates

---

# 14.3 Real Device Tests

## Test Devices

- Samsung A03
- Tecno Spark
- Infinix Hot
- Redmi A series

---

## Test Conditions

- 3G
- unstable WiFi
- offline mode
- background app state
- battery saver enabled

---

# 15. CI/CD PLAN

# GitHub Actions

## Pipeline

```yaml
- flutter analyze
- flutter test
- build apk
- build appbundle
- upload artifacts
```

---

# Android Releases

Tracks:

- Internal
- Closed Testing
- Production

---

# 16. PERFORMANCE TARGETS

| Operation | Target |
|---|---|
| App launch | < 2s |
| Sale registration | < 3s |
| Success feedback | < 300ms |
| SMS detection | < 2s |
| SQLite write | < 100ms |
| Dashboard render | < 500ms |

---

# 17. EXPLICIT NON-GOALS

DO NOT BUILD:

- customer app
- advanced analytics dashboards
- AI features
- multi-branch systems
- complex POS integrations
- banking APIs
- loyalty marketplace

---

# 18. FINAL ENGINEERING PRINCIPLE

MaisUm is not a dashboard.

It is:

A behaviour operating system.

Every screen, service, API and database decision MUST reinforce:

Register Sale → Assign Points → Bring Customer Back

