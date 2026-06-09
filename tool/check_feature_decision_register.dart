import 'dart:io';

void main() {
  final featuresDir = Directory('lib/features');
  final registerFile = File('docs/app_feature_decision_register.md');

  if (!featuresDir.existsSync()) {
    stderr.writeln('Missing lib/features directory.');
    exit(1);
  }
  if (!registerFile.existsSync()) {
    stderr.writeln('Missing docs/app_feature_decision_register.md.');
    exit(1);
  }

  final featureModules = featuresDir
      .listSync()
      .whereType<Directory>()
      .map((dir) => _basename(dir.path))
      .toList()
    ..sort();

  final registerText = registerFile.readAsStringSync();
  final moduleRegex = RegExp(r'^### Module: ([a-zA-Z0-9_-]+)\s*$', multiLine: true);
  final registeredModules = moduleRegex
      .allMatches(registerText)
      .map((m) => m.group(1)!)
      .toSet();

  final missing = featureModules
      .where((module) => !registeredModules.contains(module))
      .toList();
  final orphaned = registeredModules
      .where((module) => !featureModules.contains(module))
      .toList()
    ..sort();

  if (missing.isNotEmpty || orphaned.isNotEmpty) {
    stderr.writeln('Feature decision register coverage check failed.');
    if (missing.isNotEmpty) {
      stderr.writeln('Missing modules in register: ${missing.join(', ')}');
    }
    if (orphaned.isNotEmpty) {
      stderr.writeln('Orphaned modules in register: ${orphaned.join(', ')}');
    }
    exit(1);
  }

  stdout.writeln(
    'Feature decision register is in sync with lib/features (${featureModules.length} modules).',
  );
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
