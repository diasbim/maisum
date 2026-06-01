# Android 15 Edge-to-Edge Test Checklist

## Purpose

Verify that the app handles edge-to-edge correctly on Android 13, 14, and 15 while targeting SDK 35+.

## Scope

- Startup and splash transition
- Primary navigation screens
- Forms with keyboard
- Bottom sheets and dialogs
- Long lists and scrollables

## Device Matrix

- Android 13 (API 33)
- Android 14 (API 34)
- Android 15 (API 35)

Use at least one gesture-navigation device and one 3-button-navigation device.

## Pre-Checks

1. Confirm edge-to-edge runtime setup is enabled in Flutter startup.
2. Confirm Android embedding edge-to-edge metadata is present.
3. Build and install a release variant for realistic behavior checks.

## Functional Checks

1. Splash to first screen:

- No clipped logo/text under status bar.
- No sudden layout jump after first frame.

1. Top app bars and headers:

- Title/actions are readable and not overlapped by status bar or cutout.
- Tappable targets near top edge remain fully accessible.

1. Bottom actions/navigation:

- Bottom controls are not blocked by gesture bar.
- Persistent bottom bars have enough bottom padding on all tested devices.

1. Keyboard interactions:

- Input fields stay visible when keyboard opens.
- Submit/confirm buttons remain reachable.

1. Sheets/dialogs/snackbars:

- Bottom sheets respect gesture/nav inset.
- Dialog action buttons are not clipped.
- Snackbar is visible above system navigation area.

1. Scrolling screens:

- First and last list items are fully visible.
- Pull-to-refresh/overscroll visuals are not cut by system bars.

## Visual Regression Checks

Capture screenshots for the same screens on API 33/34/35:

- Home/dashboard
- One long list screen
- One form screen with keyboard
- One bottom sheet interaction

## Exit Criteria

- No critical overlap with status/navigation bars.
- No blocked tap targets near system bar areas.
- No clipped content during orientation lock and startup.
- Screenshots recorded for API 33/34/35 for release notes.

## Notes

If overlap is found on a specific screen, prefer local SafeArea or MediaQuery inset handling in that screen, not global padding that may break immersive layouts.
