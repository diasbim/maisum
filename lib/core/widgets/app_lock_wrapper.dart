import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../constants/app_constants.dart';
import '../constants/app_strings.dart';
import '../services/pin_verification_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_logger.dart';
import 'brand_mark.dart';
import 'pin_pad.dart';
import 'pin_verification_feedback.dart';

// ── Timings ───────────────────────────────────────────────────────────────────

const _bgLockDelay = Duration(seconds: 30);
const _inactivityTimeout = Duration(minutes: 3);
const _lockTag = 'AppLock';

// ── AppLockWrapper ─────────────────────────────────────────────────────────────

class AppLockWrapper extends ConsumerStatefulWidget {
  const AppLockWrapper({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends ConsumerState<AppLockWrapper>
    with WidgetsBindingObserver {
  Timer? _bgTimer;
  Timer? _inactivityTimer;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitialLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  // ── Initial lock check ────────────────────────────────────────────────────

  Future<void> _checkInitialLock() async {
    if (_initialized) return;
    _initialized = true;
    final isAuth = ref.read(authControllerProvider).valueOrNull != null;
    if (!isAuth) {
      Log.d(_lockTag, 'Not authenticated — skipping initial lock');
      _resetInactivityTimer();
      return;
    }
    final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
    if (!mounted) return;
    if (hasPin) {
      Log.i(_lockTag, 'PIN found — locking on startup');
      ref.read(appLockedProvider.notifier).state = true;
    } else {
      Log.d(_lockTag, 'No PIN set — starting inactivity timer');
      _resetInactivityTimer();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.d(_lockTag, 'Lifecycle → $state');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _inactivityTimer?.cancel();
      if (_bgTimer == null) {
        Log.d(_lockTag, 'App paused — bg lock in ${_bgLockDelay.inSeconds}s');
        _bgTimer = Timer(_bgLockDelay, _lock);
      }
    } else if (state == AppLifecycleState.resumed) {
      _bgTimer?.cancel();
      _bgTimer = null;
      final isLocked = ref.read(appLockedProvider);
      if (!isLocked) _resetInactivityTimer();
      Log.d(_lockTag, 'App resumed — locked=$isLocked');
    }
  }

  // ── Lock / unlock ─────────────────────────────────────────────────────────

  Future<void> _lock() async {
    _bgTimer?.cancel();
    _bgTimer = null;
    _inactivityTimer?.cancel();
    final isAuth = ref.read(authControllerProvider).valueOrNull != null;
    if (!isAuth) return;
    final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
    if (hasPin && mounted) {
      Log.i(_lockTag, 'Locking app');
      ref.read(appLockedProvider.notifier).state = true;
    }
  }

  void _unlock() {
    Log.i(_lockTag, 'App unlocked');
    ref.read(appLockedProvider.notifier).state = false;
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _lock);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLocked = ref.watch(appLockedProvider);
    final isAuthenticated =
        ref.watch(authControllerProvider).valueOrNull != null;
    final showLock = isLocked && isAuthenticated;

    return Stack(
      children: [
        // ── Main content with inactivity tracker ──
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!showLock) _resetInactivityTimer();
          },
          child: widget.child,
        ),

        // ── PIN lock overlay ──────────────────────
        if (showLock) _PinLockOverlay(onUnlock: _unlock),
      ],
    );
  }
}

// ── PIN lock overlay ──────────────────────────────────────────────────────────

class _PinLockOverlay extends ConsumerStatefulWidget {
  const _PinLockOverlay({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  ConsumerState<_PinLockOverlay> createState() => _PinLockOverlayState();
}

class _PinLockOverlayState extends ConsumerState<_PinLockOverlay>
    with SingleTickerProviderStateMixin, PinVerificationShakeMixin {
  String _input = '';
  bool _isError = false;
  bool _isLoading = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    initPinShakeAnimation();
    _loadAttempts();
  }

  @override
  void dispose() {
    disposePinShakeAnimation();
    super.dispose();
  }

  Future<void> _loadAttempts() async {
    final n = await PinVerificationService.loadPersistedAttempts(
      ref.read(secureStorageServiceProvider),
    );
    if (mounted) setState(() => _attempts = n);
  }

  void _handleDigit(String d) {
    if (_isLoading || _isError || _input.length >= AppConstants.pinLength) {
      return;
    }
    setState(() => _input += d);
    if (_input.length == AppConstants.pinLength) _verify();
  }

  void _handleDelete() {
    if (_isLoading) return;
    setState(() {
      _isError = false;
      if (_input.isNotEmpty) {
        _input = _input.substring(0, _input.length - 1);
      }
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final storage = ref.read(secureStorageServiceProvider);
    final result = await PinVerificationService.verifyPersistedPin(
      storage: storage,
      input: _input,
    );

    if (result.isSuccess) {
      Log.i(_lockTag, 'Overlay PIN verified');
      widget.onUnlock();
      return;
    }

    if (result.status == PinVerificationStatus.unavailable) {
      setState(() => _isLoading = false);
      return;
    }

    Log.w(
      _lockTag,
      'Wrong overlay PIN — attempt ${result.attempts}/${AppConstants.maxPinAttempts}',
    );

    if (result.isBlocked) {
      Log.w(_lockTag, 'Max overlay attempts — logging out');
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) {
        ref.read(appLockedProvider.notifier).state = false;
        ref.read(routerProvider).go('/login');
      }
      return;
    }

    setState(() {
      _isError = true;
      _isLoading = false;
      _attempts = result.attempts;
    });
    triggerPinShake();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _isError = false;
        _input = '';
      });
    }
  }

  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repor acesso'),
        content: const Text(
            'Isto irá apagar o PIN e terminar a sessão. Terá de fazer login novamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Repor'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    Log.i(_lockTag, 'User reset PIN from overlay — logging out');
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) {
      ref.read(appLockedProvider.notifier).state = false;
      ref.read(routerProvider).go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDarker],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ── Top section ──────────────────────────────────────
                      Column(
                        children: [
                          const SizedBox(height: 60),
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondary
                                      .withValues(alpha: 0.45),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: BrandMark(
                                size: 48,
                                padding: EdgeInsets.all(0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            AppStrings.pinEntryTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppStrings.pinEntrySubtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 52),
                          PinVerificationFeedback(
                            shakeAnimation: pinShakeAnimation,
                            inputLength: _input.length,
                            attempts: _attempts,
                            isError: _isError,
                            isLoading: _isLoading,
                            darkMode: true,
                          ),
                        ],
                      ),

                      // ── PIN pad ──────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          children: [
                            PinPad(
                              onDigit: _handleDigit,
                              onDelete: _handleDelete,
                              darkMode: true,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _isLoading ? null : _forgotPin,
                              child: Text(
                                AppStrings.pinForgot,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
