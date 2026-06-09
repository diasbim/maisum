# Product Framework Check

Link the feature request or explain why this PR does not need one.

- Related feature request:
- If no feature request exists, justify why:

## Hard Gate

Mark every item that applies.

- [ ] Increases daily sales registrations
- [ ] Reduces friction
- [ ] Improves retention
- [ ] Improves WhatsApp engagement
- [ ] Improves offline reliability

If none apply, this PR should usually not ship.

## Scoring Summary

Fill this out for feature work. For bug fixes or refactors, explain the enabler value instead.

| Dimension | Score |
| --- | ---: |
| Daily sales registrations | 0-5 |
| Friction reduction | 0-5 |
| Retention | 0-5 |
| WhatsApp engagement | 0-5 |
| Offline reliability | 0-5 |

- Evidence level: A / B / C / D
- Delivery risk: Low / Medium / High
- Enabler override: Yes / No
- Expected decision: Build now / Simplify / Delay / Reject

## Simplified MVP Scope

If this is a large feature, describe the smallest version that still fits the framework.

## Validation

- [ ] I checked this change against `docs/feature_decision_framework.md`
- [ ] I updated `docs/app_feature_decision_register.md` for any touched feature module behavior
- [ ] This change does not add unnecessary complexity to the barber's hot path
- [ ] This change preserves offline-first behavior for the primary workflow
- [ ] I ran the appropriate validation for the touched area
