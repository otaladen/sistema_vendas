import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import 'cargas_entrega.dart';

/// Recorte da venda para a viagem em andamento quando ha plano de cargas.
///
/// Sem plano (ou com todas as cargas entregues) nada e limitado: as regras
/// antigas de linha inteira continuam valendo.
abstract final class CargaAtualVenda {
  CargaAtualVenda._();

  static String _cacheJson = '';
  static List<CargaEntrega> _cacheCargas = const [];

  static List<CargaEntrega> cargas(Venda venda) {
    final raw = venda.cargasEntregaJson;
    if (raw.isEmpty) return const [];
    if (raw != _cacheJson) {
      _cacheCargas = CargasEntregaCodec.decode(raw);
      _cacheJson = raw;
    }
    return _cacheCargas;
  }

  static CargaEntrega? atual(Venda venda) =>
      CargasEntregaHelper.cargaAtual(cargas(venda));

  /// "Carga 2/3" ou null sem plano.
  static String? rotulo(Venda venda) =>
      CargasEntregaHelper.rotuloCargaAtual(cargas(venda));

  static bool _entraNaCarga(ItemVenda item) =>
      EntregaVendaHelper.itemMigradoRetiradaFuturaParaCarreto(item) ||
      EntregaVendaHelper.tipoEfetivoItem(item) ==
          EntregaVendaHelper.tipoEntregaLoja;

  static int _produtoId(ItemVenda item) {
    try {
      return item.produto.targetId;
    } catch (_) {
      return 0;
    }
  }

  static List<ItemVenda> _itensDaVenda(
    Venda venda,
    ItemVenda item,
    Iterable<ItemVenda>? itens,
  ) {
    if (itens != null) {
      final l = itens.toList();
      if (l.any((i) => i.id == item.id)) return l;
    }
    try {
      final l = List<ItemVenda>.from(venda.itens);
      if (l.any((i) => i.id == item.id)) return l;
    } catch (_) {}
    return [item];
  }

  /// itemVendaId -> fracao (0..1) da linha que pertence a [cargasAlvo]
  /// (padrao: so a carga atual). Null = venda sem plano ou sem carga pendente.
  static Map<int, double>? fracaoPorItem(
    Venda venda,
    Iterable<ItemVenda> itens, {
    bool Function(CargaEntrega carga)? incluir,
  }) {
    final todas = cargas(venda);
    final atualCarga = CargasEntregaHelper.cargaAtual(todas);
    if (atualCarga == null) return null;
    final filtro = incluir ?? (c) => c.numero == atualCarga.numero;
    final ordenados = itens.where(_entraNaCarga).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final linhas = [
      for (final i in ordenados)
        LinhaVendaCarreto(
          itemVendaId: i.id,
          produtoId: _produtoId(i),
          quantidade: i.quantidadeVendaEfetiva,
        ),
    ];
    final alocacao = CargasEntregaHelper.alocarPorLinha(
      cargas: todas,
      linhas: linhas,
    );
    final out = <int, double>{};
    for (final l in linhas) {
      var soma = 0.0;
      for (var k = 0; k < todas.length; k++) {
        if (!filtro(todas[k])) continue;
        soma += alocacao[k][l.itemVendaId] ?? 0;
      }
      final f = l.quantidade <= 0 ? 0.0 : soma / l.quantidade;
      out[l.itemVendaId] = f > 1 ? 1.0 : f;
    }
    return out;
  }

  /// Limita [quantidade] ao recorte da carga atual. [base] e o total da
  /// linha na mesma unidade de [quantidade] (estoque ou armazenada).
  static int limitar({
    required Venda venda,
    required ItemVenda item,
    required int quantidade,
    required int base,
    Iterable<ItemVenda>? itens,
    Map<int, double>? fracoes,
  }) {
    if (quantidade <= 0) return quantidade;
    final f = fracoes ??
        fracaoPorItem(venda, _itensDaVenda(venda, item, itens));
    if (f == null) return quantidade;
    final cap = ((f[item.id] ?? 0) * base).round();
    return quantidade < cap ? quantidade : cap;
  }

  /// Quantidade gravada (escala do item) que segue nesta viagem.
  static int limitarArmazenada(
    Venda venda,
    ItemVenda item,
    int quantidade, {
    Iterable<ItemVenda>? itens,
  }) =>
      limitar(
        venda: venda,
        item: item,
        quantidade: quantidade,
        base: item.quantidade,
        itens: itens,
      );

  /// Unidades de estoque que seguem nesta viagem.
  static int limitarEstoque(
    Venda venda,
    ItemVenda item,
    int quantidade, {
    Iterable<ItemVenda>? itens,
  }) =>
      limitar(
        venda: venda,
        item: item,
        quantidade: quantidade,
        base: item.quantidadeUnidadeEstoque,
        itens: itens,
      );
}
