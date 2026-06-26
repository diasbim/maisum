import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

class CrashLoggingBridge {
  CrashLoggingBridge._();

  static const _maxCustomLogsPerRun = 80;
  static int _logCount = 0;
  static bool _enabled = false;

  static Future<void> configure({required bool enabled}) async {
    _enabled = enabled && !kIsWeb;
    _logCount = 0;

    Log.bindSink(_enabled ? _handleLog : null);

    if (!_enabled) return;

    await FirebaseCrashlytics.instance.setCustomKey('platform', 'flutter');
    await FirebaseCrashlytics.instance.setCustomKey(
      'build_mode',
      kDebugMode ? 'debug' : 'release',
    );
  }

  static void _handleLog(AppLogEvent event) {
    if (!_enabled) return;

    final crashlytics = FirebaseCrashlytics.instance;

    if (event.level >= 1000 && event.error != null) {
      crashlytics.recordError(
        event.error!,
        event.stack ?? StackTrace.current,
        reason: '${event.tag}: ${event.message}',
        fatal: false,
      );
      return;
    }

    if (_logCount >= _maxCustomLogsPerRun) return;

    _logCount += 1;
    crashlytics.log('[${_toLevelLabel(event.level)}][${event.tag}] ${event.message}');
  }

  static String _toLevelLabel(int level) {
    if (level >= 1000) return 'E';
    if (level >= 900) return 'W';
    if (level >= 800) return 'I';
    return 'D';
  }
}
