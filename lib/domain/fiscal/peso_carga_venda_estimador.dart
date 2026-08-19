import '../entrega_venda_helper.dart';
import '../entregas/romaneio_carga_merge.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';

/// Estimativa de volumes e peso bruto para NF-e / romaneio (sem alterar estoque).
class EstimativaCargaVenda {
  const EstimativaCargaVenda({
    required this.volumes,
    required this.pesoBrutoKg,
    required this.quantidadeItens,
  });

  final int volumes;
  final double pesoBrutoKg;
  final int quantidadeItens;
}

abstract final class PesoCargaVendaEstimador {
  /// Heuristica por unidade de venda: KG usa quantidade como peso; demais unidades
  /// recebem fator padrao de material de construcao.
  static EstimativaCargaVenda estimar(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    final lista = itens ?? RomaneioCargaMerge.itensDaVendaSafe(venda);
    return _estimarItens(lista.where((i) => i.quantidade > 0));
  }

  /// Peso/volumes apenas dos itens de carreto ou que entram na carga.
  static EstimativaCargaVenda estimarItensComTransporte(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    final lista = itens ?? RomaneioCargaMerge.itensDaVendaSafe(venda);
    final filtrados = lista.where((item) {
      if (item.quantidade <= 0) return false;
      if (EntregaVendaHelper.tipoEfetivoItem(item) ==
          EntregaVendaHelper.tipoEntregaLoja) {
        return true;
      }
      return EntregaVendaHelper.itemEntraNaCargaEntrega(venda, item);
    });
    final est = _estimarItens(filtrados);
    if (est.quantidadeItens > 0) return est;
    return estimar(venda, itens: lista);
  }

  static EstimativaCargaVenda _estimarItens(Iterable<ItemVenda> itens) {
    var volumes = 0;
    var peso = 0.0;
    var qtdItens = 0;

    for (final item in itens) {
      final q = item.quantidade;
      if (q <= 0) continue;
      qtdItens++;
      volumes += q;
      peso += _pesoItemKg(item);
    }

    if (volumes <= 0) {
      volumes = 1;
    }
    if (peso <= 0) {
      peso = volumes.toDouble();
    }

    return EstimativaCargaVenda(
      volumes: volumes,
      pesoBrutoKg: double.parse(peso.toStringAsFixed(3)),
      quantidadeItens: qtdItens,
    );
  }

  static double _pesoItemKg(ItemVenda item) {
    Produto? produto;
    try {
      produto = item.produto.target;
    } catch (_) {
      produto = null;
    }
    final q = item.quantidade;
    if (q <= 0) return 0;
    final un = (produto?.unidade ?? 'UN').trim().toUpperCase();
    switch (un) {
      case 'KG':
        return q.toDouble();
      case 'SC':
        return q * 50;
      case 'CX':
        return q * (produto?.quantidadePorEmbalagem ?? 1) * 8;
      case 'M3':
        return q * 500;
      case 'M2':
        return q * 12;
      case 'M':
        return q * 2.5;
      case 'LT':
        return q * 1.2;
      default:
        return q * 1.0;
    }
  }
}
