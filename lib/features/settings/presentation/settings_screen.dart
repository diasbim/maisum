import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/pin_verification_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/pin_verification_feedback.dart';
import '../../auth/presentation/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.definicoes)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (session != null) ...[
            const _Section('Conta'),
            _SettingsTile(
              icon: Icons.storefront_rounded,
              iconColor: AppColors.secondary,
              title: AppStrings.nomeNegocio,
              subtitle: session.merchantName,
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.g300,
                size: 20,
              ),
              onTap: () =>
                  _editMerchantName(context, ref, session.merchantName),
            ),
            _SettingsTile(
              icon: Icons.phone_rounded,
              iconColor: AppColors.primary,
              title: AppStrings.phoneNumber,
              subtitle: session.phone,
            ),
            _SettingsTile(
              icon: Icons.verified_user_rounded,
              iconColor: AppColors.green,
              title: AppStrings.subscricao,
              subtitle: _formatSubscriptionStatus(session.subscriptionStatus),
            ),
            const _Section(AppStrings.identificadores),
            _SettingsTile(
              icon: Icons.badge_outlined,
              iconColor: AppColors.primary,
              title: AppStrings.merchantId,
              subtitle: session.resolvedMerchantId,
            ),
            _SettingsTile(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.secondary,
              title: AppStrings.appUserId,
              subtitle: session.resolvedAppUserId,
            ),
            if (session.deviceId != null && session.deviceId!.isNotEmpty)
              _SettingsTile(
                icon: Icons.phone_android_rounded,
                iconColor: AppColors.primaryDark,
                title: AppStrings.deviceId,
                subtitle: session.deviceId,
              ),
            _SettingsTile(
              icon: Icons.schedule_rounded,
              iconColor: AppColors.g800,
              title: AppStrings.sessaoValidaAte,
              subtitle: _formatExpiry(session.expiresAt),
            ),
          ],

          // ── Security ────────────────────────────────────────────────────────
          const _Section('Segurança'),
          _SettingsTile(
            icon: Icons.pin_outlined,
            iconColor: AppColors.primary,
            title: 'PIN de acesso',
            subtitle: 'Alterar o PIN de segurança',
            brandAccent: true,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () => _showPinVerifySheet(context, ref),
          ),
          _SettingsTile(
            icon: Icons.lock_clock_rounded,
            iconColor: AppColors.secondary,
            title: 'Bloquear agora',
            subtitle: 'Exige PIN para continuar',
            brandAccent: true,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.g300,
              size: 20,
            ),
            onTap: () {
              ref.read(appLockedProvider.notifier).state = true;
              context.pop();
            },
          ),

          const SizedBox(height: 8),
          const _Section('Sessao'),
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => _confirmLogout(context, ref),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      AppStrings.logout,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _editMerchantName(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final messenger = ScaffoldMessenger.of(context);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.editarNomeNegocio),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: AppStrings.nomeNegocio,
            hintText: AppStrings.nomeNegocioHint,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.cancelar),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text(AppStrings.guardar),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!context.mounted || updatedName == null) {
      return;
    }

    final normalizedName = updatedName.trim();
    if (normalizedName.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.merchantNameRequired)),
      );
      return;
    }
    if (normalizedName == currentName.trim()) {
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateMerchantName(normalizedName);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.nomeNegocioAtualizado)),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.erroGenerico)),
      );
    }
  }

  String _formatSubscriptionStatus(String status) {
    if (status.trim().isEmpty) {
      return 'Sem estado';
    }
    return status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatExpiry(DateTime expiry) {
    final localExpiry = expiry.toLocal();
    final day = localExpiry.day.toString().padLeft(2, '0');
    final month = localExpiry.month.toString().padLeft(2, '0');
    final year = localExpiry.year.toString();
    final hour = localExpiry.hour.toString().padLeft(2, '0');
    final minute = localExpiry.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _showPinVerifySheet(BuildContext context, WidgetRef ref) async {
    final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
    if (!context.mounted) return;
    if (!hasPin) {
      context.push('/pin-setup');
      return;
    }
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _PinVerifySheet(storage: ref.read(secureStorageServiceProvider)),
    );
    if (verified == true && context.mounted) {
      context.push('/pin-setup');
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.confirmarLogout),
        content: const Text(AppStrings.confirmarLogoutMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text(AppStrings.logout),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.onSurfaceVariant,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ── PIN Verify Sheet ──────────────────────────────────────────────────────────

class _PinVerifySheet extends StatefulWidget {
  const _PinVerifySheet({required this.storage});
  final SecureStorageService storage;

  @override
  State<_PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<_PinVerifySheet>
    with SingleTickerProviderStateMixin, PinVerificationShakeMixin {
  String _input = '';
  bool _isError = false;
  bool _isLoading = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    initPinShakeAnimation();
  }

  @override
  void dispose() {
    disposePinShakeAnimation();
    super.dispose();
  }

  void _handleDigit(String d) {
    if (_isLoading || _isError || _input.length >= AppConstants.pinLength) {
      return;
    }
    setState(() => _input += d);
    if (_input.length == AppConstants.pinLength) _verify();
  }

  void _handleDelete() {
    if (_isLoading) return;
    setState(() {
      _isError = false;
      if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final result = await PinVerificationService.verifyEphemeralPin(
      storage: widget.storage,
      input: _input,
      currentAttempts: _attempts,
    );
    if (result.isSuccess) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (result.status == PinVerificationStatus.unavailable) {
      setState(() => _isLoading = false);
      return;
    }

    if (result.isBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.pinBlocked)));
        Navigator.of(context).pop(false);
      }
      return;
    }

    setState(() {
      _attempts = result.attempts;
      _isError = true;
      _isLoading = false;
    });
    triggerPinShake();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _isError = false;
        _input = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.g300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text('Verificar PIN atual', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Introduza o PIN atual para continuar',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          PinVerificationFeedback(
            shakeAnimation: pinShakeAnimation,
            inputLength: _input.length,
            attempts: _attempts,
            isError: _isError,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 24),
          PinPad(onDigit: _handleDigit, onDelete: _handleDelete),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.brandAccent = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool brandAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            if (brandAccent)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.g100),
                  ),
                  child: const BrandMark(size: 10, padding: EdgeInsets.all(3)),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.g100, width: 1.5),
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: content,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: content,
            ),
    );
  }
}
