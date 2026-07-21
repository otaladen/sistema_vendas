import 'dart:convert';
import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;

import '../domain/produto_imagem_nome_arquivo.dart';
import '../model/produto.dart';
import 'objectbox.dart';
import 'sync/sync_entity_codec.dart';

class CadastroProdutosBackupResumo {
  const CadastroProdutosBackupResumo({
    required this.quantidadeProdutos,
    required this.quantidadeFotos,
    required this.tamanhoTotalKb,
    required this.pasta,
  });

  final int quantidadeProdutos;
  final int quantidadeFotos;
  final double tamanhoTotalKb;
  final Directory pasta;
}

class CadastroProdutosImportResumo {
  const CadastroProdutosImportResumo({
    required this.inseridos,
    required this.atualizados,
    required this.fotosRestauradas,
    this.fotosFaltando = 0,
  });

  final int inseridos;
  final int atualizados;
  final int fotosRestauradas;

  /// Produtos que tinham foto no backup, mas o arquivo nao foi encontrado.
  final int fotosFaltando;

  int get total => inseridos + atualizados;
}

/// Exporta e importa somente o cadastro de produtos.
class LocalBackupCadastroProdutosService {
  LocalBackupCadastroProdutosService._();

  static const subpasta = 'cadastro_produtos';
  static const arquivoProdutos = 'produtos.json';
  static const subpastaFotos = 'fotos';
  static const _versao = 1;

  static Directory pastaNoBackup(Directory pastaBackup) =>
      Directory(p.join(pastaBackup.path, subpasta));

  static File arquivoJsonNoBackup(Directory pastaBackup) =>
      File(p.join(pastaNoBackup(pastaBackup).path, arquivoProdutos));

  static Future<CadastroProdutosBackupResumo> exportar({
    required ObjectBox objectBox,
    required Directory pastaBackup,
    void Function(double progresso, String etapa)? onProgress,
  }) async {
    void report(double v, String etapa) => onProgress?.call(v, etapa);

    final destino = pastaNoBackup(pastaBackup);
    destino.createSync(recursive: true);
    final fotosDir = Directory(p.join(destino.path, subpastaFotos));
    fotosDir.createSync(recursive: true);

    report(0.18, 'Lendo produtos do banco…');
    await Future<void>.delayed(Duration.zero);
    final produtos = objectBox.produtoBox.getAll();
    report(
      0.22,
      produtos.isEmpty
          ? 'Nenhum produto para exportar…'
          : 'Exportando ${produtos.length} produto(s)…',
    );
    await Future<void>.delayed(Duration.zero);
    final linhas = <Map<String, dynamic>>[];
    var fotosCopiadas = 0;
    final jaCopiados = <String>{};

    for (var i = 0; i < produtos.length; i++) {
      final produto = produtos[i];
      final map = SyncEntityCodec.produtoParaMap(produto);
      final fotoArquivo = await _copiarFotoParaBackup(
        produto: produto,
        imagesDir: objectBox.productImagesDir,
        fotosDir: fotosDir,
        jaCopiados: jaCopiados,
      );
      if (fotoArquivo != null) {
        map['fotoArquivoBackup'] = fotoArquivo;
        // Evita gravar caminho absoluto da maquina de origem no JSON.
        map['fotoPath'] = fotoArquivo;
        fotosCopiadas++;
      } else {
        map['fotoPath'] = '';
      }
      linhas.add(map);
      if (produtos.isNotEmpty) {
        final pct = (25 + (i + 1) / produtos.length * 55).round().clamp(25, 80);
        report(
          pct / 100.0,
          'Exportando produtos… $pct%  (${i + 1}/${produtos.length})',
        );
        if ((i + 1) % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    report(0.85, 'Gravando arquivo… 85%');
    final payload = {
      'versao': _versao,
      'exportadoEm': DateTime.now().toUtc().toIso8601String(),
      'quantidade': linhas.length,
      'produtos': linhas,
    };
    await File(p.join(destino.path, arquivoProdutos)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    var tamanhoBytes = 0;
    await for (final ent in destino.list(recursive: true)) {
      if (ent is File) tamanhoBytes += ent.lengthSync();
    }

    report(1.0, 'Cadastro exportado');
    return CadastroProdutosBackupResumo(
      quantidadeProdutos: linhas.length,
      quantidadeFotos: fotosCopiadas,
      tamanhoTotalKb: tamanhoBytes / 1024.0,
      pasta: destino,
    );
  }

  static Future<CadastroProdutosImportResumo> importar({
    required ObjectBox objectBox,
    required Directory pastaBackup,
    void Function(double progresso, String etapa)? onProgress,
  }) async {
    void report(double v, String etapa) => onProgress?.call(v.clamp(0, 1), etapa);

    final pasta = _resolverPastaCadastro(pastaBackup);
    final jsonFile = File(p.join(pasta.path, arquivoProdutos));
    if (!jsonFile.existsSync()) {
      throw Exception('Arquivo $arquivoProdutos nao encontrado no backup.');
    }

    report(0.02, 'Lendo cadastro… 2%');
    // Leitura em isolate-friendly async para nao congelar o primeiro frame.
    final rawText = await jsonFile.readAsString();
    final payload = jsonDecode(rawText) as Map;
    final listaRaw = payload['produtos'];
    if (listaRaw is! List) {
      throw Exception('Formato de backup de produtos invalido.');
    }
    final total = listaRaw.length;
    if (total == 0) {
      report(1.0, 'Nenhum produto no backup — 100%');
      return const CadastroProdutosImportResumo(
        inseridos: 0,
        atualizados: 0,
        fotosRestauradas: 0,
      );
    }

    report(0.06, 'Preparando index… 6%');
    final fotosDir = Directory(p.join(pasta.path, subpastaFotos));
    objectBox.productImagesDir.createSync(recursive: true);
    final imagesAbs = p.normalize(objectBox.productImagesDir.absolute.path);

    final porCodigo = <String, Produto>{};
    for (final pr in objectBox.produtoBox.getAll()) {
      final cod = pr.codigoInterno.trim().toLowerCase();
      if (cod.isNotEmpty) porCodigo[cod] = pr;
    }

    var inseridos = 0;
    var atualizados = 0;
    var fotosRestauradas = 0;
    var fotosFaltando = 0;

    // Lotes curtos + yield: libera o UI para atualizar a % (antes travava tudo).
    const tamanhoLote = 40;
    final pendentes = <Produto>[];

    void flushLote() {
      if (pendentes.isEmpty) return;
      objectBox.store.runInTransaction(TxMode.write, () {
        for (final pr in pendentes) {
          objectBox.produtoBox.put(pr);
        }
      });
      pendentes.clear();
    }

    for (var i = 0; i < total; i++) {
      final item = listaRaw[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final importado = SyncEntityCodec.produtoDeMap(map);
      final cod = importado.codigoInterno.trim().toLowerCase();
      if (cod.isEmpty) continue;

      final existente = porCodigo[cod];
      if (existente != null) {
        importado.id = existente.id;
        importado.estoqueReal = existente.estoqueReal;
        importado.estoqueReservado = existente.estoqueReservado;
        importado.estoqueAtual = existente.estoqueReal;
        importado.estoqueVersao = existente.estoqueVersao;
        atualizados++;
      } else {
        importado.id = 0;
        inseridos++;
      }

      final fotoArquivo = map['fotoArquivoBackup']?.toString().trim() ?? '';
      final fotoPathMap = map['fotoPath']?.toString().trim() ?? '';
      final nomeFotoBackup = fotoArquivo.isNotEmpty
          ? p.basename(fotoArquivo)
          : (ProdutoImagemNomeArquivo.nomeArquivoSeguro(fotoPathMap) ?? '');

      if (nomeFotoBackup.isNotEmpty) {
        final origem = File(p.join(fotosDir.path, nomeFotoBackup));
        if (origem.existsSync()) {
          final destinoFoto = File(p.join(imagesAbs, nomeFotoBackup));
          if (!destinoFoto.existsSync() ||
              destinoFoto.lengthSync() != origem.lengthSync()) {
            await origem.copy(destinoFoto.path);
          }
          importado.fotoPath = p.normalize(destinoFoto.absolute.path);
          fotosRestauradas++;
        } else {
          fotosFaltando++;
          if (existente != null &&
              _arquivoFotoExiste(existente.fotoPath, imagesAbs)) {
            importado.fotoPath = _resolverPathAbsoluto(
              existente.fotoPath,
              imagesAbs,
            )!;
          } else {
            importado.fotoPath = '';
          }
        }
      } else if (existente != null &&
          _arquivoFotoExiste(existente.fotoPath, imagesAbs)) {
        importado.fotoPath =
            _resolverPathAbsoluto(existente.fotoPath, imagesAbs)!;
      } else {
        importado.fotoPath = '';
      }

      pendentes.add(importado);
      porCodigo[cod] = importado;

      if (pendentes.length >= tamanhoLote) {
        flushLote();
      }

      final frac = (i + 1) / total;
      final pct = (6 + frac * 88).round().clamp(6, 94);
      report(
        pct / 100.0,
        'Importando produtos… $pct%  (${i + 1}/$total)',
      );

      // Cedem o event loop a cada item do lote para a barra/% atualizar.
      if ((i + 1) % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    flushLote();
    report(0.96, 'Ajustando caminhos de fotos… 96%');
    await Future<void>.delayed(Duration.zero);
    corrigirFotoPathsLocais(objectBox);
    report(1.0, 'Cadastro importado — 100%');

    return CadastroProdutosImportResumo(
      inseridos: inseridos,
      atualizados: atualizados,
      fotosRestauradas: fotosRestauradas,
      fotosFaltando: fotosFaltando,
    );
  }

  /// Corrige produtos com fotoPath relativo ou de outra maquina.
  static int corrigirFotoPathsLocais(ObjectBox objectBox) {
    final imagesAbs = p.normalize(objectBox.productImagesDir.absolute.path);
    var corrigidos = 0;
    objectBox.store.runInTransaction(TxMode.write, () {
      for (final pr in objectBox.produtoBox.getAll()) {
        final raw = pr.fotoPath.trim();
        if (raw.isEmpty) continue;
        final resolvido = _resolverPathAbsoluto(raw, imagesAbs);
        if (resolvido == null) {
          if (File(raw).existsSync()) continue;
          // Caminho morto (outra maquina) — limpa para nao mostrar "indisponivel".
          if (raw.contains(':') || raw.contains('/') || raw.contains(r'\')) {
            if (!File(raw).existsSync()) {
              pr.fotoPath = '';
              objectBox.produtoBox.put(pr);
              corrigidos++;
            }
          }
          continue;
        }
        if (resolvido != raw) {
          pr.fotoPath = resolvido;
          objectBox.produtoBox.put(pr);
          corrigidos++;
        }
      }
    });
    return corrigidos;
  }

  /// Aceita pasta do backup raiz ou a subpasta `cadastro_produtos`.
  static Directory _resolverPastaCadastro(Directory pastaBackup) {
    final direta = File(p.join(pastaBackup.path, arquivoProdutos));
    if (direta.existsSync()) return pastaBackup;
    final aninhada = pastaNoBackup(pastaBackup);
    if (File(p.join(aninhada.path, arquivoProdutos)).existsSync()) {
      return aninhada;
    }
    return pastaNoBackup(pastaBackup);
  }

  static bool _arquivoFotoExiste(String fotoPath, String imagesAbs) {
    return _resolverPathAbsoluto(fotoPath, imagesAbs) != null;
  }

  static String? _resolverPathAbsoluto(String fotoPath, String imagesAbs) {
    final raw = fotoPath.trim();
    if (raw.isEmpty) return null;
    final direto = File(p.normalize(raw));
    if (direto.existsSync()) return p.normalize(direto.absolute.path);
    final nome = ProdutoImagemNomeArquivo.nomeArquivoSeguro(raw);
    if (nome == null) return null;
    final rel = File(p.join(imagesAbs, nome));
    if (rel.existsSync()) return p.normalize(rel.absolute.path);
    return null;
  }

  static Future<String?> _copiarFotoParaBackup({
    required Produto produto,
    required Directory imagesDir,
    required Directory fotosDir,
    required Set<String> jaCopiados,
  }) async {
    final origem = _resolverArquivoFoto(produto, imagesDir);
    if (origem == null) return null;

    // Prefere o nome canonico shared_<hash>.jpg (rede/LAN); senao usa o basename.
    final baseOrigem = p.basename(origem.path);
    final codigoSeguro = produto.codigoInterno
        .trim()
        .replaceAll(RegExp(r'[^\w\-]+'), '_');
    final ext = p.extension(origem.path).isEmpty
        ? '.jpg'
        : p.extension(origem.path);
    final nome = ProdutoImagemNomeArquivo.valido(baseOrigem)
        ? baseOrigem
        : '${codigoSeguro.isEmpty ? 'produto_${produto.id}' : codigoSeguro}$ext';

    if (!jaCopiados.contains(nome)) {
      final destino = File(p.join(fotosDir.path, nome));
      await origem.copy(destino.path);
      jaCopiados.add(nome);
    }
    return nome;
  }

  static File? _resolverArquivoFoto(Produto produto, Directory imagesDir) {
    final fp = produto.fotoPath.trim();
    if (fp.isEmpty) return null;
    final direto = File(fp);
    if (direto.existsSync()) return direto;
    final nome = ProdutoImagemNomeArquivo.nomeArquivoSeguro(fp) ?? p.basename(fp);
    final relativo = File(p.join(imagesDir.path, nome));
    if (relativo.existsSync()) return relativo;
    return null;
  }
}
