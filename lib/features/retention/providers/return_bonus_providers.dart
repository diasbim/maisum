import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/return_bonus.dart';

final activeReturnBonusProvider =
    FutureProvider.family<ReturnBonus?, String>(
  (ref, customerId) =>
      ref.read(returnBonusRepositoryProvider).getActiveForCustomer(customerId),
);
