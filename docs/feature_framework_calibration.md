# Feature Framework Calibration

This document applies the framework to current pending ideas so the team can verify that the weights produce sane roadmap decisions.

## Calibration Set

These ideas were chosen because they are either current pending work or realistic near-term candidates already discussed in this project:

1. Incremental inbound sync
2. Sale-flow debounced prefix customer search
3. Connectivity subscription leak fix
4. Replace `google_fonts` with bundled or system fonts
5. Full WhatsApp campaign calendar inside the app

## Scoring Table

Weights:

- Daily sales registrations: 30
- Friction reduction: 25
- Retention: 20
- WhatsApp engagement: 10
- Offline reliability: 15

Scoring formula:

```text
(score / 5) x weight
```

| Idea | Sales | Friction | Retention | WhatsApp | Offline | Total | Evidence | Risk | Outcome |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| Incremental inbound sync | 3 | 4 | 2 | 0 | 5 | 61 | B/C | High | Build now via enabler override |
| Sale-flow debounced prefix search | 4 | 5 | 1 | 0 | 1 | 58 | B | Medium | Build now via enabler override |
| Connectivity subscription leak fix | 2 | 3 | 1 | 0 | 5 | 46 | B/C | Low | Build now via enabler override |
| Replace `google_fonts` with bundled or system fonts | 1 | 3 | 0 | 0 | 1 | 24 | C | Medium | Delay |
| Full WhatsApp campaign calendar inside the app | 1 | 0 | 4 | 4 | 0 | 38 | C/D | High | Reject for MVP, simplify instead |

## Per-Idea Notes

### 1. Incremental inbound sync

- Gate: yes on friction and offline reliability.
- Why it matters: protects trust in local-first behavior and avoids expensive whole-collection pulls on weak networks.
- Why the raw score is not enough: it is strategic infrastructure, not a visible retention feature.
- Final call: keep as a top-priority enabler.

### 2. Sale-flow debounced prefix search

- Gate: yes on daily sales registrations and friction reduction.
- Why it matters: this improves the hottest path in the product, where every keystroke delay compounds during busy service.
- Final call: top-priority feature even though it is not a retention feature.

### 3. Connectivity subscription leak fix

- Gate: yes on friction and offline reliability.
- Why it matters: low visible business value on paper, high reliability value in practice.
- Final call: qualifies as essential platform maintenance under the enabler override.

### 4. Replace `google_fonts` with bundled or system fonts

- Gate: weak yes on friction because it can modestly improve startup and runtime behavior.
- Why it is delayed: useful, but lower impact than search and sync reliability.
- Final call: keep on the performance backlog, not the immediate roadmap.

### 5. Full WhatsApp campaign calendar inside the app

- Gate: yes on retention and WhatsApp engagement.
- Why it still loses: too much complexity for the barber persona, high implementation risk, and too much distance from the front-counter flow.
- Simplified MVP version: keep message templates and one-tap send actions, but do not build a campaign management surface.

## Calibration Result

The current weights are directionally correct.

They correctly prioritize hot-path speed improvements and deprioritize broad campaign/admin tooling.

The one adjustment needed is procedural, not mathematical: technical enablers need an explicit override so they are not undervalued when they protect the core loop indirectly.

## Decision

Keep the weights unchanged for now.

Add and use the `enabler override` rule for platform work that materially improves:

- primary sale speed
- offline trust
- sync reliability
- low-end Android performance

Revisit the weights only after real usage data shows that retention or WhatsApp outcomes are being under-prioritized.
