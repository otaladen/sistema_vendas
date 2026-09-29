import 'package:objectbox/objectbox.dart';

import '../model/historico_entrada.dart';
import '../model/item_venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

/// Consultas de venda e NF-e ja recortadas por data, para nao varrer o historico inteiro.
class VendaPeriodoQuery {
  VendaPeriodoQuery._();

  /// Piso pratico das NF-e importadas. Anterior a isso nao entra no between.
  static final DateTime inicioHistoricoNfe = DateTime.utc(2000);

  /// Ultimos [dias] ate agora, em UTC, calculados antes da query.
  static ({DateTime inicio, DateTime fim}) janelaUtcAteAgora(
    int dias, {
    DateTime? agora,
  }) {
    final fim = (agora ?? DateTime.now()).toUtc();
    final diasJanela = dias <= 0 ? 1 : dias;
    return (inicio: fim.subtract(Duration(days: diasJanela)), fim: fim);
  }

  /// Itens de venda finalizada e nao cancelada com fechamento na janela.
  ///
  /// Usa [Venda.finalizadaEm] (indice). Venda antiga sem esse campo cai em [Venda.data].
  static List<ItemVenda> itensDeVendasFinalizadasEntre(
    ObjectBox db, {
    required DateTime inicio,
    required DateTime fim,
  }) {
    final inicioUtc = inicio.toUtc();
    final fimUtc = fim.toUtc();
    final noFechamento = Venda_.finalizadaEm.betweenDate(inicioUtc, fimUtc).or(
      Venda_.finalizadaEm.isNull().and(
            Venda_.data.betweenDate(inicioUtc, fimUtc),
          ),
    );
    final qb = db.itemVendaBox.query();
    qb.link(
      ItemVenda_.venda,
      Venda_.status
          .equals('finalizada')
          .and(Venda_.cancelada.equals(false))
          .and(noFechamento),
    );
    final query = qb.build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  static List<ItemVenda> itensDeVendasFinalizadasNosUltimosDias(
    ObjectBox db, {
    required int dias,
    DateTime? agora,
  }) {
    final janela = janelaUtcAteAgora(dias, agora: agora);
    return itensDeVendasFinalizadasEntre(
      db,
      inicio: janela.inicio,
      fim: janela.fim,
    );
  }

  /// Entradas de NF-e ate [fim], da mais recente para a mais antiga.
  static List<HistoricoEntrada> historicoEntradaAte(
    ObjectBox db,
    DateTime fim,
  ) {
    final query = db.historicoEntradaBox
        .query(
          HistoricoEntrada_.dataEmissao.betweenDate(
            inicioHistoricoNfe,
            fim.toUtc(),
          ),
        )
        .order(HistoricoEntrada_.dataEmissao, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}
