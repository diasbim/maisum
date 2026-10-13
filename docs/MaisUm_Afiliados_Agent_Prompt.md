# Task: Implement MaisUm Afiliados (Referral Engine)

You are a senior engineer working in the existing MaisUm repository. Build an affiliate/referral feature **inside** the current sales, loyalty, Retention Engine, WhatsApp and offline-sync architecture. Do not build a parallel system.

---

## 0. How to work (read first)

1. **The repository is the source of truth.** Read `AGENTS.md` / `CLAUDE.md` / `README` and any architecture docs before anything else. Never assume file names, frameworks or ORM.
2. **Phase 0 is mandatory.** Inspect the codebase and write `docs/afiliados/PLAN.md` (template in §11). **Stop after Phase 0 and wait for approval.**
3. **Reuse before you create.** Use existing UI components, design tokens, navigation, forms, API client, auth middleware, RBAC, error handling, ORM/migration tooling, offline queue, sync engine, notification service and audit log.
4. **Ask, don't guess, when:**
   - the sale model cannot represent a discount (needed for `FIXED_AMOUNT` / `PERCENTAGE`);
   - there is no offline queue or sync engine to extend;
   - the Retention Engine has no event/action extension point;
   - a default in §3 conflicts with existing code or policy.
   For anything else, pick the option most consistent with the codebase and record it under "Decisions" in `PLAN.md`.
5. **Verify every phase.** Run the repo's own format, lint, typecheck, migration and test commands. Fix what you broke. Commit once per phase with a clear message.
6. **Report honestly.** Never say a test passed unless you ran it and saw it pass. If a command cannot run in your environment, say so.
7. **No new dependencies** unless the existing stack cannot do the job. Justify each one in `PLAN.md`.
8. **Never break the core loop:** Register Sale → Assign Points → Engage Customer → Customer Returns. A sale without a referral code must behave exactly as today.

---

## 1. Product context

MaisUm is an Android-first, offline-first, WhatsApp-first loyalty app used at the counter by small businesses in Maputo (barbershops, salons, cafés, restaurants, gyms). Customers are identified by phone number. Merchants are busy: every action must take 1–3 taps, with large touch targets and minimal text. UI copy is in Portuguese (Mozambique).

**Referral loop:** Affiliate shares code → New customer uses it at first visit → Customer gets a benefit → Merchant gains a customer → Affiliate earns points → Customer returns.

---

## 2. Scope

### In scope (MVP)
- Affiliate CRUD, activate/deactivate, link to merchants.
- One referral code per affiliate–merchant pair, auto-generated, with a simple customer benefit.
- Optional code entry in the existing sale flow; server-side validation.
- Attribution of a new customer to an affiliate, exactly once.
- Points-based affiliate rewards (first qualifying sale, optional return reward).
- Referral events into the existing Retention Engine; WhatsApp notifications.
- Simple metrics for merchants.
- Full offline support with safe sync.

### Out of scope (do not build)
Automatic payouts (M-Pesa, eMola, any money movement), affiliate login or portal, public marketplace, MLM or affiliate hierarchies, commission negotiation, campaign builder, tracking pixels, ad-network integrations, AI fraud detection, customer-facing app, multi-branch management, wallets or crypto, accounting, leaderboards.

Keep the data model open to these later (e.g. `valueType` already allows `FIXED_AMOUNT`), but write no code for them.

---

## 3. Defaults and decisions

Apply these unless the codebase already defines something different. Put merchant-level values in the existing merchant settings mechanism.

| Setting | Default |
|---|---|
| `firstVisitOnly` on new codes | `true` |
| Code validity | 30 days from creation |
| `usageLimit` | `null` (unlimited) |
| Percentage benefit range | 1–50 % |
| `affiliateFirstSaleRewardPoints` | merchant setting, required when affiliates are enabled |
| `affiliateReturnRewardEnabled` | `false` |
| `affiliateReturnRewardPoints` | merchant setting |
| `returnWindowDays` | 30 (counted from the first qualifying sale) |
| `affiliateRewardApprovalRequired` | `true` (rewards start as `PENDING`) |

**Resolved ambiguities:**
- **Affiliates have no login in MVP.** Admins and merchant owners manage them. Affiliates only receive WhatsApp messages.
- **Affiliate points are not customer loyalty points.** The affiliate's balance is the sum of their `APPROVED` `AffiliateReward` rows with `valueType = POINTS`. Do not write affiliate rewards into the customer loyalty ledger.
- **Affiliate identity is platform-wide**, unique by normalized phone. A merchant only sees affiliates linked to them and only their own metrics.
- **`firstVisitOnly = false`** lets existing customers receive the benefit, but creates **no attribution and no affiliate reward**. Only new customers count as acquisitions.
- **Sale cancelled or reversed:** set the attribution to `CANCELLED`, and set its `PENDING` and `APPROVED` rewards to `CANCELLED`. A `PAID` reward is never changed automatically; log it for manual review. Do not decrement `usageCount`.
- **POINTS customer benefit** means extra loyalty points added through the existing loyalty service and its rules.

---

## 4. Data model

Follow existing naming, ID, timestamp, tenant and soft-delete conventions. Use the project's ORM and migration tool. Migrations must be additive and reversible, with seed data for dev/test.

```text
Affiliate
  id, name, phone (normalized, unique), status ACTIVE|INACTIVE|SUSPENDED,
  createdAt, updatedAt

AffiliateMerchant
  id, affiliateId, merchantId, status ACTIVE|INACTIVE, createdAt, updatedAt
  unique(affiliateId, merchantId)

AffiliateCode
  id, affiliateId, merchantId, code (unique, uppercase),
  benefitType FIXED_AMOUNT|PERCENTAGE|POINTS, benefitValue,
  validFrom, expiresAt, usageLimit (nullable), usageCount (default 0),
  firstVisitOnly (default true), enabled (default true),
  createdAt, updatedAt
  unique(affiliateId, merchantId)   -- one code per pair in MVP

AffiliateAttribution
  id, affiliateId, affiliateCodeId, merchantId, customerId, firstSaleId,
  status CONFIRMED|REJECTED|CANCELLED, rejectionReason (nullable),
  attributedAt, createdAt, updatedAt
  unique(merchantId, customerId) WHERE status <> 'REJECTED'
  -- use a partial unique index if the DB supports it;
  -- otherwise enforce inside the transaction with a row lock.

AffiliateReward
  id, affiliateId, attributionId, merchantId,
  type FIRST_QUALIFYING_SALE|CUSTOMER_RETURN,
  value, valueType POINTS|FIXED_AMOUNT,
  status PENDING|APPROVED|PAID|CANCELLED,
  triggerSaleId, approvedBy (nullable), approvedAt, paidAt, cancelledAt,
  createdAt, updatedAt
  unique(attributionId, type)

AffiliateEvent   -- append-only, never updated or deleted
  id, affiliateId, merchantId, customerId (nullable), saleId (nullable),
  eventType, metadata (json), createdAt
```

**Event types (single list, used everywhere):**
`AFFILIATE_CREATED`, `AFFILIATE_CODE_CREATED`, `REFERRAL_CODE_VALIDATED`, `REFERRAL_ATTRIBUTED`, `REFERRAL_REJECTED`, `AFFILIATE_REWARD_CREATED`, `AFFILIATE_REWARD_APPROVED`, `AFFILIATE_REWARD_CANCELLED`, `REFERRED_CUSTOMER_RETURNED`.

**Indexes:** `Affiliate.phone`, `AffiliateMerchant(merchantId)`, `AffiliateCode.code`, `AffiliateCode.merchantId`, `AffiliateAttribution(merchantId, customerId)`, `AffiliateAttribution.affiliateId`, `AffiliateReward(affiliateId, status)`, `AffiliateEvent(affiliateId, createdAt)`.

**Code format:** `AFI-{NAME}-{XXXX}`.
- `{NAME}`: affiliate first name, ASCII-folded (João → JOAO), uppercase, max 8 chars.
- `{XXXX}`: 4 random chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0, O, 1, I, L).
- Retry on collision. Look up case-insensitively after trimming spaces.

---

## 5. Business rules

Implement all rules in domain services, never in controllers or UI:
`AffiliateService`, `AffiliateCodeService`, `ReferralValidationService`, `ReferralAttributionService`, `AffiliateRewardService`, `AffiliateMetricsService`.
Adapt the names to project conventions.

### 5.1 Code validation (preview, before the sale exists)
A code is valid when all are true. Return the first failing reason code.

| Check | Reason code |
|---|---|
| Code exists | `CODE_NOT_FOUND` |
| Belongs to the current merchant | `CODE_NOT_FOUND` (do not leak other merchants' codes) |
| `enabled` | `CODE_DISABLED` |
| now ≥ `validFrom` | `CODE_NOT_STARTED` |
| now < `expiresAt` | `CODE_EXPIRED` |
| `usageCount` < `usageLimit` (or limit is null) | `CODE_USAGE_LIMIT_REACHED` |
| Affiliate `ACTIVE` and link `ACTIVE` | `AFFILIATE_INACTIVE` |
| Customer phone ≠ affiliate phone | `SELF_REFERRAL_NOT_ALLOWED` |
| Customer is new (§5.2), when `firstVisitOnly` | `CUSTOMER_NOT_ELIGIBLE` |
| No non-rejected attribution exists for this customer and merchant | `CUSTOMER_ALREADY_REFERRED` |
| Benefit valid for the sale amount (§5.4) | `BENEFIT_INVALID` |

Validation is advisory for the UI. **The sale commit re-runs every check** inside the transaction.

### 5.2 New customer
A customer is new for a merchant when:
- there is no previous completed sale for that merchant;
- there is no non-rejected attribution for that merchant;
- no other customer record shares the same normalized phone (reuse existing matching logic);
- the customer is not the affiliate, not a test account and not blocked.

### 5.3 Qualifying sale
A sale qualifies when it belongs to the merchant, has a valid customer, has an amount > 0, is completed, is not cancelled, refunded, reversed or duplicate, and passes the merchant's existing minimum-sale rules.

### 5.4 Benefit calculation (server only)
- `FIXED_AMOUNT`: value > 0 and ≤ sale amount.
- `PERCENTAGE`: value within the configured range. Round using the project's money rules.
- `POINTS`: value > 0. Apply through the existing loyalty service.
- The client never sends the benefit value or the reward value. It sends only the code.

### 5.5 Sale commit with a code (one transaction)
1. Lock the code row. Re-validate (§5.1) against the real sale.
2. Persist the sale with referral metadata (`affiliateCodeId`, benefit applied).
3. Apply the customer benefit.
4. Assign normal loyalty points (unchanged logic).
5. If the customer is new: create the attribution (`CONFIRMED`) and increment `usageCount`.
6. Create the `FIRST_QUALIFYING_SALE` reward (`PENDING` or `APPROVED` per setting).
7. Write `AffiliateEvent` rows and the audit log.
8. **After commit:** publish Retention Engine events and enqueue WhatsApp messages.

If steps 1–7 fail, nothing is applied. If validation fails at commit, return the reason code. The UI then lets the cashier finish the sale without the code.

### 5.6 Return reward
On any later qualifying sale by a customer with a `CONFIRMED` attribution:
- emit `REFERRED_CUSTOMER_RETURNED` once per attribution;
- if the return reward is enabled and the sale falls within `returnWindowDays` of the first sale, create one `CUSTOMER_RETURN` reward.

### 5.7 Reward approval
Only admins or merchant owners, per existing RBAC, can approve or cancel. An affiliate never approves anything. `PAID` is set manually and only after `APPROVED`. There are no automatic payouts.

---

## 6. Sale flow and UI

Use the existing design system and navigation. Mobile layout: cards, not dense tables. Portuguese copy, short.

### Sale flow
Current: Select customer → Amount → Confirm → Points.
New: Select/create customer → **[optional] Código de indicação → Validar** → benefit panel → Confirm → (rest unchanged).

- The code field is collapsed by default ("Tem código de indicação?"). Normal sales gain zero extra taps.
- If the customer is clearly not eligible (known returning customer), hide the field. Show one short line when a code is rejected, e.g. "Código já não é válido. Pode continuar a venda."
- Confirmation panel: "Código válido · Cliente recebe: 50 MT de desconto · Afiliado: João". No IDs, no technical data.

### Screens
- **Afiliados (list):** name, phone, status, referred customers, pending rewards, last activity. Primary action: "Adicionar afiliado".
- **Adicionar afiliado:** name, phone, merchant (only if the user manages several). On success, generate the code and offer "Partilhar código" (WhatsApp deep link or native share).
- **Detalhe do afiliado:** code, share, referred, returned, pending/approved rewards. Actions: "Partilhar código", "Desativar afiliado".
- **Código:** benefit type, value, expiry, usage limit, first-visit toggle, with the §3 defaults pre-filled.
- **Recompensas:** pending list with approve/cancel.
- **Métricas (simple cards):** referred customers, confirmed referrals, conversion rate (confirmed ÷ validations), returned customers, rewards pending, rewards approved.

---

## 7. Retention Engine and WhatsApp

Extend the existing engine. Do not create a new one.

- **Events published:** `REFERRAL_ATTRIBUTED`, `REFERRED_CUSTOMER_RETURNED`, `AFFILIATE_REWARD_CREATED`.
- **Actions added:** `SEND_WHATSAPP` (reuse if it exists), `ISSUE_RETURN_BONUS`, `CREATE_AFFILIATE_REWARD`.
- Messages are async, retryable, logged, optional per merchant settings, and **never block the sale**.

Templates (keep as editable template strings, variables in braces):

```text
[customer_referral_thanks]
Obrigado pela visita 🙌
Usou o código de indicação e recebeu o seu benefício.
Também ganhou {points} pontos no MaisUm. Volte para ganhar mais!

[affiliate_new_customer]
Boa! 🎉 A sua indicação trouxe um novo cliente para {merchantName}.
Tem {points} pontos de recompensa {statusText}.

[affiliate_customer_returned]
O cliente que indicou voltou a {merchantName} 🎉
Tem uma nova recompensa de {points} pontos {statusText}.
```

`{statusText}` = "a aguardar aprovação" or "aprovados". Never tell the affiliate the reward is approved when it is still `PENDING`.

---

## 8. API

Follow existing routing, auth, validation and error-response conventions. Every route checks RBAC and merchant isolation. The paths below are a suggestion; adapt them to the project style.

```http
POST   /api/affiliates                      GET /api/affiliates        GET /api/affiliates/:id
PATCH  /api/affiliates/:id                  POST /api/affiliates/:id/activate|deactivate
POST   /api/affiliates/:id/merchants/:merchantId     DELETE (same path)
POST   /api/affiliate-codes                 GET /api/affiliate-codes   GET|PATCH /api/affiliate-codes/:id
POST   /api/affiliate-codes/:id/enable|disable
POST   /api/referrals/validate-code         (rate-limited)
GET    /api/referrals                       GET /api/referrals/:id
GET    /api/affiliate-rewards               POST /api/affiliate-rewards/:id/approve|cancel
GET    /api/affiliates/metrics              GET /api/affiliates/:id/metrics
```

**Attribution has no public endpoint.** It happens inside the sale commit (§5.5) and inside sync processing.

`POST /api/referrals/validate-code`

```json
// request
{ "merchantId": "m1", "customerPhone": "+258841234567", "code": "afi-joao-7k2p", "saleAmount": 500 }

// 200 valid
{ "valid": true, "affiliateName": "João",
  "benefit": { "type": "FIXED_AMOUNT", "value": 50, "displayText": "50 MT de desconto" },
  "firstVisitOnly": true }

// 200 invalid
{ "valid": false, "reason": "CODE_EXPIRED", "message": "Este código já expirou." }
```

---

## 9. Offline-first

Extend the existing local store and sync queue. The server is authoritative for code uniqueness, expiry, usage limits, eligibility, attribution, reward approval and conflicts.

**Local rules:**
- **Affiliate creation offline:** allowed, queued.
- **Code creation offline:** creates a *provisional* code. The share button stays disabled until the server confirms the final code.
- **Code cache:** the device caches the merchant's active codes (code, benefit, dates, enabled, limit snapshot) at each sync.
- **Sale with code offline:**
  - If the code is in the cache and passes local checks, the benefit may be applied. The sale is marked `syncStatus = PENDING_SYNC`. The UI shows "Pendente de confirmação".
  - If the code is not in the cache, no benefit is applied. The code is still stored with the sale for server-side attribution.
- **Server rejects on sync** (expired, limit reached, not eligible): the sale stands and any benefit already given stays given. Create the attribution as `REJECTED` with a reason. Create no reward. Log a fraud signal. Show the rejection in local referral history.
- **Never approve rewards offline.**

**Every queued operation carries:** `localId`, `deviceId`, `createdAt` (device clock), `idempotencyKey`, `syncStatus`, `retryCount`, `lastSyncError`.

**Deterministic idempotency keys:**
```text
sale:{deviceId}:{localSaleId}
affiliate-attribution:{merchantId}:{customerPhone}
affiliate-reward:{attributionId}:{rewardType}
```

**Conflicts:**
- Two attributions for the same customer and merchant: keep the one with the earliest qualifying sale; reject the other.
- Duplicate reward: the unique constraint wins; treat it as success.
- Usage limit hit during sync: process in server-received order; later ones are rejected.
- Device clock more than 24 h off from server time at sync: still process, but log a fraud signal.

---

## 10. Security, fraud signals, observability

**Controls:** RBAC, merchant isolation on every query, input schemas, phone and code normalization, rate limiting on `validate-code`, audit log for code changes and reward status changes, no client-supplied amounts or ownership, no direct DB access from the client.

**Fraud signals** (log only, no engine): same code used by many new customers in a short window, shared phones, affiliate phone = customer phone attempts, repeated cancelled referral sales, clock skew on sync, abnormal volume per affiliate.

**Structured logs and metrics:** validation attempts and failures by reason, attributions confirmed/rejected, duplicate attempts, rewards created/cancelled, returns, sync conflicts, notification failures.

**Never log:** full phone numbers (mask them), tokens, payment data, unnecessary personal data.

---

## 11. Phases (commit after each; run checks each time)

| # | Phase | Output |
|---|---|---|
| 0 | Assessment | `docs/afiliados/PLAN.md`: stack, files/modules to change, reused components, test and migration commands, Decisions, open questions. **Stop for approval.** |
| 1 | Data | Models, migrations (up and down), indexes, seed data |
| 2 | Domain | The services in §5, with unit tests |
| 3 | API | Routes, schemas, RBAC, error codes, integration tests |
| 4 | Sale integration | §5.5 inside the existing sale flow; regression tests for sales without a code |
| 5 | Retention and WhatsApp | Events, actions, templates, retry |
| 6 | Frontend | Screens in §6 |
| 7 | Offline | Local entities, cache, queue ops, idempotency, conflicts, pending states |
| 8 | Hardening | E2E and offline tests, security checks |
| 9 | Docs | README section, API docs, migration notes, known limitations |

---

## 12. Tests that must exist and pass

**Unit:** code generation (format, alphabet, collisions), code and phone normalization, each §5.1 reason code, new-customer logic, benefit calculation for all 3 types including edge values, qualifying sale, attribution and reward idempotency, return window, reversal handling.

**Integration:** full sale-with-code transaction; rollback on mid-transaction failure; cross-merchant code rejected as `CODE_NOT_FOUND`; same request replayed produces one sale, one attribution, one reward; cancel sale cancels rewards; Retention events published; WhatsApp enqueued and failure does not affect the sale; unauthorized approve rejected.

**E2E scenarios:**
1. New customer + valid code → benefit, points, attribution, reward, messages.
2. Existing customer + code → rejected, sale continues, no attribution.
3. Expired code → clear message, sale continues.
4. Double submit → exactly one of each record.
5. Offline sale with cached code → pending → reconnect → confirmed once.
6. Offline sale, code expires before sync → sale kept, attribution `REJECTED`, no reward.
7. Referred customer returns within the window → return event, one return reward (if enabled).

**Offline:** app restart with pending ops, many queued sales, partial network failure, retry storms.

**Regression:** existing sale and loyalty tests pass unchanged.

---

## 13. Done when

- Every scenario in §12 passes, plus the existing test suite.
- Customer benefit, attribution and affiliate reward each happen **exactly once** per qualifying first sale, online or offline.
- Existing customers, self-referrals, and expired, disabled or over-limit codes never create attributions.
- Cancelled sales never leave `PENDING` or `APPROVED` rewards.
- A sale without a code takes the same taps and time as before.

## 14. Final report

Reply with:
- files changed;
- migrations created;
- endpoints added;
- screens added;
- the Decisions list from `PLAN.md`;
- commands run with their actual results;
- known limitations;
- recommended next steps.
