import '../model/sugestao_venda_metrica_evento.dart';

/// Linha agregada do ranking de sugestoes de venda.
class SugestaoVendaRankingLinha {
  const SugestaoVendaRankingLinha({
    required this.produtoOrigemId,
    required this.produtoSugeridoId,
    required this.fonte,
    required this.exibicoes,
    required this.aceites,
    required this.ignorados,
  });

  final int produtoOrigemId;
  final int produtoSugeridoId;
  final String fonte;
  final int exibicoes;
  final int aceites;
  final int ignorados;

  int get oportunidades =>
      exibicoes > 0 ? exibicoes : aceites + ignorados;

  double get taxaAceite {
    final decisoes = aceites + ignorados;
    if (decisoes > 0) return aceites / decisoes;
    if (exibicoes > 0) return aceites / exibicoes;
    return 0;
  }
}

/// Agrupa eventos brutos em linhas de ranking.
abstract final class SugestaoVendaRankingUtil {
  SugestaoVendaRankingUtil._();

  static List<SugestaoVendaRankingLinha> agrupar(
    Iterable<SugestaoVendaMetricaEvento> eventos,
  ) {
    final map = <String, SugestaoVendaRankingLinha>{};
    for (final e in eventos) {
      final chave = '${e.produtoOrigemId}|${e.produtoSugeridoId}|${e.fonte}';
      final atual = map[chave];
      var exib = atual?.exibicoes ?? 0;
      var ace = atual?.aceites ?? 0;
      var ign = atual?.ignorados ?? 0;
      if (e.tipoEvento == 'exibiu') {
        exib++;
      } else if (e.tipoEvento == 'aceitou') {
        ace++;
      } else if (e.tipoEvento == 'ignorou') {
        ign++;
      }
      map[chave] = SugestaoVendaRankingLinha(
        produtoOrigemId: e.produtoOrigemId,
        produtoSugeridoId: e.produtoSugeridoId,
        fonte: e.fonte,
        exibicoes: exib,
        aceites: ace,
        ignorados: ign,
      );
    }
    final lista = map.values.toList()
      ..sort((a, b) {
        final cmp = b.aceites.compareTo(a.aceites);
        if (cmp != 0) return cmp;
        return b.taxaAceite.compareTo(a.taxaAceite);
      });
    return lista;
  }
}
