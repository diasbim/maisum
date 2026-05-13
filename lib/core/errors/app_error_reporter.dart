import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

class AppErrorReporter {
  static void report(
    Object error,
    StackTrace? stackTrace, {
    String? hint,
  }) {
    Log.e('Error', hint ?? 'App error', error, stackTrace);
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: hint,
      );
    } catch (e, st) {
      Log.w('Error', 'Crashlytics record failed: $e');
      Log.e('Error', 'Crashlytics stack', e, st);
    }
  }
}
