# Critical Authentication Audit: Play Store Internal Testing

## What was hardened in code

- Phone auth test bypass now requires explicit opt-in via build flag:
  - `ALLOW_TEST_PHONE_AUTH_BYPASS=true`
- Default behavior in all builds is now safe:
  - `appVerificationDisabledForTesting` stays disabled unless both conditions are true:
    - debug build
    - explicit flag enabled
- OTP and request-code errors now show actionable messages instead of generic/opaque exceptions.

## Verify Android/Firebase setup

1. Confirm package name in app/build and Firebase app registration:
   - `com.tsintsivadigital.maisum`
2. Confirm the same package is in:
   - `android/app/build.gradle.kts`
   - `android/app/google-services.json`
3. Ensure the Play Internal build uses release signing key and not debug fallback.

## SHA fingerprints checklist

Register these SHA certificates in Firebase Android app settings:

- Upload key SHA-1 and SHA-256 (the key used to sign your AAB upload)
- Play App Signing certificate SHA-1 and SHA-256 (from Play Console)
- Debug SHA only for local debug auth tests

### Commands: debug keystore

```powershell
keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android
```

### Commands: upload/release keystore

```powershell
keytool -list -v -alias <your-upload-alias> -keystore "<path-to-upload-keystore>"
```

### Commands: inspect signed artifact cert

```powershell
# APK
apksigner verify --print-certs <path-to-app-release.apk>

# AAB (uses jarsigner)
jarsigner -verify -verbose -certs <path-to-app-release.aab>
```

## Play Console checks

1. Open Play Console > Setup > App integrity.
2. Copy Play App Signing certificate SHA-1/SHA-256.
3. Add both to Firebase > Project settings > Android app > SHA certificate fingerprints.
4. Download refreshed `google-services.json` after SHA updates and replace app file.

## Runtime validation checklist

1. Install from Play Internal track.
2. Trigger phone login and request OTP.
3. Confirm OTP arrives and verification completes without reCAPTCHA/app verification loop.
4. Validate same number in two merchants does not collide customer creation.
5. Validate analytics events in Firebase DebugView/Events:
   - `client_created`
   - `sale_registration_started`
   - `sale_registration_completed`

## Build flags guidance

- Local debug phone auth bypass only (never for Play builds):

```powershell
flutter run --dart-define=ALLOW_TEST_PHONE_AUTH_BYPASS=true
```

- Internal/production builds must not include this flag.
