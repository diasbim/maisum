import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:telephony/telephony.dart';

import '../database/app_database.dart';
import 'data/sms_inbox_dao.dart';
import 'domain/sms_envelope.dart';

@pragma('vm:entry-point')
Future<void> smsBackgroundHandler(SmsMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  final body = message.body ?? '';
  if (body.trim().isEmpty) return;

  final envelope = SmsEnvelope(
    body: body,
    address: message.address,
    receivedAt: message.date != null
        ? DateTime.fromMillisecondsSinceEpoch(message.date!)
        : DateTime.now(),
  );

  final id = _buildInboxId(envelope);
  final dao = SmsInboxDao(AppDatabase.instance);
  await dao.insert(envelope, id: id);
}

String _buildInboxId(SmsEnvelope envelope) {
  final raw =
      '${envelope.address ?? ''}|${envelope.receivedAt?.millisecondsSinceEpoch ?? 0}|${envelope.body}';
  return sha256.convert(utf8.encode(raw)).toString();
}
