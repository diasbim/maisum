class SmsEnvelope {
  const SmsEnvelope({
    required this.body,
    this.address,
    this.receivedAt,
  });

  final String body;
  final String? address;
  final DateTime? receivedAt;
}
