import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/maisum_modal.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/customer_app_repository.dart';
import '../domain/customer_demo_data.dart';
import '../domain/customer_models.dart';
import 'widgets/customer_components.dart';

final customerHomeProvider = FutureProvider.autoDispose((ref) async {
  final data = await ref.read(customerAppRepositoryProvider).home();
  return _demoListIfEmpty(data, CustomerDemoData.businesses);
});
final customerBusinessesProvider = FutureProvider.autoDispose((ref) async {
  final data = await ref.read(customerAppRepositoryProvider).businesses();
  return _demoListIfEmpty(data, CustomerDemoData.businesses);
});
final customerRewardsProvider = FutureProvider.autoDispose((ref) async {
  final data = await ref.read(customerAppRepositoryProvider).rewards();
  return _demoListIfEmpty(data, CustomerDemoData.rewards);
});
final customerActivityProvider = FutureProvider.autoDispose((ref) async {
  final data = await ref.read(customerAppRepositoryProvider).activity();
  return _demoListIfEmpty(data, CustomerDemoData.activity);
});
final customerBusinessProvider = FutureProvider.autoDispose
    .family<CustomerData<CustomerBusiness>, String>((ref, businessId) {
  final demoBusiness = customerDemoDataEnabled
      ? CustomerDemoData.businessById(businessId)
      : null;
  if (demoBusiness != null) {
    return Future.value(
      CustomerData(
        demoBusiness,
        fromCache: false,
        updatedAt: DateTime.now(),
        isDemo: true,
      ),
    );
  }
  return ref.read(customerAppRepositoryProvider).business(businessId);
});
final customerProfileProvider = FutureProvider.autoDispose((ref) async {
  final data = await ref.read(customerAppRepositoryProvider).profile();
  if (!customerDemoDataEnabled || data.value.linkedBusinessCount > 0) {
    return data;
  }
  return CustomerData(
    CustomerDemoData.profileFrom(data.value),
    fromCache: false,
    updatedAt: data.updatedAt,
    isDemo: true,
  );
});
final customerQrProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).qr());
final customerNotificationsProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).notifications());
final customerFeatureFlagsProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).featureFlags());

CustomerData<List<T>> _demoListIfEmpty<T>(
  CustomerData<List<T>> data,
  List<T> demoValues,
) {
  if (!customerDemoDataEnabled || data.value.isNotEmpty) return data;
  return CustomerData(
    demoValues,
    fromCache: false,
    updatedAt: data.updatedAt,
    isDemo: true,
  );
}

CustomerReward? _findRewardById(
  List<CustomerReward> rewards,
  String rewardId,
) {
  for (final reward in rewards) {
    if (reward.id == rewardId) return reward;
  }
  return null;
}

CustomerBusiness? _findBusinessById(
  List<CustomerBusiness> businesses,
  String businessId,
) {
  for (final business in businesses) {
    if (business.id == businessId) return business;
  }
  return null;
}

String _formatCustomerTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.primaryDarker,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryDarker,
                  AppColors.primary,
                  Color(0xFF28436F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const _CustomerLoginBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _CustomerBrand(),
                      const SizedBox(height: AppSpacing.xxxxl),
                      Text(
                        'Os seus pontos,\nsempre consigo.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Consulte saldos, descubra prémios e apresente o seu código em segundos.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.white.withValues(alpha: 0.78),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      const _CustomerValueCard(),
                      const SizedBox(height: AppSpacing.xxxl),
                      KeyedSubtree(
                        key: const Key('customer_login_continue'),
                        child: MaisUmButton(
                          label: 'Continuar com telemóvel',
                          onPressed: () => context.go('/customer-login/phone'),
                          trailingIcon: Icons.arrow_forward_rounded,
                          height: AppControlSize.buttonLarge,
                          backgroundColor: AppColors.secondary,
                          foregroundColor: AppColors.primaryDarker,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MaisUmButton(
                        label: 'Aceder como comerciante',
                        onPressed: () => context.go('/login'),
                        variant: MaisUmButtonVariant.ghost,
                        foregroundColor: AppColors.white,
                        leadingIcon: Icons.storefront_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Acesso seguro por SMS. Não precisa de palavra-passe.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerLoginBackground extends StatelessWidget {
  const _CustomerLoginBackground();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -90,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
          ],
        ),
      );
}

class _CustomerBrand extends StatelessWidget {
  const _CustomerBrand();

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        label: 'MaisUm cliente',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.16),
                ),
              ),
              child: const BrandMark(size: 28),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Mais'),
                  TextSpan(
                    text: 'Um',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                ],
              ),
              style: TextStyle(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
          ],
        ),
      );
}

class _CustomerValueCard extends StatelessWidget {
  const _CustomerValueCard();

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        backgroundColor: AppColors.white.withValues(alpha: 0.10),
        borderColor: AppColors.white.withValues(alpha: 0.16),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
        child: const Column(
          children: [
            _CustomerValueItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Pontos atualizados',
              description: 'Veja todos os saldos num único lugar.',
            ),
            SizedBox(height: AppSpacing.lg),
            _CustomerValueItem(
              icon: Icons.redeem_rounded,
              title: 'Prémios sem complicações',
              description: 'Saiba o que já pode resgatar.',
            ),
            SizedBox(height: AppSpacing.lg),
            _CustomerValueItem(
              icon: Icons.qr_code_2_rounded,
              title: 'Código sempre à mão',
              description: 'Identifique-se rapidamente no negócio.',
            ),
          ],
        ),
      );
}

class _CustomerValueItem extends StatelessWidget {
  const _CustomerValueItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.white.withValues(alpha: 0.74),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      );
}

class CustomerFeatureDisabledScreen extends StatelessWidget {
  const CustomerFeatureDisabledScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: MaisUmSurface(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  radius: AppRadius.xl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _CustomerBrandDark(),
                      const SizedBox(height: AppSpacing.xxxl),
                      const _LargeStateIcon(
                        icon: Icons.hourglass_top_rounded,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Área do cliente indisponível',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppColors.primaryDarker,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Não foi possível ativar a área do cliente neste momento. Tente novamente.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      MaisUmButton(
                        label: 'Tentar novamente',
                        onPressed: () =>
                            context.go('/customer-login/phone?source=role'),
                        leadingIcon: Icons.refresh_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MaisUmButton(
                        label: 'Escolher outro perfil',
                        onPressed: () => context.go('/choose-role'),
                        variant: MaisUmButtonVariant.ghost,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _CustomerBrandDark extends StatelessWidget {
  const _CustomerBrandDark();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: 28),
          SizedBox(width: AppSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Mais'),
                TextSpan(
                  text: 'Um',
                  style: TextStyle(color: AppColors.secondaryForeground),
                ),
              ],
            ),
            style: TextStyle(
              color: AppColors.primaryDarker,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      );
}

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.child});
  final Widget child;

  static const _locations = [
    '/customer/home',
    '/customer/rewards',
    '/customer/activity',
    '/customer/businesses',
    '/customer/profile',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _locations.indexWhere((route) => location.startsWith(route));
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: child,
      bottomNavigationBar: CustomerBottomNavigation(
        selectedIndex: index < 0 ? 0 : index,
        onSelected: (value) => context.go(_locations[value]),
      ),
    );
  }
}

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(customerAppRepositoryProvider).event('CUSTOMER_HOME_OPENED');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerHomeProvider);
    final flags = ref.watch(customerFeatureFlagsProvider).valueOrNull;
    final profile = ref.watch(customerProfileProvider).valueOrNull?.value;
    final firstName = profile?.displayName?.trim().split(RegExp(r'\s+')).first;
    return _Page(
      title: firstName == null || firstName.isEmpty
          ? 'Olá 👋'
          : 'Olá, $firstName 👋',
      subtitle: 'Tudo o que ganhou, pronto para usar.',
      action: IconButton(
        tooltip: 'Mostrar código',
        onPressed: flags?.qrEnabled == false
            ? null
            : () => context.push('/customer/qr'),
        icon: const Icon(LucideIcons.qrCode),
      ),
      child: state.when(
        loading: _loading,
        error: (error, _) =>
            _error(context, error, () => ref.invalidate(customerHomeProvider)),
        data: (data) => _customerHomeContent(
          context,
          data.value,
          offline: data.isOffline,
          demo: data.isDemo,
          qrEnabled: flags?.qrEnabled != false,
          redemptionEnabled: flags?.redemptionEnabled != false,
        ),
      ),
    );
  }
}

class CustomerBusinessesScreen extends ConsumerWidget {
  const CustomerBusinessesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerBusinessesProvider);
    final qrEnabled =
        ref.watch(customerFeatureFlagsProvider).valueOrNull?.qrEnabled != false;
    return _Page(
      title: 'Os meus negócios',
      subtitle: 'Os seus pontos organizados por negócio.',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerBusinessesProvider)),
        data: (data) => _customerBusinessesContent(
          context,
          data.value,
          offline: data.isOffline,
          demo: data.isDemo,
          qrEnabled: qrEnabled,
        ),
      ),
    );
  }
}

class CustomerBusinessDetailScreen extends ConsumerWidget {
  const CustomerBusinessDetailScreen({super.key, required this.businessId});
  final String businessId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerBusinessProvider(businessId));
    final flags = ref.watch(customerFeatureFlagsProvider).valueOrNull;
    return _Page(
      title: 'Negócio',
      subtitle: 'Saldo, contacto e prémios disponíveis.',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
          context,
          error,
          () => ref.invalidate(customerBusinessProvider(businessId)),
        ),
        data: (data) {
          final business = data.value;
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              _offline(data.isOffline),
              _demoNotice(data.isDemo),
              MaisUmSurface(
                padding: const EdgeInsets.all(AppSpacing.xl),
                radius: AppRadius.xl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SurfaceIcon(
                          icon: Icons.storefront_rounded,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                business.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              if (business.address != null) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  business.address!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryLight,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SALDO DISPONÍVEL',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.secondaryForeground,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${business.confirmedPoints} pontos',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: AppColors.primaryDarker,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    MaisUmButton(
                      label: 'Meu código',
                      onPressed: flags?.qrEnabled == false
                          ? null
                          : () => context.push('/customer/qr'),
                      leadingIcon: LucideIcons.qrCode,
                    ),
                    if (business.phone != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      MaisUmButton(
                        label: data.isDemo
                            ? 'Como contactar'
                            : 'Contactar no WhatsApp',
                        onPressed: () => data.isDemo
                            ? _showDemoMessage(context)
                            : _openWhatsApp(business.phone!),
                        variant: MaisUmButtonVariant.outlined,
                        leadingIcon: LucideIcons.messageCircle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const CustomerSectionHeader(
                title: 'Como ganhar pontos',
                subtitle:
                    'Apresente o seu código MaisUm neste negócio antes de concluir a compra.',
              ),
              const SizedBox(height: AppSpacing.xxl),
              const _SectionLabel(
                title: 'Prémios deste negócio',
                subtitle:
                    'Veja o que já pode usar e o que está quase a desbloquear.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (business.rewards.isEmpty)
                const CustomerStateView(
                  icon: LucideIcons.gift,
                  title: 'Ainda não há prémios',
                  message: 'Este negócio ainda não publicou prémios.',
                )
              else
                ...business.rewards.map(
                  (reward) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: CustomerRewardCard(
                      reward: reward,
                      businessName: business.name,
                      primaryActionLabel: customerRewardState(reward) ==
                                  CustomerRewardState.available &&
                              flags?.redemptionEnabled != false
                          ? (data.isDemo
                              ? 'Ver como resgatar'
                              : 'Resgatar prémio')
                          : 'Meu código',
                      onPrimaryAction: customerRewardState(reward) ==
                                  CustomerRewardState.expired ||
                              (customerRewardState(reward) ==
                                      CustomerRewardState.available &&
                                  flags?.redemptionEnabled == false) ||
                              (customerRewardState(reward) !=
                                      CustomerRewardState.available &&
                                  flags?.qrEnabled == false)
                          ? null
                          : () => customerRewardState(reward) ==
                                  CustomerRewardState.available
                              ? (data.isDemo
                                  ? _showDemoMessage(context)
                                  : context.push(
                                      '/customer/redeem/${reward.id}',
                                    ))
                              : context.push('/customer/qr'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CustomerRewardsScreen extends ConsumerStatefulWidget {
  const CustomerRewardsScreen({super.key});

  @override
  ConsumerState<CustomerRewardsScreen> createState() =>
      _CustomerRewardsScreenState();
}

class _CustomerRewardsScreenState extends ConsumerState<CustomerRewardsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(customerAppRepositoryProvider).event('CUSTOMER_REWARD_VIEWED');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerRewardsProvider);
    final flags = ref.watch(customerFeatureFlagsProvider).valueOrNull;
    return _Page(
      title: 'Prémios',
      subtitle: 'Transforme os seus pontos em experiências.',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerRewardsProvider)),
        data: (data) => _customerRewardsContent(
          context,
          data.value,
          offline: data.isOffline,
          demo: data.isDemo,
          qrEnabled: flags?.qrEnabled != false,
          redemptionEnabled: flags?.redemptionEnabled != false,
        ),
      ),
    );
  }
}

enum _CustomerActivityFilter { all, earned, used }

class CustomerActivityScreen extends ConsumerStatefulWidget {
  const CustomerActivityScreen({super.key});

  @override
  ConsumerState<CustomerActivityScreen> createState() =>
      _CustomerActivityScreenState();
}

class _CustomerActivityScreenState
    extends ConsumerState<CustomerActivityScreen> {
  _CustomerActivityFilter _filter = _CustomerActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerActivityProvider);
    final businesses =
        ref.watch(customerBusinessesProvider).valueOrNull?.value ??
            const <CustomerBusiness>[];
    return _Page(
      title: 'Atividade',
      subtitle: 'Um registo claro dos seus pontos ganhos e utilizados.',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerActivityProvider)),
        data: (data) => _customerActivityContent(
          context,
          data.value,
          businesses: businesses,
          offline: data.isOffline,
          demo: data.isDemo,
          filter: _filter,
          onFilterChanged: (value) => setState(() => _filter = value),
        ),
      ),
    );
  }
}

class CustomerQrScreen extends ConsumerStatefulWidget {
  const CustomerQrScreen({super.key});

  @override
  ConsumerState<CustomerQrScreen> createState() => _CustomerQrScreenState();
}

class _CustomerQrScreenState extends ConsumerState<CustomerQrScreen> {
  Timer? _expirationTimer;
  DateTime? _scheduledExpiration;

  @override
  void initState() {
    super.initState();
    ref.read(customerAppRepositoryProvider).event('CUSTOMER_QR_VIEWED');
  }

  void _scheduleExpiration(DateTime expiresAt) {
    if (_scheduledExpiration == expiresAt) return;
    _scheduledExpiration = expiresAt;
    _expirationTimer?.cancel();
    final delay = expiresAt.difference(DateTime.now());
    if (delay <= Duration.zero) return;
    _expirationTimer = Timer(delay, () {
      if (mounted) ref.invalidate(customerQrProvider);
    });
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featureState = ref.watch(customerFeatureFlagsProvider);
    if (featureState.valueOrNull?.qrEnabled == false) {
      return const _Page(
        title: 'Meu código MaisUm',
        subtitle: 'A forma mais rápida e segura de ganhar pontos.',
        child: CustomerStateView(
          icon: LucideIcons.qrCode,
          title: 'Código temporariamente indisponível',
          message: 'Esta funcionalidade não está disponível neste momento.',
        ),
      );
    }
    final state = ref.watch(customerQrProvider);
    final profile = ref.watch(customerProfileProvider).valueOrNull?.value;
    return _Page(
      title: 'Meu código MaisUm',
      subtitle: 'A forma mais rápida e segura de ganhar pontos.',
      child: state.when(
        loading: _loading,
        error: (error, _) =>
            _error(context, error, () => ref.invalidate(customerQrProvider)),
        data: (data) {
          _scheduleExpiration(data.value.expiresAt);
          final expired = !data.value.expiresAt.isAfter(DateTime.now());
          if (expired) {
            return CustomerStateView(
              icon: Icons.qr_code_2_rounded,
              title: 'Código expirado',
              message: 'Ligue-se à internet para gerar um novo código seguro.',
              actionLabel: 'Gerar novo código',
              onAction: () => ref.invalidate(customerQrProvider),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              if (data.isOffline) ...[
                const CustomerOfflineBanner(
                  message:
                      'Está sem ligação · Este código guardado continua disponível',
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              CustomerQrCodeCard(
                token: data.value.token,
                expiresAt: data.value.expiresAt,
                customerName: profile?.displayName,
                offline: data.isOffline,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: data.value.token));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado.')),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class CustomerRedeemScreen extends ConsumerStatefulWidget {
  const CustomerRedeemScreen({super.key, required this.rewardId});
  final String rewardId;
  @override
  ConsumerState<CustomerRedeemScreen> createState() =>
      _CustomerRedeemScreenState();
}

class _CustomerRedeemScreenState extends ConsumerState<CustomerRedeemScreen> {
  bool _sending = false;
  bool _restoring = true;
  CustomerRedemptionReceipt? _receipt;
  bool _pendingAttempt = false;
  bool _restoredReceipt = false;
  Timer? _receiptExpirationTimer;
  DateTime? _scheduledReceiptExpiration;
  late String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4().replaceAll('-', '');
    _restoreRedemption();
  }

  void _scheduleReceiptExpiration(CustomerRedemptionReceipt? receipt) {
    if (receipt == null || receipt.status != CustomerRedemptionStatus.pending) {
      _receiptExpirationTimer?.cancel();
      _scheduledReceiptExpiration = null;
      return;
    }
    if (_scheduledReceiptExpiration == receipt.codeExpiresAt) {
      return;
    }
    _scheduledReceiptExpiration = receipt.codeExpiresAt;
    _receiptExpirationTimer?.cancel();
    final delay = receipt.codeExpiresAt.difference(DateTime.now());
    _receiptExpirationTimer =
        Timer(delay <= Duration.zero ? Duration.zero : delay, () {
      if (!mounted || _receipt?.code != receipt.code) return;
      setState(() {
        _receipt = receipt.copyWith(status: CustomerRedemptionStatus.expired);
      });
    });
  }

  @override
  void dispose() {
    _receiptExpirationTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreRedemption() async {
    try {
      final record = await ref
          .read(customerAppRepositoryProvider)
          .redemptionRecord(widget.rewardId);
      if (record?['idempotency_key'] is String) {
        _idempotencyKey = record!['idempotency_key'] as String;
      }
      _pendingAttempt = record?['status'] == 'pending';
      final updatedAt = (record?['updated_at'] as num?)?.toInt();
      final receiptIsRecent = updatedAt != null &&
          DateTime.now()
                  .difference(DateTime.fromMillisecondsSinceEpoch(updatedAt)) <
              const Duration(hours: 24);
      if (record?['status'] == 'completed' &&
          record?['result'] is Map &&
          receiptIsRecent) {
        final result = (record!['result'] as Map).cast<String, dynamic>();
        _receipt = CustomerRedemptionReceipt.fromJson(result);
        _restoredReceipt = true;
      } else if (record?['status'] == 'completed') {
        await ref
            .read(customerAppRepositoryProvider)
            .startNewRedemption(widget.rewardId);
        _idempotencyKey = const Uuid().v4().replaceAll('-', '');
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_redemption_restore',
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _redeem() async {
    setState(() => _sending = true);
    try {
      final result = await ref.read(customerAppRepositoryProvider).redeem(
            widget.rewardId,
            _idempotencyKey,
          );
      ref.invalidate(customerHomeProvider);
      ref.invalidate(customerBusinessesProvider);
      ref.invalidate(customerRewardsProvider);
      ref.invalidate(customerActivityProvider);
      setState(() {
        _receipt = result;
        _pendingAttempt = false;
        _restoredReceipt = false;
      });
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_redemption_confirm',
      );
      if (mounted) {
        final message = AppErrorMapper.describe(error).message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _refreshReceipt() async {
    final receipt = _receipt;
    if (receipt == null || _sending) return;
    final repository = ref.read(customerAppRepositoryProvider);
    setState(() => _sending = true);
    try {
      final updated = await repository.redemptionStatus(receipt.id);
      if (!mounted) return;
      ref.invalidate(customerActivityProvider);
      setState(() => _receipt = updated);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_redemption_status',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.describe(error).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reissueReceipt() async {
    final receipt = _receipt;
    if (receipt == null ||
        receipt.status != CustomerRedemptionStatus.expired ||
        _sending) {
      return;
    }
    final repository = ref.read(customerAppRepositoryProvider);
    setState(() => _sending = true);
    try {
      final updated = await repository.reissueRedemption(
        redemptionId: receipt.id,
        idempotencyKey: const Uuid().v4().replaceAll('-', ''),
      );
      if (mounted) {
        setState(() {
          _receipt = updated;
          _restoredReceipt = false;
        });
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_redemption_reissue',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.describe(error).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final featureState = ref.watch(customerFeatureFlagsProvider);
    if (featureState.valueOrNull?.redemptionEnabled == false) {
      return const _Page(
        title: 'Confirmar resgate',
        subtitle: 'Revise e confirme quando estiver no negócio.',
        child: CustomerStateView(
          icon: LucideIcons.gift,
          title: 'Resgates temporariamente indisponíveis',
          message: 'Esta funcionalidade não está disponível neste momento.',
        ),
      );
    }
    if (_restoring) {
      return const _Page(
        title: 'Confirmar resgate',
        subtitle: 'Revise e confirme quando estiver no negócio.',
        child: CustomerLoadingState(),
      );
    }
    final rewardsState = ref.watch(customerRewardsProvider);
    final businesses =
        ref.watch(customerBusinessesProvider).valueOrNull?.value ??
            const <CustomerBusiness>[];
    final rewards = rewardsState.valueOrNull?.value;
    if (rewardsState.isLoading && rewards == null) {
      return const _Page(
        title: 'Confirmar resgate',
        subtitle: 'Revise e confirme quando estiver no negócio.',
        child: CustomerLoadingState(),
      );
    }
    if (rewardsState.hasError && rewards == null) {
      return _Page(
        title: 'Confirmar resgate',
        subtitle: 'Revise e confirme quando estiver no negócio.',
        child: _error(
          context,
          rewardsState.error!,
          () => ref.invalidate(customerRewardsProvider),
        ),
      );
    }
    final reward =
        rewards == null ? null : _findRewardById(rewards, widget.rewardId);
    final business = reward == null
        ? null
        : _findBusinessById(businesses, reward.businessId);
    if (reward == null && _receipt == null) {
      return const _Page(
        title: 'Confirmar resgate',
        subtitle: 'Revise e confirme quando estiver no negócio.',
        child: CustomerStateView(
          icon: LucideIcons.gift,
          title: 'Prémio indisponível',
          message: 'Este prémio já não está disponível para resgate.',
        ),
      );
    }
    final canRedeem = reward != null &&
        customerRewardState(reward) == CustomerRewardState.available;
    final canSubmit = canRedeem || _pendingAttempt;
    _scheduleReceiptExpiration(_receipt);
    return _Page(
      title: 'Confirmar resgate',
      subtitle: 'Revise e confirme quando estiver no negócio.',
      child: Center(
        child: MaisUmSurface(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          radius: AppRadius.xl,
          child: _receipt == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _LargeStateIcon(
                      icon: Icons.verified_user_outlined,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      reward?.name ?? 'Confirmação segura',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _pendingAttempt
                          ? 'Existe uma confirmação pendente. Retome-a com segurança sem duplicar o resgate.'
                          : business == null
                              ? '${reward?.pointsRequired ?? 0} pts\n\nConfirme apenas quando estiver pronto para usar o prémio.'
                              : '${business.name} · ${reward?.pointsRequired ?? 0} pts\n\nConfirme apenas quando estiver pronto para usar o prémio.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    MaisUmButton(
                      label: _pendingAttempt
                          ? 'Recuperar confirmação'
                          : 'Confirmar resgate',
                      loadingLabel: 'A confirmar...',
                      isLoading: _sending,
                      onPressed: canSubmit ? _redeem : null,
                      leadingIcon: Icons.redeem_rounded,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LargeStateIcon(
                      icon: _receipt!.status == CustomerRedemptionStatus.pending
                          ? Icons.schedule_rounded
                          : _receipt!.status ==
                                  CustomerRedemptionStatus.consumed
                              ? Icons.check_rounded
                              : Icons.timer_off_rounded,
                      success:
                          _receipt!.status == CustomerRedemptionStatus.consumed,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      switch (_receipt!.status) {
                        CustomerRedemptionStatus.pending => _restoredReceipt
                            ? 'Último resgate pendente'
                            : 'Confirme no negócio',
                        CustomerRedemptionStatus.consumed => 'Prémio utilizado',
                        CustomerRedemptionStatus.expired => 'Código expirado',
                      },
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      switch (_receipt!.status) {
                        CustomerRedemptionStatus.pending =>
                          'Apresente este código no negócio antes de expirar:',
                        CustomerRedemptionStatus.consumed =>
                          'O negócio confirmou a utilização deste prémio.',
                        CustomerRedemptionStatus.expired =>
                          'Este código já não pode ser utilizado.',
                      },
                      textAlign: TextAlign.center,
                    ),
                    if (_receipt!.status ==
                        CustomerRedemptionStatus.pending) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        label: 'Código QR do resgate',
                        image: true,
                        child: ExcludeSemantics(
                          child: QrImageView(
                            data: _receipt!.code,
                            size: 220,
                            backgroundColor: AppColors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppColors.primaryDarker,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppColors.primaryDarker,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SelectableText(
                        _receipt!.code,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.primaryDarker,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Válido até ${_formatCustomerTime(_receipt!.codeExpiresAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_receipt!.confirmedPoints != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Saldo atual: ${_receipt!.confirmedPoints} pts',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    if (_receipt!.status ==
                        CustomerRedemptionStatus.expired) ...[
                      MaisUmButton(
                        label: 'Gerar novo código',
                        loadingLabel: 'A gerar...',
                        isLoading: _sending,
                        onPressed: _reissueReceipt,
                        leadingIcon: LucideIcons.refreshCw,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (_receipt!.status ==
                        CustomerRedemptionStatus.pending) ...[
                      MaisUmButton(
                        label: 'Copiar código',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _receipt!.code),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado.')),
                          );
                        },
                        leadingIcon: LucideIcons.copy,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    MaisUmButton(
                      label: 'Atualizar estado',
                      loadingLabel: 'A atualizar...',
                      isLoading: _sending,
                      onPressed: _refreshReceipt,
                      variant: MaisUmButtonVariant.outlined,
                      leadingIcon: LucideIcons.refreshCw,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    MaisUmButton(
                      label: 'Voltar aos prémios',
                      onPressed: () => context.go('/customer/rewards'),
                      variant: MaisUmButtonVariant.ghost,
                    ),
                    if (canRedeem &&
                        _receipt!.status !=
                            CustomerRedemptionStatus.pending) ...[
                      const SizedBox(height: AppSpacing.sm),
                      MaisUmButton(
                        label: 'Resgatar novamente',
                        onPressed: () async {
                          await ref
                              .read(customerAppRepositoryProvider)
                              .startNewRedemption(widget.rewardId);
                          if (!mounted) return;
                          setState(() {
                            _idempotencyKey =
                                const Uuid().v4().replaceAll('-', '');
                            _receipt = null;
                            _pendingAttempt = false;
                            _restoredReceipt = false;
                          });
                        },
                        variant: MaisUmButtonVariant.ghost,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerProfileProvider);
    final notificationState =
        ref.watch(customerNotificationsProvider).valueOrNull;
    final push = notificationState?.value['push'] as Map?;
    final delivery = _customerPushStatus(push);
    return _Page(
      title: 'Perfil',
      subtitle: 'Conta, preferências e segurança.',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerProfileProvider)),
        data: (data) => ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            _demoNotice(data.isDemo),
            CustomerAccountHeader(
              name: data.value.displayName ?? 'Cliente MaisUm',
              phone: data.value.phone,
              linkedBusinessCount: data.value.linkedBusinessCount,
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel(title: 'Definições'),
            const SizedBox(height: AppSpacing.md),
            MaisUmSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingsTile(
                    icon: LucideIcons.slidersHorizontal,
                    title: 'Preferências',
                    subtitle: 'Escolha as comunicações que quer receber.',
                    onTap: () => context.push('/customer/preferences'),
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: LucideIcons.bell,
                    title: 'Notificações push',
                    subtitle: delivery,
                    onTap: () => context.push('/customer/preferences'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel(title: 'Segurança'),
            const SizedBox(height: AppSpacing.md),
            const MaisUmSurface(
              padding: EdgeInsets.zero,
              child: _SettingsTile(
                icon: LucideIcons.shieldCheck,
                title: 'Acesso seguro',
                subtitle: 'A sua conta é protegida por autenticação via SMS.',
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel(title: 'MaisUm'),
            const SizedBox(height: AppSpacing.md),
            MaisUmSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingsTile(
                    icon: LucideIcons.fileText,
                    title: 'Termos de utilização',
                    onTap: () => context.push('/customer/terms'),
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: LucideIcons.shield,
                    title: 'Privacidade',
                    onTap: () => context.push('/customer/privacy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            MaisUmSurface(
              padding: EdgeInsets.zero,
              child: _SettingsTile(
                icon: LucideIcons.logOut,
                title: 'Terminar sessão',
                destructive: true,
                onTap: () async {
                  final confirmed = await MaisUmModal.confirm(
                    context: context,
                    title: AppStrings.confirmarLogout,
                    message: AppStrings.confirmarLogoutMsg,
                    primaryLabel: AppStrings.logout,
                    secondaryLabel: AppStrings.cancelar,
                    icon: Icons.logout_rounded,
                    destructive: true,
                  );
                  if (confirmed != true || !context.mounted) return;

                  await ref.read(authControllerProvider.notifier).logout();
                  if (context.mounted) context.go('/choose-role');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerPreferencesScreen extends ConsumerStatefulWidget {
  const CustomerPreferencesScreen({super.key});
  @override
  ConsumerState<CustomerPreferencesScreen> createState() =>
      _CustomerPreferencesScreenState();
}

class _CustomerPreferencesScreenState
    extends ConsumerState<CustomerPreferencesScreen> {
  CustomerPreferences? _value;
  bool _saving = false;

  Future<void> _save(CustomerPreferences value) async {
    if (_saving) return;
    final previous = _value ??
        ref.read(customerProfileProvider).valueOrNull?.value.preferences;
    setState(() {
      _value = value;
      _saving = true;
    });
    try {
      await ref.read(customerAppRepositoryProvider).updatePreferences(value);
      ref.invalidate(customerProfileProvider);
      final session = ref.read(authControllerProvider).valueOrNull;
      await ref.read(customerPlatformServiceProvider).synchronize(session);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'customer_preferences_save',
      );
      if (mounted) {
        setState(() => _value = previous);
        final message = AppErrorMapper.describe(error).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(customerProfileProvider);
    return _Page(
      title: 'Preferências',
      subtitle: 'Controle o que recebe e quando.',
      child: profile.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerProfileProvider)),
        data: (data) {
          final value = _value ?? data.value.preferences;
          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              MaisUmSurface(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary:
                            const Icon(Icons.notifications_active_outlined),
                        title: const Text('Notificações'),
                        subtitle: const Text(
                            'Atualizações importantes da sua conta.'),
                        value: value.notificationsEnabled,
                        onChanged: _saving
                            ? null
                            : (enabled) => _save(
                                  CustomerPreferences(
                                    notificationsEnabled: enabled,
                                    marketingEnabled: value.marketingEnabled,
                                    deepLinksEnabled: value.deepLinksEnabled,
                                  ),
                                ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        secondary: const Icon(Icons.campaign_outlined),
                        title: const Text('Novidades e ofertas'),
                        subtitle: const Text(
                            'Prémios e campanhas dos seus negócios.'),
                        value: value.marketingEnabled,
                        onChanged: _saving
                            ? null
                            : (enabled) => _save(
                                  CustomerPreferences(
                                    notificationsEnabled:
                                        value.notificationsEnabled,
                                    marketingEnabled: enabled,
                                    deepLinksEnabled: value.deepLinksEnabled,
                                  ),
                                ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        secondary: const Icon(LucideIcons.externalLink),
                        title: const Text('Abrir ligações MaisUm'),
                        subtitle: const Text(
                          'Permita que ligações seguras abram diretamente no app.',
                        ),
                        value: value.deepLinksEnabled,
                        onChanged: _saving
                            ? null
                            : (enabled) => _save(
                                  CustomerPreferences(
                                    notificationsEnabled:
                                        value.notificationsEnabled,
                                    marketingEnabled: value.marketingEnabled,
                                    deepLinksEnabled: enabled,
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pode alterar estas escolhas a qualquer momento.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class MerchantCustomerQrResolveScreen extends ConsumerStatefulWidget {
  const MerchantCustomerQrResolveScreen({super.key});

  @override
  ConsumerState<MerchantCustomerQrResolveScreen> createState() =>
      _MerchantCustomerQrResolveScreenState();
}

class _MerchantCustomerQrResolveScreenState
    extends ConsumerState<MerchantCustomerQrResolveScreen> {
  final _controller = TextEditingController();
  final _scannerController = MobileScannerController();
  String? _result;
  String? _error;
  bool _loading = false;
  bool _scannerVisible = false;

  @override
  void dispose() {
    _controller.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _resolve([String? scannedValue]) async {
    final value = (scannedValue ?? _controller.text).trim();
    if (_loading) return;
    if (value.isEmpty) {
      setState(() => _error = 'Introduza ou leia um código de cliente.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (scannedValue != null) {
        _controller.text = value;
        _scannerVisible = false;
      }
    });
    if (scannedValue != null) {
      await _scannerController.stop();
    }
    try {
      final token = await ref
          .read(firebaseAuthInstanceProvider)
          .currentUser
          ?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Sessão Firebase indisponível.');
      }
      final result = await ref
          .read(customerAppApiProvider)
          .resolveMerchantQr(token, value);
      final customer = (result['customer'] as Map?)?.cast<String, dynamic>();
      if (!mounted) return;
      setState(() => _result = customer == null
          ? 'Cliente encontrado.'
          : '${customer['name'] ?? 'Cliente'} · ${customer['phone'] ?? ''}');
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_customer_qr_resolve',
      );
      if (mounted) {
        setState(() => _error = AppErrorMapper.describe(error).message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_loading || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _resolve(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ler código do cliente')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(children: [
            const Text(
                'Leia o QR ou introduza o código apresentado pelo cliente.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      final visible = !_scannerVisible;
                      setState(() => _scannerVisible = visible);
                      if (visible) {
                        await _scannerController.start();
                      } else {
                        await _scannerController.stop();
                      }
                    },
              icon: Icon(
                _scannerVisible ? Icons.close : Icons.qr_code_scanner,
              ),
              label: Text(
                _scannerVisible ? 'Fechar câmara' : 'Ler com a câmara',
              ),
            ),
            if (_scannerVisible) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Código do cliente'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : () => _resolve(),
              child: Text(_loading ? 'A validar...' : 'Validar código'),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_result!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ]),
        ),
      );
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.offWhite,
        body: Column(
          children: [
            CustomerAppHeader(
              title: title,
              subtitle: subtitle,
              action: action,
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppLayout.contentMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        0,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SurfaceIcon extends StatelessWidget {
  const _SurfaceIcon({
    required this.icon,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.secondaryLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(
          icon,
          color: AppColors.primaryDarker,
          size: 22,
        ),
      );
}

class _LargeStateIcon extends StatelessWidget {
  const _LargeStateIcon({
    required this.icon,
    this.success = false,
  });

  final IconData icon;
  final bool success;

  @override
  Widget build(BuildContext context) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: success ? AppColors.successLight : AppColors.secondaryLight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 34,
          color: success ? AppColors.success : AppColors.primaryDarker,
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primaryDarker,
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: ListTile(
          minLeadingWidth: 44,
          leading: _SurfaceIcon(icon: icon),
          title: Text(
            title,
            style: TextStyle(
              color: destructive ? AppColors.error : AppColors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: onTap,
        ),
      );
}

Widget _loading() => const CustomerLoadingState();

Widget _error(BuildContext context, Object error, VoidCallback retry) =>
    CustomerStateView(
      icon: Icons.cloud_off_outlined,
      title: 'Não foi possível carregar os seus dados',
      message: 'Verifique a ligação e tente novamente.',
      actionLabel: 'Tentar novamente',
      onAction: retry,
      error: true,
    );

Widget _offline(bool offline) => offline
    ? const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: CustomerOfflineBanner(),
      )
    : const SizedBox.shrink();

Widget _demoNotice(bool demo) => demo
    ? const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: CustomerDemoModeBanner(),
      )
    : const SizedBox.shrink();

Widget _customerHomeContent(
  BuildContext context,
  List<CustomerBusiness> businesses, {
  required bool offline,
  required bool demo,
  required bool qrEnabled,
  required bool redemptionEnabled,
}) {
  final totalPoints = businesses.fold<int>(
    0,
    (total, business) => total + business.confirmedPoints,
  );
  final readyRewards = businesses
      .expand((business) => business.rewards)
      .where(
        (reward) =>
            customerRewardState(reward) == CustomerRewardState.available,
      )
      .toList();
  final pendingRewards = businesses
      .expand((business) => business.rewards)
      .where(
        (reward) =>
            customerRewardState(reward) == CustomerRewardState.inProgress,
      )
      .toList()
    ..sort((a, b) => a.pointsRemaining.compareTo(b.pointsRemaining));
  final availableReward = readyRewards.isEmpty ? null : readyRewards.first;
  final nextReward = pendingRewards.isEmpty ? null : pendingRewards.first;
  return ListView(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    children: [
      _offline(offline),
      _demoNotice(demo),
      CustomerPointsBalanceCard(
        totalPoints: totalPoints,
        businessCount: businesses.length,
        availableRewardCount: readyRewards.length,
        onRewards: () => context.go('/customer/rewards'),
        onQr: qrEnabled ? () => context.push('/customer/qr') : null,
      ),
      if (availableReward != null) ...[
        const SizedBox(height: AppSpacing.xxl),
        const CustomerSectionHeader(title: 'Você já pode resgatar 🎁'),
        const SizedBox(height: AppSpacing.md),
        CustomerRewardCard(
          reward: availableReward,
          businessName: _businessNameForReward(businesses, availableReward),
          compact: true,
          primaryActionLabel: demo ? 'Ver como resgatar' : 'Resgatar prémio',
          onPrimaryAction: redemptionEnabled
              ? () => demo
                  ? _showDemoMessage(context)
                  : context.push('/customer/redeem/${availableReward.id}')
              : null,
        ),
      ],
      if (nextReward != null) ...[
        const SizedBox(height: AppSpacing.xxl),
        const CustomerSectionHeader(
          title: 'Continue a ganhar',
          subtitle: 'Está mais perto do próximo benefício.',
        ),
        const SizedBox(height: AppSpacing.md),
        CustomerRewardCard(
          reward: nextReward,
          businessName: _businessNameForReward(businesses, nextReward),
          primaryActionLabel: 'Ganhar pontos',
          onPrimaryAction:
              qrEnabled ? () => context.push('/customer/qr') : null,
        ),
      ],
      const SizedBox(height: AppSpacing.xxl),
      CustomerSectionHeader(
        title: businesses.isEmpty ? 'Comece a ganhar' : 'Sua carteira',
        subtitle: businesses.isEmpty
            ? 'Identifique-se num negócio MaisUm para começar.'
            : 'Os seus pontos por negócio.',
        actionLabel: businesses.length > 3 ? 'Ver todos' : null,
        onAction: businesses.length > 3
            ? () => context.go('/customer/businesses')
            : null,
      ),
      const SizedBox(height: AppSpacing.md),
      if (businesses.isEmpty)
        _businessEmptyCard(
          context,
          'A sua carteira ainda está vazia.',
          qrEnabled: qrEnabled,
        )
      else
        ...businesses.take(3).map(
              (business) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: CustomerBusinessCard(
                  business: business,
                  compact: true,
                  onTap: () =>
                      context.push('/customer/business/${business.id}'),
                ),
              ),
            ),
    ],
  );
}

String? _businessNameForReward(
  List<CustomerBusiness> businesses,
  CustomerReward reward,
) {
  for (final business in businesses) {
    if (business.id == reward.businessId ||
        business.rewards.any((item) => item.id == reward.id)) {
      return business.name;
    }
  }
  return null;
}

Widget _customerBusinessesContent(
  BuildContext context,
  List<CustomerBusiness> businesses, {
  required bool offline,
  required bool demo,
  required bool qrEnabled,
}) {
  final totalPoints = businesses.fold<int>(
    0,
    (total, business) => total + business.confirmedPoints,
  );
  return ListView(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    children: [
      _offline(offline),
      _demoNotice(demo),
      _PortfolioSummary(
        count: businesses.length,
        totalPoints: totalPoints,
      ),
      const SizedBox(height: AppSpacing.xxl),
      const CustomerSectionHeader(
        title: 'Carteira por negócio',
        subtitle: 'Toque num negócio para ver saldo, contacto e prémios.',
      ),
      const SizedBox(height: AppSpacing.md),
      if (businesses.isEmpty)
        _businessEmptyCard(
          context,
          'Nenhum negócio associado.',
          qrEnabled: qrEnabled,
        )
      else
        ..._businessCards(context, businesses),
    ],
  );
}

Widget _customerRewardsContent(
  BuildContext context,
  List<CustomerReward> rewards, {
  required bool offline,
  required bool demo,
  required bool qrEnabled,
  required bool redemptionEnabled,
}) {
  final ready = rewards
      .where(
        (reward) =>
            customerRewardState(reward) == CustomerRewardState.available,
      )
      .length;
  final inProgress = rewards
      .where((reward) =>
          !reward.eligible &&
          customerRewardState(reward) == CustomerRewardState.inProgress)
      .length;
  final sortedRewards = [...rewards]..sort((a, b) {
      final stateOrder = {
        CustomerRewardState.available: 0,
        CustomerRewardState.inProgress: 1,
        CustomerRewardState.locked: 2,
        CustomerRewardState.expired: 3,
      };
      final byState = stateOrder[customerRewardState(a)]!
          .compareTo(stateOrder[customerRewardState(b)]!);
      return byState != 0
          ? byState
          : a.pointsRemaining.compareTo(b.pointsRemaining);
    });
  return ListView(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    children: [
      _offline(offline),
      _demoNotice(demo),
      _RewardsSummary(available: ready, inProgress: inProgress),
      const SizedBox(height: AppSpacing.xxl),
      const CustomerSectionHeader(
        title: 'Os seus benefícios',
        subtitle: 'O progresso atualiza quando recebe novos pontos.',
      ),
      const SizedBox(height: AppSpacing.md),
      if (rewards.isEmpty)
        const CustomerStateView(
          icon: LucideIcons.gift,
          title: 'Ainda não tem prémios disponíveis',
          message:
              'Continue a ganhar pontos para desbloquear novos benefícios.',
        )
      else
        ...sortedRewards.map(
          (reward) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: CustomerRewardCard(
              reward: reward,
              primaryActionLabel:
                  customerRewardState(reward) == CustomerRewardState.available
                      ? (demo ? 'Ver como resgatar' : 'Resgatar prémio')
                      : 'Meu código',
              onPrimaryAction:
                  customerRewardState(reward) == CustomerRewardState.expired ||
                          (customerRewardState(reward) ==
                                  CustomerRewardState.available &&
                              !redemptionEnabled) ||
                          (customerRewardState(reward) !=
                                  CustomerRewardState.available &&
                              !qrEnabled)
                      ? null
                      : () => customerRewardState(reward) ==
                              CustomerRewardState.available
                          ? (demo
                              ? _showDemoMessage(context)
                              : context.push(
                                  '/customer/redeem/${reward.id}',
                                ))
                          : context.push('/customer/qr'),
            ),
          ),
        ),
    ],
  );
}

Widget _customerActivityContent(
  BuildContext context,
  List<CustomerActivity> activity, {
  required List<CustomerBusiness> businesses,
  required bool offline,
  required bool demo,
  required _CustomerActivityFilter filter,
  required ValueChanged<_CustomerActivityFilter> onFilterChanged,
}) {
  final earned = activity
      .where((item) => item.pointsDelta > 0)
      .fold<int>(0, (total, item) => total + item.pointsDelta);
  final used = activity
      .where((item) => item.pointsDelta < 0)
      .fold<int>(0, (total, item) => total + item.pointsDelta.abs());
  final filteredActivity = switch (filter) {
    _CustomerActivityFilter.all => activity,
    _CustomerActivityFilter.earned =>
      activity.where((item) => item.pointsDelta >= 0).toList(),
    _CustomerActivityFilter.used =>
      activity.where((item) => item.pointsDelta < 0).toList(),
  };
  return ListView(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
    children: [
      _offline(offline),
      _demoNotice(demo),
      _ActivitySummary(
        earned: earned,
        used: used,
        transactions: activity.length,
      ),
      const SizedBox(height: AppSpacing.xxl),
      const CustomerSectionHeader(
        title: 'Movimentos recentes',
        subtitle: 'Um registo claro de pontos ganhos e utilizados.',
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final value in _CustomerActivityFilter.values)
            ChoiceChip(
              label: Text(switch (value) {
                _CustomerActivityFilter.all => 'Todos',
                _CustomerActivityFilter.earned => 'Ganhos',
                _CustomerActivityFilter.used => 'Utilizados',
              }),
              selected: filter == value,
              onSelected: (_) => onFilterChanged(value),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      if (activity.isEmpty)
        const CustomerStateView(
          icon: LucideIcons.history,
          title: 'Ainda não há atividade',
          message: 'As suas visitas e resgates aparecerão aqui.',
        )
      else if (filteredActivity.isEmpty)
        const CustomerStateView(
          icon: LucideIcons.listFilter,
          title: 'Sem movimentos neste filtro',
          message: 'Escolha outro filtro para consultar a sua atividade.',
        )
      else
        ...filteredActivity.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: CustomerActivityItem(
              activity: item,
              businessName: item.businessName ??
                  _businessForActivity(businesses, item)?.name,
              rewardName:
                  item.rewardName ?? _rewardForActivity(businesses, item)?.name,
            ),
          ),
        ),
    ],
  );
}

CustomerBusiness? _businessForActivity(
  List<CustomerBusiness> businesses,
  CustomerActivity activity,
) {
  for (final business in businesses) {
    if (business.id == activity.businessId) return business;
  }
  return null;
}

CustomerReward? _rewardForActivity(
  List<CustomerBusiness> businesses,
  CustomerActivity activity,
) {
  if (activity.rewardId == null) return null;
  for (final business in businesses) {
    for (final reward in business.rewards) {
      if (reward.id == activity.rewardId) return reward;
    }
  }
  return null;
}

List<Widget> _businessCards(
  BuildContext context,
  List<CustomerBusiness> businesses,
) =>
    businesses
        .map((business) => _businessCard(context, business))
        .toList(growable: false);

Widget _businessCard(BuildContext context, CustomerBusiness business) =>
    Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: CustomerBusinessCard(
        business: business,
        onTap: () => context.push('/customer/business/${business.id}'),
      ),
    );

Widget _businessEmptyCard(
  BuildContext context,
  String title, {
  required bool qrEnabled,
}) =>
    MaisUmSurface(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      radius: AppRadius.xl,
      child: Column(
        children: [
          const _LargeStateIcon(icon: LucideIcons.store),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use o seu código num negócio MaisUm. Assim que ganhar pontos, o negócio aparece aqui automaticamente.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Row(
              children: [
                Icon(
                  LucideIcons.sparkles,
                  color: AppColors.primaryDarker,
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Diga o seu número de telemóvel ao negócio para associar os pontos à sua conta.',
                    style: TextStyle(
                      color: AppColors.primaryDarker,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          MaisUmButton(
            label: 'Mostrar o meu código',
            onPressed: qrEnabled ? () => context.push('/customer/qr') : null,
            variant: MaisUmButtonVariant.outlined,
            leadingIcon: LucideIcons.qrCode,
          ),
        ],
      ),
    );

class _PortfolioSummary extends StatelessWidget {
  const _PortfolioSummary({
    required this.count,
    required this.totalPoints,
  });

  final int count;
  final int totalPoints;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        child: Row(
          children: [
            const _SurfaceIcon(icon: LucideIcons.building2),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? '1 negócio associado'
                        : '$count negócios associados',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$totalPoints pontos no total',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.primaryDarker,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RewardsSummary extends StatelessWidget {
  const _RewardsSummary({
    required this.available,
    required this.inProgress,
  });

  final int available;
  final int inProgress;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        backgroundColor: AppColors.secondaryLight,
        borderColor: AppColors.secondaryLight,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryDarker,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(
                LucideIcons.gift,
                color: AppColors.secondary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$available ${available == 1 ? 'prémio disponível' : 'prémios disponíveis'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primaryDarker,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$available ${available == 1 ? 'pronto' : 'prontos'} · '
                    '$inProgress em progresso',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({
    required this.earned,
    required this.used,
    required this.transactions,
  });

  final int earned;
  final int used;
  final int transactions;

  @override
  Widget build(BuildContext context) => MaisUmSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        radius: AppRadius.xl,
        backgroundColor: AppColors.primaryDarker,
        borderColor: AppColors.primaryDarker,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESUMO DE MOVIMENTOS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _LedgerMetric(
                    icon: LucideIcons.trendingUp,
                    value: '+$earned',
                    label: 'ganhos',
                  ),
                ),
                Expanded(
                  child: _LedgerMetric(
                    icon: LucideIcons.ticketCheck,
                    value: '-$used',
                    label: 'utilizados',
                  ),
                ),
                Expanded(
                  child: _LedgerMetric(
                    icon: LucideIcons.receiptText,
                    value: '$transactions',
                    label: 'movimentos',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _LedgerMetric extends StatelessWidget {
  const _LedgerMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.white.withValues(alpha: 0.7),
                ),
          ),
        ],
      );
}

void _showDemoMessage(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Este é um prémio de demonstração. Nenhum saldo será alterado.',
      ),
    ),
  );
}

Future<void> _openWhatsApp(String phone) async {
  final number = phone.replaceAll(RegExp(r'\D'), '');
  final uri = Uri.parse('https://wa.me/$number');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Não foi possível abrir o WhatsApp.');
  }
}

String _customerPushStatus(Map<dynamic, dynamic>? push) {
  if (push == null) return 'A verificar disponibilidade.';
  if (push['enabled'] != true) return 'Indisponíveis neste momento.';
  return switch (push['delivery']?.toString()) {
    'not_configured' => 'Ainda não configuradas neste dispositivo.',
    'configured' => 'Ativas neste dispositivo.',
    _ => 'Disponibilidade a verificar.',
  };
}
