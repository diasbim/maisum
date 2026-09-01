import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maisum/app/providers.dart';
import 'package:maisum/core/theme/customer_experience_theme.dart';
import 'package:maisum/features/customer_app/data/customer_app_repository.dart';
import 'package:maisum/features/customer_app/domain/customer_models.dart';
import 'package:maisum/features/customer_app/presentation/customer_screens.dart';
import 'package:maisum/features/customer_app/presentation/widgets/customer_components.dart';

class _FakeCustomerRepository extends Fake implements CustomerAppRepository {
  @override
  Future<void> event(String eventType) async {}
}

class _EmptyCustomerRepository extends Fake implements CustomerAppRepository {
  CustomerData<T> _data<T>(T value) => CustomerData(
        value,
        fromCache: true,
        updatedAt: DateTime(2026, 8, 31),
      );

  @override
  Future<CustomerData<List<CustomerBusiness>>> home() async => _data([]);

  @override
  Future<CustomerData<List<CustomerBusiness>>> businesses() async => _data([]);

  @override
  Future<CustomerData<List<CustomerReward>>> rewards() async => _data([]);

  @override
  Future<CustomerData<List<CustomerActivity>>> activity() async => _data([]);

  @override
  Future<CustomerData<CustomerProfile>> profile() async => _data(
        const CustomerProfile(
          displayName: null,
          phone: '+258820000001',
          linkedBusinessCount: 0,
          preferences: CustomerPreferences(
            notificationsEnabled: true,
            marketingEnabled: false,
            deepLinksEnabled: true,
          ),
        ),
      );
}

void main() {
  const readyReward = CustomerReward(
    id: 'reward-ready',
    businessId: 'business-1',
    name: 'Café grátis',
    description: 'Um café à sua escolha',
    pointsRequired: 100,
    confirmedPoints: 120,
    pointsRemaining: 0,
    eligible: true,
  );
  const pendingReward = CustomerReward(
    id: 'reward-pending',
    businessId: 'business-2',
    name: 'Desconto',
    description: null,
    pointsRequired: 300,
    confirmedPoints: 220,
    pointsRemaining: 80,
    eligible: false,
  );
  const businesses = [
    CustomerBusiness(
      id: 'business-1',
      name: 'Café Central',
      address: 'Av. 24 de Julho',
      phone: '+258820000001',
      confirmedPoints: 120,
      rewards: [readyReward],
    ),
    CustomerBusiness(
      id: 'business-2',
      name: 'Mercado Azul',
      address: 'Av. Julius Nyerere',
      phone: '+258820000002',
      confirmedPoints: 220,
      rewards: [pendingReward],
    ),
  ];

  testWidgets('customer experience scopes Manrope typography', (tester) async {
    late String? fontFamily;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerExperienceTheme(
          child: Builder(
            builder: (context) {
              fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
              return const Scaffold(body: Text('Cliente'));
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(fontFamily, contains('Manrope'));
    expect(tester.takeException(), isNull);
  });

  test('debug demo data populates every empty customer tab', () async {
    final container = ProviderContainer(
      overrides: [
        customerAppRepositoryProvider.overrideWithValue(
          _EmptyCustomerRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final home = await container.read(customerHomeProvider.future);
    final businesses = await container.read(customerBusinessesProvider.future);
    final rewards = await container.read(customerRewardsProvider.future);
    final activity = await container.read(customerActivityProvider.future);
    final business = await container.read(
      customerBusinessProvider('demo-cafe-acacia').future,
    );
    final profile = await container.read(customerProfileProvider.future);

    expect(home.isDemo, isTrue);
    expect(home.value, hasLength(3));
    expect(
      home.value.fold<int>(
        0,
        (total, business) => total + business.confirmedPoints,
      ),
      2270,
    );
    expect(businesses.isDemo, isTrue);
    expect(businesses.value, hasLength(3));
    expect(rewards.isDemo, isTrue);
    expect(rewards.value, hasLength(5));
    expect(rewards.value.where((reward) => reward.eligible), hasLength(2));
    expect(activity.isDemo, isTrue);
    expect(activity.value, hasLength(5));
    expect(business.isDemo, isTrue);
    expect(business.value.name, 'Café Acácia');
    expect(business.value.confirmedPoints, 1250);
    expect(profile.isDemo, isTrue);
    expect(profile.value.displayName, 'Ana Mucavele');
    expect(profile.value.phone, '+258820000001');
    expect(profile.value.linkedBusinessCount, 3);
  });

  testWidgets('home wallet aggregates real business and reward data',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('home-scope'),
        overrides: [
          customerAppRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
          customerHomeProvider.overrideWith(
            (ref) async => CustomerData(
              businesses,
              fromCache: false,
              updatedAt: DateTime(2025),
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: CustomerHomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('340'), findsOneWidget);
    expect(find.text('2 negócios · 1 prémio disponível'), findsOneWidget);
    expect(find.text('Você já pode resgatar 🎁'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Continue a ganhar'), 300);
    expect(find.text('Continue a ganhar'), findsOneWidget);
    expect(find.text('Café Central'), findsOneWidget);
  });

  testWidgets('tab summaries reflect rewards, businesses and activity',
      (tester) async {
    final updatedAt = DateTime(2025);
    final activity = [
      CustomerActivity(
        id: 'sale-1',
        businessId: 'business-1',
        type: 'SALE',
        pointsDelta: 120,
        occurredAt: DateTime(2025, 1, 2),
      ),
      CustomerActivity(
        id: 'redeem-1',
        businessId: 'business-1',
        type: 'REDEEM',
        pointsDelta: -40,
        occurredAt: DateTime(2025, 1, 3),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('rewards-scope'),
        overrides: [
          customerAppRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
          customerRewardsProvider.overrideWith(
            (ref) async => CustomerData(
              [readyReward, pendingReward],
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerBusinessesProvider.overrideWith(
            (ref) async => CustomerData(
              businesses,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerActivityProvider.overrideWith(
            (ref) async => CustomerData(
              activity,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: CustomerRewardsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 prémio pronto'), findsOneWidget);
    expect(find.text('1 em progresso · atualiza com novos pontos'),
        findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('businesses-scope'),
        overrides: [
          customerBusinessesProvider.overrideWith(
            (ref) async => CustomerData(
              businesses,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: CustomerBusinessesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 negócios associados'), findsOneWidget);
    expect(find.text('340 pontos no total'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('activity-scope'),
        overrides: [
          customerActivityProvider.overrideWith(
            (ref) async => CustomerData(
              activity,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
          customerBusinessesProvider.overrideWith(
            (ref) async => CustomerData(
              businesses,
              fromCache: false,
              updatedAt: updatedAt,
            ),
          ),
        ],
        child: const MaterialApp(
          home: CustomerExperienceTheme(
            child: CustomerActivityScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+120'), findsOneWidget);
    expect(find.text('+120 pts'), findsOneWidget);
    expect(find.text('-40'), findsOneWidget);
    expect(find.text('-40 pts'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('movimentos'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Ganhos'), findsOneWidget);
    expect(find.text('Utilizados'), findsOneWidget);

    await tester.tap(find.text('Ganhos'));
    await tester.pumpAndSettle();
    expect(find.text('+120 pts'), findsOneWidget);
    expect(find.text('-40 pts'), findsNothing);
  });

  testWidgets('customer cards support small screens and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  CustomerPointsBalanceCard(
                    totalPoints: 9876543,
                    businessCount: 12,
                    availableRewardCount: 4,
                    onRewards: () {},
                    onQr: () {},
                  ),
                  const SizedBox(height: 12),
                  const CustomerRewardCard(
                    reward: CustomerReward(
                      id: 'long-reward',
                      businessId: 'business-1',
                      name:
                          'Uma experiência de brunch especial para duas pessoas',
                      description:
                          'Inclui uma seleção sazonal preparada pelo negócio.',
                      pointsRequired: 1500,
                      confirmedPoints: 1250,
                      pointsRemaining: 250,
                      eligible: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
