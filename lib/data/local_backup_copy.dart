import 'dart:io';

import 'package:path/path.dart' as p;

/// Pastas de runtime que o app mantem abertas (ex.: log em disco).
/// Nao entram no backup e nao devem ser apagadas na restauracao.
const nomesIgnoradosNoBackupLocal = {'logs'};

bool nomeIgnoradoNoBackupLocal(String nome) {
  return nomesIgnoradosNoBackupLocal.contains(nome.toLowerCase());
}

bool arquivoAindaEmUso(FileSystemException e) {
  final code = e.osError?.errorCode;
  return e is PathAccessException || code == 32 || code == 33 || code == 5;
}

Future<int> contarArquivosRecursivo(Directory origem) async {
  if (!origem.existsSync()) return 0;
  var n = 0;
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    if (nomeIgnoradoNoBackupLocal(nome)) continue;
    if (entidade is File) {
      n++;
    } else if (entidade is Directory) {
      n += await contarArquivosRecursivo(entidade);
    }
  }
  return n;
}

Future<void> copiarDiretorioRecursivo({
  required Directory origem,
  required Directory destino,
  void Function()? onArquivoCopiado,
}) async {
  if (!origem.existsSync()) return;
  destino.createSync(recursive: true);
  var n = 0;
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    if (nomeIgnoradoNoBackupLocal(nome)) continue;
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      await copiarDiretorioRecursivo(
        origem: entidade,
        destino: Directory(destinoPath),
        onArquivoCopiado: onArquivoCopiado,
      );
    } else if (entidade is File) {
      await entidade.copy(destinoPath);
      onArquivoCopiado?.call();
      n++;
      // Libera o UI periodicamente em pastas grandes.
      if (n % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
}

/// Remove o conteudo de [diretorio], preservando pastas de runtime (logs).
Future<void> limparDiretorioDestinoRestauracao(Directory diretorio) async {
  if (!diretorio.existsSync()) {
    diretorio.createSync(recursive: true);
    return;
  }
  // Windows pode manter handle de data.mdb por alguns ms apos fechar o banco.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await for (final entidade in diretorio.list(recursive: false)) {
    if (nomeIgnoradoNoBackupLocal(p.basename(entidade.path))) continue;
    await excluirEntidadeComRetry(entidade);
  }
}

Future<void> excluirEntidadeComRetry(FileSystemEntity entidade) async {
  const tentativas = 6;
  for (var i = 0; i < tentativas; i++) {
    try {
      if (entidade is Directory) {
        await entidade.delete(recursive: true);
      } else {
        await entidade.delete();
      }
      return;
    } on FileSystemException catch (e) {
      if (!arquivoAindaEmUso(e)) rethrow;
      if (i == tentativas - 1) {
        final nome = p.basename(entidade.path);
        throw Exception(
          'Nao foi possivel substituir "$nome" porque o arquivo ainda '
          'esta em uso por outro processo. Feche outras copias do sistema '
          'e tente restaurar de novo.',
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 150 * (i + 1)));
    }
  }
}
