import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This product speaks European Portuguese to merchants in Mozambique. Brazilian
/// variants kept arriving one string at a time — "Informe o bairro", "Nenhum
/// item cadastrado", "Sem conexão" — and each one reads as a different product
/// speaking, which is exactly the "línguas misturadas" complaint this guard
/// exists to answer.
///
/// Scans string literals only, so prose in comments and identifiers are left
/// alone. Add to [_allowed] when a word is genuinely not user-facing copy.
void main() {
  /// Brazilian spellings, with the European form the product uses instead.
  const banned = <String, String>{
    'informe': 'indique',
    'cadastro': 'registo',
    'cadastrar': 'registar',
    'cadastrado': 'registado',
    'cadastrada': 'registada',
    'usuário': 'utilizador',
    'usuario': 'utilizador',
    'salvar': 'guardar',
    'salvo': 'guardado',
    'salva': 'guardada',
    'arquivo': 'ficheiro',
    'deletar': 'eliminar',
    'conexão': 'ligação',
    'aplicativo': 'aplicação',
    'gerenciar': 'gerir',
    // "time" (pt-BR for team) is deliberately absent: it is also an ordinary
    // Dart identifier, and it appears inside interpolations far more often
    // than it would ever appear as copy.
  };

  /// Occurrences that are not copy shown to a merchant.
  const allowed = <String, Set<String>>{
    // Keywords used to classify a business from the name the merchant typed;
    // a Mozambican shop may well call itself "celular", so the matcher has to
    // know the Brazilian word even though we never print it.
    'lib/features/business_profile/domain/business_profile.dart': {'celular'},
  };

  /// Interpolated expressions are code, not copy: `'${pad(time.hour)}'` must
  /// not be read as the Brazilian word for team.
  String copyOnly(String literal) => literal
      .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ' ');

  test('user-facing copy stays in European Portuguese', () {
    final offenders = <String>[];
    final literal = RegExp(r"'([^'\\\n]|\\.)*'");

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      // Generated code is not hand-written copy.
      if (file.path.contains('.g.dart') || file.path.contains('.freezed.dart')) {
        continue;
      }
      final relative = file.path.replaceAll(r'\', '/');
      final exempt = allowed[relative] ?? const <String>{};
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        for (final match in literal.allMatches(lines[i])) {
          final text = copyOnly(match.group(0)!).toLowerCase();
          for (final entry in banned.entries) {
            if (exempt.contains(entry.key)) continue;
            if (RegExp('\\b${entry.key}\\b').hasMatch(text)) {
              offenders.add(
                '$relative:${i + 1}  "${entry.key}" — use "${entry.value}"',
              );
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Brazilian Portuguese in user-facing copy:\n'
          '${offenders.join('\n')}',
    );
  });
}
