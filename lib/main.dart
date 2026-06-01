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
import 'core/sync/background_sync.dart';
import 'firebase_options.dart';

const _firestoreCacheSizeBytes = 20 * 1024 * 1024;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _configureSystemUi();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _configureCrashlytics();

  await registerBackgroundSync(debug: kDebugMode);

  await _configureFirebaseAuth();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: _firestoreCacheSizeBytes,
  );

  runApp(const ProviderScope(child: LoyaltyApp()));
}

Future<void> _configureCrashlytics() async {
  if (kIsWeb) return;
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
