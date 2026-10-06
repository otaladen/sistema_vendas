import 'dart:io';
import 'dart:math' as math;

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

/// Locks, temporarios e journals — nunca entram no backup.
bool arquivoIgnoradoNoBackupLocal(String nome) {
  final n = nome.toLowerCase();
  if (n.endsWith('-lock') || n.endsWith('.lock')) return true;
  if (n.endsWith('.tmp') || n.endsWith('.temp')) return true;
  if (n.endsWith('.log')) return true;
  if (n == 'lock.mdb' || n.startsWith('data.mdb-lock')) return true;
  return false;
}

bool _nomeIgnoradoNaCopia(String nome, Set<String> extras) {
  final n = nome.toLowerCase();
  return nomesIgnoradosNoBackupLocal.contains(n) || extras.contains(n);
}

bool _entidadeIgnoradaNaCopia(String nome, Set<String> extras) {
  return _nomeIgnoradoNaCopia(nome, extras) ||
      arquivoIgnoradoNoBackupLocal(nome);
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
    if (!await _entidadeAindaExiste(entidade)) continue;
    final nome = p.basename(entidade.path);
    if (_entidadeIgnoradaNaCopia(nome, ignorarNomes)) continue;
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

Future<int> contarBytesArquivosRecursivo(
  Directory origem, {
  Set<String> ignorarNomes = const {},
}) async {
  if (!origem.existsSync()) return 0;
  var total = 0;
  await for (final entidade in origem.list(recursive: false)) {
    if (!await _entidadeAindaExiste(entidade)) continue;
    final nome = p.basename(entidade.path);
    if (_entidadeIgnoradaNaCopia(nome, ignorarNomes)) continue;
    if (entidade is File) {
      total += await _tamanhoArquivo(entidade);
    } else if (entidade is Directory) {
      total += await contarBytesArquivosRecursivo(
        entidade,
        ignorarNomes: ignorarNomes,
      );
    }
  }
  return total;
}

/// Diario leve: copia apenas [data.mdb] (sem locks/temporarios).
Future<void> copiarObjectBoxSomenteBanco({
  required Directory origem,
  required Directory destino,
  void Function(int bytesCopiados, int bytesTotal)? onProgressoBytes,
}) async {
  if (!origem.existsSync()) {
    throw Exception('Pasta objectbox nao encontrada.');
  }
  final mdb = File(p.join(origem.path, 'data.mdb'));
  if (!mdb.existsSync()) {
    throw Exception('data.mdb nao encontrado na pasta objectbox.');
  }
  destino.createSync(recursive: true);
  final destinoMdb = File(p.join(destino.path, 'data.mdb'));
  await copiarArquivoComProgressoBytes(
    origem: mdb,
    destino: destinoMdb,
    onProgressoBytes: onProgressoBytes,
  );
}

Future<bool> _entidadeAindaExiste(FileSystemEntity entidade) async {
  try {
    return await entidade.exists();
  } catch (_) {
    return false;
  }
}

Future<void> _criarPastaPaiArquivoDestino(File destino) async {
  await destino.parent.create(recursive: true);
}

Future<void> copiarArquivoComProgressoBytes({
  required File origem,
  required File destino,
  void Function(int bytesCopiados, int bytesTotal)? onProgressoBytes,
}) async {
  if (!await _entidadeAindaExiste(origem)) return;
  await _criarPastaPaiArquivoDestino(destino);
  final total = await origem.length();
  if (total <= 0) {
    await origem.copy(destino.path);
    onProgressoBytes?.call(0, 0);
    return;
  }
  const chunkBytes = 512 * 1024;
  final leitura = await origem.open();
  final escrita = await destino.open(mode: FileMode.write);
  try {
    var copiados = 0;
    while (copiados < total) {
      final ler = math.min(chunkBytes, total - copiados);
      final buffer = await leitura.read(ler);
      if (buffer.isEmpty) break;
      await escrita.writeFrom(buffer);
      copiados += buffer.length;
      onProgressoBytes?.call(copiados, total);
    }
  } finally {
    await leitura.close();
    await escrita.close();
  }
}

Future<int> tamanhoDiretorioBytes(Directory origem) async {
  if (!origem.existsSync()) return 0;
  var total = 0;
  await for (final entidade in origem.list(recursive: true, followLinks: false)) {
    if (entidade is! File) continue;
    final nome = p.basename(entidade.path);
    if (arquivoIgnoradoNoBackupLocal(nome)) continue;
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
  void Function(int bytesCopiados, int bytesTotal)? onProgressoBytes,
  int bytesCopiadosAcumulado = 0,
  int? bytesTotalPrevisto,
  Set<String> ignorarNomes = const {},
}) async {
  if (!origem.existsSync()) return;
  destino.createSync(recursive: true);
  var copiados = bytesCopiadosAcumulado;
  final totalPrevisto = bytesTotalPrevisto;
  await for (final entidade in origem.list(recursive: false)) {
    if (!await _entidadeAindaExiste(entidade)) continue;
    final nome = p.basename(entidade.path);
    if (_entidadeIgnoradaNaCopia(nome, ignorarNomes)) continue;
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      copiados = await _copiarSubdiretorioComProgresso(
        origem: entidade,
        destino: Directory(destinoPath),
        ignorarNomes: ignorarNomes,
        onArquivoCopiado: onArquivoCopiado,
        onProgressoBytes: onProgressoBytes,
        bytesCopiadosAcumulado: copiados,
        bytesTotalPrevisto: totalPrevisto,
      );
    } else if (entidade is File) {
      copiados = await _copiarArquivoEntrada(
        origem: entidade,
        destinoPath: destinoPath,
        copiadosAcumulado: copiados,
        totalPrevisto: totalPrevisto,
        onArquivoCopiado: onArquivoCopiado,
        onProgressoBytes: onProgressoBytes,
      );
    }
  }
}

Future<int> _copiarArquivoEntrada({
  required File origem,
  required String destinoPath,
  required int copiadosAcumulado,
  required int? totalPrevisto,
  void Function()? onArquivoCopiado,
  void Function(int bytesCopiados, int bytesTotal)? onProgressoBytes,
}) async {
  if (!await _entidadeAindaExiste(origem)) return copiadosAcumulado;
  var copiados = copiadosAcumulado;
  final tamanho = await _tamanhoArquivo(origem);
  try {
    if (onProgressoBytes != null && totalPrevisto != null && totalPrevisto > 0) {
      await copiarArquivoComProgressoBytes(
        origem: origem,
        destino: File(destinoPath),
        onProgressoBytes: (parcial, _) {
          onProgressoBytes(copiados + parcial, totalPrevisto);
        },
      );
      copiados += tamanho;
      onProgressoBytes(copiados, totalPrevisto);
    } else {
      await _criarPastaPaiArquivoDestino(File(destinoPath));
      await origem.copy(destinoPath);
      copiados += tamanho;
      if (onProgressoBytes != null && totalPrevisto != null && totalPrevisto > 0) {
        onProgressoBytes(copiados, totalPrevisto);
      }
    }
    onArquivoCopiado?.call();
  } on FileSystemException catch (e) {
    if (e is PathNotFoundException || !await _entidadeAindaExiste(origem)) {
      return copiadosAcumulado;
    }
    rethrow;
  }
  return copiados;
}

Future<int> _copiarSubdiretorioComProgresso({
  required Directory origem,
  required Directory destino,
  required Set<String> ignorarNomes,
  void Function()? onArquivoCopiado,
  void Function(int bytesCopiados, int bytesTotal)? onProgressoBytes,
  required int bytesCopiadosAcumulado,
  required int? bytesTotalPrevisto,
}) async {
  if (!await _entidadeAindaExiste(origem)) return bytesCopiadosAcumulado;
  destino.createSync(recursive: true);
  var copiados = bytesCopiadosAcumulado;
  await for (final entidade in origem.list(recursive: false)) {
    if (!await _entidadeAindaExiste(entidade)) continue;
    final nome = p.basename(entidade.path);
    if (_entidadeIgnoradaNaCopia(nome, ignorarNomes)) continue;
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      copiados = await _copiarSubdiretorioComProgresso(
        origem: entidade,
        destino: Directory(destinoPath),
        ignorarNomes: ignorarNomes,
        onArquivoCopiado: onArquivoCopiado,
        onProgressoBytes: onProgressoBytes,
        bytesCopiadosAcumulado: copiados,
        bytesTotalPrevisto: bytesTotalPrevisto,
      );
    } else if (entidade is File) {
      copiados = await _copiarArquivoEntrada(
        origem: entidade,
        destinoPath: destinoPath,
        copiadosAcumulado: copiados,
        totalPrevisto: bytesTotalPrevisto,
        onArquivoCopiado: onArquivoCopiado,
        onProgressoBytes: onProgressoBytes,
      );
    }
  }
  return copiados;
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
