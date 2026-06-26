import 'dart:developer' as dev;

typedef AppLogSink = void Function(AppLogEvent event);

class AppLogEvent {
    const AppLogEvent({
        required this.level,
        required this.tag,
        required this.message,
        this.error,
        this.stack,
    });

    final int level;
    final String tag;
    final String message;
    final Object? error;
    final StackTrace? stack;
}

abstract final class Log {
    static AppLogSink? _sink;

    static void bindSink(AppLogSink? sink) {
        _sink = sink;
    }

    static void d(String tag, String message) {
        _write(700, tag, message);
    }

    static void i(String tag, String message) {
        _write(800, tag, message);
    }

    static void w(String tag, String message) {
        _write(900, tag, message);
    }

    static void e(String tag, String message, [Object? error, StackTrace? stack]) {
        _write(1000, tag, message, error: error, stack: stack);
    }

    static void _write(
        int level,
        String tag,
        String message, {
        Object? error,
        StackTrace? stack,
    }) {
        dev.log(
            message,
            name: tag,
            level: level,
            error: error,
            stackTrace: stack,
        );

        final sink = _sink;
        if (sink == null) return;

        try {
            sink(
                AppLogEvent(
                    level: level,
                    tag: tag,
                    message: message,
                    error: error,
                    stack: stack,
                ),
            );
        } catch (_) {
            // Never let logging instrumentation break app execution.
        }
    }
}
