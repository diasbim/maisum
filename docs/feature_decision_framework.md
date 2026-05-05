# Feature Decision Framework

This framework governs every future feature in LoyaltyOS.

The product only wins if it helps the barber register more sales, move faster at the counter, bring customers back, use WhatsApp better, or stay reliable offline.

If a feature does none of those things, it should not ship in the MVP path.

## Stage 1: Hard Gate

Every feature proposal must answer these five questions:

1. Does this increase daily sales registrations?
2. Does this reduce friction?
3. Does this improve retention?
4. Does this improve WhatsApp engagement?
5. Does this improve offline reliability?

### Gate Outcome

- `Yes` to at least one: move to scoring.
- `No` to all five: reject by default.
- Indirect enabler only: delay or simplify unless it clearly protects one of the five outcomes.

## Stage 2: Weighted Scoring

Only features that pass the hard gate get scored.

### Weights

| Dimension | Weight |
| --- | ---: |
| Daily sales registrations | 30 |
| Friction reduction | 25 |
| Retention | 20 |
| WhatsApp engagement | 10 |
| Offline reliability | 15 |

### How To Score

Score each dimension from `0` to `5`.

- `0`: no meaningful impact
- `1`: weak impact
- `2`: minor impact
- `3`: clear impact
- `4`: strong impact
- `5`: major impact

Formula:

```text
weighted score = (dimension score / 5) x weight
total score = sum of all weighted scores
```

### Score Meaning

| Total | Decision |
| --- | --- |
| 80-100 | Build now |
| 60-79 | Simplify, then schedule |
| 40-59 | Delay |
| Below 40 | Reject |

### Enabler Override

Some technical work will not score highly on retention or WhatsApp, but still protects the product's identity.

If a proposal materially improves the primary sale flow, offline trust, or low-end Android reliability, it may qualify as an `enabler`.

An enabler can move from `Delay` to `Build now` or `Simplify, then schedule` only if all of the following are true:

1. It clearly improves friction or offline reliability.
2. It directly protects the barber's daily-use workflow.
3. It does not add new user complexity.
4. It fits within the roadmap mix rule for platform and reliability work.

Examples: incremental inbound sync, startup performance fixes, connectivity lifecycle fixes, queue-drain reliability.

## Evidence Rule

Each score must cite one evidence level:

| Level | Meaning |
| --- | --- |
| A | Measured usage data or experiment result |
| B | Direct observed user pain in the barber workflow |
| C | Strong product logic tied to the core loop |
| D | Opinion only |

If all evidence is Level D, the feature cannot score above `59`.

That forces speculative ideas to stay below validated work.

## Product Prioritization Matrix

Use a 2x2 matrix:

- Y-axis: business leverage
- X-axis: delivery risk and cost

### Leverage

- High leverage: score `80+`
- Medium leverage: score `60-79`
- Low leverage: score below `60`

### Risk Factors

Assess risk using:

- implementation complexity
- QA surface area
- offline or sync risk
- low-end Android performance cost
- operator learning cost

### Matrix Decisions

| Leverage | Risk | Decision |
| --- | --- | --- |
| High | Low | Build now |
| High | High | Phase it |
| Low | Low | Only ship if bundled with a higher-priority flow |
| Low | High | Reject |

## Simplify Before You Ship

If a feature has value but adds too much complexity, simplify it first.

Prefer:

- improving an existing screen instead of adding a new section
- one-tap suggestions instead of configuration-heavy setup
- WhatsApp-triggered actions instead of new campaign tooling
- extensions to the sale or customer flow instead of new object types
- fewer steps even if the first version is narrower

Reject or cut scope if the feature adds too many decisions to the barber's hot path.

## MVP Governance Rules

1. No feature may slow the main sale flow beyond the sub-5-second target without exceptional justification.
2. No feature may require stable internet for the primary workflow.
3. No feature may add a new top-level navigation item unless it clearly beats improving an existing flow.
4. No feature may require heavy setup, dense settings, or user training.
5. No feature may replace WhatsApp as the simplest customer action path unless the replacement is clearly easier and more effective.
6. When a feature scores high on value but high on friction or risk, the default action is `simplify`, not full-scope build.

## Roadmap Mix Rules

Keep the roadmap biased toward the core loop.

- At least 50% of near-term work should improve sales speed or friction.
- At least 20% should improve retention or WhatsApp reactivation.
- At least 20% should improve offline reliability, sync trust, startup speed, or low-end Android performance.
- At most 10% should be exploratory work.

## Feature Proposal Template

Every new feature brief should include:

```text
Feature name:
Problem:
Target user moment:

Hard gate:
- Increase daily sales registrations? Yes/No
- Reduce friction? Yes/No
- Improve retention? Yes/No
- Improve WhatsApp engagement? Yes/No
- Improve offline reliability? Yes/No

Scoring:
- Sales registrations (0-5):
- Friction reduction (0-5):
- Retention (0-5):
- WhatsApp engagement (0-5):
- Offline reliability (0-5):

Evidence level: A / B / C / D
Delivery risk: Low / Medium / High
Enabler override needed? Yes / No
Decision: Build now / Simplify / Delay / Reject
Simplified MVP version:
```

## Default Rule

LoyaltyOS is not general business software.

It is a daily-use, low-friction, offline-first loyalty tool for fast-moving barbershops in Maputo.

If a feature does not strengthen that identity, it should be rejected, delayed, or simplified.
