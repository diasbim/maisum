import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/sms_transaction.dart';
import '../data/sms_transaction_dao.dart';

class DuplicateDetector {
  DuplicateDetector(this._dao);

  final SmsTransactionDao _dao;

  String buildHash(SmsTransaction transaction) {
    final parts = [
      transaction.provider,
      transaction.transactionId ?? '',
      transaction.amount.toStringAsFixed(2),
      transaction.phone ?? '',
      transaction.receivedAt?.millisecondsSinceEpoch.toString() ?? '',
    ];
    return sha256.convert(utf8.encode(parts.join('|'))).toString();
  }

  Future<bool> isDuplicate(SmsTransaction transaction) async {
    final hash = buildHash(transaction);
    return _dao.exists(hash);
  }

  Future<void> register(SmsTransaction transaction) async {
    final hash = buildHash(transaction);
    await _dao.insert(
      hash: hash,
      provider: transaction.provider,
      transactionId: transaction.transactionId,
      amount: transaction.amount,
      phone: transaction.phone,
      receivedAt: transaction.receivedAt ?? DateTime.now(),
    );
  }
}
