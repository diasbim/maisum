import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/customer_models.dart';

final customerHomeProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).home());
final customerBusinessesProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).businesses());
final customerRewardsProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).rewards());
final customerActivityProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).activity());
final customerProfileProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).profile());
final customerQrProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).qr());
final customerNotificationsProvider = FutureProvider.autoDispose(
    (ref) => ref.read(customerAppRepositoryProvider).notifications());

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Icon(Icons.card_giftcard_rounded,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text('Os seus pontos, num só lugar',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                const Text(
                  'Entre com o seu número de telefone para ver pontos, recompensas e histórico.',
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('customer_login_continue'),
                  onPressed: () => context.go('/customer-login/phone'),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(child: Text('Entrar como cliente')),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Sou comerciante'),
                ),
              ],
            ),
          ),
        ),
      );
}

class CustomerFeatureDisabledScreen extends StatelessWidget {
  const CustomerFeatureDisabledScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.pause_circle_outline, size: 64),
              const SizedBox(height: 16),
              Text('Área do cliente indisponível',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Esta funcionalidade ainda não está ativa para a sua conta.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => context.go('/customer-login'),
                child: const Text('Voltar'),
              ),
            ]),
          ),
        ),
      );
}

class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.child});
  final Widget child;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Início'),
    NavigationDestination(
        icon: Icon(Icons.card_giftcard_outlined), label: 'Prémios'),
    NavigationDestination(icon: Icon(Icons.history), label: 'Atividade'),
    NavigationDestination(
        icon: Icon(Icons.storefront_outlined), label: 'Negócios'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
  ];
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
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        destinations: _destinations,
        onDestinationSelected: (value) => context.go(_locations[value]),
      ),
    );
  }
}

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(customerAppRepositoryProvider).event('CUSTOMER_HOME_OPENED');
    final state = ref.watch(customerHomeProvider);
    return _Page(
      title: 'Olá',
      action: IconButton(
        tooltip: 'Mostrar código',
        onPressed: () => context.push('/customer/qr'),
        icon: const Icon(Icons.qr_code_rounded),
      ),
      child: state.when(
        loading: _loading,
        error: (error, _) =>
            _error(context, error, () => ref.invalidate(customerHomeProvider)),
        data: (data) => _businessList(context, data.value,
            offline: data.fromCache,
            empty: 'Ainda não tem negócios associados.'),
      ),
    );
  }
}

class CustomerBusinessesScreen extends ConsumerWidget {
  const CustomerBusinessesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerBusinessesProvider);
    return _Page(
      title: 'Os meus negócios',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerBusinessesProvider)),
        data: (data) => _businessList(context, data.value,
            offline: data.fromCache, empty: 'Nenhum negócio associado.'),
      ),
    );
  }
}

class CustomerBusinessDetailScreen extends ConsumerWidget {
  const CustomerBusinessDetailScreen({super.key, required this.businessId});
  final String businessId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(FutureProvider.autoDispose(
      (ref) => ref.read(customerAppRepositoryProvider).business(businessId),
    ));
    return _Page(
      title: 'Negócio',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(context, error, () {}),
        data: (data) {
          final business = data.value;
          return ListView(
            children: [
              Text(business.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              if (business.address != null) Text(business.address!),
              if (business.phone != null)
                TextButton.icon(
                  onPressed: () => _openWhatsApp(business.phone!),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Contactar no WhatsApp'),
                ),
              const SizedBox(height: 16),
              _offline(data.fromCache),
              Text('${business.confirmedPoints} pontos',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...business.rewards.map((reward) => _rewardTile(context, reward)),
            ],
          );
        },
      ),
    );
  }
}

class CustomerRewardsScreen extends ConsumerWidget {
  const CustomerRewardsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerRewardsProvider);
    return _Page(
      title: 'Prémios',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerRewardsProvider)),
        data: (data) => data.value.isEmpty
            ? const Center(child: Text('Ainda não há prémios disponíveis.'))
            : ListView(
                children: [
                  _offline(data.fromCache),
                  ...data.value.map((reward) => _rewardTile(context, reward)),
                ],
              ),
      ),
    );
  }
}

class CustomerActivityScreen extends ConsumerWidget {
  const CustomerActivityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerActivityProvider);
    return _Page(
      title: 'Atividade',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerActivityProvider)),
        data: (data) => data.value.isEmpty
            ? const Center(child: Text('Ainda não há atividade.'))
            : ListView(
                children: [
                  _offline(data.fromCache),
                  ...data.value.map(
                    (item) => ListTile(
                      leading: Icon(item.pointsDelta >= 0
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline),
                      title: Text(item.type == 'SALE'
                          ? 'Pontos recebidos'
                          : 'Prémio resgatado'),
                      subtitle: Text(
                          '${item.occurredAt.day}/${item.occurredAt.month}/${item.occurredAt.year}'),
                      trailing: Text(
                          '${item.pointsDelta >= 0 ? '+' : ''}${item.pointsDelta}'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class CustomerQrScreen extends ConsumerWidget {
  const CustomerQrScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(customerAppRepositoryProvider).event('CUSTOMER_QR_VIEWED');
    final state = ref.watch(customerQrProvider);
    return _Page(
      title: 'O meu código',
      child: state.when(
        loading: _loading,
        error: (error, _) =>
            _error(context, error, () => ref.invalidate(customerQrProvider)),
        data: (data) {
          final expired = !data.value.expiresAt.isAfter(DateTime.now());
          if (expired) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 72),
                  const SizedBox(height: 16),
                  const Text(
                    'O código guardado expirou. Ligue-se à internet para gerar outro.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(customerQrProvider),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QrImageView(
                    data: data.value.token,
                    version: QrVersions.auto,
                    size: 240,
                    semanticsLabel: 'Código QR do cliente',
                  ),
                  const SizedBox(height: 16),
                  const Text('Mostre este código no negócio.'),
                  if (data.fromCache)
                    const Text('Código guardado disponível sem internet.'),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('Mostrar código manual'),
                    children: [
                      SelectableText(
                        data.value.token,
                        textAlign: TextAlign.center,
                      ),
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: data.value.token),
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar código'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
  String? _success;
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4().replaceAll('-', '');
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
      setState(() => _success = result['redemption_code']?.toString() ??
          (result['redemption'] as Map?)?['redemption_code']?.toString() ??
          'Resgate confirmado.');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Confirmar resgate',
        child: Center(
          child: _success == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('O resgate só será confirmado pelo servidor.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _sending ? null : _redeem,
                    child:
                        Text(_sending ? 'A confirmar...' : 'Confirmar resgate'),
                  ),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle_outline, size: 72),
                  const SizedBox(height: 12),
                  const Text('Resgate confirmado!'),
                  SelectableText(_success!),
                  TextButton(
                      onPressed: () => context.go('/customer/rewards'),
                      child: const Text('Ver prémios')),
                ]),
        ),
      );
}

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerProfileProvider);
    final notificationState =
        ref.watch(customerNotificationsProvider).valueOrNull;
    final push = notificationState?.value['push'] as Map?;
    final delivery = push?['delivery']?.toString() ?? 'a verificar';
    return _Page(
      title: 'Perfil',
      child: state.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerProfileProvider)),
        data: (data) => ListView(children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(data.value.displayName ?? 'Cliente'),
            subtitle: Text(data.value.phone),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title:
                Text('${data.value.linkedBusinessCount} negócios associados'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Preferências'),
            onTap: () => context.push('/customer/preferences'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Notificações push'),
            subtitle: Text(
              delivery == 'not_configured'
                  ? 'Não configuradas neste momento.'
                  : 'Estado: $delivery',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Terminar sessão'),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/customer-login');
            },
          ),
        ]),
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
  Future<void> _save(CustomerPreferences value) async {
    setState(() => _value = value);
    try {
      await ref.read(customerAppRepositoryProvider).updatePreferences(value);
      ref.invalidate(customerProfileProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(customerProfileProvider);
    return _Page(
      title: 'Preferências',
      child: profile.when(
        loading: _loading,
        error: (error, _) => _error(
            context, error, () => ref.invalidate(customerProfileProvider)),
        data: (data) {
          final value = _value ?? data.value.preferences;
          return ListView(children: [
            SwitchListTile(
              title: const Text('Notificações'),
              value: value.notificationsEnabled,
              onChanged: (enabled) => _save(CustomerPreferences(
                  notificationsEnabled: enabled,
                  marketingEnabled: value.marketingEnabled,
                  deepLinksEnabled: value.deepLinksEnabled)),
            ),
            SwitchListTile(
              title: const Text('Comunicações de marketing'),
              value: value.marketingEnabled,
              onChanged: (enabled) => _save(CustomerPreferences(
                  notificationsEnabled: value.notificationsEnabled,
                  marketingEnabled: enabled,
                  deepLinksEnabled: value.deepLinksEnabled)),
            ),
          ]);
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
    if (_loading || value.isEmpty) return;
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
      setState(() => _result = customer == null
          ? 'Cliente encontrado.'
          : '${customer['name'] ?? 'Cliente'} · ${customer['phone'] ?? ''}');
    } catch (error) {
      setState(() => _error = error.toString());
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
  const _Page({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(title), actions: action == null ? null : [action!]),
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

Widget _loading() => const Center(child: CircularProgressIndicator());
Widget _error(BuildContext context, Object error, VoidCallback retry) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 8),
        Text('Não foi possível carregar: $error', textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Tentar novamente')),
      ]),
    );
Widget _offline(bool offline) => offline
    ? const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('A mostrar dados guardados.',
            style: TextStyle(fontStyle: FontStyle.italic)),
      )
    : const SizedBox.shrink();
Widget _businessList(BuildContext context, List<CustomerBusiness> businesses,
    {required bool offline, required String empty}) {
  if (businesses.isEmpty) return Center(child: Text(empty));
  return ListView(children: [
    _offline(offline),
    ...businesses.map((business) => Card(
            child: ListTile(
          title: Text(business.name),
          subtitle: Text(
              '${business.confirmedPoints} pontos${business.address == null ? '' : ' · ${business.address}'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/customer/business/${business.id}'),
        ))),
  ]);
}

Widget _rewardTile(BuildContext context, CustomerReward reward) => Card(
        child: ListTile(
      title: Text(reward.name),
      subtitle: Text(
          '${reward.pointsRequired} pontos${reward.description == null ? '' : ' · ${reward.description}'}'),
      trailing: reward.eligible
          ? FilledButton(
              onPressed: () => context.push('/customer/redeem/${reward.id}'),
              child: const Text('Resgatar'),
            )
          : Text('Faltam ${reward.pointsRemaining}'),
    ));
Future<void> _openWhatsApp(String phone) async {
  final number = phone.replaceAll(RegExp(r'\D'), '');
  final uri = Uri.parse('https://wa.me/$number');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Não foi possível abrir o WhatsApp.');
  }
}
