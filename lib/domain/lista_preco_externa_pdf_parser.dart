import 'lista_preco_externa.dart';

/// Extrai itens da tabela "Codigo Produto Preco" (PDF Comprou Levou / Itinga).
///
/// Aceita:
/// - linha unica: `002748 Abracad ... 3,90`
/// - blocos Syncfusion (codigo / nome / preco em linhas separadas)
abstract final class ListaPrecoExternaPdfParser {
  ListaPrecoExternaPdfParser._();

  static final _linhaItem = RegExp(
    r'^(\d{4,8})\s+(.+?)\s+(\d{1,3}(?:\.\d{3})*,\d{2})$',
  );
  static final _soCodigo = RegExp(r'^(\d{4,8})$');
  static final _soPreco = RegExp(r'^(\d{1,3}(?:\.\d{3})*,\d{2})$');
  static final _dataCabecalho = RegExp(r'(\d{2}/\d{2}/\d{4})');

  static ListaPrecoExternaParseResult parseTexto(
    String texto, {
    String arquivoOrigem = '',
    String nomeLojaPadrao = 'Comprou Levou',
  }) {
    final linhas = texto
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final itens = <ItemListaPrecoExterna>[];
    var ignoradas = 0;
    DateTime? dataLista;
    var nomeLoja = nomeLojaPadrao;

    for (var i = 0; i < linhas.length; i++) {
      final line = linhas[i];
      final upper = line.toUpperCase();

      if (upper.contains('COMPROU LEVOU')) {
        nomeLoja = 'Comprou Levou';
      }
      if (upper.contains('ITINGA')) {
        nomeLoja = 'Itinga';
      }
      final dataMatch = _dataCabecalho.firstMatch(line);
      if (dataMatch != null && dataLista == null) {
        dataLista = _parseDataBr(dataMatch.group(1)!);
      }

      if (_ehRuidoCabecalho(upper)) {
        continue;
      }

      // Formato Syncfusion: codigo / nome (1+ linhas) / preco
      final codM = _soCodigo.firstMatch(line);
      if (codM != null && i + 1 < linhas.length) {
        final nomeParts = <String>[];
        var j = i + 1;
        String? precoRaw;
        while (j < linhas.length) {
          final cand = linhas[j];
          if (_soPreco.hasMatch(cand)) {
            precoRaw = cand;
            break;
          }
          if (_soCodigo.hasMatch(cand) || _ehRuidoCabecalho(cand.toUpperCase())) {
            break;
          }
          nomeParts.add(cand);
          j++;
          if (nomeParts.length > 6) break;
        }
        if (precoRaw != null && nomeParts.isNotEmpty) {
          final preco = _parsePrecoBr(precoRaw);
          final nome = nomeParts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
          if (preco >= 0 && nome.isNotEmpty) {
            itens.add(
              ItemListaPrecoExterna(
                codigo: codM.group(1)!,
                nome: nome,
                preco: preco,
              ),
            );
            i = j;
            continue;
          }
        }
      }

      // Formato pypdf / linha unica
      final m = _linhaItem.firstMatch(line);
      if (m != null) {
        final preco = _parsePrecoBr(m.group(3)!);
        final nome = m.group(2)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (nome.isNotEmpty && preco >= 0) {
          itens.add(
            ItemListaPrecoExterna(
              codigo: m.group(1)!.trim(),
              nome: nome,
              preco: preco,
            ),
          );
          continue;
        }
      }

      if (_soCodigo.hasMatch(line) || _soPreco.hasMatch(line)) {
        // Pedaco isolado de bloco malformado.
        ignoradas++;
      }
    }

    final porCodigo = <String, ItemListaPrecoExterna>{};
    for (final i in itens) {
      porCodigo[i.codigo] = i;
    }
    final unicos = porCodigo.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    return ListaPrecoExternaParseResult(
      nomeLoja: nomeLoja,
      dataLista: dataLista ?? DateTime.now(),
      itens: unicos,
      linhasIgnoradas: ignoradas,
      arquivoOrigem: arquivoOrigem,
    );
  }

  static bool _ehRuidoCabecalho(String upper) {
    return upper.contains('TABELA DE PRE') ||
        upper.startsWith('CODIGO') ||
        upper.startsWith('CÓDIGO') ||
        upper == 'PRODUTO' ||
        upper == 'PRECO' ||
        upper == 'PREÇO' ||
        upper.contains('PAGINA') ||
        upper.contains('PÁGINA');
  }

  static DateTime? _parseDataBr(String raw) {
    final p = raw.split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final a = int.tryParse(p[2]);
    if (d == null || m == null || a == null) return null;
    return DateTime(a, m, d);
  }

  static double _parsePrecoBr(String raw) {
    final limpo = raw.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(limpo) ?? -1;
  }
}

class ListaPrecoExternaParseResult {
  const ListaPrecoExternaParseResult({
    required this.nomeLoja,
    required this.dataLista,
    required this.itens,
    required this.linhasIgnoradas,
    required this.arquivoOrigem,
  });

  final String nomeLoja;
  final DateTime dataLista;
  final List<ItemListaPrecoExterna> itens;
  final int linhasIgnoradas;
  final String arquivoOrigem;
}
