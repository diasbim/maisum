import 'dart:convert';
import 'dart:io';

/// Cross-checks the declared public plan catalog (docs/plans.json) against the
/// landing page cards (docs/index.html) and the provisioned entitlements
/// (functions/sql/seed_plans.sql, functions/sql/seed_plan_features.sql).
///
/// Divergences that are already acknowledged in the `openDecisions` block are
/// reported as warnings. Anything else fails the check.
///
/// Context: docs/landing_page_recommendations.md
void main() {
  final plansFile = File('docs/plans.json');
  final landingFile = File('docs/index.html');
  final seedPlansFile = File('functions/sql/seed_plans.sql');
  final seedFeaturesFile = File('functions/sql/seed_plan_features.sql');

  for (final file in [plansFile, landingFile, seedPlansFile, seedFeaturesFile]) {
    if (!file.existsSync()) {
      stderr.writeln('Missing ${file.path}.');
      exit(1);
    }
  }

  final catalog =
      jsonDecode(plansFile.readAsStringSync()) as Map<String, dynamic>;
  final plans = (catalog['plans'] as List).cast<Map<String, dynamic>>();
  final acknowledged = {
    for (final decision in (catalog['openDecisions'] as List))
      (decision as Map<String, dynamic>)['id'] as String: decision,
  };

  final seededPlans = _seededPlanCodes(seedPlansFile.readAsStringSync());
  final entitlements = _entitlements(seedFeaturesFile.readAsStringSync());
  final advertisedCards = _landingPlanCards(landingFile.readAsStringSync());

  final errors = <String>[];
  final warnings = <String>[];

  void report(String message, String? decisionId) {
    if (decisionId == null) {
      errors.add(message);
      return;
    }
    if (!acknowledged.containsKey(decisionId)) {
      errors.add('$message (refers to unknown decision $decisionId)');
      return;
    }
    warnings.add('[$decisionId] $message');
  }

  final declaredCodes = <String>{};

  for (final plan in plans) {
    final code = plan['code'] as String;
    final publicName = plan['publicName'] as String;
    final advertised = plan['advertised'] as bool;
    declaredCodes.add(code);

    if (!seededPlans.contains(code)) {
      report('Plan "$code" is declared in plans.json but absent from '
          'seed_plans.sql.', plan['decision'] as String?);
    }

    if (advertised && !advertisedCards.contains(publicName)) {
      errors.add('Plan "$publicName" is marked advertised but has no card in '
          'docs/index.html.');
    }
    if (!advertised && advertisedCards.contains(publicName)) {
      errors.add('Plan "$publicName" has a card in docs/index.html but is '
          'marked advertised:false in plans.json.');
    }

    for (final raw in (plan['promises'] as List)) {
      final promise = raw as Map<String, dynamic>;
      final text = promise['text'] as String;
      final backing = promise['backing'] as String;
      final decision = promise['decision'] as String?;

      switch (backing) {
        case 'core':
        case 'inherits':
          break;
        case 'none':
          report('Plan "$code" promises "$text" with no technical backing.',
              decision);
        case 'feature_key':
          final key = promise['featureKey'] as String?;
          if (key == null) {
            errors.add('Plan "$code" promise "$text" declares backing '
                'feature_key without a featureKey.');
            break;
          }
          final enabled = entitlements['$code:$key'];
          if (enabled == null) {
            report('Plan "$code" promises "$text" via feature key "$key", '
                'which is not provisioned for this plan in '
                'seed_plan_features.sql.', decision);
          } else if (!enabled) {
            report('Plan "$code" promises "$text" via feature key "$key", '
                'which is provisioned as disabled.', decision);
          }
        default:
          errors.add('Plan "$code" promise "$text" has unknown backing '
              '"$backing".');
      }
    }
  }

  for (final code in seededPlans) {
    if (!declaredCodes.contains(code)) {
      errors.add('Plan "$code" exists in seed_plans.sql but is not declared in '
          'docs/plans.json.');
    }
  }

  for (final name in advertisedCards) {
    final declared = plans.any((plan) => plan['publicName'] == name);
    if (!declared) {
      errors.add('Landing page shows a plan card "$name" that is not declared '
          'in docs/plans.json.');
    }
  }

  // Inverse direction: entitlements provisioned as enabled that no public
  // promise refers to. Informational — capability granted without being
  // advertised is not necessarily wrong, but it should be deliberate.
  final byCode = {for (final plan in plans) plan['code'] as String: plan};
  final advertisedCodes = plans
      .where((plan) => plan['advertised'] as bool)
      .map((plan) => plan['code'] as String)
      .toSet();

  final unadvertised = <String>[];
  for (final code in advertisedCodes) {
    final promised = _promisedKeys(code, byCode, <String>{});
    for (final entry in entitlements.entries) {
      if (!entry.value) continue;
      final parts = entry.key.split(':');
      if (parts[0] != code) continue;
      if (promised.contains(parts[1])) continue;
      unadvertised.add(entry.key);
    }
  }
  unadvertised.sort();

  if (unadvertised.isNotEmpty) {
    stdout.writeln('Provisioned but not advertised (informational):');
    for (final entry in unadvertised) {
      final parts = entry.split(':');
      stdout.writeln('  - plan "${parts[0]}" has "${parts[1]}" enabled, '
          'with no matching public promise.');
    }
    stdout.writeln('');
  }

  if (warnings.isNotEmpty) {
    stdout.writeln('Known divergences pending a product decision:');
    for (final warning in warnings) {
      stdout.writeln('  - $warning');
    }
    stdout.writeln('See docs/landing_page_recommendations.md.');
    stdout.writeln('');
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Plan catalog check failed.');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exit(1);
  }

  stdout.writeln('Plan catalog check passed '
      '(${plans.length} plans, ${warnings.length} acknowledged divergences).');
}

/// Feature keys a plan promises, following `inherits` promises transitively.
Set<String> _promisedKeys(
  String code,
  Map<String, Map<String, dynamic>> byCode,
  Set<String> seen,
) {
  if (!seen.add(code)) return <String>{};
  final plan = byCode[code];
  if (plan == null) return <String>{};

  final keys = <String>{};
  for (final raw in (plan['promises'] as List)) {
    final promise = raw as Map<String, dynamic>;
    final key = promise['featureKey'] as String?;
    if (key != null) keys.add(key);
    final parent = promise['inheritsFrom'] as String?;
    if (parent != null) keys.addAll(_promisedKeys(parent, byCode, seen));
  }
  return keys;
}

Set<String> _seededPlanCodes(String sql) {
  // Matches the plan-name tuples, e.g. ('free', 1, 'Free').
  // Price tuples have four elements and do not match.
  final regex = RegExp(r"\(\s*'([a-z_]+)'\s*,\s*\d+\s*,\s*'[^']+'\s*\)");
  return regex.allMatches(sql).map((m) => m.group(1)!).toSet();
}

Map<String, bool> _entitlements(String sql) {
  // Matches ('free', 1, 'whatsapp_automation', true).
  final regex =
      RegExp(r"\(\s*'([a-z_]+)'\s*,\s*\d+\s*,\s*'([a-z_]+)'\s*,\s*(true|false)\s*\)");
  return {
    for (final match in regex.allMatches(sql))
      '${match.group(1)}:${match.group(2)}': match.group(3) == 'true',
  };
}

Set<String> _landingPlanCards(String html) {
  final regex = RegExp(r'<div class="plan-label"><h3>([^<]+)</h3>');
  return regex.allMatches(html).map((m) => m.group(1)!.trim()).toSet();
}
