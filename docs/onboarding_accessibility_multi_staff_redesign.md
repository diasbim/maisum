# Onboarding Redesign Proposal

## Scope

Redesign onboarding to:

- improve accessibility (cognitive, motor, screen-reader, low-vision), and
- support merchants with multiple staff from day zero.

This proposal is aligned with the current implementation and routing:

- onboarding plan route: `/onboarding-plan`
- device-link route: `/link-device`
- owner-only staff-management route: `/staff-management`

## Current Baseline (From Code)

- Plan confirmation is mandatory before dashboard for authenticated users.
- Staff management exists but is separated from onboarding.
- Staff can link a device by barbershop code.
- Owner-only gating for staff management is enforced.

## External Best-Practice Inputs Used

- W3C WCAG 2.2 Quick Reference and Understanding docs.
- W3C Forms tutorial (labels, error handling, multi-step progress, notifications).
- NNGroup mobile onboarding guidance (skip heavyweight tutorials, use contextual help).
- NNGroup coach-mark guidance (short, sparse, contextual, dismissible).
- Microsoft multitenant identity guidance (tenant mapping, role-based access, tenant switching, lifecycle).

## Design Principles

1. Start task-first, not tutorial-first.
2. Keep onboarding minimal and progressive.
3. Make every step reversible and skippable where safe.
4. Ensure role-aware flows (owner, staff) from first login.
5. Build for low connectivity and shared-device reality.

## Target Information Architecture

### Step 0 - Entry split by intent

User chooses one clear intent first:

- Join existing barbershop
- Create new barbershop

This reduces cognitive load and removes hidden branching.

### Step 1A - Join existing barbershop (staff or owner)

- Primary action: enter barbershop code.
- Secondary action: QR scan (future enhancement).
- Result: device linked to merchant; role resolved.

After linking:

- Owner goes to Plan + Team Setup track.
- Staff goes to PIN + Quick Start track.

### Step 1B - Create new barbershop (owner)

- Minimal business profile form (only required fields).
- Explain why each data point is requested.

Then proceed to plan setup and optional staff invitations.

### Step 2 - Plan confirmation (owner only)

- Keep current plan confirmation pattern but simplify copy.
- Present 1 recommended plan with concise rationale.
- Make pricing and limits screen-reader friendly.

### Step 3 - Team setup (owner)

New onboarding step:

- Invite first staff members immediately (phone-based invite/manual create).
- Optional skip with explicit "Do this later in Settings" confirmation.
- Show expected permission model per role (Owner vs Staff).

### Step 4 - Security setup (all)

- PIN setup flow remains, but add:
  - show/hide PIN option,
  - allow paste where applicable,
  - avoid forced memory-only challenges.

### Step 5 - Contextual first-run help

No long deck tutorial.

Use pull-based contextual tips:

- first sale screen tip when user opens first sale,
- customer creation tip when first customer action starts,
- staff-management tip when owner first opens team.

## Accessibility Requirements (Definition of Done)

1. Target size:
- tap targets >= 24x24 minimum (prefer >= 44x44 on critical actions).

2. Labels and semantics:
- every input has persistent label and assistive name,
- status messages announced programmatically,
- errors tied to specific fields.

3. Error UX:
- inline errors + correction suggestion,
- avoid generic "try again" only messages.

4. Auth accessibility:
- do not block paste in auth/code inputs,
- avoid multi-field OTP that blocks full paste,
- allow password/PIN visibility toggle.

5. Step clarity:
- visible progress for multi-step onboarding,
- consistent heading structure and action naming.

6. Motion and interruption:
- no forced chained coach marks,
- all hints dismissible and recoverable later.

## Multi-Staff Product Model

### Roles

- OWNER: full business, plan, and team permissions.
- STAFF: operational permissions only (sales, customers, appointments, engage actions by policy).

### Onboarding role outcomes

- Owner can invite and activate staff during onboarding.
- Staff can only link and proceed to operational setup.

### Team lifecycle requirements

- invite, activate/deactivate, audit trail,
- explicit offboarding path,
- per-tenant role mapping based on immutable ids.

### Optional next milestone

- tenant switcher for users with access to multiple merchants.

## Proposed Route and Screen Updates

1. Add new route `/onboarding-entry`:
- first decision screen (Join vs Create).

2. Reuse existing routes:
- `/link-device`
- `/merchant-config`
- `/onboarding-plan`
- `/staff-management` (can be embedded as onboarding step for owner)

3. Add lightweight onboarding state machine:
- stores completion flags per merchant and role,
- supports resume after interruption/offline.

## Rollout Plan

### Phase 1 - Low-risk UX improvements

- Introduce onboarding entry split.
- Reduce copy complexity and tighten step labels.
- Add progress indicators and stronger error messaging.

### Phase 2 - Owner team setup in onboarding

- Add optional "Invite staff now" step.
- Track conversion: owner->staff invitations created.

### Phase 3 - Accessibility hardening

- semantics audit,
- target-size audit,
- auth accessibility fixes,
- screen-reader QA passes.

### Phase 4 - Advanced multi-tenant support

- tenant switcher (if required by business model),
- richer access policies and audit views.

## Success Metrics

- Time to first successful sale (owner/staff split).
- Onboarding completion rate by role.
- Staff invitation completion in first session.
- Error rate per step and retry loops.
- Accessibility defect count and severity.

## QA Checklist Additions

- Keyboard/switch navigation order is logical.
- VoiceOver/TalkBack reads labels, hints, and errors correctly.
- Offline interruption and resume preserves entered data.
- Staff path never attempts owner-only operations.
- Owner path can complete with zero staff and with >=1 staff invited.
