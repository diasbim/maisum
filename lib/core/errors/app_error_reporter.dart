import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

class AppErrorReporter {
  static void report(Object error, StackTrace? stackTrace, {String? hint}) {
    Log.eLocal('Error', hint ?? 'App error', error, stackTrace);
    if (kIsWeb) return;

    unawaited(_recordError(error, stackTrace, hint));
  }

  static void breadcrumb(String tag, String message) {
    Log.i(tag, message);
  }

  static void setCustomKey(String key, Object value) {
    if (kIsWeb) return;

    unawaited(_setCustomKey(key, value));
  }

  static Future<void> _recordError(
    Object error,
    StackTrace? stackTrace,
    String? hint,
  ) async {
    try {
      if (hint != null && hint.isNotEmpty) {
        await FirebaseCrashlytics.instance.setCustomKey(
          'last_error_hint',
          hint,
        );
        await FirebaseCrashlytics.instance.log('reason=$hint');
      }
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: hint,
        fatal: false,
      );
    } catch (e, st) {
      Log.eLocal('Error', 'Crashlytics record failed', e, st);
    }
  }

  static Future<void> _setCustomKey(String key, Object value) async {
    try {
      await FirebaseCrashlytics.instance.setCustomKey(key, value);
    } catch (e, st) {
      Log.eLocal('Error', 'Crashlytics custom key failed: $key', e, st);
    }
  }
}
