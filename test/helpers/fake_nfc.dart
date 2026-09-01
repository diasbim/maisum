import 'dart:typed_data';

import 'package:maisum/features/nfc_cards/domain/nfc_card_reader.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
// The Android tag-data pigeon type isn't part of nfc_manager's public
// export surface (only nfc_manager_android.dart's tag wrappers are), so it
// is imported directly to construct a fake discovered [NfcTag] in tests.
import 'package:nfc_manager/src/nfc_manager_android/pigeon.g.dart'
    show TagPigeon;

/// Test double for the platform-agnostic [NfcManager] surface used by
/// [NfcCardReader]. Lets widget/integration tests simulate a physical NFC
/// card tap without real hardware (which emulators/simulators don't have)
/// by immediately "discovering" a tag carrying the given UID bytes.
///
/// Only the Android tag-data shape ([TagPigeon]) is populated because
/// widget/integration tests run with `defaultTargetPlatform` forced to
/// [TargetPlatform.android] by the Flutter test harness.
class FakeNfcManager extends NfcManager {
  FakeNfcManager({
    this.availability = NfcAvailability.enabled,
    this.uidBytes,
  });

  /// Availability reported by [checkAvailability]/[readOnce] gating.
  final NfcAvailability availability;

  /// Raw UID bytes of the tag to "discover" once a session starts. When
  /// null, the fake session never discovers a tag (useful for timeout
  /// tests).
  final List<int>? uidBytes;

  bool sessionStarted = false;
  bool sessionStopped = false;

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
    sessionStarted = true;
    final bytes = uidBytes;
    if (bytes == null) return;
    final tag = NfcTag(
      data: TagPigeon(
        handle: 'fake-handle',
        id: Uint8List.fromList(bytes),
        techList: const ['android.nfc.tech.NfcA'],
      ),
    );
    onDiscovered(tag);
  }

  @override
  Future<void> stopSession({
    String? alertMessageIos,
    String? errorMessageIos,
  }) async {
    sessionStopped = true;
  }
}

/// Builds an [NfcCardReader] backed by [FakeNfcManager], ready to inject
/// into the NFC screens under test.
NfcCardReader fakeNfcCardReader({
  NfcAvailability availability = NfcAvailability.enabled,
  List<int>? uidBytes,
}) =>
    NfcCardReader(
      manager: FakeNfcManager(availability: availability, uidBytes: uidBytes),
    );
