import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/features/business_profile/domain/business_profile.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/presentation/rewards_controller.dart';
import 'package:maisum/features/rewards/presentation/rewards_screen.dart';

class _FakeRewardsController extends RewardsController {
  _FakeRewardsController(this._rewards);

  final List<Reward> _rewards;

  @override
  Future<List<Reward>> build() async => _rewards;
}

Widget _buildScreen(
  List<Reward> rewards, {
  BusinessProfile profile = BusinessProfiles.generic,
}) {
  return ProviderScope(
    overrides: [
      rewardsControllerProvider
          .overrideWith(() => _FakeRewardsController(rewards)),
      activeBusinessProfileProvider.overrideWith((_) async => profile),
    ],
    child: const MaterialApp(home: RewardsScreen()),
  );
}

void main() {
  testWidgets('renders quick template chips on rewards screen', (tester) async {
    await tester.pumpWidget(_buildScreen(const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_reward_template_desconto_10')),
        findsOneWidget);
    expect(find.byKey(const Key('quick_reward_template_desconto_20')),
        findsOneWidget);
    expect(
        find.byKey(const Key('quick_reward_template_brinde')), findsOneWidget);
    expect(find.byKey(const Key('quick_reward_template_corte_gratis')),
        findsNothing);
  });

  testWidgets('keeps barber rewards inside the barbershop preset',
      (tester) async {
    await tester.pumpWidget(
      _buildScreen(
        const [],
        profile: BusinessProfiles.resolve('barbershop'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('quick_reward_template_corte_gratis')),
      findsOneWidget,
    );
  });
}
