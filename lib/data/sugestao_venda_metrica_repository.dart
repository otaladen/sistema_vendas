import '../domain/sugestao_venda_metrica_constantes.dart';
import '../domain/sugestao_venda_ranking.dart';
import '../model/sugestao_venda_metrica_evento.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class SugestaoVendaMetricaRepository {
  SugestaoVendaMetricaRepository(this._db);

  final ObjectBox _db;

  Box<SugestaoVendaMetricaEvento> get _box =>
      _db.sugestaoVendaMetricaEventoBox;

  void registrarExibiu({
    required int produtoOrigemId,
    required int produtoSugeridoId,
    required String canal,
    required String fonte,
    String usuarioLogin = '',
  }) {
    _registrar(
      SugestaoVendaMetricaEvento(
        produtoOrigemId: produtoOrigemId,
        produtoSugeridoId: produtoSugeridoId,
        tipoEvento: SugestaoVendaMetricaTipo.exibiu,
        canal: canal,
        fonte: fonte,
        usuarioLogin: usuarioLogin,
      ),
    );
  }

  void registrarAceite({
    required int produtoOrigemId,
    required int produtoSugeridoId,
    required String canal,
    required String fonte,
    required int quantidade,
    String usuarioLogin = '',
  }) {
    if (produtoOrigemId <= 0 || produtoSugeridoId <= 0) return;
    _registrar(
      SugestaoVendaMetricaEvento(
        produtoOrigemId: produtoOrigemId,
        produtoSugeridoId: produtoSugeridoId,
        tipoEvento: SugestaoVendaMetricaTipo.aceitou,
        canal: canal,
        fonte: fonte,
        quantidade: quantidade.clamp(1, 999999),
        usuarioLogin: usuarioLogin,
      ),
    );
  }

  void registrarIgnorou({
    required int produtoOrigemId,
    required int produtoSugeridoId,
    required String canal,
    required String fonte,
    String usuarioLogin = '',
  }) {
    if (produtoOrigemId <= 0 || produtoSugeridoId <= 0) return;
    _registrar(
      SugestaoVendaMetricaEvento(
        produtoOrigemId: produtoOrigemId,
        produtoSugeridoId: produtoSugeridoId,
        tipoEvento: SugestaoVendaMetricaTipo.ignorou,
        canal: canal,
        fonte: fonte,
        usuarioLogin: usuarioLogin,
      ),
    );
  }

  List<SugestaoVendaRankingLinha> listarRanking({
    required DateTime inicio,
    required DateTime fim,
    int limite = 200,
  }) {
    final i = inicio.toUtc();
    final f = fim.toUtc();
    final q = _box
        .query(
          SugestaoVendaMetricaEvento_.dataHora
              .greaterOrEqualDate(i)
              .and(SugestaoVendaMetricaEvento_.dataHora.lessOrEqualDate(f)),
        )
        .build();
    try {
      final ranking = SugestaoVendaRankingUtil.agrupar(q.find());
      if (limite <= 0) return ranking;
      return ranking.take(limite).toList();
    } finally {
      q.close();
    }
  }

  void _registrar(SugestaoVendaMetricaEvento evento) {
    _db.store.runInTransaction(TxMode.write, () {
      _box.put(evento);
    });
    notificarAlteracaoParaRede(
      entidade: 'sugestao_venda_metrica',
      entidadeId: 0,
    );
  }
}
