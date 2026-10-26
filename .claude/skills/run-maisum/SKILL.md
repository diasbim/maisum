---
name: run-maisum
description: Launch and drive the MaisUm Flutter merchant/customer app on an Android emulator, wired to the Firebase emulators, and take screenshots of real screens. Use when asked to run, start, open, or screenshot the app; to reproduce a bug on a device; to check that a change works in the real app rather than in tests; or whenever a task needs the app actually running rather than analysed.
---

# Running MaisUm

The app is a Flutter Android app (`com.tsintsivadigital.maisum`, label "MaisUm")
that talks to Cloud Functions and Firestore. Running it for real means three
processes, in this order: the **Firebase emulators** on the host, the **Android
emulator**, and the **app** built against the first.

`driver.mjs` in this folder does the Android half. Run it with no arguments for
the command list.

## The order that works

```bash
# 1. Firebase emulators, on the host. Must be first: the APK is compiled
#    against them, and the app logs its wiring on startup.
firebase emulators:start --only auth,functions,firestore --project loyaltyos-fc4dd

# 2. The AVD (Medium_Phone). Takes a couple of minutes.
node .claude/skills/run-maisum/driver.mjs boot

# 3. Build + install. ~10 minutes cold.
node .claude/skills/run-maisum/driver.mjs install

# 4. Open it.
node .claude/skills/run-maisum/driver.mjs launch
```

`install` bakes `--dart-define=USE_FIREBASE_EMULATORS=true` and
`FIREBASE_EMULATOR_HOST=10.0.2.2` into the APK. **10.0.2.2, never 127.0.0.1**:
that is how the guest reaches the host's loopback, and the default sends it
looking inside itself.

Confirm the wiring took, rather than assuming — `state` prints the app's own
log line:

```bash
node .claude/skills/run-maisum/driver.mjs state
```

```
"emuladoresFirebase": "flutter : Firebase emulators: auth 10.0.2.2:9099, firestore 10.0.2.2:8085"
```

## Gotchas

**Never background the emulators through a pipe.** `firebase emulators:start |
tail` writes nothing until the command ends, and it never ends. The log stays
empty, the ports look dead, and the obvious conclusion — "it failed to start" —
is wrong. It is running. If a second start reports **"port taken"**, that is the
first one answering. Run it unpiped.

**`adb shell input text` does not reach the OTP boxes.** They are a `Pinput`,
which listens for key events, so text typed at it goes nowhere and the boxes
stay empty. Send digits as keycodes instead (`KEYCODE_0` is 7, so digit *d* is
`7 + d`), after tapping the first box to focus it:

```bash
adb shell input tap 145 1045
for d in 4 7 6 5 9 1; do adb shell input keyevent $((7+d)); done
```

`driver.mjs signin` still uses `input text` for this step and fails there. The
phone field accepts `input text` fine; only the code boxes do not.

**Another app on the AVD steals the foreground.** A package called **ElaMove**
raises "isn't responding" and covers the screen. It is not MaisUm — the label
in `AndroidManifest.xml` is `MaisUm`, and `state` will show the app still alive
with `"erros": []`. Dismiss with *Wait* and `launch` again; the app comes back
to the same screen.

**`shots/` holds screenshots from every past run.** They are tracked in git and
are not cleared between runs, so a stale image sits next to a fresh one with no
indication which is which. **Check the clock in the image, or the file mtime,
before believing a screenshot.** Reading a six-week-old capture as the current
state produces a confident, wrong bug report — this has already happened once.

**The Firebase CLI's login can be expired and the emulators still work.**
`firebase projects:list` failing with "credentials are no longer valid" says
nothing about whether `emulators:start` will run. It will.

## Getting a verification code

The auth emulator issues real codes and exposes them over HTTP. There is no SMS:

```bash
curl -s "http://127.0.0.1:9099/emulator/v1/projects/loyaltyos-fc4dd/verificationCodes"
```

`driver.mjs otp [+258…]` wraps this. Codes accumulate across runs, so take the
**last** one for the number on screen, not the first.

## Driving it

Every handle is a coordinate — Flutter paints to a canvas, so `uiautomator
dump` returns no text and nothing can be found by label. `tap` takes fractions
of the screen so a different AVD still lands on the target, and waits for the
screen to stop changing before returning.

```bash
node .claude/skills/run-maisum/driver.mjs tap 0.5 0.71   # fractions, not pixels
node .claude/skills/run-maisum/driver.mjs ss depois      # shots/depois.png
node .claude/skills/run-maisum/driver.mjs logs 'flutter' # recent logcat
```

**Look at the screenshot.** A launch with no interaction only proves the
entrypoint resolves. The first screen is the profile gate ("Como quer usar a
MaisUm?"); past it the business flow is phone → SMS code → PIN.

## When it is not worth the emulator

`flutter test` covers 800+ cases including widget tests of most screens, and
`dart analyze lib/` is clean. Use the emulator when the question is about the
real device — a route that only breaks on restore, a keyboard, a provider
talking to Firebase — and the test suite when it is about logic.
