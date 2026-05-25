import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/repository_operational_policy.dart';

void main() {
  test('telas operacionais nao usam listarTodas/listarTodos sem policy-allow', () {
    final raiz = Directory.current;
    final violacoes = <String>[];

    for (final caminhoRel in operationalUiPaths) {
      final alvo = File('${raiz.path}/$caminhoRel');
      if (alvo.existsSync()) {
        _verificarArquivo(alvo, violacoes);
        continue;
      }
      final dir = Directory('${raiz.path}/$caminhoRel');
      if (!dir.existsSync()) continue;
      for (final ent in dir.listSync(recursive: true)) {
        if (ent is! File || !ent.path.endsWith('.dart')) continue;
        _verificarArquivo(ent, violacoes);
      }
    }

    expect(
      violacoes,
      isEmpty,
      reason: violacoes.join('\n'),
    );
  });
}

void _verificarArquivo(File arquivo, List<String> violacoes) {
  final linhas = arquivo.readAsLinesSync();
  for (var i = 0; i < linhas.length; i++) {
    final linha = linhas[i];
    if (linha.contains('policy-allow:')) continue;
    for (final padrao in operationalForbiddenPatterns) {
      if (linha.contains(padrao)) {
        violacoes.add('${arquivo.path}:${i + 1}: $linha');
      }
    }
  }
}
