import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

import '../matching/customer_match_engine.dart';
import '../utils/points_calculator.dart';
import '../../features/sales/domain/suggested_sale.dart';
import 'data/sms_inbox_dao.dart';
import 'domain/sms_envelope.dart';
import 'parsers/parser_registry.dart';
import 'sms_channel_bridge.dart';
import 'validation/duplicate_detector.dart';
import 'validation/transaction_validator.dart';

class SmsListenerService {
  SmsListenerService(
    this._bridge,
    this._registry,
    this._validator,
    this._duplicateDetector,
    this._inboxDao,
    this._matchEngine,
  );

  final SmsChannelBridge _bridge;
  final ParserRegistry _registry;
  final TransactionValidator _validator;
  final DuplicateDetector _duplicateDetector;
  final SmsInboxDao _inboxDao;
  final CustomerMatchEngine _matchEngine;
  final PointsCalculator _pointsCalculator = const PointsCalculator();

  final _controller = StreamController<SuggestedSale>.broadcast();
  Stream<SuggestedSale> get suggestions => _controller.stream;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    final status = await Permission.sms.status;
    if (!status.isGranted) {
      return;
    }

    _started = true;
    await _bridge.start();
    _bridge.stream.listen(_handleEnvelope);
    await _processInbox();
  }

  Future<void> requestPermission() async {
    await Permission.sms.request();
  }

  Future<void> _processInbox() async {
    final pending = await _inboxDao.getPending(limit: 30);
    for (final entry in pending) {
      await _handleEnvelope(entry.envelope);
      await _inboxDao.markProcessed(entry.id);
    }
  }

  Future<void> _handleEnvelope(SmsEnvelope envelope) async {
    final transaction = _registry.parse(
      message: envelope.body,
      address: envelope.address,
      receivedAt: envelope.receivedAt,
    );
    if (transaction == null) return;
    if (!_validator.isValid(transaction)) return;

    final isDuplicate = await _duplicateDetector.isDuplicate(transaction);
    if (isDuplicate) return;
    await _duplicateDetector.register(transaction);

    final match = await _matchEngine.match(phone: transaction.phone);
    final points = _pointsCalculator.calculate(transaction.amount);

    _controller.add(
      SuggestedSale(
        transaction: transaction,
        points: points,
        customer: match.customer,
        matchReason: match.reason,
      ),
    );
  }

  void dispose() {
    _controller.close();
    _bridge.dispose();
  }
}
