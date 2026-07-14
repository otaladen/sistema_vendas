import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/importacao/produto_importacao_linha.dart';
import '../domain/importacao/produto_importacao_util.dart';
import 'produto_busca_util.dart';

/// Le produtos de um dump MySQL do Chacal (MySqlBackup.NET .sql).
class ChacalMysqlDumpImport {
  ChacalMysqlDumpImport._();

  static const _tabelas = {
    'produto',
    'produto_marca',
    'produto_familia',
    'produto_grupo',
    'produto_sub_grupo',
    'produto_unidade',
    'produto_estoque',
  };

  /// Le o dump em streaming (nao carrega o arquivo inteiro na memoria).
  static ({List<ProdutoImportacaoLinha> linhas, int pulados}) lerArquivo({
    required String caminhoArquivo,
    bool incluirInativos = false,
  }) {
    final marca = <int, String>{};
    final familia = <int, String>{};
    final grupo = <int, String>{};
    final subgrupo = <int, String>{};
    final unidade = <int, String>{};
    final estoque = <int, double>{};
    List<String>? produtoCols;
    final produtoRows = <List<Object?>>[];

    final file = File(caminhoArquivo);
    _forEachLineSync(file, (line) {
      if (!line.startsWith('INSERT INTO `')) return;
      final tableGuess = _tableNameFromInsert(line);
      if (tableGuess == null || !_tabelas.contains(tableGuess)) return;

      final parsed = _parseInsertLine(line);
      if (parsed == null) return;
      final (table, cols, rows) = parsed;

      switch (table) {
        case 'produto_marca':
          marca.addAll(_mapLookup(rows, cols, 'ID_PRODUTO_MARCA', 'NOME'));
        case 'produto_familia':
          familia.addAll(_mapLookup(rows, cols, 'ID_PRODUTO_FAMILIA', 'NOME'));
        case 'produto_grupo':
          grupo.addAll(_mapLookup(rows, cols, 'ID_PRODUTO_GRUPO', 'NOME'));
        case 'produto_sub_grupo':
          subgrupo
              .addAll(_mapLookup(rows, cols, 'ID_PRODUTO_SUB_GRUPO', 'NOME'));
        case 'produto_unidade':
          if (cols.contains('SIGLA')) {
            unidade
                .addAll(_mapLookup(rows, cols, 'ID_PRODUTO_UNIDADE', 'SIGLA'));
          }
        case 'produto_estoque':
          final iId = cols.indexOf('ID_PRODUTO');
          final iSaldo = cols.indexOf('SALDO');
          if (iId < 0 || iSaldo < 0) break;
          for (final row in rows) {
            if (iId >= row.length) continue;
            final pid = _asInt(row[iId]);
            if (pid == null) continue;
            estoque[pid] = (estoque[pid] ?? 0) + _asDouble(row[iSaldo]);
          }
        case 'produto':
          produtoCols ??= cols;
          produtoRows.addAll(rows);
      }
    });

    final colsResolvidas = produtoCols;
    if (colsResolvidas == null || produtoRows.isEmpty) {
      throw Exception(
        'Dump sem dados de produto. Confira se e o backup MySQL completo do Chacal (.sql).',
      );
    }

    final idx = {
      for (var i = 0; i < colsResolvidas.length; i++) colsResolvidas[i]: i,
    };

    Object? get(List<Object?> row, String name) {
      final i = idx[name];
      if (i == null || i >= row.length) return null;
      return row[i];
    }

    String lookup(List<Object?> row, String idCol, Map<int, String> map) {
      final id = _asInt(get(row, idCol));
      if (id == null) return '';
      return map[id] ?? '';
    }

    final linhas = <ProdutoImportacaoLinha>[];
    var pulados = 0;

    for (final row in produtoRows) {
      final inativo = _txt(get(row, 'INATIVO'));
      if (!incluirInativos &&
          !ProdutoImportacaoUtil.ativoDeFlagLegado(inativo)) {
        pulados++;
        continue;
      }

      var codigoBruto = ProdutoImportacaoUtil.codigoInternoChacal(
        codigoInternoBruto: _txt(get(row, 'CODIGO_INTERNO')),
        gtin: _txt(get(row, 'GTIN')),
      );
      final nome = _txt(get(row, 'NOME'));
      final gtin = _txt(get(row, 'GTIN'));
      if (nome.isEmpty) {
        pulados++;
        continue;
      }
      if (codigoBruto.isEmpty &&
          gtin.isEmpty &&
          _txt(get(row, 'ID_PRODUTO')).isEmpty) {
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

      final nomePdv = _txt(get(row, 'NOME_PDV'));
      final preco1 = _asDouble(get(row, 'PRECO1'));
      final preco2 = _asDouble(get(row, 'PRECO2'));
      final preco3 = _asDouble(get(row, 'PRECO3'));

      var precocusto = _asDouble(get(row, 'VALOR_COMPRA'));
      if (precocusto <= 0) {
        precocusto = _asDouble(get(row, 'VALOR_COMPRA_LIQUIDO'));
      }

      var und = lookup(row, 'ID_PRODUTO_UNIDADE', unidade);
      if (und.isEmpty) {
        und = _txt(get(row, 'SIGLA'));
      }
      if (und.isEmpty) {
        und = _txt(get(row, 'UNIDADE_COMPRA'));
      }
      if (und.isEmpty) und = 'UN';

      final pid = _asInt(get(row, 'ID_PRODUTO'));
      final est = pid == null ? 0.0 : (estoque[pid] ?? 0.0);
      final estInt = est.round();
      final estMin = _asDouble(get(row, 'ESTOQUE_MINIMO')).round();

      linhas.add(
        ProdutoImportacaoLinha(
          codigoInterno: codigo,
          nome: nome,
          descricao: nomePdv.isNotEmpty && nomePdv != nome ? nomePdv : '',
          preco1: preco1,
          preco2: preco2,
          preco3: preco3,
          precoCusto: precocusto,
          custoMedio: _asDouble(get(row, 'CUSTO_MEDIO_LIQUIDO')),
          estoque: estInt < 0 ? 0 : estInt,
          quantidadeMinima: estMin < 0 ? 0 : estMin,
          unidade: und,
          marca: lookup(row, 'ID_PRODUTO_MARCA', marca),
          codigoBarras: ProdutoImportacaoUtil.normalizarCodigoBarras(
            gtin: gtin,
          ),
          ncm: ProdutoImportacaoUtil.normalizarNcm(_txt(get(row, 'NCM'))),
          familia: lookup(row, 'ID_PRODUTO_FAMILIA', familia),
          grupo: lookup(row, 'ID_PRODUTO_GRUPO', grupo),
          subgrupo: lookup(row, 'ID_PRODUTO_SUB_GRUPO', subgrupo),
          ativo: ProdutoImportacaoUtil.ativoDeFlagLegado(inativo),
          subcategoriaFallback: 'Importacao Chacal',
        ),
      );
    }

    return (linhas: linhas, pulados: pulados);
  }

  /// Percorre o arquivo linha a linha por blocos (evita OOM em dumps grandes).
  static void _forEachLineSync(File file, void Function(String line) onLine) {
    final raf = file.openSync(mode: FileMode.read);
    try {
      final lineSink = _MysqlLineSink(onLine);
      final byteSink =
          const Utf8Decoder(allowMalformed: true).startChunkedConversion(lineSink);
      final chunk = Uint8List(256 * 1024);
      while (true) {
        final n = raf.readIntoSync(chunk);
        if (n <= 0) break;
        byteSink.add(
          n == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, n),
        );
      }
      byteSink.close();
    } finally {
      raf.closeSync();
    }
  }

  static String? _tableNameFromInsert(String line) {
    final start = line.indexOf('`');
    if (start < 0) return null;
    final end = line.indexOf('`', start + 1);
    if (end < 0) return null;
    return line.substring(start + 1, end);
  }

  static (String, List<String>, List<List<Object?>>)? _parseInsertLine(
    String line,
  ) {
    final trimmed = line.trimRight();
    final into = RegExp(
      r"^INSERT INTO `([^`]+)`\s*\(([^)]+)\)\s*VALUES\s*(.+);\s*$",
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);
    if (into == null) return null;
    final table = into.group(1)!;
    final cols = into
        .group(2)!
        .split(',')
        .map((c) => c.trim().replaceAll('`', ''))
        .where((c) => c.isNotEmpty)
        .toList();
    var body = into.group(3)!.trimRight();
    if (body.endsWith(';')) {
      body = body.substring(0, body.length - 1);
    }
    final rows = _parseMysqlValues(body);
    return (table, cols, rows);
  }

  static List<List<Object?>> _parseMysqlValues(String body) {
    final rows = <List<Object?>>[];
    var i = 0;
    final n = body.length;
    while (i < n) {
      while (i < n && ' \t\r\n,'.contains(body[i])) {
        i++;
      }
      if (i >= n) break;
      if (body[i] != '(') {
        throw Exception('INSERT MySQL invalido (esperado "(").');
      }
      i++;
      final row = <Object?>[];
      while (true) {
        while (i < n && ' \t\r\n'.contains(body[i])) {
          i++;
        }
        if (i >= n) {
          throw Exception('INSERT MySQL truncado.');
        }
        final ch = body[i];
        if (ch == ')') {
          i++;
          rows.add(row);
          break;
        }
        if (ch == "'" || ch == '"') {
          final quote = ch;
          i++;
          final buf = StringBuffer();
          while (i < n) {
            final c = body[i];
            if (c == r'\' && i + 1 < n) {
              final nxt = body[i + 1];
              buf.write(switch (nxt) {
                '0' => '\u0000',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'Z' => '\u001a',
                r'\' => r'\',
                "'" => "'",
                '"' => '"',
                _ => nxt,
              });
              i += 2;
              continue;
            }
            if (c == quote) {
              if (i + 1 < n && body[i + 1] == quote) {
                buf.write(quote);
                i += 2;
                continue;
              }
              i++;
              break;
            }
            buf.write(c);
            i++;
          }
          row.add(buf.toString());
        } else if (body.startsWith('NULL', i) &&
            (i + 4 >= n || ',)'.contains(body[i + 4]))) {
          row.add(null);
          i += 4;
        } else {
          final start = i;
          while (i < n && body[i] != ',' && body[i] != ')') {
            i++;
          }
          final token = body.substring(start, i).trim();
          if (token.isEmpty) {
            row.add(null);
          } else {
            final asInt = int.tryParse(token);
            if (asInt != null) {
              row.add(asInt);
            } else {
              final asDbl = double.tryParse(token);
              row.add(asDbl ?? token);
            }
          }
        }
        while (i < n && ' \t\r\n'.contains(body[i])) {
          i++;
        }
        if (i < n && body[i] == ',') {
          i++;
          continue;
        }
        if (i < n && body[i] == ')') {
          continue;
        }
        if (i < n && body[i] != ',' && body[i] != ')') {
          throw Exception('Token MySQL inesperado na leitura do dump.');
        }
      }
    }
    return rows;
  }

  static Map<int, String> _mapLookup(
    List<List<Object?>> rows,
    List<String> cols,
    String idCol,
    String nameCol,
  ) {
    final iId = cols.indexOf(idCol);
    final iNome = cols.indexOf(nameCol);
    if (iId < 0 || iNome < 0) return {};
    final out = <int, String>{};
    for (final row in rows) {
      if (iId >= row.length || iNome >= row.length) continue;
      final id = _asInt(row[iId]);
      if (id == null) continue;
      out[id] = _txt(row[iNome]);
    }
    return out;
  }

  static String _txt(Object? v) => v?.toString().trim() ?? '';

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return ProdutoImportacaoUtil.parseMonetario(v.toString());
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim());
  }
}

class _MysqlLineSink implements Sink<String> {
  _MysqlLineSink(this._onLine);

  final void Function(String line) _onLine;
  String _carry = '';
  bool _closed = false;

  @override
  void add(String data) {
    if (_closed) return;
    final parts = '$_carry$data'.split('\n');
    _carry = parts.removeLast();
    for (final raw in parts) {
      _onLine(raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (_carry.isEmpty) return;
    final line =
        _carry.endsWith('\r') ? _carry.substring(0, _carry.length - 1) : _carry;
    _carry = '';
    _onLine(line);
  }
}
