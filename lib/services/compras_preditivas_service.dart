import 'package:objectbox/objectbox.dart';

import '../data/objectbox.dart';
import '../data/ponto_pedido_api_dto.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_estoque_sync.dart';
import '../model/produto.dart';

/// Compras preditivas: ponto de pedido (PP) e indicadores de estoque critico.
///
/// Formula (com giro confiavel): PP = (vendaMediaDiaria * leadTimeDias) + estoqueSeguranca
class ComprasPreditivasService {
  ComprasPreditivasService(
    this._db, {
    this.diasHistoricoVendas = 60,
    this.diasMinimosCadastroParaGiro = 14,
  });

  final ObjectBox _db;

  /// Janela para recalcular [Produto.vendaMediaDiaria] a partir das vendas finalizadas.
  final int diasHistoricoVendas;

  /// Produtos com menos dias de cadastro usam [estoqueSeguranca] como gatilho de alerta.
  final int diasMinimosCadastroParaGiro;

  static const double _epsilonMedia = 1e-9;

  /// Calcula o PP teorico (formula completa).
  double calcularPontoPedido(Produto produto) => produto.pontoPedido;

  /// Limiar de estoque para produtos novos / sem giro (seguranca ou minimo).
  int limiarEstoqueNovoProduto(Produto produto) {
    if (produto.estoqueSeguranca > 0) return produto.estoqueSeguranca;
    if (produto.quantidadeMinima > 0) return produto.quantidadeMinima;
    return 0;
  }

  /// Dias desde o cadastro do produto.
  int diasDesdeCadastro(Produto produto) {
    return DateTime.now()
        .toUtc()
        .difference(produto.criadoEm.toUtc())
        .inDays;
  }

  /// Giro confiavel: cadastro maduro (>= [diasMinimosCadastroParaGiro]) e media > 0.
  bool temGiroVendaConfiavel(
    Produto produto, {
    double? mediaOverride,
    int? consumoNoPeriodo,
  }) {
    if (diasDesdeCadastro(produto) < diasMinimosCadastroParaGiro) {
      return false;
    }
    final media = mediaOverride ?? produto.vendaMediaDiaria;
    if (media > _epsilonMedia) return true;
    if (consumoNoPeriodo != null) {
      return consumoNoPeriodo > 0;
    }
    return calcularVendaMediaDiariaDoHistorico(produto.id) > _epsilonMedia;
  }

  /// Valor exibido como "ponto de pedido" (PP ou limiar de seguranca).
  /// Sempre na unidade de venda ([Produto.estoqueExibicao]), nunca em raw.
  double calcularPontoPedidoExibicao(
    Produto produto, {
    int? consumoNoPeriodo,
  }) {
    if (temGiroVendaConfiavel(
      produto,
      consumoNoPeriodo: consumoNoPeriodo,
    )) {
      final media = _mediaDiariaExibicao(
        produto,
        consumoNoPeriodo: consumoNoPeriodo,
      );
      return media * produto.leadTimeDias + produto.estoqueSeguranca;
    }
    return limiarEstoqueNovoProduto(produto).toDouble();
  }

  /// PP a partir do cadastro (sem consultar historico). Usado no terminal.
  static double pontoPedidoExibicaoDeCadastro(Produto produto) {
    if (produto.vendaMediaDiaria > _epsilonMedia) {
      final media = ProdutoEmbalagem.valorMediaDiariaExibicao(
        produto,
        produto.vendaMediaDiaria,
      );
      return media * produto.leadTimeDias + produto.estoqueSeguranca;
    }
    if (produto.estoqueSeguranca > 0) {
      return produto.estoqueSeguranca.toDouble();
    }
    if (produto.quantidadeMinima > 0) {
      return produto.quantidadeMinima.toDouble();
    }
    return 0;
  }

  /// Media diaria na unidade de venda (m²/CX/UN).
  double _mediaDiariaExibicao(
    Produto produto, {
    int? consumoNoPeriodo,
  }) {
    if (consumoNoPeriodo != null && consumoNoPeriodo > 0) {
      final dias = diasHistoricoVendas <= 0 ? 1 : diasHistoricoVendas;
      return ProdutoEmbalagem.valorEstoqueExibicao(produto, consumoNoPeriodo) /
          dias;
    }
    return ProdutoEmbalagem.valorMediaDiariaExibicao(
      produto,
      produto.vendaMediaDiaria,
    );
  }

  /// `true` se estoque atual (unidade de venda) atingiu ou ficou abaixo do limiar.
  bool verificarEstoqueCritico(
    Produto produto, {
    int? consumoNoPeriodo,
  }) {
    final estoque = produto.estoqueExibicao;
    final limiar = calcularPontoPedidoExibicao(
      produto,
      consumoNoPeriodo: consumoNoPeriodo,
    );
    return estoque <= limiar + 1e-9;
  }

  /// Monta consumo por produto em uma unica passagem (60 dias).
  Map<int, int> montarConsumoPorProdutoNoPeriodo({int? dias}) {
    final janela = dias ?? diasHistoricoVendas;
    final diasJanela = janela <= 0 ? 1 : janela;
    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: diasJanela));

    final consumo = <int, int>{};
    for (final item in _db.itemVendaBox.getAll()) {
      final produtoId = item.produto.targetId;
      if (produtoId == 0) continue;
      final venda = item.venda.target;
      if (venda == null) continue;
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      final dataVenda = venda.data.toUtc();
      if (dataVenda.isBefore(inicio) || dataVenda.isAfter(fim)) continue;
      final qtd = item.quantidade - item.quantidadeDevolvida;
      if (qtd <= 0) continue;
      consumo.update(
        produtoId,
        (x) => x + qtd,
        ifAbsent: () => qtd,
      );
    }
    return consumo;
  }

  double mediaDiariaFromConsumo(Map<int, int> consumo, int produtoId) {
    final dias = diasHistoricoVendas <= 0 ? 1 : diasHistoricoVendas;
    final total = consumo[produtoId] ?? 0;
    return total / dias;
  }

  /// Soma saidas no historico e retorna media diaria (unidades/dia).
  double calcularVendaMediaDiariaDoHistorico(int produtoId) {
    final consumo = montarConsumoPorProdutoNoPeriodo();
    return mediaDiariaFromConsumo(consumo, produtoId);
  }

  /// Atualiza [vendaMediaDiaria] no produto (nao persiste).
  void atualizarVendaMediaDiaria(
    Produto produto, {
    Map<int, int>? consumoPrecalculado,
  }) {
    if (produto.id <= 0) return;
    final mapa = consumoPrecalculado ?? montarConsumoPorProdutoNoPeriodo();
    produto.vendaMediaDiaria = mediaDiariaFromConsumo(mapa, produto.id);
  }

  /// Atualiza metricas apos venda (estoque atual + media diaria). Sem UI.
  void atualizarAposVendaRegistrada({
    required Produto produto,
    required int quantidadeVendida,
    bool estoqueRealJaAbatido = true,
    Map<int, int>? consumoPrecalculado,
  }) {
    if (quantidadeVendida <= 0) return;

    if (!estoqueRealJaAbatido) {
      produto.estoqueReal -= quantidadeVendida;
    }
    produto.estoqueAtual = produto.estoqueReal;

    atualizarVendaMediaDiaria(
      produto,
      consumoPrecalculado: consumoPrecalculado,
    );
    ProdutoEstoqueSync.marcarEstoqueAlterado(produto);
    _db.produtoBox.put(produto);
  }

  /// Produtos ativos no ou abaixo do PP (ou limiar de seguranca).
  int contarProdutosAtivosCriticos({Map<int, int>? consumoPrecalculado}) {
    final consumo = consumoPrecalculado ?? montarConsumoPorProdutoNoPeriodo();
    var total = 0;
    for (final produto in _db.produtoBox.getAll()) {
      if (!produto.ativo || produto.id <= 0) continue;
      if (verificarEstoqueCritico(
        produto,
        consumoNoPeriodo: consumo[produto.id] ?? 0,
      )) {
        total++;
      }
    }
    return total;
  }

  /// Mapa produtoId -> critico PP (para listagem na tela Estoque).
  Map<int, bool> mapaProdutosAtivosCriticos({Map<int, int>? consumoPrecalculado}) {
    final consumo = consumoPrecalculado ?? montarConsumoPorProdutoNoPeriodo();
    final mapa = <int, bool>{};
    for (final produto in _db.produtoBox.getAll()) {
      if (!produto.ativo || produto.id <= 0) continue;
      final critico = verificarEstoqueCritico(
        produto,
        consumoNoPeriodo: consumo[produto.id] ?? 0,
      );
      if (critico) {
        mapa[produto.id] = true;
      }
    }
    return mapa;
  }

  /// Recalcula medias em **uma transacao** com consumo pre-agregado (rapido).
  int recalcularTodosProdutosAtivos() {
    final consumo = montarConsumoPorProdutoNoPeriodo();
    var atualizados = 0;

    _db.store.runInTransaction(TxMode.write, () {
      final produtos = _db.produtoBox.getAll();
      for (final produto in produtos) {
        if (!produto.ativo || produto.id <= 0) continue;
        produto.estoqueAtual = produto.estoqueReal;
        produto.vendaMediaDiaria = mediaDiariaFromConsumo(consumo, produto.id);
        _db.produtoBox.put(produto);
        atualizados++;
      }
    });

    return atualizados;
  }

  /// Executa [recalcularTodosProdutosAtivos] fora da UI thread.
  Future<int> recalcularTodosProdutosAtivosAsync() {
    return Future<int>(recalcularTodosProdutosAtivos);
  }

  /// Snapshot de PP/critico para o terminal (GET /api/estoque/ponto-pedido).
  List<PontoPedidoApiItem> montarItensPontoPedidoApi({int dias = 60}) {
    final consumo = montarConsumoPorProdutoNoPeriodo(dias: dias);
    final items = <PontoPedidoApiItem>[];
    for (final produto in _db.produtoBox.getAll()) {
      if (!produto.ativo || produto.id <= 0) continue;
      final bruto = consumo[produto.id] ?? 0;
      items.add(
        PontoPedidoApiItem(
          produtoId: produto.id,
          critico: verificarEstoqueCritico(
            produto,
            consumoNoPeriodo: bruto,
          ),
          pontoPedido: calcularPontoPedidoExibicao(
            produto,
            consumoNoPeriodo: bruto,
          ),
          consumo60d: bruto,
          vendaMediaDiariaExibicao: _mediaDiariaExibicao(
            produto,
            consumoNoPeriodo: bruto > 0 ? bruto : null,
          ),
        ),
      );
    }
    return items;
  }
}
