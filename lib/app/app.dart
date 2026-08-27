import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_lock_wrapper.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/auth/presentation/auth_controller.dart';
import 'router.dart';
import 'providers.dart';

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
      locale: const Locale('pt', 'PT'),
      supportedLocales: const [Locale('pt', 'PT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (_, child) => _CustomerPlatformBootstrap(
        router: router,
        child: AppLockWrapper(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _CustomerPlatformBootstrap extends ConsumerStatefulWidget {
  const _CustomerPlatformBootstrap({
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_CustomerPlatformBootstrap> createState() =>
      _CustomerPlatformBootstrapState();
}

class _CustomerPlatformBootstrapState
    extends ConsumerState<_CustomerPlatformBootstrap> {
  late final ProviderSubscription<AsyncValue<AuthSession?>> _authSubscription;

  @override
  void initState() {
    super.initState();
    final platform = ref.read(customerPlatformServiceProvider);
    unawaited(platform.start(widget.router));
    _authSubscription = ref.listenManual<AsyncValue<AuthSession?>>(
      authControllerProvider,
      (_, next) => unawaited(platform.synchronize(next.valueOrNull)),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _authSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
