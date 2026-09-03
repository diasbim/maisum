---
name: senior-ui-ux-design
description: Design or critique user-facing UI the way a senior product designer would - screen layouts, component APIs, states, flows, spacing, typography, color, accessibility, microcopy, and motion. Use when building or changing any screen, widget, page, modal, form, or empty/error/loading state in the Flutter app or the admin portal; when asked for a design review, UX critique, "make this look better", or "is this good UX"; or when choosing between layout/interaction options.
---

# Senior UI/UX Design

Design decisions here are judged by whether a real user finishes their task, not by whether the
screen looks busy or modern. Work in this order.

## 1. Name the job before drawing anything

Before writing UI code, state in one line: **who** is on this screen, **what** they came to do,
and **what they see next**. If the answer is unclear from the request or the code, ask - a
beautiful screen for the wrong job is wasted work.

Then decide the **primary action**. Exactly one per screen. Everything else is secondary and must
look secondary.

## 2. Reuse the design system - do not re-invent it

This repo already has design primitives. Check them first; extend them rather than forking:

- Flutter widgets: [lib/design_system/design_system.dart](lib/design_system/design_system.dart)
  (`MaisumButton`, `MaisumTextField`, `MaisumSurface`, `MaisumModal`, `MaisumToast`,
  `LoadingButton`, `MaisumAppBar`, `MaisumSheetHeader`, `ValidationState`)
- Flutter theme + tokens: [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart),
  [lib/core/theme/customer_experience_theme.dart](lib/core/theme/customer_experience_theme.dart)
- Admin portal styles: [admin/src/app/globals.css](admin/src/app/globals.css)

Rules:
- Never hardcode a color, radius, or font size that a token already covers. In Flutter pull from
  `Theme.of(context).colorScheme` / `textTheme`; in the admin portal use the existing CSS custom
  properties and utility classes.
- A one-off style that appears twice becomes a component. Add it to `design_system/components/`
  and export it from `design_system.dart`.
- If a token genuinely does not exist, add it to the theme - not to the widget.

## 3. Spacing, hierarchy, alignment

- Use a **4/8pt scale** (4, 8, 12, 16, 24, 32, 48). No 7s, no 13s.
- Space belongs **between** related things in small amounts and between **groups** in large ones.
  If two elements are related, they should be visibly closer than unrelated ones.
- Establish hierarchy with **size, weight, and color** - in that order. Reach for a divider or a
  border only after whitespace has failed.
- Align to a single left edge per column. Ragged left edges read as broken.
- Content width: cap long-form text around 60-75 characters. Full-bleed tables and dashboards are
  fine; full-bleed paragraphs are not.
- Touch targets: minimum 48x48 logical pixels in the Flutter app.

## 4. Every state, every time

A screen is not done until all of these are designed. Missing states are the most common defect in
this codebase's reviews:

| State | Requirement |
| --- | --- |
| Loading | Skeleton or inline spinner in the element's own space - never a full-screen blocker for a partial update. Disable the submit control (`LoadingButton`), do not hide it. |
| Empty | Explain what would be here, and give the action that fills it. Never a bare "No data". |
| Error | Say what failed, in the user's terms, and offer the retry. Never surface a raw exception, error code, or Firestore message. |
| Partial / stale | If some data loaded and some failed, show what you have and flag the gap. |
| Success | Confirm the action happened (`MaisumToast`) and leave the user somewhere useful. |
| Offline | The mobile app runs on flaky connections - assume it and say so plainly. |

Forms additionally need: inline validation on blur (not on every keystroke), errors next to the
offending field, preserved input after a failed submit, and a disabled-with-reason submit rather
than a submit that fails silently.

## 5. Accessibility is part of the design, not a pass afterwards

- Contrast: 4.5:1 for body text, 3:1 for large text and meaningful icons. Check it, do not eyeball
  it.
- Color is never the only carrier of meaning - pair it with an icon, label, or shape.
- Flutter: give interactive widgets `Semantics` labels; icon-only buttons always need one.
  Respect `MediaQuery.textScalerOf(context)` - layouts must survive 200% text without clipping.
- Web: real semantic elements (`button`, `a`, `label`, `th`), a visible focus ring, keyboard
  reachability for every action, and `aria-live` for async status.
- Never disable zoom or fix `font-size` in absolute pixels for body copy.

## 6. Microcopy

- Buttons name the outcome: "Save changes", "Associate card" - not "OK", "Submit".
- Write in the product's language. This product's user-facing surfaces are Portuguese - match the
  surrounding screen's language and tone exactly rather than mixing.
- Never blame the user. "Não foi possível concluir" beats "Você digitou errado".
- Titles are sentence case, short, and describe the screen's job.

## 7. Motion

Motion explains a relationship or it does not ship. 150-250ms, ease-out for entrances, ease-in for
exits. Honor reduced-motion. Nothing animates on every rebuild.

## Design review checklist

When asked to critique a screen, walk this and report concrete, located findings - file and line,
what is wrong, and the specific fix. Rank by user impact, not by how easy the fix is:

1. Is the primary action obvious within two seconds?
2. Are all six states from section 4 handled?
3. Any hardcoded values that should be tokens? Any duplicated styling that should be a component?
4. Does the spacing follow the 4/8 scale, and does grouping match the actual information
   structure?
5. Contrast, target size, semantics, text scaling.
6. Does the copy tell the user what happened and what to do next?
7. What happens on a slow connection, an empty account, and a 200%-text-scale phone?

State clearly when a screen is already good. Padding a review with invented nitpicks costs more
trust than it buys.
