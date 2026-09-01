import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import '../../../core/utils/nfc_card_uid_utils.dart';

/// Result of a successful NFC card read: the normalized card UID (see
/// [NfcCardUidUtils]), ready to send to the backend link/resolve routes.
class NfcCardReadResult {
  const NfcCardReadResult(this.cardUid);

  final String cardUid;
}

enum NfcCardReaderErrorReason {
  /// The device/platform does not support NFC at all.
  unsupported,

  /// NFC hardware exists but is turned off (Android only; iOS has no
  /// system-level NFC toggle).
  disabled,

  /// No compatible tag was read before [NfcCardReader.readOnce]'s timeout.
  timeout,

  /// The caller cancelled the read via [NfcCardReader.cancel].
  cancelled,

  /// A tag was discovered but none of the known tag technologies exposed a
  /// usable UID.
  unreadableTag,

  /// The native NFC session reported an error (e.g. tag moved away too
  /// fast, multiple tags present).
  sessionError,
}

class NfcCardReaderException implements Exception {
  const NfcCardReaderException(this.reason, [this.message]);

  final NfcCardReaderErrorReason reason;
  final String? message;

  @override
  String toString() => message ?? 'NfcCardReaderException(${reason.name})';
}

/// Thin wrapper around `package:nfc_manager` that reads a single physical
/// card UID per session. Cards are identified only by their factory UID
/// (see functions/src/customer_nfc.ts); this class does not read/write any
/// application data on the card.
class NfcCardReader {
  NfcCardReader({NfcManager? manager}) : _providedManager = manager;

  final NfcManager? _providedManager;
  NfcManager? _resolvedManager;
  bool _sessionActive = false;

  NfcManager? get _manager {
    final provided = _providedManager;
    if (provided != null) return provided;
    if (_resolvedManager != null) return _resolvedManager;
    try {
      _resolvedManager = NfcManager.instance;
    } catch (_) {
      // Thrown by NfcManager.instance on platforms without NFC support
      // (web, desktop). Treat as "unsupported" rather than crashing.
      _resolvedManager = null;
    }
    return _resolvedManager;
  }

  Future<NfcAvailability> checkAvailability() async {
    final manager = _manager;
    if (manager == null) return NfcAvailability.unsupported;
    return manager.checkAvailability();
  }

  /// Starts an NFC session and resolves with the first card UID read.
  ///
  /// Throws [NfcCardReaderException] if NFC is unsupported/disabled, the
  /// read times out, is cancelled, or the discovered tag has no readable
  /// UID.
  Future<NfcCardReadResult> readOnce({
    Duration timeout = const Duration(seconds: 30),
    String? alertMessageIos,
  }) async {
    final manager = _manager;
    if (manager == null) {
      throw const NfcCardReaderException(NfcCardReaderErrorReason.unsupported);
    }

    final availability = await manager.checkAvailability();
    if (availability == NfcAvailability.unsupported) {
      throw const NfcCardReaderException(NfcCardReaderErrorReason.unsupported);
    }
    if (availability == NfcAvailability.disabled) {
      throw const NfcCardReaderException(NfcCardReaderErrorReason.disabled);
    }

    final completer = Completer<NfcCardReadResult>();
    Timer? timer;
    _sessionActive = true;

    void completeOnce(FutureOr<void> Function() action) {
      if (completer.isCompleted) return;
      action();
    }

    try {
      await manager.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        alertMessageIos: alertMessageIos,
        onSessionErrorIos: (_) {
          completeOnce(() {
            completer.completeError(
              const NfcCardReaderException(
                NfcCardReaderErrorReason.sessionError,
              ),
            );
          });
        },
        onDiscovered: (tag) async {
          final uidBytes = _extractUidBytes(tag);
          if (uidBytes == null || uidBytes.isEmpty) {
            await manager.stopSession(
              errorMessageIos: 'Cartão não suportado.',
            );
            completeOnce(() {
              completer.completeError(
                const NfcCardReaderException(
                  NfcCardReaderErrorReason.unreadableTag,
                ),
              );
            });
            return;
          }

          String normalizedUid;
          try {
            normalizedUid = NfcCardUidUtils.fromBytes(uidBytes);
          } on FormatException {
            await manager.stopSession(
              errorMessageIos: 'Cartão não suportado.',
            );
            completeOnce(() {
              completer.completeError(
                const NfcCardReaderException(
                  NfcCardReaderErrorReason.unreadableTag,
                ),
              );
            });
            return;
          }

          await manager.stopSession(alertMessageIos: 'Cartão lido.');
          completeOnce(() {
            completer.complete(NfcCardReadResult(normalizedUid));
          });
        },
      );

      timer = Timer(timeout, () {
        completeOnce(() async {
          await manager.stopSession(errorMessageIos: 'Tempo esgotado.');
          completer.completeError(
            const NfcCardReaderException(NfcCardReaderErrorReason.timeout),
          );
        });
      });

      return await completer.future;
    } finally {
      timer?.cancel();
      _sessionActive = false;
    }
  }

  /// Cancels an in-flight [readOnce] session, if any.
  Future<void> cancel() async {
    final manager = _manager;
    if (manager == null || !_sessionActive) return;
    await manager.stopSession(errorMessageIos: 'Leitura cancelada.');
  }

  Uint8List? _extractUidBytes(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return NfcTagAndroid.from(tag)?.id;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final mifare = MiFareIos.from(tag);
      if (mifare != null) return mifare.identifier;
      final iso7816 = Iso7816Ios.from(tag);
      if (iso7816 != null) return iso7816.identifier;
      final iso15693 = Iso15693Ios.from(tag);
      if (iso15693 != null) return iso15693.identifier;
      final felica = FeliCaIos.from(tag);
      if (felica != null) return felica.currentIDm;
    }
    return null;
  }
}
