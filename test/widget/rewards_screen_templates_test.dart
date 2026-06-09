import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/features/rewards/domain/reward.dart';
import 'package:maisum/features/rewards/presentation/rewards_controller.dart';
import 'package:maisum/features/rewards/presentation/rewards_screen.dart';

class _FakeRewardsController extends RewardsController {
  _FakeRewardsController(this._rewards);

  final List<Reward> _rewards;

  @override
  Future<List<Reward>> build() async => _rewards;
}

Widget _buildScreen(List<Reward> rewards) {
  return ProviderScope(
    overrides: [
      rewardsControllerProvider
          .overrideWith(() => _FakeRewardsController(rewards)),
    ],
    child: const MaterialApp(home: RewardsScreen()),
  );
}

void main() {
  testWidgets('renders quick template chips on rewards screen', (tester) async {
    await tester.pumpWidget(_buildScreen(const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_reward_template_corte_gratis')),
        findsOneWidget);
    expect(find.byKey(const Key('quick_reward_template_barba_premium')),
        findsOneWidget);
    expect(find.byKey(const Key('quick_reward_template_desconto_20')),
        findsOneWidget);
    expect(find.byKey(const Key('quick_reward_template_combo_lavagem')),
        findsOneWidget);
  });
}
