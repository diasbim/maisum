# PLANS.md

# MaisUm Engage — Customer Recovery Engine + Engage Surveys

Status: Ready for Implementation
Priority: HIGH
Product: MaisUm
Module: Engage (Business Plan)
Architecture: Offline-First
Platform: Flutter + Riverpod + SQLite + Node.js + PostgreSQL

---

# Objective

Implement MaisUm Engage.

Transform MaisUm from a passive loyalty system into an active customer recovery engine.

Core Goal:

Recover customers before they churn.

---

# Implementation Status Snapshot

Last update: current workspace iteration

Completed now

* Milestones 1-6: database foundation, risk engine, dashboard, recovery queue, actions, and visits implemented in app + backend.
* Milestones 7-11 (fast path): surveys vertical slice implemented (builder-lite, submit flow, analytics endpoint stubs, sync wiring).
* Milestone 13: Engage endpoint documentation added in OpenAPI file at docs/engage_openapi.yaml.
* Milestone 14 (partial): automation hooks wired in backend for RED-risk task creation, near-reward reminders, and survey-completed side effects.

Pending / needs hardening

* Backend environment stabilization for functions TypeScript build (dependencies/types install is currently blocked by network resolution in this environment).
* Automation E2E validation and trigger-tuning against real business scenarios.
* Final acceptance sweep for endpoint schema parity between code and OpenAPI.

Immediate unblock checklist

* Restore npm registry connectivity in functions workspace and complete npm install.
* Re-run functions build and diagnostics, then lock remaining typing issues.
* Execute focused tests for RED task auto-creation, near-reward reminder enqueue, and survey-completed risk adjustment.

---

# Success Metrics

Primary KPI

Recovered Customers / Month

---

Secondary KPIs

* Recovery Rate
* Revenue Recovered
* Survey Response Rate
* Recovery Task Completion Rate
* WhatsApp Conversion Rate
* Risk Prediction Accuracy

---

# Scope

Included

✓ Risk Engine

✓ Recovery Queue

✓ Recovery Dashboard

✓ Recovery Tasks

✓ Recovery Actions

✓ Relationship Visits

✓ Engage Surveys

✓ Survey Analytics

✓ Offline Support

✓ WhatsApp Integration

---

Excluded

✗ AI Prediction Engine

✗ Machine Learning Models

✗ Geofencing

✗ Generic Form Builder

✗ Enterprise Workflow Approvals

---

# Milestone 1

# Database Foundation

Goal

Create Engage database structure.

---

Backend Tables

customer_risk_scores

recovery_tasks

recovery_actions

visit_reports

surveys

survey_questions

survey_responses

survey_response_answers

---

SQLite Tables

Mirror backend schema.

Include:

sync_status

created_at

updated_at

local_id

---

Acceptance

* Tables created
* Migrations pass
* Offline DB operational

---

Validation

npm run migration:test

flutter test db

---

# Milestone 2

# Risk Engine

Goal

Automatically classify customers.

---

Rules

GREEN

0-15 days

---

YELLOW

16-30 days

---

ORANGE

31-45 days

---

RED

46+ days

---

Backend Service

CustomerRiskService

Functions

calculateRisk()

calculateDaysSinceVisit()

calculateRecoveryPriority()

---

Acceptance

* Risk updates automatically
* Dashboard reflects changes
* Unit coverage >90%

---

Tests

CustomerRiskService.test.ts

---

# Milestone 3

# Engage Dashboard

Goal

Create premium dashboard.

---

Widgets

Customers Active

Customers At Risk

Critical Customers

Revenue At Risk

Recovered Customers

---

CTA

Recover Customers

---

Acceptance

* Dashboard loads <1 sec
* Offline support enabled
* Pull-to-refresh works

---

Flutter Components

EngageDashboardScreen

RiskSummaryCard

RevenueRiskCard

RecoveryCTA

---

# Milestone 4

# Recovery Queue

Goal

Generate prioritised recovery list.

---

Sort Order

1 High Value Customers

2 Highest Risk

3 Most Points

---

UI

RecoveryQueueScreen

RecoveryCard

CustomerRecoveryProfile

---

Actions

Send WhatsApp

Call

Offer

Visit

---

Acceptance

* Queue updates automatically
* Offline access works

---

# Milestone 5

# Recovery Actions

Goal

Implement engagement actions.

---

Action Types

WHATSAPP

CALL

OFFER

VISIT

---

Database

recovery_actions

---

API

POST /engage/actions

---

Acceptance

* Action logged
* History visible
* Offline queue operational

---

# Milestone 6

# Relationship Visits

Goal

Implement customer recovery visits.

---

Create Task

Customer

Priority

Due Date

Notes

---

Visit Result

Returned

Interested

Needs Promotion

Wrong Number

Lost Customer

---

Screen

VisitTaskScreen

VisitResultScreen

---

Acceptance

* Visit can be completed offline
* Syncs correctly

---

# Milestone 7

# Engage Surveys

Goal

Implement lightweight retention surveys.

---

Survey Constraints

Maximum 5 questions

Maximum 10 active surveys

---

Question Types

MULTIPLE_CHOICE

YES_NO

RATING

SHORT_TEXT

---

Forbidden

PHOTO

SIGNATURE

CONDITIONAL LOGIC

FILE UPLOADS

---

Acceptance

* Survey creation <60 seconds
* Mobile friendly
* WhatsApp friendly

---

# Milestone 8

# Survey Templates

Goal

Provide ready-to-use templates.

---

Templates

Why Didn't You Return?

Customer Satisfaction

Staff Evaluation

Promotion Interest

General Feedback

---

Acceptance

* Merchant can activate instantly
* No editing required

---

# Milestone 9

# Survey Builder

Goal

Simple survey creation.

---

Merchant Flow

New Survey

↓

Title

↓

Questions

↓

Publish

---

UI

SurveyBuilderScreen

QuestionEditor

SurveyPreview

---

Acceptance

* Max 5 questions
* Publish in <2 minutes

---

# Milestone 10

# Survey Delivery

Goal

Deliver surveys through recovery flow.

---

Triggers

Customer inactive

Visit completed

Reward redeemed

Manual send

---

Channels

WhatsApp

In-App Link

SMS Fallback

---

Acceptance

* Survey links generated
* Responses stored

---

# Milestone 11

# Survey Analytics

Goal

Measure recovery insights.

---

Metrics

Response Rate

Customer Satisfaction

Top Churn Reasons

Top Recovery Incentives

Staff Ratings

---

Dashboard Widgets

Top Reasons Not Returning

Recovery Drivers

Staff Performance

---

Acceptance

* Analytics generated automatically

---

# Milestone 12

# Offline Sync

Goal

Support low connectivity.

---

Must Sync

Recovery Tasks

Survey Responses

Visit Reports

Actions

Risk Updates

---

Conflict Resolution

Last Write Wins

---

Acceptance

* No data loss
* Sync queue retries

---

# Milestone 13

# Backend APIs

Implement

GET /engage/dashboard

GET /engage/recovery-queue

POST /engage/task

POST /engage/task/complete

POST /engage/action

POST /engage/visit-report

GET /engage/surveys

POST /engage/surveys

POST /engage/survey-response

GET /engage/analytics

---

Acceptance

All endpoints documented in OpenAPI.

---

# Milestone 14

# Notifications

Goal

Automate engagement.

---

Triggers

Customer becomes RED

↓

Create Recovery Task

---

Customer near reward

↓

WhatsApp Reminder

---

Survey Completed

↓

Update Engage Score

---

Acceptance

* Automation engine operational

---

# Milestone 15

# Testing

Unit Tests

Risk Engine

Survey Logic

Recovery Queue

Analytics

---

Integration Tests

Risk → Recovery

Visit → Survey

Survey → Analytics

---

E2E

Customer inactive

↓

Recovery task

↓

Survey

↓

Return visit

↓

Customer recovered

---

Offline Tests

Create task offline

Submit survey offline

Complete visit offline

Sync later

---

Acceptance

100% critical paths tested

---

# Milestone 16

# Business Plan Gating

Goal

Protect premium feature.

---

Starter

No Engage

---

Pro

Read-only risk indicators

---

Business

Full Engage

Recovery

Visits

Surveys

Analytics

---

Acceptance

Feature flags operational

Subscription validated

---

# Rollout Strategy

Phase 1

Risk Engine

Recovery Queue

WhatsApp Recovery

---

Phase 2

Recovery Tasks

Visits

Offers

---

Phase 3

Engage Surveys

Survey Analytics

---

Phase 4

Advanced Recovery Insights

Engage Score

Revenue Recovery Dashboard

---

Definition of Done

The feature is complete when:

✓ Merchant can identify at-risk customers

✓ Merchant can recover customers

✓ Merchant can create micro-surveys

✓ Merchant can measure recovery effectiveness

✓ All workflows function offline

✓ Business plan gating works correctly

Final Principle

Every screen, action and automation must answer:

"Will this help bring the customer back?"
