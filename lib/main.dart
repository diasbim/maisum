import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app/app.dart';
import 'core/constants/app_constants.dart';
import 'core/errors/crash_logging_bridge.dart';
import 'core/errors/app_error_reporter.dart';
import 'core/sync/background_sync.dart';
import 'firebase_options.dart';

const _firestoreCacheSizeBytes = 20 * 1024 * 1024;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      _configureFocusHighlightStrategy();

      await _configureSystemUi();

      await _initializeFirebaseApp();

      await _configureCrashlytics();

      await registerBackgroundSync(debug: kDebugMode);

      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: _firestoreCacheSizeBytes,
      );

      // After the settings assignment, not before: pointing Firestore at the
      // emulator works by rewriting host and TLS in those same settings, and
      // assigning over them afterwards would silently send the app back to
      // production.
      await _configureFirebaseEmulators();

      // Last, so that the emulator connection cannot land on top of it. Both
      // of these write Auth settings, and the testing flag is the one that has
      // to survive: without it the app asks for a reCAPTCHA it cannot get from
      // an emulator, and the sign-in disappears into a browser tab.
      await _configureFirebaseAuth();

      runApp(const ProviderScope(child: LoyaltyApp()));
    },
    (error, stack) {
      AppErrorReporter.report(error, stack, hint: 'run_zoned_guarded_uncaught');
    },
  );
}

void _configureFocusHighlightStrategy() {
  if (kIsWeb) return;
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
}

Future<FirebaseApp> _initializeFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) {
    return Firebase.app();
  }

  if (kIsWeb) {
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  try {
    // Prefer native config (google-services/GoogleService-Info) to avoid
    // option mismatch with an already-created native [DEFAULT] app.
    return Firebase.initializeApp();
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      return Firebase.app();
    }
    if (e.code != 'no-app') rethrow;
    try {
      return Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (fallbackError) {
      if (fallbackError.code == 'duplicate-app') {
        return Firebase.app();
      }
      rethrow;
    }
  }
}

/// Sends Auth and Firestore to the local emulator suite.
///
/// Opt-in, and debug-only. The app otherwise has no way to be run against the
/// local stack at all, so "run it on localhost" meant running the client
/// locally while it read and wrote the production database — the one thing
/// that must not happen by accident.
Future<void> _configureFirebaseEmulators() async {
  if (!AppConstants.useFirebaseEmulators) return;

  if (!kDebugMode) {
    // Loud rather than ignored: a build that was asked for the emulators and
    // quietly used production would be worse than one that refuses to start.
    throw StateError(
      'USE_FIREBASE_EMULATORS is only honoured in debug builds.',
    );
  }

  const host = AppConstants.firebaseEmulatorHost;

  await FirebaseAuth.instance.useAuthEmulator(
    host,
    AppConstants.firebaseAuthEmulatorPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    AppConstants.firestoreEmulatorPort,
  );

  debugPrint(
    'Firebase emulators: auth $host:${AppConstants.firebaseAuthEmulatorPort}, '
    'firestore $host:${AppConstants.firestoreEmulatorPort}',
  );
}

Future<void> _configureCrashlytics() async {
  const crashlyticsEnabled =
      !kDebugMode || AppConstants.enableCrashlyticsInDebug;

  if (kIsWeb) {
    await CrashLoggingBridge.configure(enabled: false);
    return;
  }

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    crashlyticsEnabled,
  );

  await CrashLoggingBridge.configure(enabled: crashlyticsEnabled);

  FlutterError.onError = (FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppErrorReporter.report(error, stack, hint: 'platform_dispatcher_uncaught');
    return true;
  };
}

Future<void> _configureSystemUi() async {
  await Future.wait([
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  ]);
}

Future<void> _configureFirebaseAuth() async {
  if (!kDebugMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      !AppConstants.allowTestPhoneAuthBypass) {
    return;
  }

  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: true,
  );
}
