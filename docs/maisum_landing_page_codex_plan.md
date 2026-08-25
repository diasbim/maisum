# CODE_PLAN.md
# MaisUm - Premium Landing Page UI/UX Implementation Plan

Version: 1.0
Status: Execution Ready
Surface: Static landing page in `docs/`
Primary file: `docs/index.html`
Primary KPI: Qualified Google Play CTA clicks per landing-page session
Secondary KPI: Qualified WhatsApp demo clicks per landing-page session
Target standard: WCAG 2.2 AA

---

# 1. PURPOSE

This document is the execution plan for turning the existing MaisUm landing
page into a premium, locally credible, conversion-focused product experience.

The implementation must preserve the strongest parts of the current page:

- Maputo and Mozambique positioning;
- Android, WhatsApp, M-Pesa, MT, and +258 relevance;
- offline-first product value;
- the real MaisUm application interface;
- the existing canonical URL, metadata, structured data, and tracked links.

The implementation must correct:

- competing conversion actions;
- repeated and generic card patterns;
- duplicate workflow explanations;
- weak or unverifiable social proof;
- inconsistent typography;
- inaccessible color combinations;
- incomplete keyboard and mobile-menu behavior;
- crowded mobile hierarchy;
- non-deterministic A/B variants;
- incomplete plan and pricing communication.

No testimonial, metric, customer name, logo, price, or business result may be
invented. If verified content is not available, use the fallback defined in
this plan instead of adding placeholder proof.

---

# 2. PRODUCT AND DESIGN DECISIONS

These decisions are fixed for the first implementation pass.

## 2.1 Conversion hierarchy

Primary action:

```text
Instalar gratis no Android
```

Primary destination:

```text
https://play.google.com/store/apps/details?id=com.tsintsivadigital.maisum&hl=pt
```

Secondary action:

```text
Ver demonstracao no WhatsApp
```

The same hierarchy must be used in:

- desktop header;
- hero;
- mobile sticky action;
- product sections;
- final CTA.

Do not render WhatsApp and Google Play as two equally dominant primary
buttons. WhatsApp remains the assisted-sales and demonstration route.

## 2.2 Premium design direction

Design theme:

```text
Local Commerce, Operational Confidence
```

The page must feel:

- grounded in real Maputo business operations;
- warm, confident, and practical;
- product-led rather than decoration-led;
- premium without looking corporate or imported;
- fast and reliable rather than futuristic.

Avoid:

- glassmorphism;
- decorative gradient blobs;
- excessive floating cards;
- a pill above every section;
- nested cards inside rounded shells;
- repeated three-card grids;
- unsupported growth claims;
- generic SaaS illustrations;
- AI-purple gradients;
- stock images presented as real customers.

## 2.3 Technical approach

Keep the landing page:

- static;
- progressively enhanced;
- deployable without a JavaScript framework;
- functional when JavaScript fails;
- compatible with the existing `docs/` deployment.

Extract maintainable assets:

```text
docs/
  index.html
  assets/
    css/
      landing.css
    js/
      landing.js
    images/
      landing/
```

Do not modify `privacy.html` unless a shared navigation or legal-link change
requires it.

## 2.4 Content fallback rules

| Required content | Preferred implementation | Fallback when unavailable |
|---|---|---|
| Customer result | Named, consented case study with a verified metric | Omit the case-study section |
| Customer quote | Named owner, business, and location | Omit the quote; do not use anonymous praise |
| Usage statistics | Exact, dated, defensible figures | Remove the statistics band |
| Pricing | Current price, limits, and billing basis | Remove "Planos" from navigation and show "Falar connosco sobre o plano ideal" |
| Business photography | Original, consented local photography | Use authentic product screens and operational diagrams |

Missing proof must never block the rest of the redesign.

---

# 3. SUCCESS CRITERIA

The redesign is complete only when all of the following are true.

## 3.1 Conversion

- One primary CTA is visually dominant on every viewport.
- CTA copy and destination are consistent across the page.
- The hero contains no more than two actions.
- Google Play and WhatsApp events identify CTA type and location.
- A visitor can understand the product, target user, and next action within
  the first mobile viewport.

## 3.2 Visual quality

- The product UI is visible within approximately 1.5 mobile viewports.
- No more than one decorative eyebrow is used in a major viewport.
- Major sections do not all use the same shell-and-card composition.
- Shadows are limited to two elevation levels.
- Bright WhatsApp green is not used behind white body text.
- The page has a clear editorial rhythm rather than uniform section spacing.

## 3.3 Accessibility

- WCAG 2.2 AA contrast passes for text and meaningful graphics.
- Every interactive element has a visible keyboard focus state.
- Mobile navigation supports open, close, Escape, outside click, and focus
  restoration.
- Anchored headings are not hidden by the sticky header.
- Content remains usable at 200% browser zoom.
- No horizontal scrolling occurs at supported viewport widths.
- Motion is removed or minimized with `prefers-reduced-motion`.
- Touch targets are at least 44 by 44 CSS pixels.

## 3.4 Performance

Target field metrics:

- LCP <= 2.5 seconds;
- CLS <= 0.1;
- INP <= 200 milliseconds.

Target lab quality, when the repository's available tooling can measure it:

- Performance >= 90;
- Accessibility >= 95;
- Best Practices >= 95;
- SEO >= 95.

Do not install a new audit tool solely to produce these scores. Use existing
browser tooling if no repository command exists.

---

# 4. TARGET INFORMATION ARCHITECTURE

Implement this page order.

| Order | Section | Purpose |
|---|---|---|
| 1 | Header | Brand, reduced navigation, primary install action |
| 2 | Hero | Outcome, audience, primary CTA, secondary demo, product proof |
| 3 | Proof band | Verified proof or concise product facts |
| 4 | Core loop | Sale -> points -> WhatsApp -> customer return |
| 5 | Product proof: WhatsApp | Show the customer-facing return mechanism |
| 6 | Product proof: Offline | Show reliability in weak connectivity |
| 7 | Product proof: Growth | Retention, appointments, and Engage |
| 8 | Team and plans | Team operation and real plan information or fallback |
| 9 | Local case study | Only when verified content exists |
| 10 | FAQ | Objection handling |
| 11 | Final CTA | Install first, WhatsApp demo second |
| 12 | Footer | Product, legal, contact, and navigation links |

## 4.1 Navigation

Desktop navigation should contain no more than four section links:

```text
Como funciona
Recursos
Planos
FAQ
```

Rules:

- Omit `Planos` when no real plan comparison is published.
- Preserve old `#retorno` deep links with an anchor alias that forwards users
  to `#como-funciona`.
- Keep `#whatsapp`, `#offline`, `#crescimento`, `#equipa-planos`, `#faq`, and
  `#comecar` as valid deep-link destinations where practical.
- Use `aria-current="location"` for the currently viewed section.

---

# 5. TARGET DESIGN SYSTEM

Create all tokens in `:root` and consume tokens throughout the stylesheet.
Do not leave repeated hard-coded colors or spacing values when a semantic
token applies.

## 5.1 Color tokens

Initial palette:

```css
--color-canvas: #f4f1ea;
--color-surface: #ffffff;
--color-surface-subtle: #f9f7f2;
--color-ink: #0d1b33;
--color-ink-muted: #53606f;
--color-brand: #eab63f;
--color-brand-hover: #d9a42d;
--color-whatsapp-action: #0b5d4b;
--color-whatsapp-action-hover: #084a3c;
--color-whatsapp-accent: #25d366;
--color-border: rgba(13, 27, 51, 0.12);
--color-focus: #2563eb;
--color-danger: #b42318;
--color-success: #137a45;
```

Requirements:

- Verify final contrast after rendering, including hover and focus states.
- Use `--color-whatsapp-accent` for brand details, progress, and small
  non-text accents, not as a white-text button background.
- Do not communicate status through color alone.

## 5.2 Typography tokens

Font roles:

```text
Display and major headings: Bricolage Grotesque 700/800
Body and UI: Outfit 400/500/600/700
```

Target scale:

| Role | Mobile | Desktop |
|---|---:|---:|
| Display | 40-44px | 64-72px |
| H2 | 30-34px | 42-48px |
| H3 | 20-22px | 22-24px |
| Lead | 18px | 18-20px |
| Body | 16px | 16-18px |
| Supporting | 14px minimum | 14-16px |

Rules:

- Heading letter spacing must not be tighter than approximately `-0.035em`.
- Avoid forced `<br>` elements in responsive marketing copy.
- Avoid `word-break: break-word` for normal headings.
- Use `text-wrap: balance` only as progressive enhancement.
- Keep paragraph line lengths between approximately 45 and 70 characters.
- Use sentence case consistently.

## 5.3 Spacing tokens

Use:

```css
--space-1: 4px;
--space-2: 8px;
--space-3: 12px;
--space-4: 16px;
--space-6: 24px;
--space-8: 32px;
--space-12: 48px;
--space-18: 72px;
--space-24: 96px;
```

Section rules:

- related sections: 64-72px desktop;
- major narrative transitions: 88-96px desktop;
- mobile sections: 48-64px;
- do not apply identical spacing to every section.

## 5.4 Radius and elevation

```css
--radius-control: 12px;
--radius-card: 16px;
--radius-feature: 24px;
--radius-pill: 999px;
--shadow-raised: 0 12px 30px rgba(13, 27, 51, 0.10);
--shadow-product: 0 24px 60px rgba(13, 27, 51, 0.18);
```

Rules:

- Use pills only for status, metadata, or compact filters.
- Do not place every section inside a rounded shell.
- Do not nest multiple shadowed cards without a functional reason.

## 5.5 Button system

Implement:

```text
ButtonPrimary     -> Google Play install
ButtonSecondary   -> WhatsApp demonstration
ButtonTertiary    -> in-page or low-priority action
ButtonIcon        -> menu and compact controls
```

All variants require:

- default;
- hover;
- focus-visible;
- active;
- disabled;
- reduced-motion behavior.

---

# 6. COMPONENT SPECIFICATION

## 6.1 Header

Desktop:

- compact logo and wordmark;
- maximum four navigation links;
- one primary Google Play CTA;
- no secondary CTA in the header.

Mobile:

- logo;
- menu button;
- no full-width text CTA inside the header;
- primary install action is provided by the mobile sticky bar after the hero.

Acceptance criteria:

- no crowding at 320px;
- menu button remains fully visible;
- sticky header height is exposed as a CSS custom property;
- section anchors use that value for `scroll-margin-top`.

## 6.2 Hero

Content order:

1. one compact local-context label;
2. outcome-focused H1;
3. one lead paragraph;
4. primary install CTA;
5. secondary WhatsApp demo action;
6. no more than three concise trust facts;
7. authentic MaisUm product screen.

Desktop:

- asymmetric editorial two-column composition;
- product screen receives similar visual weight to the headline;
- remove unnecessary floating notification cards unless they clarify real
  product behavior.

Mobile:

- keep the H1 within 40-44px;
- place an identifiable portion of the product UI within 1.5 viewports;
- move secondary trust details below the product visual when necessary.

## 6.3 Proof band

Preferred:

- exact verified usage or outcome metrics with a date or scope.

Fallback:

- product facts such as "Android", "Funciona offline", and "WhatsApp para o
  cliente";
- do not style product facts as numerical social proof.

Delete "Centenas" and "Dezenas" unless exact source data is supplied.

## 6.4 Core loop

Merge the current "Clientes voltam" and "Como funciona" sections.

Use one four-stage sequence:

```text
1. Regista a venda
2. Atribui pontos
3. Envia o progresso no WhatsApp
4. Da ao cliente um motivo para voltar
```

Requirements:

- one concise sentence per stage;
- a single product screenshot or workflow illustration;
- no duplicate three-step section elsewhere;
- sequence remains understandable without arrows or color.

## 6.5 Product proof sections

Use alternating editorial split layouts rather than repeated card grids.

### WhatsApp

- retain the recognizable conversation;
- use semantic `figure` and `figcaption`;
- expose meaningful content to assistive technology;
- avoid pretending a recreated chat is a live WhatsApp component.

### Offline

- show offline -> locally saved -> synchronized as one operational timeline;
- keep the states textually explicit;
- do not rely on red, gold, and green alone.

### Growth

- group appointments, retention, and Engage under one product narrative;
- use real app screens where available;
- avoid English feature labels when a clear Portuguese label exists;
- retain exact English product names only when they are official.

## 6.6 Team and plans

When verified prices and limits are available:

- show a comparison table or accessible stacked plan cards;
- state billing period;
- state WhatsApp limits;
- state team/device limits;
- identify the recommended plan in text, not color alone.

When pricing is unavailable:

- present team and multi-device capabilities;
- provide one "Falar connosco sobre o plano ideal" action;
- remove `Planos` from the main navigation;
- do not present Free, Starter, and Business as a complete pricing section.

## 6.7 Local case study

Render only with verified and consented content.

Required fields:

```text
Business name
Owner or spokesperson name
Location
Original quote
Verified result or clearly qualitative outcome
Consent status
Optional original photo
```

If any required attribution is missing, omit the section.

## 6.8 FAQ

- keep native `details` and `summary`;
- reduce to the highest-value objections;
- keep visible FAQ content synchronized with FAQ structured data;
- provide clear focus, hover, and open states;
- do not animate content height in a way that causes motion or layout issues.

## 6.9 Final CTA

- repeat the primary install action;
- keep WhatsApp as the secondary demonstration route;
- remove decorative blurred circles;
- use one concise reassurance statement;
- avoid three simultaneous actions.

## 6.10 Mobile sticky action

- primary Google Play action only;
- appears after the hero;
- hides before the final CTA;
- respects safe-area insets;
- does not cover focused controls or the final lines of a section;
- uses no pulsing animation;
- remains at least 44px high;
- subtitle may be removed below 360px.

---

# 7. ACCESSIBILITY IMPLEMENTATION

Complete all tasks in this section before visual polish is considered done.

## 7.1 Contrast

- Replace bright-green WhatsApp button backgrounds.
- Verify every text/background pair.
- Verify icons and borders that communicate state at 3:1 minimum.
- Verify text at 4.5:1 minimum unless it qualifies as large text.
- Recheck contrast in hover, active, disabled, and focus states.

## 7.2 Focus

Add a shared focus-visible treatment to:

- logo link;
- desktop and mobile navigation;
- all CTA links;
- inline links;
- footer links;
- FAQ summaries;
- menu control.

Do not remove native outlines unless the replacement is clearly visible.

## 7.3 Mobile menu behavior

Implement:

- correct `aria-expanded`;
- correct `aria-controls`;
- close on Escape;
- close on backdrop;
- close after selecting a link;
- restore focus to the menu button;
- prevent background interaction while open where appropriate;
- do not trap focus if the menu is a simple non-modal disclosure;
- reset menu state when crossing the desktop breakpoint.

## 7.4 Navigation state

- Track unique section IDs, not duplicated desktop/mobile link indexes.
- Update every link that targets the active section.
- Use `aria-current="location"`.
- Do not mark "Como funciona" active while the hero is still the primary
  visible section unless that behavior is intentionally documented.

## 7.5 Semantics

- Preserve one H1.
- Keep heading levels sequential.
- Use lists for actual groups and sequences.
- Use figures for product demonstrations.
- Mark decorative SVGs and visual-only overlays as hidden.
- Ensure emoji do not replace accessible labels.
- Keep essential content available when JavaScript is disabled.

## 7.6 Motion

Under `prefers-reduced-motion: reduce`:

- disable reveal transitions;
- disable button translation;
- disable sticky-CTA transitions;
- disable mockup floating animation;
- disable smooth scrolling.

---

# 8. RESPONSIVE IMPLEMENTATION

Use content-driven breakpoints. Initial target ranges:

```text
Base: 320px and above
Medium: 640px and above
Hero split: 900px and above
Full desktop navigation: 960px and above
Wide: 1200px and above
```

Do not switch the hero to two columns at 760px.

## 8.1 Required viewport matrix

| Width | Required checks |
|---:|---|
| 320px | Header, menu, H1 wrapping, CTA labels, no horizontal scroll |
| 360px | Sticky CTA, trust facts, product visibility |
| 390px | Primary mobile reference |
| 768px | Tablet layout without compressed two-column hero |
| 1024px | Desktop navigation and balanced hero |
| 1440px | Maximum content width and whitespace |

Also test:

- landscape mobile;
- 200% browser zoom;
- increased text spacing;
- reduced motion;
- keyboard-only navigation;
- slow or failed font loading;
- JavaScript disabled.

## 8.2 Responsive acceptance criteria

- no horizontal document scrolling;
- no clipped button text;
- no broken long Portuguese words;
- no overlap between sticky CTA and focused content;
- no anchor heading hidden behind the header;
- product UI remains legible;
- FAQ controls remain at least 44px high;
- layout remains usable when Google Fonts fail.

---

# 9. JAVASCRIPT AND ANALYTICS

Move behavior to `docs/assets/js/landing.js` with `defer`.

## 9.1 Progressive enhancement

Without JavaScript:

- all content is visible;
- navigation links work;
- FAQ works through native HTML;
- CTAs work;
- no element remains permanently at `opacity: 0`.

Apply reveal classes only after JavaScript has initialized.

## 9.2 A/B testing

Do not randomly change copy on every page load.

For the first premium release:

- ship one approved CTA and one approved growth headline;
- establish a stable analytics baseline.

If testing is re-enabled later:

- test one variable at a time;
- assign a stable visitor variant;
- persist it in local storage;
- include the variant ID in analytics events;
- keep accessible names synchronized with visible text;
- document the experiment start and end date.

## 9.3 Event schema

Normalize CTA events with properties:

```text
cta_type: play_store | whatsapp | anchor
cta_location: header | hero | workflow | whatsapp | growth | plans | final | mobile_sticky | footer
cta_text: visible CTA text
cta_href: destination
variant_id: optional stable experiment ID
```

Requirements:

- do not collect personal information;
- preserve local and `file:` safeguards;
- confirm every tracked CTA fires once;
- confirm section-view events fire once per page view;
- use the real host when `plausible-domain` is empty.

---

# 10. SEO AND CONTENT INTEGRITY

Preserve:

- canonical URL;
- `pt-MZ` language;
- robots directives;
- local geo metadata;
- Open Graph and Twitter metadata;
- SoftwareApplication schema;
- Organization schema;
- FAQ schema;
- sitemap and robots integration.

Update:

- page title and description only if final hero positioning changes;
- Open Graph image if a stronger 1200x630 asset is created;
- `featureList` to match published capabilities;
- FAQ structured data to exactly match visible questions and answers;
- image alternative text after final asset selection.

Validate:

- one H1;
- descriptive link text;
- no broken internal anchors;
- no stale structured-data claims;
- no plan or pricing claim absent from visible content.

---

# 11. PERFORMANCE IMPLEMENTATION

## 11.1 Images

- Keep explicit width and height on every content image.
- Preserve eager loading and high priority only for the LCP product image.
- Lazy-load below-the-fold images.
- Create responsive image candidates when source quality permits.
- Prefer AVIF or WebP with a reliable fallback.
- Do not upscale low-resolution product screens.
- Avoid loading hidden desktop and mobile images simultaneously.

## 11.2 Fonts

- Keep preconnects only for origins that are used.
- Ensure font loading uses swap behavior.
- Keep system-font fallbacks metrically reasonable.
- Remove unused font weights.

## 11.3 CSS and JavaScript

- Keep critical above-the-fold CSS compact.
- Remove obsolete selectors during migration.
- Avoid layout thrashing in scroll handlers.
- Prefer IntersectionObserver for section state and visibility.
- Keep event listeners passive where appropriate.
- Do not add a framework or runtime dependency.

## 11.4 Stability

- Reserve dimensions for product media.
- Avoid content changes after load that move CTAs.
- Do not randomize headline height during initialization.
- Verify the sticky header and sticky CTA do not create CLS.

---

# 12. EXECUTION PHASES

Execute phases in order. A phase is complete only when its acceptance criteria
pass.

## PHASE 0 - Baseline and content gate

### Tasks

- [ ] Record desktop and mobile screenshots of the current page.
- [ ] Record current viewport behavior at all required widths.
- [ ] Inventory all CTA links, event names, section IDs, metadata, and schema.
- [ ] Confirm which statistics can be supported by source data.
- [ ] Confirm whether current prices and limits can be published.
- [ ] Confirm whether a consented customer case study is available.
- [ ] Inventory existing product screenshots and their resolution.
- [ ] Record current key performance and accessibility results when available.

### Output

Create an implementation checklist in the working session. Do not add
placeholder content files to the repository.

### Acceptance criteria

- Every unverifiable content item has a preferred or fallback decision.
- Existing deep links and tracked destinations are documented.
- No implementation depends on missing content.

## PHASE 1 - Safe static-asset extraction

### Tasks

- [ ] Create `docs/assets/css/landing.css`.
- [ ] Create `docs/assets/js/landing.js`.
- [ ] Move inline CSS without changing rendered behavior.
- [ ] Move inline JavaScript without changing behavior.
- [ ] Load JavaScript with `defer`.
- [ ] Verify relative paths from `docs/index.html`.
- [ ] Remove inline blocks only after parity is confirmed.

### Acceptance criteria

- Page works from local file and deployed HTTP contexts.
- Current links, menu, FAQ, analytics safeguards, and images still work.
- No visual regression is introduced by extraction alone.

## PHASE 2 - Design tokens and accessibility foundation

### Tasks

- [ ] Replace legacy color variables with semantic tokens.
- [ ] Implement accessible button colors.
- [ ] Implement the typography scale.
- [ ] Implement spacing, radius, elevation, and focus tokens.
- [ ] Add global focus-visible behavior.
- [ ] Add anchor scroll margins.
- [ ] Set a 14px minimum for supporting copy.
- [ ] Complete reduced-motion coverage.
- [ ] Fix active-navigation state.
- [ ] Complete mobile-menu keyboard behavior.

### Acceptance criteria

- Automated or manual contrast checks pass.
- Keyboard navigation reaches every control in a logical order.
- Menu behavior passes mouse, touch, and keyboard tests.
- Existing content remains readable without JavaScript.

## PHASE 3 - Information architecture and copy consolidation

### Tasks

- [ ] Reduce main navigation.
- [ ] Establish Google Play as the primary action.
- [ ] Reduce hero actions to two.
- [ ] Merge the duplicate return/workflow sections.
- [ ] Replace or remove vague proof.
- [ ] Apply the pricing fallback rule.
- [ ] Remove repeated copy and unnecessary badges.
- [ ] Synchronize visible FAQ and structured data.
- [ ] Preserve required legacy anchors.

### Acceptance criteria

- Every section has a unique role in the narrative.
- No feature is explained in two near-identical sections.
- No unsupported metric, price, or customer claim remains.
- All primary CTA instances use consistent copy and destination.

## PHASE 4 - Premium header and hero

### Tasks

- [ ] Build the compact desktop and mobile header.
- [ ] Build the editorial hero layout.
- [ ] Reduce local-context labels to one.
- [ ] Bring the product visual earlier on mobile.
- [ ] Remove decorative floating elements that do not add meaning.
- [ ] Limit trust facts to three.
- [ ] Implement the primary and secondary button hierarchy.

### Acceptance criteria

- Product, audience, value, and next action are clear in five seconds.
- Hero works at 320px without awkward word breaking.
- Product UI is visible within 1.5 mobile viewports.
- Desktop hero remains balanced between copy and product evidence.

## PHASE 5 - Product narrative and proof sections

### Tasks

- [ ] Build the consolidated core loop.
- [ ] Rebuild WhatsApp proof as an accessible figure.
- [ ] Rebuild offline behavior as a text-complete timeline.
- [ ] Rebuild growth features as an editorial product section.
- [ ] Rebuild team/plans using the verified-content decision.
- [ ] Add a case study only when all required content is verified.
- [ ] Simplify FAQ presentation.
- [ ] Rebuild the final CTA.

### Acceptance criteria

- Section compositions visibly vary while sharing one design system.
- Real product evidence is more prominent than decorative cards.
- Status and sequence remain understandable without color.
- Missing case-study or pricing content produces no empty placeholders.

## PHASE 6 - Responsive and interaction refinement

### Tasks

- [ ] Replace the 760px hero split with a content-safe breakpoint.
- [ ] Validate the complete viewport matrix.
- [ ] Implement sticky-CTA collision avoidance.
- [ ] Verify safe-area behavior.
- [ ] Verify focus visibility behind sticky elements.
- [ ] Verify long Portuguese text and translated expansion.
- [ ] Verify no-font and no-JavaScript behavior.

### Acceptance criteria

- All responsive criteria in Section 8 pass.
- No viewport has horizontal scrolling.
- Header, hero, product proof, and CTA hierarchy remain intact.

## PHASE 7 - Analytics, SEO, and performance

### Tasks

- [ ] Remove per-load random copy variants.
- [ ] Implement the normalized analytics event schema.
- [ ] Verify events and section views.
- [ ] Reconcile metadata, visible copy, and structured data.
- [ ] Optimize and size media.
- [ ] Remove unused CSS and JavaScript.
- [ ] Measure performance after optimization.

### Acceptance criteria

- Every CTA is measurable by type and location.
- No event fires more than once per intended action.
- Schema matches visible content.
- Target performance budgets are met or any external constraint is documented.

## PHASE 8 - Final QA and release readiness

### Tasks

- [ ] Run the final accessibility checklist.
- [ ] Run the responsive matrix.
- [ ] Test all external and internal links.
- [ ] Test local file and deployed HTTP behavior.
- [ ] Test Chrome, Edge, Firefox, and a WebKit-based browser when available.
- [ ] Validate analytics in a non-production or debug-safe way.
- [ ] Compare final screenshots against Phase 0.
- [ ] Confirm no unrelated files changed.

### Acceptance criteria

- All P0 and P1 issues are closed.
- There are no known WCAG AA blockers.
- There are no broken links or anchors.
- The final page has one coherent conversion path.
- The repository contains no temporary audit files.

---

# 13. VALIDATION CHECKLIST

## Functional

- [ ] Header links scroll to the correct sections.
- [ ] Legacy anchors remain valid.
- [ ] Mobile menu opens and closes correctly.
- [ ] Google Play links use the correct package and locale.
- [ ] WhatsApp links retain the intended prefilled messages.
- [ ] FAQ works without JavaScript.
- [ ] Analytics is skipped for file, localhost, and loopback contexts.

## Visual

- [ ] No generic repeated shell pattern dominates the page.
- [ ] No unsupported floating proof card remains.
- [ ] Typography is consistent.
- [ ] Shadows and pills are restrained.
- [ ] Product UI is sharp and readable.
- [ ] Section rhythm is intentionally varied.

## Accessibility

- [ ] Contrast passes.
- [ ] Focus order is logical.
- [ ] Focus is never hidden.
- [ ] Menu supports Escape and focus restoration.
- [ ] Reduced motion is complete.
- [ ] Semantic labels remain meaningful.
- [ ] 200% zoom works.
- [ ] Text spacing overrides work.

## Content

- [ ] No fabricated proof.
- [ ] No vague statistics styled as evidence.
- [ ] No unpublished price or limit.
- [ ] Portuguese copy uses consistent sentence case.
- [ ] FAQ schema equals visible FAQ.
- [ ] Product claims match currently available behavior.

## Performance and SEO

- [ ] LCP image is correctly prioritized.
- [ ] Below-fold media is lazy-loaded.
- [ ] Image dimensions prevent layout shifts.
- [ ] Canonical and social metadata remain valid.
- [ ] Structured data contains no stale claims.
- [ ] No unnecessary runtime dependency was added.

---

# 14. RECOMMENDED CODEX COMMIT SLICES

If commits are requested, use small reviewable slices:

```text
1. refactor(landing): extract static CSS and JavaScript
2. fix(landing): add accessible tokens and navigation behavior
3. feat(landing): consolidate information architecture and CTA hierarchy
4. feat(landing): implement premium hero and product narrative
5. fix(landing): harden responsive and reduced-motion behavior
6. chore(landing): align analytics SEO and performance
7. test(landing): complete cross-viewport and accessibility QA
```

Do not combine unrelated mobile-app or backend changes with this landing-page
work.

---

# 15. DEFINITION OF DONE

This plan is fully implemented only when:

- the page uses one primary conversion path;
- duplicate workflow content has been consolidated;
- all published proof is verifiable;
- pricing is either complete or intentionally omitted;
- the visual system is tokenized and consistently applied;
- the page no longer relies on repetitive generic SaaS card patterns;
- WCAG 2.2 AA requirements pass;
- keyboard and mobile navigation are complete;
- responsive behavior passes the required matrix;
- analytics variants are stable and measurable;
- SEO and structured data match visible content;
- performance targets are met or constraints are documented;
- final visual and functional QA is complete.
