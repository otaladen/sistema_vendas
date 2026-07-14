import '../../data/venda_repository.dart';
import '../../model/registro_devolucao.dart';

/// Linha agregada por produto em devolucoes/trocas.
class DevolucaoProdutoResumoLinha {
  DevolucaoProdutoResumoLinha({
    required this.chave,
    required this.nome,
    this.produtoId = 0,
    this.quantidade = 0,
    this.valor = 0,
    this.registros = 0,
  });

  final String chave;
  final String nome;
  final int produtoId;
  int quantidade;
  double valor;
  int registros;
}

/// Linha detalhada por registro de devolucao/troca.
class DevolucaoDetalheLinha {
  const DevolucaoDetalheLinha({
    required this.data,
    required this.tipo,
    required this.motivo,
    required this.cliente,
    required this.numeroVenda,
    required this.produto,
    required this.quantidade,
    required this.valor,
    required this.registradoPor,
    required this.impactoFaturamento,
  });

  final DateTime data;
  final String tipo;
  final String motivo;
  final String cliente;
  final int numeroVenda;
  final String produto;
  final int quantidade;
  final double valor;
  final String registradoPor;
  final double impactoFaturamento;
}

List<DevolucaoDetalheLinha> montarDetalhesDevolucao(
  VendaRepository repo,
  List<RegistroDevolucao> registros,
) {
  final linhas = <DevolucaoDetalheLinha>[];
  for (final r in registros) {
    final venda = r.vendaOrigem.target;
    final cliente = venda?.cliente.target?.nomeRazao ?? 'Sem cliente';
    final numero = venda?.numeroOrcamento ?? 0;
    final impacto = repo.impactoFaturamentoRegistro(r);
    if (r.tipo == 'troca') {
      for (final l in r.linhasEntrada) {
        final nome = l.nomeProdutoSnapshot.trim().isNotEmpty
            ? l.nomeProdutoSnapshot
            : (l.produto.target?.nome ?? 'Produto');
        linhas.add(
          DevolucaoDetalheLinha(
            data: r.data.toLocal(),
            tipo: 'Troca (entrada)',
            motivo: r.motivo,
            cliente: cliente,
            numeroVenda: numero,
            produto: nome,
            quantidade: l.quantidade,
            valor: l.quantidade * l.precoUnitarioReferencia,
            registradoPor: r.registradoPor,
            impactoFaturamento: impacto,
          ),
        );
      }
      for (final l in r.linhasSaidaTroca) {
        final nome = l.nomeProdutoSnapshot.trim().isNotEmpty
            ? l.nomeProdutoSnapshot
            : (l.produto.target?.nome ?? 'Produto');
        linhas.add(
          DevolucaoDetalheLinha(
            data: r.data.toLocal(),
            tipo: 'Troca (saida)',
            motivo: r.motivo,
            cliente: cliente,
            numeroVenda: numero,
            produto: nome,
            quantidade: l.quantidade,
            valor: l.quantidade * l.precoUnitario,
            registradoPor: r.registradoPor,
            impactoFaturamento: impacto,
          ),
        );
      }
      continue;
    }
    for (final l in r.linhasEntrada) {
      final nome = l.nomeProdutoSnapshot.trim().isNotEmpty
          ? l.nomeProdutoSnapshot
          : (l.produto.target?.nome ?? 'Produto');
      linhas.add(
        DevolucaoDetalheLinha(
          data: r.data.toLocal(),
          tipo: 'Devolucao',
          motivo: r.motivo,
          cliente: cliente,
          numeroVenda: numero,
          produto: nome,
          quantidade: l.quantidade,
          valor: l.quantidade * l.precoUnitarioReferencia,
          registradoPor: r.registradoPor,
          impactoFaturamento: impacto,
        ),
      );
    }
  }
  linhas.sort((a, b) => b.data.compareTo(a.data));
  return linhas;
}

List<DevolucaoProdutoResumoLinha> agregarDevolucoesPorProduto(
  List<DevolucaoDetalheLinha> detalhes,
) {
  final map = <String, DevolucaoProdutoResumoLinha>{};
  for (final d in detalhes) {
    if (!d.tipo.startsWith('Devolucao') && !d.tipo.contains('entrada')) {
      continue;
    }
    final chave = d.produto.toLowerCase();
    map.putIfAbsent(
      chave,
      () => DevolucaoProdutoResumoLinha(chave: chave, nome: d.produto),
    );
    final a = map[chave]!;
    a.quantidade += d.quantidade;
    a.valor += d.valor;
    a.registros++;
  }
  final lista = map.values.toList()
    ..sort((a, b) => b.quantidade.compareTo(a.quantidade));
  return lista;
}

double totalValorDevolucoes(List<DevolucaoDetalheLinha> detalhes) =>
    detalhes
        .where((d) => d.tipo == 'Devolucao' || d.tipo.contains('entrada'))
        .fold<double>(0, (s, d) => s + d.valor);
