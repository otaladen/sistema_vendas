import 'dart:io';

import 'package:path/path.dart' as p;

/// Validacao e resolucao de caminhos para backup/restauracao local (Windows/Android).
class LocalBackupValidation {
  LocalBackupValidation._();

  static const int _tamanhoMinimoDataMdbBytes = 4096;

  /// Localiza `data.mdb` em `dados_aplicacao` ou em `dados_aplicacao/objectbox`.
  static File? localizarDataMdb(Directory dadosAplicacao) {
    final direto = File(p.join(dadosAplicacao.path, 'data.mdb'));
    if (direto.existsSync()) return direto;
    final aninhado = File(p.join(dadosAplicacao.path, 'objectbox', 'data.mdb'));
    if (aninhado.existsSync()) return aninhado;
    return null;
  }

  static bool ehPastaObjectBox(Directory dir) {
    return File(p.join(dir.path, 'data.mdb')).existsSync();
  }

  /// Resolve a pasta selecionada pelo usuario para o nivel `dados_aplicacao`.
  static Directory resolverPastaDadosBackup(Directory pastaSelecionada) {
    final filho = Directory(p.join(pastaSelecionada.path, 'dados_aplicacao'));
    if (filho.existsSync()) {
      return filho;
    }
    if (ehPastaObjectBox(pastaSelecionada)) {
      return pastaSelecionada;
    }
    if (Directory(p.join(pastaSelecionada.path, 'objectbox')).existsSync()) {
      return pastaSelecionada;
    }
    throw LocalBackupInvalidoException(
      'Pasta de backup invalida. Selecione a pasta backup_sistema_vendas_* '
      'ou a subpasta dados_aplicacao (deve conter objectbox/data.mdb).',
    );
  }

  /// Garante que o backup/restauracao tem banco ObjectBox utilizavel.
  static void validarDadosAplicacao(Directory dadosAplicacao) {
    final mdb = localizarDataMdb(dadosAplicacao);
    if (mdb == null) {
      throw LocalBackupInvalidoException(
        'Nao foi encontrado objectbox/data.mdb neste backup. '
        'Refaca o backup com o programa fechado ou use "Criar backup agora" '
        'na maquina de origem (versao atualizada).',
      );
    }
    final bytes = mdb.lengthSync();
    if (bytes < _tamanhoMinimoDataMdbBytes) {
      throw LocalBackupInvalidoException(
        'O arquivo data.mdb do backup esta vazio ou corrompido ($bytes bytes). '
        'Feche o sistema na maquina de origem, crie um novo backup e tente de novo.',
      );
    }
  }

  static String descreverTamanhoBanco(Directory dadosAplicacao) {
    final mdb = localizarDataMdb(dadosAplicacao);
    if (mdb == null) return 'banco nao encontrado';
    final kb = (mdb.lengthSync() / 1024).toStringAsFixed(1);
    return '$kb KB';
  }
}

class LocalBackupInvalidoException implements Exception {
  LocalBackupInvalidoException(this.message);
  final String message;
  @override
  String toString() => message;
}
