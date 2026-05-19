# Retention + Appointments Execution Backlog

This backlog converts the strategy into incremental PRs with strict scope, acceptance criteria, and test gates.

## Delivery Principles

- Keep each PR deployable and reversible.
- Keep UX simple and fast for daily use.
- Local-first writes for all user actions.
- Sync and cloud jobs must be idempotent.
- Prefer additive changes; avoid broad refactors.

## PR1 - Data Foundation (Local DB + Sync Contracts)

### Objective

Create local persistence and sync contract support for appointments and retention metrics before adding UI.

### Scope

- Add DB migration version 15.
- Add SQLite tables:
  - appointments
  - retention_metrics
- Add indexes for local query speed.
- Add sync entity registrations for:
  - appointment
  - retention_metric
- Add remote apply handlers and synced mark handlers.
- Add Firestore transport map entries.

### Files (expected)

- lib/core/constants/app_constants.dart
- lib/core/database/app_migrations.dart
- lib/features/sync/sync_service.dart
- lib/core/services/firestore_sync_service.dart

### Acceptance Criteria

- App boots with DB migration from v14 to v15 without crash.
- New tables exist and are queryable offline.
- Sync engine can push/pull appointment and retention_metric entities.
- No regressions in existing entity sync.

### Test Gate

- Migration test for v14 -> v15 schema.
- Sync unit tests for new entity routing.
- Smoke run: create sample rows locally and run queue processing.

---

## PR2 - Appointments Domain + Data Layer

### Objective

Implement Appointment model, DAO/repository, and command APIs with optimistic local-first behavior.

### Scope

- Add feature module structure:
  - lib/features/appointments/data
  - lib/features/appointments/domain
  - lib/features/appointments/presentation
  - lib/features/appointments/providers
  - lib/features/appointments/widgets
  - lib/features/appointments/services
- Implement Appointment model:
  - fromJson
  - toJson
  - copyWith
  - equality
- Implement repository methods:
  - createAppointment
  - updateAppointment
  - cancelAppointment
  - getUpcomingAppointments
  - markAppointmentAsMissed
- Queue sync items for create/update/cancel.

### Files (expected)

- lib/features/appointments/domain/appointment.dart
- lib/features/appointments/data/appointment_repository.dart
- lib/features/appointments/data/appointment_dao.dart

### Acceptance Criteria

- Appointment create/update/cancel works while offline.
- Upcoming query is sorted and filtered correctly.
- Sync payloads are generated and queued correctly.
- No dependency on UI yet.

### Test Gate

- Unit tests for model serialization and riskless copyWith.
- Repository tests for each method.
- DAO query tests for upcoming filter and ordering.

---

## PR3 - Post-Sale Scheduling UX + Providers

### Objective

Integrate scheduling into post-sale success flow with quick choices and manual date picker.

### Scope

- Add Riverpod providers:
  - appointmentsProvider
  - upcomingAppointmentsProvider
  - createAppointmentProvider
- Extend sale success UX with CTA:
  - quick options: 7, 14, 21, 30 days
  - manual date picker
  - save action and status feedback
- Trigger local scheduling service for reminder metadata.
- Keep user flow fast and optional.

### Files (expected)

- lib/features/sales/presentation/sale_success_screen.dart
- lib/features/appointments/providers/appointments_providers.dart
- lib/app/router.dart (if route is needed)

### Acceptance Criteria

- After sale success, user can schedule in <= 3 taps.
- Action completes quickly even offline (local-first).
- Errors are non-blocking and user-friendly.
- Existing sale success behavior remains intact.

### Test Gate

- Widget tests for quick date buttons and date picker path.
- Provider tests for loading/success/error transitions.
- Manual UX check for low-friction flow.

---

## PR4 - Retention Domain + Dashboard UI

### Objective

Deliver retention intelligence in a simple two-tab dashboard.

### Scope

- Add feature module structure:
  - lib/features/retention/data
  - lib/features/retention/domain
  - lib/features/retention/presentation
  - lib/features/retention/providers
  - lib/features/retention/widgets
  - lib/features/retention/services
- Implement RetentionMetric model:
  - fromJson
  - toJson
  - copyWith
  - equality
- Implement repository methods:
  - getRecurringCustomers
  - getInactiveCustomers
  - calculateRetention
  - updateCustomerRisk
- Add providers:
  - recurringCustomersProvider
  - inactiveCustomersProvider
  - retentionDashboardProvider
- Build RetentionDashboardScreen with tabs:
  - Recorrentes
  - Em risco
- Build cards:
  - RecurringCustomerCard
  - InactiveCustomerCard

### Files (expected)

- lib/features/retention/domain/retention_metric.dart
- lib/features/retention/data/retention_repository.dart
- lib/features/retention/providers/retention_providers.dart
- lib/features/retention/presentation/retention_dashboard_screen.dart
- lib/features/retention/widgets/recurring_customer_card.dart
- lib/features/retention/widgets/inactive_customer_card.dart
- lib/app/router.dart

### Acceptance Criteria

- Risk rules are applied exactly:
  - 0-14 active
  - 15-29 attention
  - 30-59 risk
  - 60+ lost
- Dashboard supports loading, empty, and error states.
- Dashboard remains responsive on small screens.
- Send reminder CTA is visible for at-risk customers.

### Test Gate

- Unit tests for risk classification boundaries.
- Widget tests for tab rendering and card content.
- Snapshot/golden checks for compact layouts.

---

## PR5 - Notifications + Cloud Functions

### Objective

Implement reminder dispatch and retention metric calculation in backend jobs.

### Scope

- Add local notification scheduling service integration in app.
- Implement cloud function:
  - dailyAppointmentReminder
- Implement cloud function:
  - calculateRetentionMetrics
- Ensure idempotency and duplicate-send protection.
- Update reminderSent / updatedAt consistently.

### Files (expected)

- functions/src/index.ts
- lib/features/appointments/services/appointment_notification_service.dart

### Acceptance Criteria

- Daily reminder job processes only eligible appointments.
- Metrics job updates retention_metrics deterministically.
- Re-running a job does not duplicate sends or corrupt metrics.
- Function logs are actionable for failures.

### Test Gate

- Emulator tests for both scheduled jobs.
- Logic tests for eligibility windows.
- Dry-run mode test with no outgoing side effects.

---

## PR6 - Firestore Indexes + Hardening + Release Checks

### Objective

Finalize query performance, reliability, and production readiness.

### Scope

- Add Firestore composite indexes:
  - merchantId + scheduledDate
  - merchantId + riskLevel
  - merchantId + lastVisitAt
- Add instrumentation for key events.
- Validate target performance goals.
- Add rollback notes and release checklist.

### Files (expected)

- firestore.indexes.json
- docs/retention_appointments_execution_backlog.md (status updates)

### Acceptance Criteria

- Firestore queries run without missing-index runtime errors.
- End-to-end flow passes on emulator and real device smoke tests.
- Performance goals are met or documented with mitigation actions.

### Test Gate

- End-to-end smoke:
  - sale -> success -> appointment
  - offline appointment create -> online sync
  - retention dashboard load and refresh
- Deployment dry run for functions and indexes.

---

## Cross-PR Non-Functional Checklist

- Offline-first: all create/update/cancel operations are local-first.
- Sync safety: retries, dedupe, and conflict handling documented.
- UX clarity: no heavy ERP patterns; minimal steps and clear CTA labels.
- Telemetry: add event names for appointment_created, reminder_sent, retention_level_changed.
- Documentation: keep this backlog updated with done/pending items.

## Suggested Branching Strategy

- feature/appointments-retention-pr1-foundation
- feature/appointments-retention-pr2-appointments-data
- feature/appointments-retention-pr3-post-sale-ux
- feature/appointments-retention-pr4-retention-dashboard
- feature/appointments-retention-pr5-notifications-functions
- feature/appointments-retention-pr6-hardening

## Go/No-Go Checklist Before Production

- DB migration validated from production-like snapshot.
- Firestore indexes deployed and active.
- Scheduled functions tested in emulator and staging.
- Offline create/update flows verified on airplane mode.
- Monitoring alerts configured for function failures.
