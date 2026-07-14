import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../domain/importacao/produto_importacao_linha.dart';
import '../domain/importacao/produto_importacao_util.dart';
import 'chacal_json_export_import.dart';
import 'chacal_mysql_dump_import.dart';
import 'produto_busca_util.dart';

class ChacalBackupLeituraResumo {
  const ChacalBackupLeituraResumo({
    required this.linhas,
    required this.pulados,
  });

  final List<ProdutoImportacaoLinha> linhas;
  final int pulados;
}

/// Le produtos de um backup Chacal (.s3db, .sql MySQL ou .txt/.json).
class ChacalBackupImportService {
  ChacalBackupImportService._();

  static const _sqlProdutos = '''
SELECT
    p.ID_PRODUTO,
    COALESCE(NULLIF(TRIM(p.CODIGO_INTERNO), ''), '') AS codigo,
    TRIM(CAST(p.GTIN AS TEXT)) AS gtin,
    TRIM(p.NOME) AS nome,
    TRIM(COALESCE(p.NOME_PDV, '')) AS nome_pdv,
    TRIM(COALESCE(p.NCM, '')) AS ncm,
    COALESCE(p.PRECO1, 0) AS preco1,
    COALESCE(p.PRECO2, 0) AS preco2,
    COALESCE(p.PRECO3, 0) AS preco3,
    COALESCE(p.VALOR_COMPRA, p.VALOR_COMPRA_LIQUIDO, 0) AS precocusto,
    COALESCE(p.CUSTO_MEDIO_LIQUIDO, 0) AS customedio,
    COALESCE(p.ESTOQUE_MINIMO, 0) AS estminimo,
    COALESCE(p.INATIVO, 'N') AS inativo,
    TRIM(COALESCE(u.SIGLA, p.SIGLA, p.UNIDADE_COMPRA, 'UN')) AS unidade,
    TRIM(COALESCE(m.NOME, '')) AS marca,
    TRIM(COALESCE(f.NOME, '')) AS familia,
    TRIM(COALESCE(g.NOME, '')) AS grupo,
    TRIM(COALESCE(sg.NOME, '')) AS subgrupo,
    COALESCE(es.estoque, 0) AS estoque
FROM produto p
LEFT JOIN produto_unidade u ON u.ID_PRODUTO_UNIDADE = p.ID_PRODUTO_UNIDADE
LEFT JOIN produto_marca m ON m.ID_PRODUTO_MARCA = p.ID_PRODUTO_MARCA
LEFT JOIN produto_familia f ON f.ID_PRODUTO_FAMILIA = p.ID_PRODUTO_FAMILIA
LEFT JOIN produto_grupo g ON g.ID_PRODUTO_GRUPO = p.ID_PRODUTO_GRUPO
LEFT JOIN produto_sub_grupo sg ON sg.ID_PRODUTO_SUB_GRUPO = p.ID_PRODUTO_SUB_GRUPO
LEFT JOIN (
    SELECT ID_PRODUTO, SUM(COALESCE(SALDO, 0)) AS estoque
    FROM produto_estoque
    GROUP BY ID_PRODUTO
) es ON es.ID_PRODUTO = p.ID_PRODUTO
WHERE (? = 1 OR COALESCE(p.INATIVO, 'N') <> 'S')
ORDER BY p.ID_PRODUTO
''';

  static Future<ChacalBackupLeituraResumo> lerArquivo({
    required String caminhoArquivo,
    bool incluirInativos = false,
  }) async {
    final arquivo = File(caminhoArquivo);
    if (!await arquivo.exists()) {
      throw Exception('Arquivo nao encontrado: $caminhoArquivo');
    }

    // Isolate separado: dump .sql grande nao trava/fecha a UI.
    final transfer = await Isolate.run(
      () => _lerParaTransfer(
            caminhoArquivo: caminhoArquivo,
            incluirInativos: incluirInativos,
          ),
    );
    return _deTransfer(transfer);
  }

  static bool _ehDumpMysql(String caminho) {
    final lower = caminho.toLowerCase();
    return lower.endsWith('.sql');
  }

  static Map<String, Object?> _lerParaTransfer({
    required String caminhoArquivo,
    required bool incluirInativos,
  }) {
    final resumo = _lerSincrono(
      caminhoArquivo: caminhoArquivo,
      incluirInativos: incluirInativos,
    );
    return {
      'pulados': resumo.pulados,
      'linhas': [
        for (final l in resumo.linhas)
          <String, Object?>{
            'codigoInterno': l.codigoInterno,
            'nome': l.nome,
            'descricao': l.descricao,
            'preco1': l.preco1,
            'preco2': l.preco2,
            'preco3': l.preco3,
            'precoCusto': l.precoCusto,
            'custoMedio': l.custoMedio,
            'estoque': l.estoque,
            'quantidadeMinima': l.quantidadeMinima,
            'unidade': l.unidade,
            'marca': l.marca,
            'codigoBarras': l.codigoBarras,
            'ncm': l.ncm,
            'familia': l.familia,
            'grupo': l.grupo,
            'subgrupo': l.subgrupo,
            'ativo': l.ativo,
            'manterEstoqueAoAtualizar': l.manterEstoqueAoAtualizar,
          },
      ],
    };
  }

  static ChacalBackupLeituraResumo _deTransfer(Map<String, Object?> transfer) {
    final pulados = (transfer['pulados'] as num?)?.toInt() ?? 0;
    final raw = transfer['linhas'];
    final linhas = <ProdutoImportacaoLinha>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, Object?>.from(item);
        linhas.add(
          ProdutoImportacaoLinha(
            codigoInterno: (m['codigoInterno'] ?? '').toString(),
            nome: (m['nome'] ?? '').toString(),
            descricao: (m['descricao'] ?? '').toString(),
            preco1: (m['preco1'] as num?)?.toDouble() ?? 0,
            preco2: (m['preco2'] as num?)?.toDouble() ?? 0,
            preco3: (m['preco3'] as num?)?.toDouble() ?? 0,
            precoCusto: (m['precoCusto'] as num?)?.toDouble() ?? 0,
            custoMedio: (m['custoMedio'] as num?)?.toDouble() ?? 0,
            estoque: (m['estoque'] as num?)?.toInt() ?? 0,
            quantidadeMinima: (m['quantidadeMinima'] as num?)?.toInt() ?? 0,
            unidade: (m['unidade'] ?? 'UN').toString(),
            marca: (m['marca'] ?? '').toString(),
            codigoBarras: (m['codigoBarras'] ?? '').toString(),
            ncm: (m['ncm'] ?? '').toString(),
            familia: (m['familia'] ?? '').toString(),
            grupo: (m['grupo'] ?? '').toString(),
            subgrupo: (m['subgrupo'] ?? '').toString(),
            ativo: m['ativo'] != false,
            subcategoriaFallback: 'Importacao Chacal',
            manterEstoqueAoAtualizar: m['manterEstoqueAoAtualizar'] == true,
          ),
        );
      }
    }
    return ChacalBackupLeituraResumo(linhas: linhas, pulados: pulados);
  }

  static ChacalBackupLeituraResumo _lerSincrono({
    required String caminhoArquivo,
    required bool incluirInativos,
  }) {
    if (_ehDumpMysql(caminhoArquivo)) {
      final r = ChacalMysqlDumpImport.lerArquivo(
        caminhoArquivo: caminhoArquivo,
        incluirInativos: incluirInativos,
      );
      return ChacalBackupLeituraResumo(linhas: r.linhas, pulados: r.pulados);
    }

    if (ChacalJsonExportImport.pareceArquivoJsonChacal(caminhoArquivo)) {
      final r = ChacalJsonExportImport.lerArquivo(
        caminhoArquivo: caminhoArquivo,
        incluirInativos: incluirInativos,
      );
      return ChacalBackupLeituraResumo(linhas: r.linhas, pulados: r.pulados);
    }

    final db = sqlite3.open(caminhoArquivo, mode: OpenMode.readOnly);
    try {
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet();

      if (!tables.contains('produto')) {
        throw Exception(
          'Arquivo sem tabela "produto". Nao parece backup Chacal (.s3db).',
        );
      }

      final linhas = <ProdutoImportacaoLinha>[];
      var pulados = 0;

      final rows = db.select(_sqlProdutos, [incluirInativos ? 1 : 0]);
      for (final row in rows) {
        final gtin = _txt(row, 'gtin');
        final codigoBruto = ProdutoImportacaoUtil.codigoInternoChacal(
          codigoInternoBruto: _txt(row, 'codigo'),
          gtin: gtin,
        );
        final nome = _txt(row, 'nome');
        if (nome.isEmpty) {
          pulados++;
          continue;
        }
        if (codigoBruto.isEmpty && gtin.isEmpty) {
          pulados++;
          continue;
        }

        final codigo = codigoBruto.isEmpty
            ? ''
            : normalizarCodigoInternoPersistido(codigoBruto);
        if (codigoBruto.isNotEmpty && codigo.isEmpty) {
          pulados++;
          continue;
        }

        final nomePdv = _txt(row, 'nome_pdv');
        final preco1 = _dbl(row, 'preco1');
        final preco2 = _dbl(row, 'preco2');
        final preco3 = _dbl(row, 'preco3');

        linhas.add(
          ProdutoImportacaoLinha(
            codigoInterno: codigo,
            nome: nome,
            descricao: nomePdv.isNotEmpty && nomePdv != nome ? nomePdv : '',
            preco1: preco1,
            preco2: preco2,
            preco3: preco3,
            precoCusto: _dbl(row, 'precocusto'),
            custoMedio: _dbl(row, 'customedio'),
            estoque: _int(row, 'estoque'),
            quantidadeMinima: _int(row, 'estminimo'),
            unidade: _txt(row, 'unidade'),
            marca: _txt(row, 'marca'),
            codigoBarras: ProdutoImportacaoUtil.normalizarCodigoBarras(
              gtin: gtin,
              codigoInterno: codigo.isNotEmpty ? codigo : gtin,
            ),
            ncm: ProdutoImportacaoUtil.normalizarNcm(_txt(row, 'ncm')),
            familia: _txt(row, 'familia'),
            grupo: _txt(row, 'grupo'),
            subgrupo: _txt(row, 'subgrupo'),
            ativo: ProdutoImportacaoUtil.ativoDeFlagLegado(
              _txt(row, 'inativo'),
            ),
            subcategoriaFallback: 'Importacao Chacal',
          ),
        );
      }

      return ChacalBackupLeituraResumo(linhas: linhas, pulados: pulados);
    } finally {
      db.close();
    }
  }

  static String _txt(Map<String, Object?> row, String col) {
    final v = row[col];
    if (v == null) return '';
    return v.toString().trim();
  }

  static double _dbl(Map<String, Object?> row, String col) {
    final v = row[col];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return ProdutoImportacaoUtil.parseMonetario(v.toString());
  }

  static int _int(Map<String, Object?> row, String col) {
    final v = row[col];
    if (v == null) return 0;
    if (v is int) return v < 0 ? 0 : v;
    if (v is num) {
      final arred = v.round();
      return arred < 0 ? 0 : arred;
    }
    return ProdutoImportacaoUtil.parseQuantidade(v.toString());
  }
}
