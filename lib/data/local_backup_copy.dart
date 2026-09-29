import 'dart:io';

import 'package:path/path.dart' as p;

/// Fotos de catalogo, funcionario e prova de entrega.
/// Entram so no backup completo; o diario leve e o "sem fotos" pulam estas pastas.
const nomesPastasImagemNoBackup = {
  'product_images',
  'funcionario_images',
  'pod_entrega',
};

/// Caches reproduziveis. Nao entram em nenhum backup.
const nomesCachesForaDoBackup = {
  'pod_entrega_cache',
  'product_images_cache',
};

/// Pastas que a copia ignora. Logs tambem ficam na restauracao.
const nomesIgnoradosNoBackupLocal = {
  'logs',
  ...nomesCachesForaDoBackup,
};

bool nomeIgnoradoNoBackupLocal(String nome) {
  return nomesIgnoradosNoBackupLocal.contains(nome.toLowerCase());
}

bool _nomeIgnoradoNaCopia(String nome, Set<String> extras) {
  final n = nome.toLowerCase();
  return nomesIgnoradosNoBackupLocal.contains(n) || extras.contains(n);
}

/// Na restauracao so logs (e pastas extras, ex.: fotos num backup sem imagens)
/// sao preservados. Caches sao recriados pelo app.
bool nomePreservadoNaRestauracao(String nome, [Set<String> extras = const {}]) {
  final n = nome.toLowerCase();
  return n == 'logs' || extras.contains(n);
}

bool arquivoAindaEmUso(FileSystemException e) {
  final code = e.osError?.errorCode;
  return e is PathAccessException || code == 32 || code == 33 || code == 5;
}

Future<int> contarArquivosRecursivo(
  Directory origem, {
  Set<String> ignorarNomes = const {},
}) async {
  if (!origem.existsSync()) return 0;
  var n = 0;
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    if (_nomeIgnoradoNaCopia(nome, ignorarNomes)) continue;
    if (entidade is File) {
      n++;
    } else if (entidade is Directory) {
      n += await contarArquivosRecursivo(
        entidade,
        ignorarNomes: ignorarNomes,
      );
    }
  }
  return n;
}

Future<int> tamanhoDiretorioBytes(Directory origem) async {
  if (!origem.existsSync()) return 0;
  var total = 0;
  await for (final entidade in origem.list(recursive: true, followLinks: false)) {
    if (entidade is! File) continue;
    try {
      total += await entidade.length();
    } catch (_) {}
  }
  return total;
}

/// Banco, fotos e caches na pasta de dados do app (para o painel de backup).
class ResumoTamanhoDadosLocais {
  const ResumoTamanhoDadosLocais({
    required this.bancoBytes,
    required this.fotosBytes,
    required this.cacheBytes,
    required this.totalBytes,
  });

  final int bancoBytes;
  final int fotosBytes;
  final int cacheBytes;
  final int totalBytes;
}

Future<ResumoTamanhoDadosLocais> medirTamanhoDadosLocais(Directory base) async {
  if (!base.existsSync()) {
    return const ResumoTamanhoDadosLocais(
      bancoBytes: 0,
      fotosBytes: 0,
      cacheBytes: 0,
      totalBytes: 0,
    );
  }
  var banco = 0;
  var fotos = 0;
  var cache = 0;
  var outros = 0;
  await for (final entidade in base.list(followLinks: false)) {
    final nome = p.basename(entidade.path).toLowerCase();
    if (nome == 'logs') continue;
    final bytes = entidade is File
        ? await _tamanhoArquivo(entidade)
        : entidade is Directory
            ? await tamanhoDiretorioBytes(entidade)
            : 0;
    if (nome == 'objectbox') {
      banco += bytes;
    } else if (nomesPastasImagemNoBackup.contains(nome)) {
      fotos += bytes;
    } else if (nomesCachesForaDoBackup.contains(nome)) {
      cache += bytes;
    } else {
      outros += bytes;
    }
  }
  return ResumoTamanhoDadosLocais(
    bancoBytes: banco,
    fotosBytes: fotos,
    cacheBytes: cache,
    totalBytes: banco + fotos + cache + outros,
  );
}

Future<int> _tamanhoArquivo(File arquivo) async {
  try {
    return await arquivo.length();
  } catch (_) {
    return 0;
  }
}

Future<void> copiarDiretorioRecursivo({
  required Directory origem,
  required Directory destino,
  void Function()? onArquivoCopiado,
  Set<String> ignorarNomes = const {},
}) async {
  if (!origem.existsSync()) return;
  destino.createSync(recursive: true);
  var n = 0;
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    if (_nomeIgnoradoNaCopia(nome, ignorarNomes)) continue;
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      await copiarDiretorioRecursivo(
        origem: entidade,
        destino: Directory(destinoPath),
        onArquivoCopiado: onArquivoCopiado,
        ignorarNomes: ignorarNomes,
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

/// Remove o conteudo de [diretorio], preservando logs e [preservarNomes].
Future<void> limparDiretorioDestinoRestauracao(
  Directory diretorio, {
  Set<String> preservarNomes = const {},
}) async {
  if (!diretorio.existsSync()) {
    diretorio.createSync(recursive: true);
    return;
  }
  // Windows pode manter handle de data.mdb por alguns ms apos fechar o banco.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await for (final entidade in diretorio.list(recursive: false)) {
    if (nomePreservadoNaRestauracao(
      p.basename(entidade.path),
      preservarNomes,
    )) {
      continue;
    }
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
