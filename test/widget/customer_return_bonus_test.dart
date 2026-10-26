import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';
import 'package:maisum/features/customer_app/presentation/widgets/customer_components.dart';
import 'package:maisum/features/retention/domain/return_bonus.dart';

/// The Bónus de Regresso was issued and redeemed entirely merchant-side, so
/// the customer it was meant to bring back never learned it existed. These
/// tests pin the customer-facing half: that a live bonus is shown, that a
/// spent or lapsed one is not, and that nothing about it is phrased as an
/// action the app cannot perform.
class _FakeCustomerRepository extends Fake implements CustomerAppRepository {
  @override
  Future<void> event(String eventType) async {}
}

void main() {
  // A fixed instant for everything that can be told what "now" is.
  final now = DateTime(2026, 9, 15, 10);

  // The home screen reads the wall clock — it has no seam, and giving it one
  // just to be testable would be inventing a dependency for the test's sake.
  // So screen-level tests place the bonus relative to the real clock, and the
  // date arithmetic is pinned separately below with an injected instant.
  CustomerReturnBonus bonus({
    String id = 'bonus-1',
    String businessId = 'business-1',
    String type = ReturnBonusType.discount,
    double value = 150,
    Duration expiresIn = const Duration(days: 5),
    DateTime? reference,
  }) {
    final from = reference ?? now;
    return CustomerReturnBonus(
      id: id,
      businessId: businessId,
      type: type,
      value: value,
      expiresAt: from.add(expiresIn),
      issuedAt: from.subtract(const Duration(days: 1)),
    );
  }

  /// Placed against the real clock, so the assertion holds whenever it runs.
  CustomerReturnBonus liveBonus({
    String id = 'bonus-1',
    String type = ReturnBonusType.discount,
    double value = 150,
    Duration expiresIn = const Duration(days: 5),
  }) =>
      bonus(
        id: id,
        type: type,
        value: value,
        // Half a day past the boundary, so the "ceil to whole days" rounding
        // lands on the same number no matter the hour the suite runs at.
        expiresIn: expiresIn - const Duration(hours: 12),
        reference: DateTime.now(),
      );

  CustomerBusiness business({List<CustomerReturnBonus> bonuses = const []}) =>
      CustomerBusiness(
        id: 'business-1',
        name: 'Café Central',
        address: 'Av. 24 de Julho',
        phone: '+258820000001',
        confirmedPoints: 120,
        rewards: const [],
        returnBonuses: bonuses,
      );

  Widget home(List<CustomerBusiness> businesses) => ProviderScope(
        overrides: [
          customerAppRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
          customerHomeProvider.overrideWith(
            (ref) async => CustomerData(
              businesses,
              fromCache: false,
              updatedAt: now,
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(child: CustomerHomeScreen()),
        ),
      );

  group('the customer sees the bonus they earned', () {
    testWidgets('a live bonus is named, priced and dated on the home screen',
        (tester) async {
      await tester.pumpWidget(home([
        business(bonuses: [liveBonus()]),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Tem um bónus à espera'), findsOneWidget);
      expect(find.text('150 MZN de desconto'), findsOneWidget);
      expect(find.text('Faltam 5 dias'), findsOneWidget);
      expect(find.text('Café Central'), findsWidgets);
    });

    testWidgets('the count is in the heading when there is more than one',
        (tester) async {
      await tester.pumpWidget(home([
        business(bonuses: [
          liveBonus(),
          liveBonus(
            id: 'bonus-2',
            type: ReturnBonusType.extraPoints,
            value: 50,
            expiresIn: const Duration(days: 2),
          ),
        ]),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Tem 2 bónus à espera'), findsOneWidget);
      expect(find.text('50 pontos extra'), findsOneWidget);
      // Soonest first: the one about to lapse is the one worth acting on.
      final cards = tester
          .widgetList<CustomerReturnBonusCard>(
            find.byType(CustomerReturnBonusCard),
          )
          .toList();
      expect(cards.first.bonus.id, 'bonus-2');
    });

    testWidgets('an expired bonus is not shown at all', (tester) async {
      await tester.pumpWidget(home([
        business(bonuses: [liveBonus(expiresIn: const Duration(hours: -1))]),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerReturnBonusCard), findsNothing);
      expect(find.textContaining('bónus à espera'), findsNothing);
    });

    testWidgets('nothing on the card offers to redeem it', (tester) async {
      await tester.pumpWidget(home([
        business(bonuses: [liveBonus()]),
      ]));
      await tester.pumpAndSettle();

      // The merchant applies the bonus at the counter. A button here would
      // promise something the app cannot do.
      final card = find.byType(CustomerReturnBonusCard);
      expect(
        find.descendant(of: card, matching: find.byType(ElevatedButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(
        find.text('Peça ao negócio para aplicar na próxima compra.'),
        findsOneWidget,
      );
    });
  });

  group('the deadline is phrased the way a person would say it', () {
    test('a bonus that lapses later today still has a day left', () {
      expect(
        bonus(expiresIn: const Duration(hours: 3)).daysUntilExpiry(now),
        1,
        reason: 'rounding down would read "0 dias" on something still valid',
      );
    });

    test('an already-lapsed bonus is zero, never negative', () {
      expect(
        bonus(expiresIn: const Duration(days: -3)).daysUntilExpiry(now),
        0,
      );
    });

    testWidgets('the last two days read as today and tomorrow',
        (tester) async {
      for (final (expiresIn, expected) in [
        (const Duration(hours: 2), 'Termina amanhã'),
        (const Duration(days: 2), 'Faltam 2 dias'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: CustomerExperienceTheme(
              child: Scaffold(
                body: CustomerReturnBonusCard(
                  bonus: bonus(expiresIn: expiresIn),
                  now: now,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
      }
    });
  });

  group('the stored type never reaches the screen raw', () {
    test('every issued type has Portuguese words', () {
      const types = [
        ReturnBonusType.discount,
        ReturnBonusType.extraPoints,
        ReturnBonusType.freeService,
      ];
      for (final type in types) {
        final label = customerReturnBonusValue(bonus(type: type, value: 100));
        expect(label, isNot(contains(type)), reason: 'raw "$type" shown');
        expect(label, isNotEmpty);
      }
    });

    test('an unknown type degrades to a sentence, not to a crash', () {
      expect(
        customerReturnBonusValue(bonus(type: 'SOMETHING_NEW')),
        'Bónus de regresso',
      );
    });
  });

  group('the payload is read defensively', () {
    test('a bonus without an expiry is dropped rather than shown forever', () {
      expect(
        CustomerReturnBonus.tryFromJson({
          'bonus_id': 'b1',
          'type': 'DISCOUNT',
          'value': 100,
        }),
        isNull,
      );
    });

    test('a business payload keeps only the bonuses it can parse', () {
      final parsed = CustomerBusiness.fromJson({
        'business_id': 'business-1',
        'name': 'Café Central',
        'confirmed_points': 10,
        'rewards': <Map<String, dynamic>>[],
        'return_bonuses': [
          {
            'bonus_id': 'good',
            'type': 'DISCOUNT',
            'value': 150,
            'expires_at': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
          },
          {'bonus_id': 'no-expiry', 'type': 'DISCOUNT', 'value': 150},
          {'type': 'DISCOUNT', 'value': 150, 'expires_at': 1},
        ],
      });

      expect(parsed.returnBonuses.map((b) => b.id), ['good']);
      expect(parsed.returnBonuses.single.businessId, 'business-1');
    });

    test('a payload with no bonuses at all is an empty list', () {
      final parsed = CustomerBusiness.fromJson({
        'business_id': 'business-1',
        'name': 'Café Central',
        'rewards': <Map<String, dynamic>>[],
      });

      expect(parsed.returnBonuses, isEmpty);
    });
  });
}
