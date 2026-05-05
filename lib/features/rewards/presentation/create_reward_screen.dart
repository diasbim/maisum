import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';
import 'rewards_controller.dart';

class CreateRewardScreen extends ConsumerStatefulWidget {
  const CreateRewardScreen({super.key});

  @override
  ConsumerState<CreateRewardScreen> createState() => _CreateRewardScreenState();
}

class _CreateRewardScreenState extends ConsumerState<CreateRewardScreen> {
  final _nameCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pointsCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(rewardsControllerProvider.notifier).createReward(
          name: _nameCtrl.text.trim(),
          pointsRequired: int.parse(_pointsCtrl.text.trim()),
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(rewardsControllerProvider);
    final isLoading = state is AsyncLoading;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text(AppStrings.novaRecompensa)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(size: 32),
                      const SizedBox(height: 12),
                      Text(
                        'Nova Recompensa',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Defina o premio e os pontos necessarios para resgate.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Form fields
                Text('NOME',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      hintText: AppStrings.nomeRecompensa),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppStrings.rewardNameRequired
                      : null,
                ),
                const SizedBox(height: 20),

                Text('PONTOS NECESSARIOS',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pointsCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      hintText: AppStrings.pontosNecessarios,
                      suffixText: 'pts'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return AppStrings.pointsRequired;
                    }
                    if (int.tryParse(v) == null || int.parse(v) <= 0) {
                      return 'Valor invalido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                Text('DESCRICAO (OPCIONAL)',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(hintText: AppStrings.descricao),
                ),
                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: isLoading ? null : AppTheme.primaryGradient,
                      color: isLoading ? AppColors.surfaceContainerHigh : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isLoading ? null : AppTheme.shadowMd,
                    ),
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white)))
                          : const Text(
                              AppStrings.guardar,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
