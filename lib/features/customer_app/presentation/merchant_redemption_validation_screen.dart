import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_error_mapper.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../design_system/components/maisum_button.dart';
import '../../../design_system/components/maisum_surface.dart';
import '../domain/customer_models.dart';
import 'widgets/customer_components.dart';

class MerchantRedemptionValidationScreen extends ConsumerStatefulWidget {
  const MerchantRedemptionValidationScreen({super.key});

  @override
  ConsumerState<MerchantRedemptionValidationScreen> createState() =>
      _MerchantRedemptionValidationScreenState();
}

class _MerchantRedemptionValidationScreenState
    extends ConsumerState<MerchantRedemptionValidationScreen>
    with WidgetsBindingObserver {
  final _codeController = TextEditingController();
  final _scannerController = MobileScannerController();
  MerchantRedemptionPreview? _preview;
  String? _error;
  bool _loading = false;
  bool _scannerVisible = false;
  String _idempotencyKey = const Uuid().v4().replaceAll('-', '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scannerVisible) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_setScannerActive(true));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_setScannerActive(false));
        break;
    }
  }

  Future<void> _setScannerActive(bool active) async {
    try {
      if (active) {
        await _scannerController.start();
      } else {
        await _scannerController.stop();
      }
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: active
            ? 'merchant_redemption_scanner_start'
            : 'merchant_redemption_scanner_stop',
      );
      if (active && mounted) {
        setState(() {
          _scannerVisible = false;
          _error = 'Não foi possível iniciar a câmara.';
        });
      }
    }
  }

  Future<void> _resolve([String? scannedCode]) async {
    if (_loading) return;
    final code = (scannedCode ?? _codeController.text).trim();
    if (code.isEmpty) {
      setState(() => _error = 'Introduza ou leia o código do resgate.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      if (scannedCode != null) {
        _codeController.text = code;
        _scannerVisible = false;
      }
    });
    if (scannedCode != null) await _setScannerActive(false);
    try {
      final preview =
          await ref.read(merchantRedemptionServiceProvider).resolve(code);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _idempotencyKey = const Uuid().v4().replaceAll('-', '');
      });
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_redemption_resolve',
      );
      if (mounted) {
        setState(() => _error = AppErrorMapper.describe(error).message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _consume() async {
    final preview = _preview;
    if (_loading ||
        preview == null ||
        preview.receipt.status != CustomerRedemptionStatus.pending) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final consumed =
          await ref.read(merchantRedemptionServiceProvider).consume(
                redemptionCode: preview.receipt.code,
                idempotencyKey: _idempotencyKey,
              );
      if (!mounted) return;
      setState(() => _preview = consumed);
    } catch (error, stackTrace) {
      AppErrorReporter.report(
        error,
        stackTrace,
        hint: 'merchant_redemption_consume',
      );
      if (mounted) {
        setState(() => _error = AppErrorMapper.describe(error).message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_loading || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _resolve(value);
  }

  void _reset() {
    setState(() {
      _preview = null;
      _error = null;
      _codeController.clear();
      _idempotencyKey = const Uuid().v4().replaceAll('-', '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Validar prémio')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Leia o código apresentado pelo cliente antes de entregar o prémio.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (preview == null) ...[
              MaisUmButton(
                label: _scannerVisible ? 'Fechar câmara' : 'Ler código QR',
                onPressed: _loading
                    ? null
                    : () async {
                        final visible = !_scannerVisible;
                        setState(() => _scannerVisible = visible);
                        await _setScannerActive(visible);
                      },
                leadingIcon:
                    _scannerVisible ? LucideIcons.x : LucideIcons.scanQrCode,
                variant: MaisUmButtonVariant.outlined,
              ),
              if (_scannerVisible) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _codeController,
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Código do resgate',
                  hintText: 'r1_...',
                  prefixIcon: Icon(LucideIcons.ticketCheck),
                ),
                onSubmitted: (_) => _resolve(),
              ),
              const SizedBox(height: AppSpacing.md),
              MaisUmButton(
                label: 'Validar código',
                loadingLabel: 'A validar...',
                isLoading: _loading,
                onPressed: _resolve,
                leadingIcon: LucideIcons.searchCheck,
              ),
            ] else
              _RedemptionPreviewCard(
                preview: preview,
                loading: _loading,
                onConsume: _consume,
                onReset: _reset,
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              CustomerStateView(
                icon: LucideIcons.circleAlert,
                title: 'Não foi possível validar',
                message: _error!,
                error: true,
                actionLabel: 'Tentar outro código',
                onAction: _reset,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RedemptionPreviewCard extends StatelessWidget {
  const _RedemptionPreviewCard({
    required this.preview,
    required this.loading,
    required this.onConsume,
    required this.onReset,
  });

  final MerchantRedemptionPreview preview;
  final bool loading;
  final VoidCallback onConsume;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final receipt = preview.receipt;
    final pending = receipt.status == CustomerRedemptionStatus.pending;
    final consumed = receipt.status == CustomerRedemptionStatus.consumed;
    return MaisUmSurface(
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomerStatusChip(
            label: switch (receipt.status) {
              CustomerRedemptionStatus.pending => 'Pronto para confirmar',
              CustomerRedemptionStatus.consumed => 'Já utilizado',
              CustomerRedemptionStatus.expired => 'Código expirado',
            },
            tone: consumed
                ? CustomerStatusTone.success
                : pending
                    ? CustomerStatusTone.warning
                    : CustomerStatusTone.error,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            preview.rewardName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${preview.customerName} · ${receipt.pointsSpent} pts',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (preview.customerPhone != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              preview.customerPhone!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (pending)
            Text(
              'Confirme apenas depois de verificar o prémio com o cliente. Esta ação não pode ser repetida.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else if (consumed)
            Text(
              'Utilização confirmada às ${_formatTime(receipt.consumedAt)}.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Text(
              'A validade terminou às ${_formatTime(receipt.codeExpiresAt)}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: AppSpacing.xl),
          if (pending)
            MaisUmButton(
              label: 'Confirmar utilização',
              loadingLabel: 'A confirmar...',
              isLoading: loading,
              onPressed: onConsume,
              leadingIcon: LucideIcons.badgeCheck,
            ),
          if (pending) const SizedBox(height: AppSpacing.sm),
          MaisUmButton(
            label: 'Validar outro código',
            onPressed: loading ? null : onReset,
            variant: MaisUmButtonVariant.outlined,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '--:--';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
