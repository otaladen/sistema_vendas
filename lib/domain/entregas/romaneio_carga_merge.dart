import '../../data/api/lan_api_client.dart';
import '../../data/lote_produto_repository.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../services/lote_fefo_service.dart';
import '../entrega_venda_helper.dart';
import '../produto_embalagem.dart';
import 'carreto_saida_produto_orfao.dart';

/// Linha consolidada da carga no patio (romaneio / conferencia).
class RomaneioCargaLinha {
  const RomaneioCargaLinha({
    required this.chaveMerge,
    required this.nomeProduto,
    required this.codigoSku,
    required this.unidade,
    required this.quantidadeTotal,
    this.escalaFracionada = false,
    this.rotuloLote = '',
    this.produtoNaoEncontradoNoCadastro = false,
  });

  final String chaveMerge;
  final String nomeProduto;
  final String codigoSku;
  final String unidade;

  /// Soma persistida (pode estar em milésimos se [escalaFracionada]).
  final int quantidadeTotal;

  /// Produto fracionado / CX→m²: [quantidadeTotal] esta em milésimos.
  final bool escalaFracionada;

  /// Texto FEFO para separacao (ex.: "Retirar do LOTE: ...").
  final String rotuloLote;

  /// Item de venda aponta para produto excluido — exibir alerta e usar snapshot.
  final bool produtoNaoEncontradoNoCadastro;

  /// Qtd para UI/PDF (2; 18,9) — nao o inteiro bruto 2000/18900.
  String get quantidadeTotalTexto =>
      EntregaVendaHelper.formatarQuantidadeRomaneioConsolidada(
        quantidadeTotal,
        escalaFracionada: escalaFracionada,
      );
}

/// Soma quantidades por produto para romaneio e conferencia de carga.
abstract final class RomaneioCargaMerge {
  RomaneioCargaMerge._();

  static String chaveMergeDeItem(ItemVenda item) {
    var pid = 0;
    try {
      pid = item.produto.targetId;
    } catch (_) {
      pid = 0;
    }
    if (pid > 0) return 'p:$pid';
    return 'n:${item.nomeProduto.trim().toLowerCase()}';
  }

  /// Itens sem depender de ToMany detached (terminal leve / API).
  static List<ItemVenda> itensDaVendaSafe(
    Venda v, {
    List<ItemVenda> Function(Venda venda)? resolver,
  }) {
    if (resolver != null) {
      try {
        final via = resolver(v);
        if (via.isNotEmpty) return via;
      } catch (_) {}
    }
    try {
      final anexos = LanApiClient.itensExtraidos[v];
      if (anexos != null && anexos.isNotEmpty) {
        return List<ItemVenda>.from(anexos);
      }
    } catch (_) {}
    try {
      final locais = v.itens.toList();
      if (locais.isNotEmpty) return locais;
    } catch (_) {}
    return const [];
  }

  static String _rotuloLoteItem(ItemVenda item) {
    final consumos = LoteConsumoSnapshot.decodeList(item.loteConsumosJson);
    if (consumos.isEmpty) return '';
    return LoteFefoService.formatarRotuloRetiradaPatio(consumos);
  }

  static List<RomaneioCargaLinha> montarLinhas(
    List<Venda> vendasGrupo, {
    List<ItemVenda> Function(Venda venda)? itensDaVenda,
    Produto? Function(int id)? obterProduto,
  }) {
    final acumulado = <String, RomaneioCargaLinha>{};
    for (final v in vendasGrupo) {
      final itens = itensDaVendaSafe(v, resolver: itensDaVenda);
      for (final item in itens) {
        final q = EntregaVendaHelper.quantidadeRomaneioCarga(
          v,
          item,
          itens: itens,
        );
        if (q <= 0) continue;
        final chave = chaveMergeDeItem(item);
        final orfao = RomaneioProdutoOrfaoHelper.itemOrfao(
          item,
          obterProduto: obterProduto,
        );
        // Nao ler produto.target em entidade detached (terminal leve).
        Produto? p;
        try {
          p = item.produto.target;
        } catch (_) {
          p = null;
        }
        if (orfao) {
          p = null;
        }
        final nomeProdutoAlvo = p?.nome.trim() ?? '';
        final nome = orfao
            ? RomaneioProdutoOrfaoHelper.nomeSnapshot(item)
            : (nomeProdutoAlvo.isNotEmpty
                ? nomeProdutoAlvo
                : item.nomeProduto.trim());
        final skuAlvo = p?.codigoInterno.trim() ?? '';
        final sku = skuAlvo.isNotEmpty ? skuAlvo : '-';
        final un = orfao
            ? RomaneioProdutoOrfaoHelper.unidadeSnapshot(
                item,
                obterProduto: obterProduto,
              )
            : ProdutoEmbalagem.normalizarUnidade(p?.unidade);
        final rotuloLote = _rotuloLoteItem(item);
        final escala = orfao
            ? false
            : EntregaVendaHelper.quantidadeRomaneioUsaEscalaFracionada(item);
        final prev = acumulado[chave];
        if (prev == null) {
          acumulado[chave] = RomaneioCargaLinha(
            chaveMerge: chave,
            nomeProduto: nome,
            codigoSku: sku,
            unidade: un,
            quantidadeTotal: q,
            escalaFracionada: escala,
            rotuloLote: rotuloLote,
            produtoNaoEncontradoNoCadastro: orfao,
          );
        } else {
          final rotulos = <String>{
            if (prev.rotuloLote.trim().isNotEmpty) prev.rotuloLote.trim(),
            if (rotuloLote.trim().isNotEmpty) rotuloLote.trim(),
          };
          acumulado[chave] = RomaneioCargaLinha(
            chaveMerge: chave,
            nomeProduto: prev.nomeProduto,
            codigoSku: prev.codigoSku,
            unidade: prev.unidade,
            quantidadeTotal: prev.quantidadeTotal + q,
            escalaFracionada: prev.escalaFracionada || escala,
            rotuloLote: rotulos.join(' | '),
            produtoNaoEncontradoNoCadastro:
                prev.produtoNaoEncontradoNoCadastro || orfao,
          );
        }
      }
    }
    final lista = acumulado.values.toList()
      ..sort(
        (a, b) =>
            a.nomeProduto.toLowerCase().compareTo(b.nomeProduto.toLowerCase()),
      );
    return lista;
  }
}
