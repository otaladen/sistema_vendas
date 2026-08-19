import '../../data/api/lan_api_client.dart';
import '../../data/lote_produto_repository.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../../services/lote_fefo_service.dart';
import '../entrega_venda_helper.dart';

/// Linha consolidada da carga no patio (romaneio / conferencia).
class RomaneioCargaLinha {
  const RomaneioCargaLinha({
    required this.chaveMerge,
    required this.nomeProduto,
    required this.codigoSku,
    required this.unidade,
    required this.quantidadeTotal,
    this.rotuloLote = '',
  });

  final String chaveMerge;
  final String nomeProduto;
  final String codigoSku;
  final String unidade;
  final int quantidadeTotal;

  /// Texto FEFO para separacao (ex.: "Retirar do LOTE: ...").
  final String rotuloLote;
}

/// Soma quantidades por produto para romaneio e conferencia de carga.
abstract final class RomaneioCargaMerge {
  RomaneioCargaMerge._();

  static String chaveMergeDeItem(ItemVenda item) {
    final pid = item.produto.targetId;
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
        // Nao ler produto.target em entidade detached (terminal leve).
        dynamic p;
        try {
          p = item.produto.target;
        } catch (_) {
          p = null;
        }
        final nomeProdutoAlvo = (p?.nome as String?)?.trim() ?? '';
        final nome = nomeProdutoAlvo.isNotEmpty
            ? nomeProdutoAlvo
            : item.nomeProduto.trim();
        final skuAlvo = (p?.codigoInterno as String?)?.trim() ?? '';
        final sku = skuAlvo.isNotEmpty ? skuAlvo : '-';
        var un = ((p?.unidade as String?) ?? 'UN').trim();
        if (un.isEmpty) un = 'UN';
        un = un.toUpperCase();
        final rotuloLote = _rotuloLoteItem(item);
        final prev = acumulado[chave];
        if (prev == null) {
          acumulado[chave] = RomaneioCargaLinha(
            chaveMerge: chave,
            nomeProduto: nome,
            codigoSku: sku,
            unidade: un,
            quantidadeTotal: q,
            rotuloLote: rotuloLote,
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
            rotuloLote: rotulos.join(' | '),
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
