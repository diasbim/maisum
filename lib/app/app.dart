import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_lock_wrapper.dart';
import '../core/widgets/sms_suggestion_listener.dart';
import 'router.dart';

class LoyaltyApp extends ConsumerWidget {
  const LoyaltyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MaisUm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (_, child) => AppLockWrapper(
        child: SmsSuggestionListener(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
