import 'dart:convert';
import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;

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
  });

  final int inseridos;
  final int atualizados;
  final int fotosRestauradas;

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

    report(0.25, 'Lendo produtos…');
    final produtos = objectBox.produtoBox.getAll();
    final linhas = <Map<String, dynamic>>[];
    var fotosCopiadas = 0;

    for (var i = 0; i < produtos.length; i++) {
      final produto = produtos[i];
      final map = SyncEntityCodec.produtoParaMap(produto);
      final fotoArquivo = await _copiarFotoParaBackup(
        produto: produto,
        imagesDir: objectBox.productImagesDir,
        fotosDir: fotosDir,
      );
      if (fotoArquivo != null) {
        map['fotoArquivoBackup'] = fotoArquivo;
        fotosCopiadas++;
      }
      linhas.add(map);
      if (produtos.isNotEmpty) {
        report(
          0.25 + (i + 1) / produtos.length * 0.55,
          'Exportando produtos… (${i + 1}/${produtos.length})',
        );
      }
    }

    report(0.85, 'Gravando arquivo…');
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
    void report(double v, String etapa) => onProgress?.call(v, etapa);

    final pasta = pastaNoBackup(pastaBackup);
    final jsonFile = File(p.join(pasta.path, arquivoProdutos));
    if (!jsonFile.existsSync()) {
      throw Exception('Arquivo $arquivoProdutos nao encontrado no backup.');
    }

    report(0.1, 'Lendo cadastro…');
    final payload = jsonDecode(jsonFile.readAsStringSync()) as Map;
    final listaRaw = payload['produtos'];
    if (listaRaw is! List) {
      throw Exception('Formato de backup de produtos invalido.');
    }

    final fotosDir = Directory(p.join(pasta.path, subpastaFotos));
    final porCodigo = <String, Produto>{};
    for (final p in objectBox.produtoBox.getAll()) {
      final cod = p.codigoInterno.trim().toLowerCase();
      if (cod.isNotEmpty) porCodigo[cod] = p;
    }

    var inseridos = 0;
    var atualizados = 0;
    var fotosRestauradas = 0;

    objectBox.store.runInTransaction(TxMode.write, () {
      for (var i = 0; i < listaRaw.length; i++) {
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
        if (fotoArquivo.isNotEmpty && fotosDir.existsSync()) {
          final origem = File(p.join(fotosDir.path, fotoArquivo));
          if (origem.existsSync()) {
            objectBox.productImagesDir.createSync(recursive: true);
            final destinoFoto = File(
              p.join(objectBox.productImagesDir.path, p.basename(fotoArquivo)),
            );
            origem.copySync(destinoFoto.path);
            importado.fotoPath = p.basename(destinoFoto.path);
            fotosRestauradas++;
          }
        } else if (existente != null && fotoArquivo.isEmpty) {
          importado.fotoPath = existente.fotoPath;
        }

        objectBox.produtoBox.put(importado);
        porCodigo[cod] = importado;

        report(
          0.15 + (i + 1) / listaRaw.length * 0.8,
          'Importando produtos… (${i + 1}/${listaRaw.length})',
        );
      }
    });

    report(1.0, 'Cadastro importado');
    return CadastroProdutosImportResumo(
      inseridos: inseridos,
      atualizados: atualizados,
      fotosRestauradas: fotosRestauradas,
    );
  }

  static Future<String?> _copiarFotoParaBackup({
    required Produto produto,
    required Directory imagesDir,
    required Directory fotosDir,
  }) async {
    final origem = _resolverArquivoFoto(produto, imagesDir);
    if (origem == null) return null;

    final codigoSeguro = produto.codigoInterno
        .trim()
        .replaceAll(RegExp(r'[^\w\-]+'), '_');
    final ext = p.extension(origem.path);
    final nome =
        '${codigoSeguro.isEmpty ? 'produto_${produto.id}' : codigoSeguro}$ext';
    final destino = File(p.join(fotosDir.path, nome));
    await origem.copy(destino.path);
    return nome;
  }

  static File? _resolverArquivoFoto(Produto produto, Directory imagesDir) {
    final fp = produto.fotoPath.trim();
    if (fp.isEmpty) return null;
    final direto = File(fp);
    if (direto.existsSync()) return direto;
    final relativo = File(p.join(imagesDir.path, p.basename(fp)));
    if (relativo.existsSync()) return relativo;
    return null;
  }
}
