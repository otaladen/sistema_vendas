import '../../domain/entrega_venda_helper.dart';
import '../../model/venda.dart';

/// Tipo de pendencia operacional exibida no relatorio.
enum TipoPendenciaEntregaRelatorio {
  todas,
  retiradaFutura,
  carreto,
}

/// Linha de item pendente de retirada ou carreto.
class LinhaPendenciaEntregaRelatorio {
  const LinhaPendenciaEntregaRelatorio({
    required this.vendaId,
    required this.numeroOrcamento,
    required this.cliente,
    required this.produto,
    required this.codigoProduto,
    required this.quantidadePendente,
    required this.dataVenda,
    required this.tipo,
    required this.statusEntrega,
    this.dataEntregaMarcada,
    this.vendedor = '',
  });

  final int vendaId;
  final int numeroOrcamento;
  final String cliente;
  final String produto;
  final String codigoProduto;
  final int quantidadePendente;
  final DateTime dataVenda;
  final String tipo;
  final String statusEntrega;
  final DateTime? dataEntregaMarcada;
  final String vendedor;
}

String rotuloTipoPendenciaEntrega(String tipo) {
  switch (tipo) {
    case EntregaVendaHelper.tipoRetiradaFutura:
      return 'Retirada futura';
    case EntregaVendaHelper.tipoEntregaLoja:
      return 'Carreto';
    default:
      return tipo;
  }
}

List<LinhaPendenciaEntregaRelatorio> montarLinhasPendenciaEntrega(
  List<Venda> vendas, {
  required TipoPendenciaEntregaRelatorio filtroTipo,
}) {
  final linhas = <LinhaPendenciaEntregaRelatorio>[];
  for (final v in vendas) {
    if (v.cancelada || v.status != 'finalizada' || !v.entregaPendente) {
      continue;
    }
    final cliente = v.cliente.target?.nomeRazao ?? 'Sem cliente';
    final vendedor = v.vendedor.target?.nomeCompleto ?? '';
    for (final item in v.itens) {
      final tipoItem = EntregaVendaHelper.tipoEfetivoItem(item);
      var qtd = 0;
      if (tipoItem == EntregaVendaHelper.tipoRetiradaFutura) {
        qtd = item.quantidadePendenteRetirada;
      } else if (tipoItem == EntregaVendaHelper.tipoEntregaLoja) {
        qtd = item.quantidadeNoCarreto;
        if (qtd <= 0) {
          qtd =
              item.quantidade -
              item.quantidadeDevolvida -
              item.quantidadeJaRetirada;
          if (qtd < 0) qtd = 0;
        }
      }
      if (qtd <= 0) continue;

      final tipoLinha = tipoItem == EntregaVendaHelper.tipoRetiradaFutura
          ? EntregaVendaHelper.tipoRetiradaFutura
          : EntregaVendaHelper.tipoEntregaLoja;

      switch (filtroTipo) {
        case TipoPendenciaEntregaRelatorio.retiradaFutura:
          if (tipoLinha != EntregaVendaHelper.tipoRetiradaFutura) continue;
        case TipoPendenciaEntregaRelatorio.carreto:
          if (tipoLinha != EntregaVendaHelper.tipoEntregaLoja) continue;
        case TipoPendenciaEntregaRelatorio.todas:
          break;
      }

      final produto = item.produto.target;
      linhas.add(
        LinhaPendenciaEntregaRelatorio(
          vendaId: v.id,
          numeroOrcamento: v.numeroOrcamento,
          cliente: cliente,
          produto: produto?.nome ?? item.nomeProduto,
          codigoProduto: produto?.codigoInterno ?? '',
          quantidadePendente: qtd,
          dataVenda: v.data.toLocal(),
          tipo: tipoLinha,
          statusEntrega: v.statusEntrega,
          dataEntregaMarcada: v.dataEntregaMarcada?.toLocal(),
          vendedor: vendedor,
        ),
      );
    }
  }
  linhas.sort((a, b) {
    final da = a.dataEntregaMarcada ?? a.dataVenda;
    final db = b.dataEntregaMarcada ?? b.dataVenda;
    return da.compareTo(db);
  });
  return linhas;
}

int totalUnidadesPendencia(List<LinhaPendenciaEntregaRelatorio> linhas) =>
    linhas.fold<int>(0, (s, l) => s + l.quantidadePendente);
