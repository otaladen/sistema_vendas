import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import 'loja_origem_mercadoria.dart';

/// Motorista na outra loja pede para buscar o item nesta prateleira.
///
/// Nao misturar com complemento (falta na casa do cliente).
abstract final class BuscarNaLoja {
  BuscarNaLoja._();

  static const solicitar = 'solicitar';
  static const confirmar = 'confirmar';
  static const cancelar = 'cancelar';

  static const solicitado = 'solicitado';
  static const separado = 'separado';

  static bool ehSolicitado(String? status) =>
      (status ?? '').trim() == solicitado;

  static bool ehSeparado(String? status) => (status ?? '').trim() == separado;

  static bool temPendente(Venda venda, [Iterable<ItemVenda>? itens]) {
    for (final item in itens ?? _itens(venda)) {
      if (ehSolicitado(item.buscarNaLojaStatus)) return true;
    }
    return false;
  }

  static int contarPedidosPendentes(
    Iterable<Venda> vendas, [
    Iterable<ItemVenda> Function(Venda venda)? itensDe,
  ]) {
    var n = 0;
    for (final v in vendas) {
      if (temPendente(v, itensDe?.call(v))) n++;
    }
    return n;
  }

  static List<ItemVenda> pendentesDaVenda(
    Venda venda, [
    Iterable<ItemVenda>? itens,
  ]) {
    return [
      for (final item in itens ?? _itens(venda))
        if (ehSolicitado(item.buscarNaLojaStatus)) item,
    ];
  }

  static String? resumoPendentes(Venda venda, [Iterable<ItemVenda>? itens]) {
    final linhas = <String>[];
    for (final item in pendentesDaVenda(venda, itens)) {
      linhas.add('${rotuloQuantidade(venda, item)} ${item.nomeProduto}');
    }
    if (linhas.isEmpty) return null;
    return 'Buscar nesta loja: ${linhas.join('; ')}';
  }

  static bool podeSolicitarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    if (!EntregaVendaHelper.itemEntraNaCargaEntrega(venda, item)) return false;
    if (_qtd(venda, item) <= 0) return false;
    if (ehSeparado(item.buscarNaLojaStatus)) return false;
    final origem = LojaOrigemMercadoria.origemEfetiva(
      origemItem: item.lojaOrigemMercadoria,
      origemVenda: venda.lojaOrigemMercadoria,
      cargaSaiu: venda.cargaSaiu,
    );
    return !LojaOrigemMercadoria.ehLocal(origem);
  }

  static bool podeCancelarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    return ehSolicitado(item.buscarNaLojaStatus) ||
        ehSeparado(item.buscarNaLojaStatus);
  }

  static bool _entregaAberta(Venda venda) {
    if (venda.cancelada) return false;
    switch (venda.statusEntrega) {
      case 'entregue':
      case 'entregue_complemento_pendente':
      case 'cancelada':
        return false;
      default:
        return true;
    }
  }

  static int qtdCarga(Venda venda, ItemVenda item) => _qtd(venda, item);

  static int clampQuantidade(Venda venda, ItemVenda item, int quantidade) {
    final max = qtdCarga(venda, item);
    if (max <= 0) return 0;
    if (quantidade < 1) return 1;
    if (quantidade > max) return max;
    return quantidade;
  }

  static String rotuloQuantidade(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    final q = quantidadeEfetiva(venda, item);
    if (q >= total) return '${total}x';
    return '$q de $total';
  }

  static int quantidadeEfetiva(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    if (total <= 0) return 0;
    if (item.quantidadeBuscarNaLoja <= 0) return total;
    return item.quantidadeBuscarNaLoja.clamp(1, total);
  }

  /// Confirmar no patio: linha inteira = desta loja; recorte = misto.
  static String origemAposConfirmar(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    final q = quantidadeEfetiva(venda, item);
    if (total > 0 && q < total) return LojaOrigemMercadoria.misto;
    return LojaOrigemMercadoria.local;
  }

  static Map<int, int> parseQuantidades(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, int>{};
    raw.forEach((k, v) {
      final id = int.tryParse(k.toString()) ?? 0;
      if (id <= 0) return;
      final q = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      if (q > 0) out[id] = q;
    });
    return out;
  }

  static int _qtd(Venda venda, ItemVenda item) {
    return item.quantidadeParaExibicaoEntrega(
      EntregaVendaHelper.vendaTemItensMigradosRetiradaParaCarreto(venda),
      carretoReservaNativoAntesSaida:
          venda.carretoReservaAteSaida && !venda.cargaSaiu,
    );
  }

  static Iterable<ItemVenda> _itens(Venda venda) {
    try {
      return venda.itens;
    } catch (_) {
      return const <ItemVenda>[];
    }
  }
}
