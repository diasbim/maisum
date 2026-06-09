# App Feature Decision Register

This register applies the Feature Decision Framework to the entire app.

Source framework: docs/feature_decision_framework.md

Scope rule:

- Every module under lib/features must have one section in this file.
- New modules must add a new section before merge.

## Module Coverage Snapshot

Covered modules:

- appointments
- auth
- customers
- dashboard
- engage
- legal
- onboarding
- retention
- rewards
- sales
- settings
- subscription
- sync

## Module Decisions

### Module: appointments

Feature name: Appointment list and customer follow-through
Problem: Barbers need visibility of upcoming cuts to reduce no-shows and keep daily rhythm.
Target user moment: At opening and between services.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 4
- Retention (0-5): 4
- WhatsApp engagement (0-5): 1
- Offline reliability (0-5): 3

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (4/5) x 25 = 20
- Retention: (4/5) x 20 = 16
- WhatsApp: (1/5) x 10 = 2
- Offline: (3/5) x 15 = 9
- Total = 71

Evidence level: B
Delivery risk: Low
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep one-screen agenda list with pull-to-refresh.
- Keep one-tap jump to customer details.
- Delay advanced scheduling configuration.

### Module: auth

Feature name: Phone auth, OTP, PIN setup, post-auth routing
Problem: Login must be fast and reliable on unstable mobile networks.
Target user moment: First open and every return session.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 5
- Retention (0-5): 3
- WhatsApp engagement (0-5): 1
- Offline reliability (0-5): 4

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (5/5) x 25 = 25
- Retention: (3/5) x 20 = 12
- WhatsApp: (1/5) x 10 = 2
- Offline: (4/5) x 15 = 12
- Total = 75

Evidence level: B
Delivery risk: Medium
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep OTP + PIN flow with minimal steps.
- Keep post-auth routing deterministic.
- Avoid adding optional branches during login.

### Module: customers

Feature name: Customer list, detail, quick contact
Problem: Staff need fast lookup and context while serving customers.
Target user moment: During sale registration and follow-up.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? Yes
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 4
- Retention (0-5): 4
- WhatsApp engagement (0-5): 3
- Offline reliability (0-5): 3

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (4/5) x 25 = 20
- Retention: (4/5) x 20 = 16
- WhatsApp: (3/5) x 10 = 6
- Offline: (3/5) x 15 = 9
- Total = 75

Evidence level: B
Delivery risk: Low
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep list -> detail path optimized for quick search.
- Keep direct WhatsApp action simple.
- Avoid dense profile or CRM-like complexity.

### Module: dashboard

Feature name: Daily dashboard and quick actions
Problem: Operators need a fast overview and launch point for core tasks.
Target user moment: Immediately after login and throughout the day.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 4
- Retention (0-5): 3
- WhatsApp engagement (0-5): 2
- Offline reliability (0-5): 3

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (4/5) x 25 = 20
- Retention: (3/5) x 20 = 12
- WhatsApp: (2/5) x 10 = 4
- Offline: (3/5) x 15 = 9
- Total = 69

Evidence level: B
Delivery risk: Low
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep dashboard focused on top KPIs and quick actions.
- Avoid adding non-operational widgets.
- Keep rendering lightweight for low-end devices.

### Module: engage

Feature name: Engage dashboard, recovery actions, visits, surveys
Problem: Merchants need proactive tools to recover customers before churn.
Target user moment: Daily review and recovery execution.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? Yes
- Improve offline reliability? No

Scoring:

- Sales registrations (0-5): 3
- Friction reduction (0-5): 3
- Retention (0-5): 5
- WhatsApp engagement (0-5): 4
- Offline reliability (0-5): 2

Weighted total:

- Sales: (3/5) x 30 = 18
- Friction: (3/5) x 25 = 15
- Retention: (5/5) x 20 = 20
- WhatsApp: (4/5) x 10 = 8
- Offline: (2/5) x 15 = 6
- Total = 67

Evidence level: B
Delivery risk: Medium
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep one daily path: queue -> create recovery task.
- Keep clear Pro/Business gating with upgrade path.
- Keep survey flow narrow and execution-focused.

### Module: legal

Feature name: Terms and privacy presentation
Problem: Users need transparent policy visibility and consent context.
Target user moment: Trust and compliance checkpoints.

Hard gate:

- Increase daily sales registrations? No
- Reduce friction? No
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? No

Scoring:

- Sales registrations (0-5): 1
- Friction reduction (0-5): 1
- Retention (0-5): 2
- WhatsApp engagement (0-5): 0
- Offline reliability (0-5): 1

Weighted total:

- Sales: (1/5) x 30 = 6
- Friction: (1/5) x 25 = 5
- Retention: (2/5) x 20 = 8
- WhatsApp: (0/5) x 10 = 0
- Offline: (1/5) x 15 = 3
- Total = 22

Evidence level: C
Delivery risk: Low
Enabler override needed? Yes
Decision: Simplify, then schedule
Simplified MVP version:

- Keep static legal pages clear and lightweight.
- Avoid legal UX complexity in primary flow.
- Keep compliance content accessible from settings.

### Module: onboarding

Feature name: Onboarding shell module
Problem: Ensure new-user bootstrapping path remains minimal.
Target user moment: First app setup.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 3
- Friction reduction (0-5): 4
- Retention (0-5): 3
- WhatsApp engagement (0-5): 1
- Offline reliability (0-5): 3

Weighted total:

- Sales: (3/5) x 30 = 18
- Friction: (4/5) x 25 = 20
- Retention: (3/5) x 20 = 12
- WhatsApp: (1/5) x 10 = 2
- Offline: (3/5) x 15 = 9
- Total = 61

Evidence level: C
Delivery risk: Low
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep onboarding responsibilities narrow.
- Reuse subscription onboarding flow where possible.
- Avoid duplicate setup screens.

### Module: retention

Feature name: Retention dashboard with recurring and at-risk segments
Problem: Merchants need a fast view of loyal and at-risk customers to act early.
Target user moment: Daily planning and follow-up windows.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? Yes
- Improve offline reliability? No

Scoring:

- Sales registrations (0-5): 3
- Friction reduction (0-5): 4
- Retention (0-5): 5
- WhatsApp engagement (0-5): 3
- Offline reliability (0-5): 2

Weighted total:

- Sales: (3/5) x 30 = 18
- Friction: (4/5) x 25 = 20
- Retention: (5/5) x 20 = 20
- WhatsApp: (3/5) x 10 = 6
- Offline: (2/5) x 15 = 6
- Total = 70

Evidence level: B
Delivery risk: Medium
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep two tabs only: recurring and at-risk.
- Keep one reminder-oriented follow-up path.
- Keep premium gating explicit.

### Module: rewards

Feature name: Reward creation, listing, redemption
Problem: Staff need simple reward mechanics to drive repeat visits.
Target user moment: During sale close and customer follow-up.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? Yes
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 3
- Retention (0-5): 4
- WhatsApp engagement (0-5): 3
- Offline reliability (0-5): 3

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (3/5) x 25 = 15
- Retention: (4/5) x 20 = 16
- WhatsApp: (3/5) x 10 = 6
- Offline: (3/5) x 15 = 9
- Total = 70

Evidence level: B
Delivery risk: Low
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep rewards simple and understandable at the counter.
- Keep redemption fast with minimal confirmation friction.
- Avoid campaign-style complexity in reward setup.

### Module: sales

Feature name: New sale registration and confirmation flow
Problem: This is the core business loop and must remain fast and reliable.
Target user moment: Every service transaction at the counter.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 5
- Friction reduction (0-5): 5
- Retention (0-5): 4
- WhatsApp engagement (0-5): 1
- Offline reliability (0-5): 4

Weighted total:

- Sales: (5/5) x 30 = 30
- Friction: (5/5) x 25 = 25
- Retention: (4/5) x 20 = 16
- WhatsApp: (1/5) x 10 = 2
- Offline: (4/5) x 15 = 12
- Total = 85

Evidence level: A
Delivery risk: Medium
Enabler override needed? No
Decision: Build now
Simplified MVP version:

- Preserve sub-5-second sale capture path.
- Keep default flow to minimal taps.
- Push non-critical options away from hot path.

### Module: settings

Feature name: Merchant configuration and operational settings
Problem: Operators need account and operational controls without hurting daily flow.
Target user moment: Before opening and occasional maintenance tasks.

Hard gate:

- Increase daily sales registrations? No
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 2
- Friction reduction (0-5): 4
- Retention (0-5): 2
- WhatsApp engagement (0-5): 1
- Offline reliability (0-5): 3

Weighted total:

- Sales: (2/5) x 30 = 12
- Friction: (4/5) x 25 = 20
- Retention: (2/5) x 20 = 8
- WhatsApp: (1/5) x 10 = 2
- Offline: (3/5) x 15 = 9
- Total = 51

Evidence level: C
Delivery risk: Low
Enabler override needed? Yes
Decision: Simplify, then schedule
Simplified MVP version:

- Keep settings focused on merchant identity and plan/admin essentials.
- Keep staff management action-oriented with low setup burden.
- Avoid turning settings into a high-maintenance control center.

### Module: subscription

Feature name: Plan selection, subscription admin, entitlement management
Problem: Plan and entitlement clarity is needed to unlock value without confusion.
Target user moment: Onboarding and periodic plan changes.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? Yes
- Improve WhatsApp engagement? Yes
- Improve offline reliability? No

Scoring:

- Sales registrations (0-5): 4
- Friction reduction (0-5): 5
- Retention (0-5): 3
- WhatsApp engagement (0-5): 3
- Offline reliability (0-5): 1

Weighted total:

- Sales: (4/5) x 30 = 24
- Friction: (5/5) x 25 = 25
- Retention: (3/5) x 20 = 12
- WhatsApp: (3/5) x 10 = 6
- Offline: (1/5) x 15 = 3
- Total = 70

Evidence level: B
Delivery risk: Medium
Enabler override needed? No
Decision: Simplify, then schedule
Simplified MVP version:

- Keep plan list pricing readable and mobile-safe.
- Keep onboarding confirmation and next-step choice concise.
- Keep entitlement messaging explicit for restricted modules.

### Module: sync

Feature name: Queue visibility and synchronization reliability
Problem: Trust breaks if local writes do not sync predictably when connectivity returns.
Target user moment: Background operation and manual pending queue review.

Hard gate:

- Increase daily sales registrations? Yes
- Reduce friction? Yes
- Improve retention? No
- Improve WhatsApp engagement? No
- Improve offline reliability? Yes

Scoring:

- Sales registrations (0-5): 3
- Friction reduction (0-5): 4
- Retention (0-5): 2
- WhatsApp engagement (0-5): 0
- Offline reliability (0-5): 5

Weighted total:

- Sales: (3/5) x 30 = 18
- Friction: (4/5) x 25 = 20
- Retention: (2/5) x 20 = 8
- WhatsApp: (0/5) x 10 = 0
- Offline: (5/5) x 15 = 15
- Total = 61

Evidence level: B
Delivery risk: Medium
Enabler override needed? Yes
Decision: Build now
Simplified MVP version:

- Prioritize queue drain reliability and transient error retry behavior.
- Keep pending-sync visibility clear and actionable.
- Avoid adding noisy controls that confuse operators.
