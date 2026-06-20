import '../../model/venda.dart';
import '../entrega_venda_helper.dart';

/// Linha consolidada da carga no patio (romaneio / conferencia).
class RomaneioCargaLinha {
  const RomaneioCargaLinha({
    required this.chaveMerge,
    required this.nomeProduto,
    required this.codigoSku,
    required this.unidade,
    required this.quantidadeTotal,
  });

  final String chaveMerge;
  final String nomeProduto;
  final String codigoSku;
  final String unidade;
  final int quantidadeTotal;
}

/// Soma quantidades por produto para romaneio e conferencia de carga.
abstract final class RomaneioCargaMerge {
  RomaneioCargaMerge._();

  static List<RomaneioCargaLinha> montarLinhas(List<Venda> vendasGrupo) {
    final acumulado = <String, RomaneioCargaLinha>{};
    for (final v in vendasGrupo) {
      for (final item in v.itens) {
        final q = EntregaVendaHelper.quantidadeRomaneioCarga(v, item);
        if (q <= 0) continue;
        final pid = item.produto.targetId;
        final chave = pid > 0
            ? 'p:$pid'
            : 'n:${item.nomeProduto.trim().toLowerCase()}';
        final p = item.produto.target;
        final nome = (p?.nome.trim().isNotEmpty == true)
            ? p!.nome.trim()
            : item.nomeProduto.trim();
        final sku = (p?.codigoInterno.trim().isNotEmpty == true)
            ? p!.codigoInterno.trim()
            : '-';
        var un = (p?.unidade ?? 'UN').trim();
        if (un.isEmpty) un = 'UN';
        un = un.toUpperCase();
        final prev = acumulado[chave];
        if (prev == null) {
          acumulado[chave] = RomaneioCargaLinha(
            chaveMerge: chave,
            nomeProduto: nome,
            codigoSku: sku,
            unidade: un,
            quantidadeTotal: q,
          );
        } else {
          acumulado[chave] = RomaneioCargaLinha(
            chaveMerge: chave,
            nomeProduto: prev.nomeProduto,
            codigoSku: prev.codigoSku,
            unidade: prev.unidade,
            quantidadeTotal: prev.quantidadeTotal + q,
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
