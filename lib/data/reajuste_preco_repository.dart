import '../domain/auditoria_catalogo.dart';
import '../domain/reajuste_preco_lote.dart';
import '../model/reajuste_preco.dart';
import '../model/reajuste_preco_item.dart';
import '../model/usuario_sistema.dart';
import '../objectbox.g.dart';
import '../services/auditoria_registrar.dart';
import 'objectbox.dart';
import 'produto_repository.dart';
import 'sync/sync_write_trigger.dart';

class ReajustePrecoRepository {
  ReajustePrecoRepository(this._db, this._produtoRepository);

  final ObjectBox _db;
  final ProdutoRepository _produtoRepository;

  List<ReajustePreco> listarHistorico({int limite = 100}) {
    final q = _db.reajustePrecoBox
        .query()
        .order(ReajustePreco_.criadoEm, flags: Order.descending)
        .build();
    try {
      return q.find().take(limite).toList();
    } finally {
      q.close();
    }
  }

  ReajustePreco? obterPorId(int id) => _db.reajustePrecoBox.get(id);

  List<ReajustePrecoItem> listarItensDoReajuste(int reajusteId) {
    final q = _db.reajustePrecoItemBox
        .query(ReajustePrecoItem_.reajuste.equals(reajusteId))
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  ReajustePrecoLoteAplicacaoResultado aplicarLote({
    required ReajustePrecoParametros parametros,
    required List<ReajustePrecoLinhaPreview> linhas,
    required UsuarioSistema usuario,
    String motivo = '',
  }) {
    final alteradas =
        linhas.where((l) => l.seraAlterado).toList(growable: false);
    if (alteradas.isEmpty) {
      return ReajustePrecoLoteAplicacaoResultado(
        produtosGravados: 0,
        ignorados: linhas.length,
      );
    }

    final cabecalho = ReajustePreco(
      usuarioLogin: usuario.login,
      usuarioNome: usuario.nome,
      motivo: motivo.trim(),
      modo: ReajustePrecoParametros.codigoModo(parametros.modo),
      percentualSobrePreco: parametros.percentualSobrePreco,
      margemPercentual: parametros.margemPercentual,
      baseCusto: ReajustePrecoParametros.codigoBaseCusto(parametros.baseCusto),
      arredondamento:
          ReajustePrecoParametros.codigoArredondamento(parametros.arredondamento),
      tabelasCsv: parametros.tabelasCsv,
      somenteAtivos: parametros.somenteAtivos,
      protegerAbaixoCusto: parametros.naoAlterarSeAbaixoDoCusto,
      margemMinimaPercentual: parametros.margemMinimaPercentual,
      totalEscopo: linhas.length,
      totalAlterados: alteradas.length,
      totalIgnorados: linhas.length - alteradas.length,
    );

    var gravados = 0;
    int reajusteId = 0;

    _db.store.runInTransaction(TxMode.write, () {
      reajusteId = _db.reajustePrecoBox.put(cabecalho);

      for (final linha in alteradas) {
        final produto = _db.produtoBox.get(linha.produtoId);
        if (produto == null) continue;

        ReajustePrecoLoteService.aplicarLinhaNoProduto(
          produto,
          linha,
          parametros,
        );
        produto.estoqueAtual = produto.estoqueReal;
        _db.produtoBox.put(produto);

        final item = ReajustePrecoItem(
          produtoId: linha.produtoId,
          codigoInterno: linha.codigoInterno,
          nome: linha.nome,
          preco1Antes: linha.preco1Antes,
          preco2Antes: linha.preco2Antes,
          preco3Antes: linha.preco3Antes,
          preco1Depois: linha.preco1Depois,
          preco2Depois: linha.preco2Depois,
          preco3Depois: linha.preco3Depois,
          alterouPreco1: parametros.tabelas.contains(ReajusteTabelaPreco.preco1) &&
              (linha.preco1Depois - linha.preco1Antes).abs() > 0.0001,
          alterouPreco2: parametros.tabelas.contains(ReajusteTabelaPreco.preco2) &&
              (linha.preco2Depois - linha.preco2Antes).abs() > 0.0001,
          alterouPreco3: parametros.tabelas.contains(ReajusteTabelaPreco.preco3) &&
              (linha.preco3Depois - linha.preco3Antes).abs() > 0.0001,
        );
        item.reajuste.targetId = reajusteId;
        _db.reajustePrecoItemBox.put(item);
        gravados++;
      }
    });

    if (gravados > 0) {
      _produtoRepository.invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.estoque,
        acao: AuditoriaAcao.reajustePrecoLote,
        usuarioLogin: usuario.login,
        entidade: 'reajuste_preco',
        entidadeId: '$reajusteId',
        resumo:
            'Reajuste em lote #$reajusteId: $gravados produto(s) alterado(s)',
        detalhes: {
          'modo': ReajustePrecoParametros.codigoModo(parametros.modo),
          if (motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
          'totalEscopo': linhas.length,
          'totalAlterados': alteradas.length,
          'totalIgnorados': linhas.length - gravados,
        },
      );
    }

    return ReajustePrecoLoteAplicacaoResultado(
      produtosGravados: gravados,
      ignorados: linhas.length - gravados,
      reajustePrecoId: reajusteId,
    );
  }

  /// Restaura precos gravados no snapshot e marca o reajuste como estornado.
  ReajustePrecoLoteAplicacaoResultado estornar({
    required int reajusteId,
    required UsuarioSistema usuario,
  }) {
    final cab = _db.reajustePrecoBox.get(reajusteId);
    if (cab == null) {
      return const ReajustePrecoLoteAplicacaoResultado(
        produtosGravados: 0,
        ignorados: 0,
      );
    }
    if (cab.estornado) {
      return const ReajustePrecoLoteAplicacaoResultado(
        produtosGravados: 0,
        ignorados: 0,
      );
    }

    final itens = listarItensDoReajuste(reajusteId);
    var gravados = 0;

    _db.store.runInTransaction(TxMode.write, () {
      for (final item in itens) {
        final produto = _db.produtoBox.get(item.produtoId);
        if (produto == null) continue;
        ReajustePrecoLoteService.restaurarPrecosAntesNoProduto(
          produto,
          ReajustePrecoItemSnapshot(
            produtoId: item.produtoId,
            preco1Antes: item.preco1Antes,
            preco2Antes: item.preco2Antes,
            preco3Antes: item.preco3Antes,
            alterouPreco1: item.alterouPreco1,
            alterouPreco2: item.alterouPreco2,
            alterouPreco3: item.alterouPreco3,
          ),
        );
        produto.estoqueAtual = produto.estoqueReal;
        _db.produtoBox.put(produto);
        gravados++;
      }
      cab.estornado = true;
      cab.estornadoEm = DateTime.now().toUtc();
      cab.estornadoPorLogin = usuario.login;
      _db.reajustePrecoBox.put(cab);
    });

    if (gravados > 0) {
      _produtoRepository.invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.estoque,
        acao: AuditoriaAcao.reajustePrecoEstorno,
        usuarioLogin: usuario.login,
        entidade: 'reajuste_preco',
        entidadeId: '$reajusteId',
        resumo:
            'Estorno reajuste #$reajusteId: $gravados produto(s) restaurado(s)',
      );
    }

    return ReajustePrecoLoteAplicacaoResultado(
      produtosGravados: gravados,
      ignorados: itens.length - gravados,
      reajustePrecoId: reajusteId,
    );
  }
}
