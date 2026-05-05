import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

const _firestoreCacheSizeBytes = 20 * 1024 * 1024;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _configureFirebaseAuth();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: _firestoreCacheSizeBytes,
  );

  runApp(const ProviderScope(child: LoyaltyApp()));

  unawaited(_warmUpApp());
}

Future<void> _warmUpApp() async {
  await Future.wait([
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
    _configureFirebaseAuth(),
  ]);
}

Future<void> _configureFirebaseAuth() async {
  if (!kDebugMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: true,
  );
}
