import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'retention_metric.dart';

/// Portuguese presentation for the retention risk scale.
///
/// The engine stores the levels in English ('active', 'attention', 'risk',
/// 'lost') because they are database values. Every user-facing surface must go
/// through here, so the merchant never reads a raw enum on a Portuguese screen.
///
/// Severity is ordered by *what the merchant should do*, not by how bad the
/// number looks: `risk` is the loudest because it is still recoverable, while
/// `lost` is muted — worth a win-back, but not the thing to do first today.
@immutable
class RetentionRiskPresentation {
  const RetentionRiskPresentation({
    required this.label,
    required this.meaning,
    required this.foreground,
    required this.background,
    required this.icon,
  });

  /// Short badge text, e.g. "Em risco".
  final String label;

  /// One line telling the merchant what the level actually means.
  final String meaning;

  /// Text/icon colour — at least 4.5:1 against [background] and white.
  final Color foreground;

  /// Badge fill.
  final Color background;

  /// Meaning never rides on colour alone.
  final IconData icon;

  static RetentionRiskPresentation of(String riskLevel) {
    switch (riskLevel) {
      case RetentionRiskLevel.attention:
        return const RetentionRiskPresentation(
          label: 'Atenção',
          meaning: 'Está a demorar mais do que o habitual a voltar.',
          foreground: AppColors.secondaryForeground,
          background: AppColors.amberLight,
          icon: Icons.schedule_rounded,
        );
      case RetentionRiskLevel.risk:
        return const RetentionRiskPresentation(
          label: 'Em risco',
          meaning: 'Ainda dá para recuperar. Fale com este cliente hoje.',
          foreground: AppColors.red,
          background: AppColors.redLight,
          icon: Icons.priority_high_rounded,
        );
      case RetentionRiskLevel.lost:
        return const RetentionRiskPresentation(
          label: 'Perdido',
          meaning: 'Há muito que não volta. Vale uma oferta de reconquista.',
          foreground: AppColors.g800,
          background: AppColors.g100,
          icon: Icons.person_off_rounded,
        );
      default:
        return const RetentionRiskPresentation(
          label: 'Ativo',
          meaning: 'Continua a voltar dentro do padrão dele.',
          foreground: AppColors.greenDark,
          background: AppColors.greenLight,
          icon: Icons.check_circle_rounded,
        );
    }
  }
}

/// Portuguese presentation for the loyalty tier badge on recurring customers.
@immutable
class RecurringBadgePresentation {
  const RecurringBadgePresentation({
    required this.label,
    required this.meaning,
    required this.icon,
  });

  final String label;
  final String meaning;
  final IconData icon;

  static RecurringBadgePresentation of(RecurringCustomerSummary customer) {
    switch (customer.badge) {
      case 'VIP':
        return const RecurringBadgePresentation(
          label: 'VIP',
          meaning: 'Está entre quem mais gasta na sua loja.',
          icon: Icons.workspace_premium_rounded,
        );
      case 'Campeão':
        return const RecurringBadgePresentation(
          label: 'Campeão',
          meaning: 'Já voltou dez vezes ou mais.',
          icon: Icons.emoji_events_rounded,
        );
      default:
        return const RecurringBadgePresentation(
          label: 'Frequente',
          meaning: 'Volta com regularidade.',
          icon: Icons.repeat_rounded,
        );
    }
  }
}
