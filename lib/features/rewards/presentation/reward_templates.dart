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

const genericRewardTemplatePresets = <RewardTemplatePreset>[
  RewardTemplatePreset(
    code: 'desconto_10',
    label: 'Desconto 10%',
    rewardName: 'Desconto de 10%',
    pointsRequired: 500,
    description: 'Aplique 10% de desconto na próxima compra.',
    icon: Icons.percent_rounded,
  ),
  RewardTemplatePreset(
    code: 'desconto_20',
    label: 'Desconto 20%',
    rewardName: 'Desconto de 20%',
    pointsRequired: 800,
    description: 'Aplique 20% de desconto na próxima compra.',
    icon: Icons.percent_rounded,
  ),
  RewardTemplatePreset(
    code: 'brinde',
    label: 'Brinde',
    rewardName: 'Brinde especial',
    pointsRequired: 600,
    description: 'Ofereça um brinde escolhido pelo negócio.',
    icon: Icons.card_giftcard_rounded,
  ),
];

const barberRewardTemplatePresets = <RewardTemplatePreset>[
  RewardTemplatePreset(
    code: 'corte_gratis',
    label: 'Corte grátis',
    rewardName: 'Corte grátis',
    pointsRequired: 1000,
    description: 'Ganhe um corte completo após juntar os pontos.',
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
    code: 'combo_lavagem',
    label: 'Lavagem + finalização',
    rewardName: 'Lavagem + finalização',
    pointsRequired: 850,
    description: 'Resgate um conjunto rápido de lavagem e finalização.',
    icon: Icons.shower_rounded,
  ),
];

List<RewardTemplatePreset> rewardTemplatesForProfile(String? profileId) {
  return [
    ...genericRewardTemplatePresets,
    if (profileId == 'barbershop') ...barberRewardTemplatePresets,
  ];
}

RewardTemplatePreset? rewardTemplateByCode(String? code) {
  final normalized = code?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  for (final template in [
    ...genericRewardTemplatePresets,
    ...barberRewardTemplatePresets,
  ]) {
    if (template.code == normalized) {
      return template;
    }
  }
  return null;
}
