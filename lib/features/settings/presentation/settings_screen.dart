import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
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
              icon: Icons.phone_rounded,
              iconColor: AppColors.primary,
              title: AppStrings.phoneNumber,
              subtitle: session.phone,
            ),
          ],

          const _Section('Negocio'),
          _SettingsTile(
            icon: Icons.star_rate_rounded,
            iconColor: AppColors.secondary,
            title: AppStrings.taxaPontos,
            subtitle: AppStrings.taxaDesc,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.secondaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '1 / ${AppConstants.pointsPerMzn} MZN',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondaryDark,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // ── Security ────────────────────────────────────────────────────────
          const _Section('Segurança'),
          _SettingsTile(
            icon: Icons.pin_outlined,
            iconColor: AppColors.primary,
            title: 'PIN de acesso',
            subtitle: 'Alterar o PIN de segurança',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.g300, size: 20),
            onTap: () => context.push('/pin-setup'),
          ),
          _SettingsTile(
            icon: Icons.lock_clock_rounded,
            iconColor: AppColors.secondary,
            title: 'Bloquear agora',
            subtitle: 'Exige PIN para continuar',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.g300, size: 20),
            onTap: () {
              ref.read(appLockedProvider.notifier).state = true;
              context.pop();
            },
          ),

          const _Section('Aplicacao'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.g500,
            title: AppStrings.versao,
            trailing: Text('1.0.0',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.onSurfaceVariant)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.logout_rounded,
                          color: AppColors.error, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      AppStrings.logout,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.error, fontWeight: FontWeight.w600),
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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Row(
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
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
                      horizontal: 16, vertical: 14),
                  child: content,
                ),
              ),
            )
          : Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: content,
            ),
    );
  }
}
