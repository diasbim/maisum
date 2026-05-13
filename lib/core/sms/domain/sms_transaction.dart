class SmsTransaction {
  const SmsTransaction({
    required this.provider,
    required this.amount,
    this.phone,
    this.transactionId,
    this.reference,
    this.receivedAt,
    required this.rawMessage,
  });

  final String provider;
  final double amount;
  final String? phone;
  final String? transactionId;
  final String? reference;
  final DateTime? receivedAt;
  final String rawMessage;
}
