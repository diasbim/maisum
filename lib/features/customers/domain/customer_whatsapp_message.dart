import '../../rewards/domain/reward.dart';
import '../../sales/domain/sale.dart';
import 'customer.dart';

const _inactiveAfterDays = 21;
const _nearRewardThresholdPoints = 10;

enum CustomerWhatsAppMessageType {
  rewardUnlocked,
  nearReward,
  inactive,
  repeatVisit,
  welcome,
}

class CustomerWhatsAppDraft {
  const CustomerWhatsAppDraft({required this.type, required this.message});

  final CustomerWhatsAppMessageType type;
  final String message;
}

CustomerWhatsAppDraft buildCustomerWhatsAppDraft({
  required Customer customer,
  required List<Sale> sales,
  required List<Reward> rewards,
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final firstName = _firstName(customer.name);
  final sortedRewards = [...rewards]
    ..sort((a, b) => a.pointsRequired.compareTo(b.pointsRequired));
  final eligibleRewards = sortedRewards
      .where((reward) => reward.pointsRequired <= customer.totalPoints)
      .toList();

  if (eligibleRewards.isNotEmpty) {
    final reward = eligibleRewards.first;
    return CustomerWhatsAppDraft(
      type: CustomerWhatsAppMessageType.rewardUnlocked,
      message:
          'Parabéns, $firstName. Já tens pontos para resgatar ${reward.name}. Passa aqui e aproveita.',
    );
  }

  Reward? nextReward;
  for (final reward in sortedRewards) {
    if (reward.pointsRequired > customer.totalPoints) {
      nextReward = reward;
      break;
    }
  }

  if (nextReward != null) {
    final pointsLeft = nextReward.pointsRequired - customer.totalPoints;
    if (pointsLeft <= _nearRewardThresholdPoints) {
      return CustomerWhatsAppDraft(
        type: CustomerWhatsAppMessageType.nearReward,
        message:
            '$firstName, faltam só $pointsLeft pontos para ${nextReward.name}. Passa aqui e fecha isso.',
      );
    }
  }

  final sortedSales = [...sales]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final lastSale = sortedSales.isEmpty ? null : sortedSales.first;

  if (lastSale != null &&
      referenceTime.difference(lastSale.createdAt).inDays >=
          _inactiveAfterDays) {
    return CustomerWhatsAppDraft(
      type: CustomerWhatsAppMessageType.inactive,
      message:
          '$firstName, sentimos a tua falta. Os teus ${customer.totalPoints} pontos continuam guardados. Passa aqui esta semana.',
    );
  }

  if (lastSale != null) {
    final nextStep = nextReward != null
        ? 'Faltam ${nextReward.pointsRequired - customer.totalPoints} pontos para ${nextReward.name}.'
        : 'Continua assim.';
    return CustomerWhatsAppDraft(
      type: CustomerWhatsAppMessageType.repeatVisit,
      message:
          'Obrigado, $firstName. Já tens ${customer.totalPoints} pontos. $nextStep',
    );
  }

  return CustomerWhatsAppDraft(
    type: CustomerWhatsAppMessageType.welcome,
    message:
        'Olá, $firstName. Na tua próxima visita já começas a juntar pontos. Passa aqui quando quiseres.',
  );
}

String _firstName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'amigo';
  return trimmed.split(RegExp(r'\s+')).first;
}
