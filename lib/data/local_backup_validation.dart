import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_backup_cadastro_produtos_service.dart';
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

  /// Formata bytes em B / KB / MB / GB (ex.: 4532 KB → "4.4 MB").
  static String formatarTamanhoBytes(int bytes) {
    var b = bytes;
    if (b < 0) b = 0;
    const kb = 1024.0;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (b >= gb) {
      return '${(b / gb).toStringAsFixed(2)} GB';
    }
    if (b >= mb) {
      return '${(b / mb).toStringAsFixed(1)} MB';
    }
    if (b >= kb) {
      return '${(b / kb).toStringAsFixed(1)} KB';
    }
    return '$b B';
  }

  /// [tamanhoKb] como no manifesto/historico (pode ser fracionario).
  static String formatarTamanhoKb(num tamanhoKb) {
    if (tamanhoKb <= 0) return '—';
    return formatarTamanhoBytes((tamanhoKb * 1024).round());
  }

  static String descreverTamanhoBanco(Directory dadosAplicacao) {
    final mdb = localizarDataMdb(dadosAplicacao);
    if (mdb == null) return 'banco nao encontrado';
    return formatarTamanhoBytes(mdb.lengthSync());
  }

  static void validarCadastroProdutos(Directory pastaBackup) {
    final jsonFile = _arquivoJsonCadastroFlexivel(pastaBackup);
    if (jsonFile == null || !jsonFile.existsSync()) {
      throw LocalBackupInvalidoException(
        'Backup de cadastro de produtos invalido: '
        'arquivo ${LocalBackupCadastroProdutosService.arquivoProdutos} ausente.',
      );
    }
    if (jsonFile.lengthSync() < 4) {
      throw LocalBackupInvalidoException(
        'Arquivo de produtos do backup esta vazio ou corrompido.',
      );
    }
  }

  /// Aceita pasta raiz do backup ou a subpasta `cadastro_produtos`.
  static File? _arquivoJsonCadastroFlexivel(Directory pastaBackup) {
    final aninhado =
        LocalBackupCadastroProdutosService.arquivoJsonNoBackup(pastaBackup);
    if (aninhado.existsSync()) return aninhado;
    final direto = File(
      p.join(
        pastaBackup.path,
        LocalBackupCadastroProdutosService.arquivoProdutos,
      ),
    );
    if (direto.existsSync()) return direto;
    return null;
  }

  static int? contarProdutosCadastroBackup(Directory pastaBackup) {
    try {
      final jsonFile = _arquivoJsonCadastroFlexivel(pastaBackup);
      if (jsonFile == null || !jsonFile.existsSync()) return null;
      final map = jsonDecode(jsonFile.readAsStringSync()) as Map;
      final q = map['quantidade'];
      if (q is num) return q.toInt();
      final lista = map['produtos'];
      if (lista is List) return lista.length;
    } catch (_) {}
    return null;
  }
}

class LocalBackupInvalidoException implements Exception {
  LocalBackupInvalidoException(this.message);
  final String message;
  @override
  String toString() => message;
}
