# TEST_PLAN.md
# MaisUm — Feature Validation & QA Test Document

Version: 1.0  
Status: QA Ready  
Platform: Android (Flutter) + Spring Boot Backend  
Product: MaisUm  
Primary KPI: Sales registered per day per merchant

---

# 1. PURPOSE

This document defines the complete validation strategy for the new MaisUm behaviour-driven and semi-automatic registration features.

The objective is to validate:

- operational reliability,
- merchant usability,
- offline resilience,
- behaviour reinforcement,
- SMS detection accuracy,
- and performance under real Maputo conditions.

This document follows the offline-first, WhatsApp-first and low-connectivity principles already defined in the product architecture and UX documentation.

---

# 2. PRIMARY VALIDATION GOALS

## Goal 1 — Reduce Forgotten Registrations

Validate that merchants:

- register more sales,
- forget fewer transactions,
- and complete registrations faster.

---

## Goal 2 — Increase Merchant Daily Habit

Validate:

- repeated daily usage,
- streak engagement,
- operational consistency.

---

## Goal 3 — Validate Semi-Automatic Registration

Validate:

- SMS detection,
- transaction parsing,
- duplicate prevention,
- customer matching,
- suggestion accuracy.

---

## Goal 4 — Validate Offline Reliability

Validate that the app continues functioning:

- without internet,
- with unstable connectivity,
- during sync failures,
- during background operation.

---

# 3. TEST ENVIRONMENTS

# 3.1 Android Devices

## Required Physical Devices

| Device | Android |
|---|---|
| Samsung A03 | 11 |
| Tecno Spark | 12 |
| Infinix Hot | 13 |
| Redmi A2 | 13 |
| Samsung J Series | 8 |

---

# 3.2 Connectivity Conditions

## Test Conditions

- Offline
- Weak 3G
- Intermittent WiFi
- Slow network
- Battery saver enabled
- Background restrictions enabled

---

# 3.3 Backend Environment

## Required

- staging backend
- local backend
- offline-only mode

---

# 4. TEST CATEGORIES

| Category | Objective |
|---|---|
| Unit Tests | Validate isolated logic |
| Integration Tests | Validate service communication |
| E2E Tests | Validate complete flows |
| Offline Tests | Validate disconnected behaviour |
| Performance Tests | Validate speed |
| UX Tests | Validate simplicity |
| Behaviour Tests | Validate habit reinforcement |
| SMS Tests | Validate transaction detection |
| Regression Tests | Prevent feature breakage |

---

# 5. UNIT TEST PLAN

# 5.1 Points Calculation Engine

## Objective

Validate loyalty points logic.

---

## Test Cases

| Test | Expected Result |
|---|---|
| 100 MT purchase | 1 point |
| 250 MT purchase | 2 points |
| 999 MT purchase | 9 points |
| zero value | 0 points |
| negative value | rejected |

---

## Example

```dart
expect(calculatePoints(500), 5);
```

---

# 5.2 Reward Progress Engine

## Validate

- progress percentage
- next reward logic
- remaining points

---

## Example

| Current | Required | Expected |
|---|---|---|
| 20 | 50 | 40% |
| 45 | 50 | 90% |

---

# 5.3 Streak Engine

## Validate

- consecutive days
- grace period
- streak reset

---

## Test Cases

| Scenario | Expected |
|---|---|
| active 7 days | streak = 7 |
| miss 1 day | preserved |
| miss 2 days | reset |

---

# 5.4 SMS Parser Engine

## Objective

Validate transaction extraction.

---

## Input Example

```text
Recebeu 500 MT de 841234567.
Txn ID: ABC123
```

---

## Expected

```json
{
  "amount": 500,
  "phone": "841234567",
  "transactionId": "ABC123"
}
```

---

# 5.5 Duplicate Detection

## Validate

- same SMS not processed twice
- same transaction hash ignored

---

## Test Cases

| Scenario | Expected |
|---|---|
| repeated SMS | ignored |
| duplicated transaction ID | ignored |
| unique transaction | accepted |

---

# 5.6 Customer Match Engine

## Validate

- exact phone match
- recent customer fallback
- manual fallback

---

## Success Threshold

≥ 80% automatic match accuracy.

---

# 6. INTEGRATION TEST PLAN

# 6.1 Sale Registration Flow

## Flow

Dashboard → Quick Sale → Success Overlay

---

## Validate

- sale stored locally
- points assigned
- reward updated
- sync queue created
- UI feedback shown

---

## Acceptance Criteria

Complete flow:

≤ 3 seconds

---

# 6.2 Offline Sync Flow

## Scenario

Merchant creates sales offline.

---

## Validate

- local persistence
- queued sync
- automatic retry
- no data loss
- no duplicates

---

## Test Steps

1. disable internet
2. create 10 sales
3. reopen app
4. restore internet
5. validate sync

---

## Expected

- all 10 sales synchronized
- no duplicates
- queue emptied

---

# 6.3 SMS → Suggestion → Sale Flow

## Validate

- SMS detected
- parsed correctly
- customer matched
- popup shown
- sale created
- WhatsApp queued

---

## Acceptance Criteria

Full flow completed:

≤ 5 seconds

---

# 6.4 WhatsApp Queue Flow

## Scenario

Merchant offline during message trigger.

---

## Validate

- message queued
- retry later
- merchant informed silently
- no duplicate sends

---

# 6.5 Dashboard Metrics Flow

## Validate

Dashboard updates instantly after:

- new sale
- streak update
- sync completion

---

# 7. END-TO-END (E2E) TESTS

# 7.1 Complete Merchant Journey

## Flow

1. Login
2. Register customer
3. Create sale
4. Assign points
5. Send WhatsApp
6. View reward progress
7. Return to dashboard

---

## Expected

Entire flow:

≤ 30 seconds

---

# 7.2 Semi-Automatic Registration Journey

## Flow

1. Receive M-Pesa SMS
2. Detect SMS
3. Parse transaction
4. Match customer
5. Show popup
6. Merchant confirms
7. Sale registered
8. WhatsApp triggered

---

## Expected

- one-tap registration
- no manual typing
- correct customer

---

# 7.3 Offline Recovery Journey

## Flow

1. disable internet
2. create sales
3. close app
4. reopen app
5. reconnect internet
6. validate sync recovery

---

## Expected

- no data loss
- all sales synchronized
- app stable

---

# 8. PERFORMANCE TEST PLAN

# 8.1 Performance Targets

| Operation | Target |
|---|---|
| App launch | < 2s |
| Dashboard render | < 500ms |
| Sale registration | < 3s |
| Success feedback | < 300ms |
| SMS detection | < 2s |
| SQLite write | < 100ms |

---

# 8.2 Stress Tests

## Validate

- 500 local sales
- 100 queued sync operations
- rapid SMS bursts
- low storage devices

---

# 8.3 Battery Tests

## Validate

- background sync impact
- SMS listener battery usage
- Workmanager behaviour

---

# 9. OFFLINE TEST PLAN

# 9.1 Complete Offline Usage

## Validate

Merchant can:

- open app
- search customer
- create sale
- assign points
- view dashboard
- view rewards

without internet.

---

# 9.2 Sync Recovery

## Validate

- retry policy
- exponential backoff
- queue recovery

---

# 9.3 App Restart Recovery

## Scenario

Force close app during sync.

---

## Expected

- no corrupted queue
- retry continues later

---

# 10. UX VALIDATION TESTS

# 10.1 Quick Sale Simplicity

## Objective

Validate low cognitive load.

---

## Acceptance Criteria

New merchants can:

- register sale without training
- complete sale in ≤ 3 taps
- understand success state immediately

---

# 10.2 One-Hand Usage

## Validate

- thumb reachability
- button size
- readability on small screens

---

# 10.3 Merchant Observation Sessions

## Required

Observe real barbers:

- during haircut flow
- under noisy conditions
- during busy periods

---

## Record

- hesitation points
- forgotten actions
- confusion areas
- time per sale

---

# 11. BEHAVIOURAL VALIDATION TESTS

# 11.1 Daily Habit Validation

## Objective

Validate if merchants naturally return daily.

---

## Metrics

- DAU
- streak participation
- sales/day increase
- repeat sessions/day

---

# 11.2 Reward Anticipation Validation

## Validate

Customers react positively to:

- reward progress
- WhatsApp notifications
- nearing reward state

---

# 11.3 Merchant Motivation Validation

## Validate if merchants notice:

- streaks
- progress indicators
- WhatsApp sent states
- customer return effects

---

# 12. SMS DETECTION VALIDATION

# 12.1 Supported Providers

## Validate

- M-Pesa
- eMola

---

# 12.2 SMS Variations

## Validate

- Portuguese variations
- spacing changes
- capitalization changes
- older SMS formats

---

# 12.3 False Positive Tests

## Validate system ignores:

- airtime messages
- promotions
- spam SMS
- personal messages

---

## Expected

False positives:

< 1%

---

# 12.4 Background Detection Tests

## Validate

Detection works:

- app minimized
- screen locked
- battery saver enabled

---

# 13. SECURITY TEST PLAN

# 13.1 SMS Privacy Validation

## Validate

- unrelated SMS ignored
- inbox not uploaded
- only payment metadata stored

---

# 13.2 Authentication Tests

## Validate

- expired token handling
- unauthorized requests
- session persistence

---

# 13.3 Local Storage Encryption

## Validate

- secure token storage
- encrypted sensitive data
- secure SQLite access

---

# 14. PLAY STORE COMPLIANCE TESTS

# 14.1 SMS Permission Flow

## Validate

- permission requested contextually
- clear explanation shown
- merchant understands benefit

---

# 14.2 Permission Denial Flow

## Validate

App still works if:

- SMS permissions denied

Manual registration MUST remain functional.

---

# 15. ANALYTICS VALIDATION

# Validate events fire correctly

| Event | Trigger |
|---|---|
| sale_registered | sale completed |
| sale_suggested | SMS suggestion shown |
| sale_suggestion_accepted | merchant confirms |
| whatsapp_sent | successful queue send |
| streak_updated | streak increases |
| reward_redeemed | reward used |

---

# 16. REGRESSION TEST CHECKLIST

Before every release validate:

- login
- onboarding
- customer registration
- sale registration
- points assignment
- offline mode
- sync engine
- dashboard
- rewards
- WhatsApp queue
- SMS detection
- app startup

---

# 17. PILOT VALIDATION PLAN

# Phase 1 — Internal Testing

Test with:

- 2 barbershops
- 7 days

---

# Validate

- operational flow
- forgotten sales
- merchant reactions
- app stability

---

# Phase 2 — Controlled Pilot

Test with:

- 5–10 barbershops
- 30 days

---

# Metrics

- sales/day increase
- suggestion acceptance rate
- DAU
- retention
- sync failures

---

# Phase 3 — Public Rollout

Expand gradually.

Monitor:

- crash rate
- SMS parser failures
- Play Store issues
- WhatsApp delivery rate

---

# 18. RELEASE ACCEPTANCE CRITERIA

A release is approved only if:

## Functional

- critical flows operational
- no blocking bugs
- offline stable
- sync reliable

---

## Performance

- performance targets achieved
- no ANRs
- no memory leaks

---

## UX

- merchants complete sale in ≤ 3 taps
- low confusion observed
- success feedback instant

---

## Behaviour

- merchants use app daily
- streak engagement visible
- customer return indicators positive

---

## SMS Engine

- parser accuracy ≥ 95%
- duplicate prevention working
- false positives < 1%

---

# 19. FINAL QA PRINCIPLE

MaisUm is not only software.

It is:

A behaviour system operating inside real barbershops in Maputo.

Therefore testing MUST validate:

- speed,
- habit formation,
- operational simplicity,
- and resilience under real-world conditions.

