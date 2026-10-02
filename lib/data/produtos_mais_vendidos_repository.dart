import '../domain/relatorio_vendas_service.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../ui/relatorios/relatorio_helpers.dart';
import '../ui/relatorios/relatorio_periodo.dart';
import 'venda_repository.dart';

/// Linha agregada do ranking de produtos mais vendidos.
class ProdutoMaisVendidoLinha {
  ProdutoMaisVendidoLinha({
    required this.nome,
    required this.produtoId,
  });

  final String nome;
  final int produtoId;
  double quantidade = 0;
  double faturamentoTotal = 0;
  double lucro = 0;
  bool margemIrreal = false;

  double get margemPercentual => RelatorioVendasService.margemPercentual(
        faturamentoTotal: faturamentoTotal,
        lucro: lucro,
      );
}

/// Agrega vendas finalizadas e deltas de devolucao/troca para o ranking.
class ProdutosMaisVendidosRepository {
  const ProdutosMaisVendidosRepository({
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final dynamic vendaRepository;
  final dynamic produtoRepository;

  Produto? _produto(int produtoId) =>
      produtoId > 0 ? produtoRepository.obterPorId(produtoId) as Produto? : null;

  Map<String, ProdutoMaisVendidoLinha> agregarPeriodo(LimitesPeriodo limites) {
    final map = <String, ProdutoMaisVendidoLinha>{};
    final vendas =
        relatorioVendasFinalizadasPeriodo(vendaRepository, limites);
    for (final Venda v in vendas) {
      for (final item in relatorioItensDaVenda(vendaRepository, v)) {
        _acumularItem(map, item);
      }
    }
    final deltas = (vendaRepository.listarDeltasProdutosDevolucaoPeriodo(
          relatorioPeriodoFiltro(limites),
        ) as List)
        .cast<DeltaProdutoDevolucao>();
    for (final d in deltas) {
      map.putIfAbsent(
        d.chaveAgg,
        () => ProdutoMaisVendidoLinha(
          nome: d.nomeExibicao,
          produtoId: d.produtoId,
        ),
      );
      final linha = map[d.chaveAgg]!;
      final prod = _produto(d.produtoId);
      linha.quantidade += RelatorioVendasService.deltaQuantidadeReal(
        deltaQuantidadeArmazenada: d.deltaQuantidade,
        produto: prod,
      );
      linha.faturamentoTotal += d.deltaValor;
    }
    return map;
  }

  List<ProdutoMaisVendidoLinha> listarRanking(
    LimitesPeriodo limites, {
    String ordenarPor = 'quantidade',
  }) {
    final lista = agregarPeriodo(limites)
        .values
        .where((a) => a.quantidade > 0)
        .toList();
    switch (ordenarPor) {
      case 'valor':
        lista.sort((a, b) => b.faturamentoTotal.compareTo(a.faturamentoTotal));
      case 'lucro':
        lista.sort((a, b) => b.lucro.compareTo(a.lucro));
      default:
        lista.sort((a, b) => b.quantidade.compareTo(a.quantidade));
    }
    return lista;
  }

  void _acumularItem(Map<String, ProdutoMaisVendidoLinha> map, ItemVenda item) {
    final pid = item.produto.targetId;
    final chave = pid > 0 ? 'id:$pid' : 'nome:${item.nomeProduto}';
    final prod = _produto(pid);
    final nome = pid > 0 ? (prod?.nome ?? item.nomeProduto) : item.nomeProduto;
    map.putIfAbsent(
      chave,
      () => ProdutoMaisVendidoLinha(nome: nome, produtoId: pid),
    );
    final linha = map[chave]!;
    final m = RelatorioVendasService.metricasItemVenda(item: item, produto: prod);
    linha.quantidade += m.quantidadeReal;
    linha.faturamentoTotal += m.faturamentoTotal;
    linha.lucro += m.lucro;
    linha.margemIrreal = linha.margemIrreal || m.margemIrreal;
  }
}
