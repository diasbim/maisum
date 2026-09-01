import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/features/nfc_cards/domain/nfc_card_reader.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

typedef _StartSessionCallback = Future<void> Function({
  required Set<NfcPollingOption> pollingOptions,
  required void Function(NfcTag tag) onDiscovered,
  String? alertMessageIos,
  bool invalidateAfterFirstReadIos,
  void Function(NfcReaderSessionErrorIos)? onSessionErrorIos,
  bool noPlatformSoundsAndroid,
});

/// Fakes only the platform-agnostic [NfcManager] surface (availability +
/// session lifecycle). Extracting a UID from a real [NfcTag] requires
/// platform-native tag data that can only be produced by an actual NFC
/// read, so that part of [NfcCardReader] is validated manually on device
/// rather than here.
class _FakeNfcManager extends NfcManager {
  _FakeNfcManager({
    this.availability = NfcAvailability.enabled,
    this.onStartSession,
  });

  final NfcAvailability availability;
  final _StartSessionCallback? onStartSession;
  bool stopped = false;

  @override
  Future<bool> isAvailable() async => availability == NfcAvailability.enabled;

  @override
  Future<NfcAvailability> checkAvailability() async => availability;

  @override
  Future<void> startSession({
    required Set<NfcPollingOption> pollingOptions,
    required void Function(NfcTag tag) onDiscovered,
    String? alertMessageIos,
    bool invalidateAfterFirstReadIos = true,
    void Function(NfcReaderSessionErrorIos)? onSessionErrorIos,
    bool noPlatformSoundsAndroid = false,
  }) async {
    final callback = onStartSession;
    if (callback != null) {
      await callback(
        pollingOptions: pollingOptions,
        onDiscovered: onDiscovered,
        alertMessageIos: alertMessageIos,
        invalidateAfterFirstReadIos: invalidateAfterFirstReadIos,
        onSessionErrorIos: onSessionErrorIos,
        noPlatformSoundsAndroid: noPlatformSoundsAndroid,
      );
    }
  }

  @override
  Future<void> stopSession({
    String? alertMessageIos,
    String? errorMessageIos,
  }) async {
    stopped = true;
  }
}

void main() {
  test('reports unsupported without starting a session', () async {
    final manager = _FakeNfcManager(availability: NfcAvailability.unsupported);
    final reader = NfcCardReader(manager: manager);

    await expectLater(
      reader.readOnce(),
      throwsA(
        isA<NfcCardReaderException>().having(
          (e) => e.reason,
          'reason',
          NfcCardReaderErrorReason.unsupported,
        ),
      ),
    );
  });

  test('reports disabled when NFC hardware exists but is turned off',
      () async {
    final manager = _FakeNfcManager(availability: NfcAvailability.disabled);
    final reader = NfcCardReader(manager: manager);

    await expectLater(
      reader.readOnce(),
      throwsA(
        isA<NfcCardReaderException>().having(
          (e) => e.reason,
          'reason',
          NfcCardReaderErrorReason.disabled,
        ),
      ),
    );
  });

  test('times out and stops the session when no tag is discovered', () async {
    final manager = _FakeNfcManager(
      onStartSession: ({
        required pollingOptions,
        required onDiscovered,
        alertMessageIos,
        invalidateAfterFirstReadIos = true,
        onSessionErrorIos,
        noPlatformSoundsAndroid = false,
      }) async {},
    );
    final reader = NfcCardReader(manager: manager);

    await expectLater(
      reader.readOnce(timeout: const Duration(milliseconds: 30)),
      throwsA(
        isA<NfcCardReaderException>().having(
          (e) => e.reason,
          'reason',
          NfcCardReaderErrorReason.timeout,
        ),
      ),
    );
    expect(manager.stopped, isTrue);
  });

  test('surfaces a native reader session error', () async {
    final manager = _FakeNfcManager(
      onStartSession: ({
        required pollingOptions,
        required onDiscovered,
        alertMessageIos,
        invalidateAfterFirstReadIos = true,
        onSessionErrorIos,
        noPlatformSoundsAndroid = false,
      }) async {
        // Fire after startSession() itself returns, matching how a real
        // native session reports an error asynchronously once the caller
        // is already awaiting the read.
        scheduleMicrotask(() {
          onSessionErrorIos?.call(
            const NfcReaderSessionErrorIos(
              code: NfcReaderErrorCodeIos
                  .readerSessionInvalidationErrorSystemIsBusy,
              message: 'busy',
            ),
          );
        });
      },
    );
    final reader = NfcCardReader(manager: manager);

    await expectLater(
      reader.readOnce(timeout: const Duration(seconds: 5)),
      throwsA(
        isA<NfcCardReaderException>().having(
          (e) => e.reason,
          'reason',
          NfcCardReaderErrorReason.sessionError,
        ),
      ),
    );
  });

  test('checkAvailability delegates to the underlying manager', () async {
    final manager = _FakeNfcManager(availability: NfcAvailability.enabled);
    final reader = NfcCardReader(manager: manager);

    expect(await reader.checkAvailability(), NfcAvailability.enabled);
  });
}
