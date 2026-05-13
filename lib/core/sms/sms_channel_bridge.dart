import 'dart:async';

import 'package:telephony/telephony.dart';

import 'domain/sms_envelope.dart';
import 'sms_background_handler.dart';

class SmsChannelBridge {
  SmsChannelBridge({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;
  final _controller = StreamController<SmsEnvelope>.broadcast();

  Stream<SmsEnvelope> get stream => _controller.stream;

  Future<void> start() async {
    _telephony.listenIncomingSms(
      onNewMessage: _handleForegroundMessage,
      onBackgroundMessage: smsBackgroundHandler,
      listenInBackground: true,
    );
  }

  void _handleForegroundMessage(SmsMessage message) {
    final body = message.body ?? '';
    if (body.trim().isEmpty) return;
    _controller.add(
      SmsEnvelope(
        body: body,
        address: message.address,
        receivedAt: message.date != null
            ? DateTime.fromMillisecondsSinceEpoch(message.date!)
            : DateTime.now(),
      ),
    );
  }

  void dispose() {
    _controller.close();
  }
}
