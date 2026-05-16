import '../../model/item_venda.dart';
import '../../model/venda.dart';

/// Linha da carga total consolidada de um grupo (mesmo carro) no romaneio.
class RomaneioCargaConsolidadaLinha {
  const RomaneioCargaConsolidadaLinha({
    required this.chaveMerge,
    required this.nomeProduto,
    required this.codigoSku,
    required this.unidade,
    required this.quantidadeTotal,
  });

  /// Chave interna para UI (checkbox de conferencia).
  final String chaveMerge;
  final String nomeProduto;
  final String codigoSku;
  final String unidade;
  final int quantidadeTotal;
}

/// Percorre [vendasGrupo] (mesmo `grupoEntregaFreteId`), soma quantidades por produto
/// usando a mesma regra de quantidade da tela de entregas ([quantidadeEntrega]).
List<RomaneioCargaConsolidadaLinha> romaneioMergeCargaGrupo(
  List<Venda> vendasGrupo,
  int Function(Venda venda, ItemVenda item) quantidadeEntrega,
) {
  final acumulado = <String, RomaneioCargaConsolidadaLinha>{};
  for (final v in vendasGrupo) {
    for (final item in v.itens) {
      final q = quantidadeEntrega(v, item);
      if (q <= 0) continue;
      final pid = item.produto.targetId;
      final chave = pid > 0 ? 'p:$pid' : 'n:${item.nomeProduto.trim().toLowerCase()}';
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
        acumulado[chave] = RomaneioCargaConsolidadaLinha(
          chaveMerge: chave,
          nomeProduto: nome,
          codigoSku: sku,
          unidade: un,
          quantidadeTotal: q,
        );
      } else {
        acumulado[chave] = RomaneioCargaConsolidadaLinha(
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
      (a, b) => a.nomeProduto.toLowerCase().compareTo(b.nomeProduto.toLowerCase()),
    );
  return lista;
}
