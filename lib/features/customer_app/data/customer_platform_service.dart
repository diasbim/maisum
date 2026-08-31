import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error_reporter.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/customer_models.dart';
import '../presentation/customer_route_parser.dart';
import 'customer_app_api.dart';

class CustomerPlatformService {
  CustomerPlatformService(
    this._messaging,
    this._appLinks,
    this._api,
    this._auth,
    this._connectivity,
    this._secureStorage,
  );

  final FirebaseMessaging _messaging;
  final AppLinks _appLinks;
  final CustomerAppApi _api;
  final FirebaseAuth _auth;
  final ConnectivityService _connectivity;
  final SecureStorageService _secureStorage;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _notificationTapSubscription;
  StreamSubscription<Uri>? _linkSubscription;
  GoRouter? _router;
  AuthSession? _customerSession;
  CustomerFeatureFlags? _flags;
  CustomerPreferences? _preferences;
  RemoteMessage? _pendingNotification;
  Uri? _pendingLink;
  String? _registeredToken;
  bool _started = false;

  Future<void> start(GoRouter router) async {
    _router = router;
    if (_started) return;
    _started = true;

    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        _handleDeepLink,
        onError: (Object error, StackTrace stackTrace) =>
            AppErrorReporter.report(
          error,
          stackTrace,
          hint: 'customer_deep_link_stream',
        ),
      );
      _pendingLink = await _appLinks.getInitialLink();
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace,
          hint: 'customer_deep_link_init');
    }

    if (!_supportsMessaging) return;
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
      onError: (Object error, StackTrace stackTrace) => AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_push_foreground',
      ),
    );
    _notificationTapSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
      onError: (Object error, StackTrace stackTrace) => AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_push_tap',
      ),
    );
    try {
      _pendingNotification = await _messaging.getInitialMessage();
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'customer_push_init');
    }
  }

  Future<void> synchronize(AuthSession? session) async {
    _customerSession = session?.isCustomer == true ? session : null;
    _flags = null;
    _preferences = null;
    if (_customerSession == null) return;

    final user = _auth.currentUser;
    if (user == null || user.uid != _customerSession!.firebaseUid) return;
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return;
      final customerSession = await _api.session(token);
      _flags = customerSession.flags;
      if (!customerSession.flags.appEnabled) return;
      if (customerSession.flags.pushEnabled) {
        await _removePendingToken(token);
      }
      final profile = CustomerProfile.fromJson(await _api.profile(token));
      _preferences = profile.preferences;
      if (customerSession.flags.pushEnabled &&
          profile.preferences.notificationsEnabled) {
        await _enablePush();
      } else {
        await removeToken(_customerSession);
      }
      if (customerSession.flags.deepLinksEnabled &&
          profile.preferences.deepLinksEnabled) {
        final pendingLink = _pendingLink;
        _pendingLink = null;
        if (pendingLink != null) {
          _handleDeepLink(pendingLink);
        }
        final pendingNotification = _pendingNotification;
        _pendingNotification = null;
        if (pendingNotification != null) {
          _handleNotificationTap(pendingNotification);
        }
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace,
          hint: 'customer_platform_sync');
    }
  }

  Future<void> removeToken([AuthSession? session]) async {
    final customer = session ?? _customerSession;
    if (customer == null || !customer.isCustomer || !_supportsMessaging) return;
    final customerUid = customer.firebaseUid;
    final user = _auth.currentUser;
    if (customerUid == null || user == null || user.uid != customerUid) return;

    try {
      final platform = _platform;
      if (platform == null) return;
      final token = _registeredToken ?? await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      var removedRemotely = false;
      if (await _connectivity.check()) {
        final authToken = await user.getIdToken();
        if (authToken != null && authToken.isNotEmpty) {
          try {
            await _api.removePushToken(
              authToken,
              platform: platform,
              token: token,
            );
            removedRemotely = true;
          } catch (error, stackTrace) {
            AppErrorReporter.report(
              error,
              stackTrace,
              hint: 'customer_push_remove_remote',
            );
          }
        }
      }
      if (removedRemotely) {
        final pending = await _secureStorage.getPendingCustomerPushRemoval();
        if (pending?.accountId == customerUid && pending?.token == token) {
          await _secureStorage.clearPendingCustomerPushRemoval();
        }
      } else {
        await _secureStorage.savePendingCustomerPushRemoval(
          accountId: customerUid,
          platform: platform,
          token: token,
        );
      }
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      await _messaging.deleteToken();
      _registeredToken = null;
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace, hint: 'customer_push_remove');
    }
  }

  Future<void> _removePendingToken(String authToken) async {
    if (!await _connectivity.check()) return;
    final pending = await _secureStorage.getPendingCustomerPushRemoval();
    final customer = _customerSession;
    if (pending == null ||
        customer == null ||
        pending.accountId != customer.firebaseUid) {
      return;
    }
    try {
      await _api.removePushToken(
        authToken,
        platform: pending.platform,
        token: pending.token,
      );
      await _secureStorage.clearPendingCustomerPushRemoval();
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_push_remove_pending',
      );
    }
  }

  Future<void> _enablePush() async {
    if (!_supportsMessaging || _customerSession == null) return;
    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
      onError: (Object error, StackTrace stackTrace) => AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_push_token_refresh',
      ),
    );
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final customer = _customerSession;
    final user = _auth.currentUser;
    final platform = _platform;
    if (customer == null ||
        _flags?.pushEnabled != true ||
        _preferences?.notificationsEnabled == false ||
        user == null ||
        user.uid != customer.firebaseUid ||
        platform == null ||
        !await _connectivity.check()) {
      return;
    }
    try {
      final authToken = await user.getIdToken();
      if (authToken == null || authToken.isEmpty) return;
      await _api.registerPushToken(
        authToken,
        platform: platform,
        token: token,
      );
      _registeredToken = token;
    } catch (error, stackTrace) {
      AppErrorReporter.report(error, stackTrace,
          hint: 'customer_push_register');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (_customerSession == null ||
        _flags?.pushEnabled != true ||
        _preferences?.notificationsEnabled == false) {
      return;
    }
    AppErrorReporter.breadcrumb(
      'CustomerPush',
      'Foreground customer notification received.',
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (_customerSession == null ||
        _flags?.deepLinksEnabled != true ||
        _preferences?.deepLinksEnabled == false) {
      _pendingNotification = message;
      return;
    }
    final route = parseCustomerPushRoute(message.data);
    if (route != null) _router?.go(route);
  }

  void _handleDeepLink(Uri uri) {
    if (_customerSession == null ||
        _flags?.deepLinksEnabled != true ||
        _preferences?.deepLinksEnabled == false) {
      _pendingLink = uri;
      return;
    }
    final route = parseCustomerDeepLink(uri);
    if (route != null) _router?.go(route);
  }

  bool get _supportsMessaging =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  String? get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _linkSubscription?.cancel();
  }
}
