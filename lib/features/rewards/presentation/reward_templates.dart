import 'package:flutter/material.dart';

class RewardTemplatePreset {
  const RewardTemplatePreset({
    required this.code,
    required this.label,
    required this.rewardName,
    required this.pointsRequired,
    required this.description,
    required this.icon,
  });

  final String code;
  final String label;
  final String rewardName;
  final int pointsRequired;
  final String description;
  final IconData icon;
}

const rewardTemplatePresets = <RewardTemplatePreset>[
  RewardTemplatePreset(
    code: 'corte_gratis',
    label: 'Corte gratis',
    rewardName: 'Corte gratis',
    pointsRequired: 1000,
    description: 'Ganhe um corte completo apos juntar os pontos.',
    icon: Icons.content_cut_rounded,
  ),
  RewardTemplatePreset(
    code: 'barba_premium',
    label: 'Barba premium',
    rewardName: 'Barba premium',
    pointsRequired: 700,
    description: 'Finalize o visual com barba premium sem custo.',
    icon: Icons.face_retouching_natural_rounded,
  ),
  RewardTemplatePreset(
    code: 'desconto_20',
    label: 'Desconto 20%',
    rewardName: 'Desconto de 20%',
    pointsRequired: 600,
    description: 'Aplique 20% de desconto no proximo atendimento.',
    icon: Icons.percent_rounded,
  ),
  RewardTemplatePreset(
    code: 'combo_lavagem',
    label: 'Lavagem + finalizacao',
    rewardName: 'Lavagem + finalizacao',
    pointsRequired: 850,
    description: 'Resgate um combo rapido de lavagem e finalizacao.',
    icon: Icons.shower_rounded,
  ),
];

RewardTemplatePreset? rewardTemplateByCode(String? code) {
  final normalized = code?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  for (final template in rewardTemplatePresets) {
    if (template.code == normalized) {
      return template;
    }
  }
  return null;
}
