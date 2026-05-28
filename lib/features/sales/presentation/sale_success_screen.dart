import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/errors/app_error_reporter.dart';
import '../../customers/domain/customer.dart';
import '../../rewards/domain/reward.dart';
import '../../rewards/domain/reward_progress.dart';
import '../../rewards/presentation/rewards_controller.dart';
import '../../subscription/domain/feature_keys.dart';
import '../../subscription/domain/usage_metrics.dart';
import '../../appointments/providers/appointments_providers.dart';
import 'sale_controller.dart';

class SaleSuccessArgs {
  const SaleSuccessArgs({required this.result});

  final SaleResult result;
}

class SaleSuccessScreen extends ConsumerStatefulWidget {
  const SaleSuccessScreen({super.key, required this.args});

  final SaleSuccessArgs args;

  @override
  ConsumerState<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends ConsumerState<SaleSuccessScreen> {
  bool _playedFeedback = false;
  bool _isSendingWhatsApp = false;
  DateTime? _scheduledDate;
  bool _appointmentCreated = false;

  void _handleBackPressed() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/dashboard');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playSuccessFeedback();
    });
  }

  void _playSuccessFeedback() {
    if (_playedFeedback) return;
    _playedFeedback = true;
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'sale_success_sound');
    }
    try {
      HapticFeedback.mediumImpact();
    } catch (e, st) {
      AppErrorReporter.report(e, st, hint: 'sale_success_haptic');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sale = widget.args.result.sale;
    final customer = widget.args.result.customer;
    final createAppointmentState = ref.watch(createAppointmentProvider);

    final rewardsAsync = ref.watch(rewardsControllerProvider);
    final rewards = rewardsAsync.valueOrNull ?? const <Reward>[];
    final progress = RewardProgress.fromRewards(
      currentPoints: customer.totalPoints,
      rewards: rewards,
    );

    final customerName = customer.name.trim();
    final customerLabel = customerName.isEmpty ? 'O cliente' : customerName;

    final message = _buildSuccessMessage(
      pointsEarned: sale.points,
      pointsLeft: progress.pointsRemaining,
      customerName: customerName,
      nextRewardName: progress.nextRewardName,
      unlockedRewardName: progress.unlockedRewardName,
    );

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDarker, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -60,
                child: _GlowCircle(color: AppColors.secondary, size: 180),
              ),
              Positioned(
                bottom: -120,
                left: -80,
                child: _GlowCircle(color: AppColors.primaryDark, size: 220),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: _handleBackPressed,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const BrandMark(size: 28),
                            const SizedBox(width: 10),
                            Text(
                              AppStrings.appName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Center(child: _SuccessHero(points: sale.points)),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            AppStrings.vendaRegistada,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            '$customerLabel ganhou ${sale.points} pontos',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _RewardProgressCard(
                          pointsLeft: progress.pointsRemaining,
                          currentPoints: progress.currentPoints,
                          targetPoints: progress.targetPoints,
                          progress: progress.progressFraction,
                          nextRewardName: progress.nextRewardName,
                          unlockedRewardName: progress.unlockedRewardName,
                          hasRewards: rewards.isNotEmpty,
                        ),
                        const SizedBox(height: 16),
                        _MessagePreviewCard(
                          message: message,
                          onSendSms: () => _sendSms(context, customer, message),
                          isSendingWhatsApp: _isSendingWhatsApp,
                          onSendWhatsApp: () =>
                              _sendWhatsApp(customer, message),
                        ),
                        const SizedBox(height: 16),
                        _ScheduleNextVisitCard(
                          selectedDate: _scheduledDate,
                          appointmentCreated: _appointmentCreated,
                          isSaving: createAppointmentState.isLoading,
                          onQuickSelect: (days) =>
                              _handleQuickSchedule(customer.id, days),
                          onPickDate: () => _handleManualSchedule(customer.id),
                          onViewAll: () => context.push('/appointments'),
                        ),
                        const SizedBox(height: 18),
                        _PrimaryCtaButton(
                          label: AppStrings.novaVenda,
                          onPressed: () => context.go('/new-sale'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => context.go('/dashboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          child: Text(AppStrings.voltarAoInicio),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _buildSuccessMessage({
    required int pointsEarned,
    required int pointsLeft,
    required String customerName,
    required String? nextRewardName,
    required String? unlockedRewardName,
  }) {
    final firstName = _firstName(customerName);
    final greeting = firstName == null
        ? 'Obrigado pela sua visita!'
        : 'Obrigado pela sua visita, $firstName!';
    final buffer = StringBuffer()
      ..writeln(greeting)
      ..writeln('Ganhou $pointsEarned pontos.');
    final safePointsLeft = pointsLeft < 0 ? 0 : pointsLeft;
    if (unlockedRewardName != null) {
      buffer.writeln('Já tem pontos para resgatar $unlockedRewardName.');
    }
    if (nextRewardName != null) {
      buffer.writeln('Faltam $safePointsLeft pontos para $nextRewardName.');
    } else if (unlockedRewardName == null) {
      buffer.writeln('Continue a juntar pontos para ganhar recompensas.');
    }
    buffer.writeln('Volte sempre!');
    return buffer.toString().trim();
  }

  static String? _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  static Future<void> _sendSms(
    BuildContext context,
    Customer customer,
    String message,
  ) async {
    final clean = customer.phone.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return;
    final number = clean.startsWith('258') ? clean : '258$clean';
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: {'body': message},
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      AppFeedback.showMessage(
        context,
        message: 'Não foi possível abrir o SMS neste dispositivo.',
      );
    }
  }

  Future<void> _sendWhatsApp(Customer customer, String message) async {
    if (_isSendingWhatsApp) return;
    setState(() => _isSendingWhatsApp = true);

    try {
      final connectivity = ref.read(connectivityServiceProvider);
      final gate = ref.read(featureGateProvider);
      final decision = await gate.check(
        featureKey: FeatureKeys.whatsappAutomation,
        metricKey: UsageMetrics.whatsappMessages,
      );
      if (!decision.allowed) {
        if (context.mounted) {
          AppFeedback.showMessage(
            context,
            message: AppStrings.funcaoIndisponivel,
          );
        }
        return;
      }
      if (decision.softLimited && context.mounted) {
        AppFeedback.showMessage(context, message: AppStrings.limiteSoftAviso);
      }

      if (!connectivity.isOnline) {
        final clean = customer.phone.replaceAll(RegExp(r'\D'), '');
        if (clean.isEmpty) return;
        final number = clean.startsWith('258') ? clean : '258$clean';
        await ref
            .read(notificationQueueServiceProvider)
            .enqueueWhatsApp(
              phone: number,
              message: message,
              source: 'sale_success',
            );
        try {
          await ref
              .read(analyticsServiceProvider)
              .record(
                eventType: 'whatsapp_sent',
                source: 'whatsapp',
                properties: {'queued': true, 'source': 'sale_success'},
              );
        } catch (_) {}
        if (context.mounted) {
          AppFeedback.showMessage(context, message: AppStrings.whatsappQueued);
        }
        return;
      }

      final clean = customer.phone.replaceAll(RegExp(r'\D'), '');
      if (clean.isEmpty) return;
      final number = clean.startsWith('258') ? clean : '258$clean';
      final url = Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
      );
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppFeedback.showMessage(
          context,
          message: 'Não foi possível abrir o WhatsApp neste dispositivo.',
        );
        return;
      }
      if (launched) {
        try {
          await ref
              .read(usageTrackerProvider)
              .record(
                metricKey: UsageMetrics.whatsappMessages,
                source: 'whatsapp',
                metadata: {'message_type': 'sale_success'},
              );
          await ref
              .read(analyticsServiceProvider)
              .record(
                eventType: 'whatsapp_sent',
                source: 'whatsapp',
                properties: {'queued': false, 'source': 'sale_success'},
              );
        } catch (_) {}
        if (context.mounted) {
          AppFeedback.showMessage(context, message: AppStrings.whatsappSent);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingWhatsApp = false);
      }
    }
  }

  Future<void> _handleQuickSchedule(String customerId, int days) async {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day + days, 10);
    await _createAppointment(customerId, target);
  }

  Future<void> _handleManualSchedule(String customerId) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('pt', 'PT'),
      helpText: 'Escolher data do próximo corte',
      cancelText: 'Cancelar',
      confirmText: 'Guardar',
    );
    if (picked == null) return;

    final target = DateTime(picked.year, picked.month, picked.day, 10);
    await _createAppointment(customerId, target);
  }

  Future<void> _createAppointment(
    String customerId,
    DateTime scheduledDate,
  ) async {
    try {
      await ref
          .read(createAppointmentProvider.notifier)
          .createAppointment(
            customerId: customerId,
            scheduledDate: scheduledDate,
            source: 'post_sale_flow',
          );
      if (!mounted) return;
      setState(() {
        _scheduledDate = scheduledDate;
        _appointmentCreated = true;
      });
      AppFeedback.showMessage(
        context,
        message: 'Próximo corte agendado para ${_formatDate(scheduledDate)}.',
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.showMessage(context, message: AppStrings.erroGenericoAcao);
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 80,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  const _SuccessHero({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.secondary.withValues(alpha: 0.7),
                  AppColors.secondary.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.secondary, AppColors.secondaryDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.5),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 64,
            ),
          ),
          Positioned(
            right: 18,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Text(
                '+$points',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 18,
            child: _Sparkle(
              size: 8,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Positioned(
            right: 4,
            top: 36,
            child: _Sparkle(
              size: 12,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          Positioned(
            left: 32,
            bottom: 12,
            child: _Sparkle(
              size: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.6,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _RewardProgressCard extends StatelessWidget {
  const _RewardProgressCard({
    required this.pointsLeft,
    required this.currentPoints,
    required this.targetPoints,
    required this.progress,
    required this.nextRewardName,
    required this.unlockedRewardName,
    required this.hasRewards,
  });

  final int pointsLeft;
  final int currentPoints;
  final int? targetPoints;
  final double progress;
  final String? nextRewardName;
  final String? unlockedRewardName;
  final bool hasRewards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlocked = nextRewardName == null && unlockedRewardName != null;
    final displayTarget = targetPoints ?? currentPoints;
    final unclampedCurrent = isUnlocked ? displayTarget : currentPoints;
    final displayCurrent = displayTarget > 0
        ? unclampedCurrent.clamp(0, displayTarget).toInt()
        : unclampedCurrent;
    final label = hasRewards
        ? (nextRewardName != null
              ? 'Faltam $pointsLeft pontos para $nextRewardName'
              : unlockedRewardName != null
              ? 'Recompensa disponível: $unlockedRewardName'
              : 'Recompensa disponível')
        : 'Crie uma recompensa para continuar';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(end: hasRewards ? progress : 0),
                  builder: (context, animatedProgress, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: animatedProgress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.secondary,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(end: displayCurrent.toDouble()),
                      builder: (context, animatedCurrent, _) {
                        return Text(
                          '${animatedCurrent.round()} pts',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    Text(
                      '$displayTarget pts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: AppColors.secondary,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePreviewCard extends StatelessWidget {
  const _MessagePreviewCard({
    required this.message,
    required this.onSendSms,
    required this.isSendingWhatsApp,
    required this.onSendWhatsApp,
  });

  final String message;
  final VoidCallback onSendSms;
  final bool isSendingWhatsApp;
  final VoidCallback onSendWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.mensagemProntaEnvio,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSendSms,
                  icon: const Icon(Icons.sms_rounded, size: 16),
                  label: const Text(AppStrings.enviarSms),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSendingWhatsApp ? null : onSendWhatsApp,
                  icon: isSendingWhatsApp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(
                    isSendingWhatsApp
                        ? 'A enviar...'
                        : AppStrings.enviarWhatsApp,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  const _PrimaryCtaButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.arrow_forward_rounded),
        ],
      ),
    );
  }
}

class _ScheduleNextVisitCard extends StatelessWidget {
  const _ScheduleNextVisitCard({
    required this.selectedDate,
    required this.appointmentCreated,
    required this.isSaving,
    required this.onQuickSelect,
    required this.onPickDate,
    required this.onViewAll,
  });

  final DateTime? selectedDate;
  final bool appointmentCreated;
  final bool isSaving;
  final ValueChanged<int> onQuickSelect;
  final VoidCallback onPickDate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Agendar próximo corte?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('Ver agenda'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Escolha em 1 toque para aumentar a recorrência.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sugestão rápida',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in const [7, 14, 21, 30])
                _QuickDayActionButton(
                  days: days,
                  isSaving: isSaving,
                  onTap: () => onQuickSelect(days),
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: isSaving ? null : onPickDate,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: const Text('Escolher no calendário'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (isSaving) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(color: AppColors.secondary),
          ],
          if (appointmentCreated && selectedDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.secondary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Agendado para ${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickDayActionButton extends StatelessWidget {
  const _QuickDayActionButton({
    required this.days,
    required this.isSaving,
    required this.onTap,
  });

  final int days;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isSaving ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text('+$days'),
    );
  }
}
