import '../data/lote_produto_repository.dart';
import '../domain/lote_validade_config.dart';
import '../model/lote_produto.dart';
import '../model/produto.dart';

/// Motor FEFO + pricing Bota-Fora.
class LoteFefoService {
  LoteFefoService(this._repo);

  final LoteProdutoRepository _repo;

  List<LoteProduto> lotesAtivosOrdenadosFefo(int produtoId) =>
      _repo.lotesVendaveisFefo(produtoId);

  int estoqueDisponivelPdv(Produto produto) {
    if (!produto.controlaLoteValidade) return produto.estoqueLivreParaVenda;
    _repo.garantirMigracaoSemLote(produto, notificar: false);
    final somaLotes = _repo.somaQuantidadeAtiva(produto.id);
    final livre = produto.estoqueLivreParaVenda;
    // Disponivel = minimo entre fisico livre e soma dos lotes vendaveis.
    return somaLotes < livre ? somaLotes : livre;
  }

  LoteProduto? loteFefoAtual(Produto produto) {
    if (!produto.controlaLoteValidade) return null;
    final lotes = lotesAtivosOrdenadosFefo(produto.id);
    return lotes.isEmpty ? null : lotes.first;
  }

  bool loteFefoEmBotaFora(Produto produto) {
    final lote = loteFefoAtual(produto);
    if (lote == null) return false;
    final dias = lote.diasParaVencer;
    if (dias == null) return false;
    return dias >= 0 && dias <= LoteValidadeConfigStore.diasCriticoBotaFora;
  }

  double percentualBotaForaEfetivo(Produto produto) {
    if (produto.percentualBotaFora > 0) return produto.percentualBotaFora;
    return LoteValidadeConfigStore.percentualBotaForaPadraoEfetivo;
  }

  double precoComBotaForaSeAplicavel({
    required Produto produto,
    required double precoBase,
  }) {
    if (!produto.controlaLoteValidade) return precoBase;
    if (!loteFefoEmBotaFora(produto)) return precoBase;
    final pct = percentualBotaForaEfetivo(produto);
    if (pct <= 0) return precoBase;
    final fator = (100 - pct) / 100.0;
    return (precoBase * fator * 100).roundToDouble() / 100.0;
  }

  /// Consome lotes FEFO e devolve snapshots para o item da venda.
  List<LoteConsumoSnapshot> consumirFefo({
    required Produto produto,
    required int quantidade,
    bool notificar = true,
  }) {
    if (!produto.controlaLoteValidade || quantidade <= 0) {
      return const [];
    }
    _repo.garantirMigracaoSemLote(produto, notificar: notificar);
    var restante = quantidade;
    final consumos = <LoteConsumoSnapshot>[];
    final lotes = lotesAtivosOrdenadosFefo(produto.id);
    for (final lote in lotes) {
      if (restante <= 0) break;
      final usar = lote.quantidadeEstoque < restante
          ? lote.quantidadeEstoque
          : restante;
      if (usar <= 0) continue;
      lote.quantidadeEstoque -= usar;
      if (lote.quantidadeEstoque <= 0) {
        lote.quantidadeEstoque = 0;
        lote.ativo = false;
      }
      _repo.gravar(lote, notificar: notificar);
      consumos.add(
        LoteConsumoSnapshot(
          loteId: lote.id,
          numeroLote: lote.numeroLote,
          dataValidade: lote.dataValidade,
          quantidade: usar,
        ),
      );
      restante -= usar;
    }
    if (restante > 0) {
      // Saldo sem lote suficiente: cria consumo sintetico (estoque fisico ainda
      // sera abatido pelo GerenciadorEstoque).
      consumos.add(
        LoteConsumoSnapshot(
          loteId: 0,
          numeroLote: LoteProduto.numeroSemLote,
          dataValidade: null,
          quantidade: restante,
        ),
      );
    }
    return consumos;
  }

  void devolverConsumos(
    Produto produto,
    List<LoteConsumoSnapshot> consumos, {
    bool notificar = true,
  }) {
    if (!produto.controlaLoteValidade || consumos.isEmpty) return;
    for (final c in consumos) {
      if (c.quantidade <= 0) continue;
      if (c.loteId > 0) {
        final lote = _repo.obterPorId(c.loteId);
        if (lote != null) {
          lote.quantidadeEstoque += c.quantidade;
          lote.ativo = true;
          _repo.gravar(lote, notificar: notificar);
          continue;
        }
      }
      _repo.registrarEntrada(
        produto: produto,
        quantidade: c.quantidade,
        numeroLote: c.numeroLote.isEmpty
            ? LoteProduto.numeroSemLote
            : c.numeroLote,
        dataValidade: c.dataValidade,
        notificar: notificar,
      );
    }
  }

  String rotuloRetiradaPatio(List<LoteConsumoSnapshot> consumos) =>
      formatarRotuloRetiradaPatio(consumos);

  static String formatarRotuloRetiradaPatio(List<LoteConsumoSnapshot> consumos) {
    if (consumos.isEmpty) return '';
    final partes = <String>[];
    for (final c in consumos) {
      final val = c.dataValidade;
      final valTxt = val == null
          ? 'sem validade'
          : '${val.day.toString().padLeft(2, '0')}/'
              '${val.month.toString().padLeft(2, '0')}/'
              '${val.year}';
      partes.add(
        'LOTE: ${c.numeroLote} (Validade: $valTxt)'
        '${c.quantidade > 0 ? ' x${c.quantidade}' : ''}',
      );
    }
    return 'Retirar do ${partes.join(' | ')}';
  }
}
