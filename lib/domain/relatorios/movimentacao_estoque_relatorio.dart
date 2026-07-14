import '../../domain/estoque/tipo_movimento_estoque.dart';
import '../../model/movimento_estoque.dart';
import '../../model/produto.dart';

export '../../domain/estoque/tipo_movimento_estoque.dart'
    show TipoMovimentoEstoque;

/// Filtro de natureza do movimento para relatorios gerenciais.
enum FiltroNaturezaMovimentacaoEstoque {
  todas,
  entradas,
  saidas,
  devolucoes,
  cancelamentos,
  ajustes,
  reservas,
}

/// Agrupamento do resumo de movimentacao.
enum AgrupamentoMovimentacaoEstoque {
  produto,
  categoria,
  subcategoria,
  marca,
}

/// Linha resumida por produto ou grupo.
class ResumoMovimentacaoEstoqueLinha {
  ResumoMovimentacaoEstoqueLinha({
    required this.chave,
    required this.rotulo,
    this.produtoId = 0,
    this.codigo = '',
    this.entradas = 0,
    this.saidas = 0,
    this.cancelamentos = 0,
    this.saldoInicial = 0,
    this.saldoFinal = 0,
    this.movimentos = 0,
  });

  final String chave;
  final String rotulo;
  final int produtoId;
  final String codigo;
  int entradas;
  int saidas;
  int cancelamentos;
  int saldoInicial;
  int saldoFinal;
  int movimentos;
}

/// Linha detalhada do kardex no periodo.
class DetalheMovimentacaoEstoqueLinha {
  const DetalheMovimentacaoEstoqueLinha({
    required this.registradoEm,
    required this.tipoMovimento,
    required this.deltaFisico,
    required this.deltaReserva,
    required this.saldoFisicoDepois,
    required this.documentoReferencia,
    required this.motivo,
    required this.usuarioLogin,
    required this.produtoId,
    required this.nomeProduto,
    required this.codigoProduto,
  });

  final DateTime registradoEm;
  final String tipoMovimento;
  final int deltaFisico;
  final int deltaReserva;
  final int saldoFisicoDepois;
  final String documentoReferencia;
  final String motivo;
  final String usuarioLogin;
  final int produtoId;
  final String nomeProduto;
  final String codigoProduto;
}

bool movimentacaoEstoqueEhCancelamento(String tipoMovimento) {
  switch (tipoMovimento) {
    case 'cancelamentoVendaEstorno':
    case 'carretoEstornoSaida':
    case 'estornoEntradaNfeCompra':
      return true;
    default:
      return false;
  }
}

bool movimentacaoEstoquePassaFiltroNatureza(
  MovimentoEstoque m, {
  required FiltroNaturezaMovimentacaoEstoque natureza,
}) {
  switch (natureza) {
    case FiltroNaturezaMovimentacaoEstoque.todas:
      return true;
    case FiltroNaturezaMovimentacaoEstoque.entradas:
      return m.deltaFisico > 0 &&
          m.tipoMovimento != TipoMovimentoEstoque.devolucaoCliente.name;
    case FiltroNaturezaMovimentacaoEstoque.saidas:
      return m.deltaFisico < 0 &&
          !movimentacaoEstoqueEhCancelamento(m.tipoMovimento);
    case FiltroNaturezaMovimentacaoEstoque.devolucoes:
      return m.tipoMovimento == TipoMovimentoEstoque.devolucaoCliente.name;
    case FiltroNaturezaMovimentacaoEstoque.cancelamentos:
      return movimentacaoEstoqueEhCancelamento(m.tipoMovimento);
    case FiltroNaturezaMovimentacaoEstoque.ajustes:
      return m.tipoMovimento == TipoMovimentoEstoque.ajusteManual.name;
    case FiltroNaturezaMovimentacaoEstoque.reservas:
      return m.deltaFisico == 0 && m.deltaReserva != 0;
  }
}

String chaveAgrupamentoMovimentacao(
  Produto? produto, {
  required AgrupamentoMovimentacaoEstoque agrupamento,
}) {
  switch (agrupamento) {
    case AgrupamentoMovimentacaoEstoque.produto:
      final id = produto?.id ?? 0;
      return id > 0 ? 'id:$id' : 'sem_produto';
    case AgrupamentoMovimentacaoEstoque.categoria:
      final c = produto?.categoria.trim() ?? '';
      return c.isEmpty ? '(sem categoria)' : c;
    case AgrupamentoMovimentacaoEstoque.subcategoria:
      final s = produto?.subcategoria.trim() ?? '';
      return s.isEmpty ? '(sem subcategoria)' : s;
    case AgrupamentoMovimentacaoEstoque.marca:
      final m = produto?.marca.trim() ?? '';
      return m.isEmpty ? '(sem marca)' : m;
  }
}

String rotuloAgrupamentoMovimentacao(
  Produto? produto, {
  required AgrupamentoMovimentacaoEstoque agrupamento,
}) {
  switch (agrupamento) {
    case AgrupamentoMovimentacaoEstoque.produto:
      if (produto == null) return 'Produto desconhecido';
      final cod = produto.codigoInterno.trim();
      final nome = produto.nome.trim();
      if (cod.isEmpty) return nome;
      return '$cod — $nome';
    case AgrupamentoMovimentacaoEstoque.categoria:
      final c = produto?.categoria.trim() ?? '';
      return c.isEmpty ? '(sem categoria)' : c;
    case AgrupamentoMovimentacaoEstoque.subcategoria:
      final s = produto?.subcategoria.trim() ?? '';
      return s.isEmpty ? '(sem subcategoria)' : s;
    case AgrupamentoMovimentacaoEstoque.marca:
      final m = produto?.marca.trim() ?? '';
      return m.isEmpty ? '(sem marca)' : m;
  }
}

void acumularMovimentacaoResumo(
  ResumoMovimentacaoEstoqueLinha linha,
  MovimentoEstoque m,
) {
  linha.movimentos++;
  if (m.deltaFisico > 0) {
    linha.entradas += m.deltaFisico;
  } else if (m.deltaFisico < 0) {
    linha.saidas += -m.deltaFisico;
  }
  if (movimentacaoEstoqueEhCancelamento(m.tipoMovimento)) {
    linha.cancelamentos += m.deltaFisico.abs();
  }
}

List<ResumoMovimentacaoEstoqueLinha> agregarMovimentacaoEstoque({
  required List<MovimentoEstoque> movimentos,
  required Map<int, Produto> produtosPorId,
  required AgrupamentoMovimentacaoEstoque agrupamento,
  required FiltroNaturezaMovimentacaoEstoque natureza,
  int? produtoIdFiltro,
  bool somenteAtivos = true,
}) {
  final map = <String, ResumoMovimentacaoEstoqueLinha>{};
  final saldoInicialPorChave = <String, int>{};
  final saldoFinalPorChave = <String, int>{};

  final filtrados = movimentos.where((m) {
    if (!movimentacaoEstoquePassaFiltroNatureza(m, natureza: natureza)) {
      return false;
    }
    final pid = m.produto.targetId;
    if (produtoIdFiltro != null && pid != produtoIdFiltro) return false;
    final produto = produtosPorId[pid] ?? m.produto.target;
    if (produto != null && somenteAtivos && !produto.ativo) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.registradoEm.compareTo(b.registradoEm));

  for (final m in filtrados) {
    final pid = m.produto.targetId;
    final produto = produtosPorId[pid] ?? m.produto.target;
    final chave = chaveAgrupamentoMovimentacao(
      produto,
      agrupamento: agrupamento,
    );
    map.putIfAbsent(
      chave,
      () => ResumoMovimentacaoEstoqueLinha(
        chave: chave,
        rotulo: rotuloAgrupamentoMovimentacao(
          produto,
          agrupamento: agrupamento,
        ),
        produtoId: agrupamento == AgrupamentoMovimentacaoEstoque.produto
            ? (produto?.id ?? 0)
            : 0,
        codigo: produto?.codigoInterno ?? '',
      ),
    );
    acumularMovimentacaoResumo(map[chave]!, m);

    saldoInicialPorChave.putIfAbsent(chave, () => m.saldoFisicoAntes);
    saldoFinalPorChave[chave] = m.saldoFisicoDepois;
  }

  for (final e in map.entries) {
    e.value.saldoInicial = saldoInicialPorChave[e.key] ?? 0;
    e.value.saldoFinal = saldoFinalPorChave[e.key] ?? e.value.saldoInicial;
  }

  final lista = map.values.toList();
  lista.sort((a, b) => b.movimentos.compareTo(a.movimentos));
  return lista;
}

List<DetalheMovimentacaoEstoqueLinha> detalharMovimentacaoEstoque({
  required List<MovimentoEstoque> movimentos,
  required Map<int, Produto> produtosPorId,
  required FiltroNaturezaMovimentacaoEstoque natureza,
  int? produtoIdFiltro,
  bool somenteAtivos = true,
}) {
  final linhas = <DetalheMovimentacaoEstoqueLinha>[];
  for (final m in movimentos) {
    if (!movimentacaoEstoquePassaFiltroNatureza(m, natureza: natureza)) {
      continue;
    }
    final pid = m.produto.targetId;
    if (produtoIdFiltro != null && pid != produtoIdFiltro) continue;
    final produto = produtosPorId[pid] ?? m.produto.target;
    if (produto != null && somenteAtivos && !produto.ativo) continue;
    linhas.add(
      DetalheMovimentacaoEstoqueLinha(
        registradoEm: m.registradoEm.toLocal(),
        tipoMovimento: m.tipoMovimento,
        deltaFisico: m.deltaFisico,
        deltaReserva: m.deltaReserva,
        saldoFisicoDepois: m.saldoFisicoDepois,
        documentoReferencia: m.documentoReferencia,
        motivo: m.motivo,
        usuarioLogin: m.usuarioLogin,
        produtoId: pid,
        nomeProduto: produto?.nome ?? 'Produto #$pid',
        codigoProduto: produto?.codigoInterno ?? '',
      ),
    );
  }
  linhas.sort((a, b) => b.registradoEm.compareTo(a.registradoEm));
  return linhas;
}

/// Tipos que alteram estoque fisico (para legenda do relatorio).
List<TipoMovimentoEstoque> tiposMovimentacaoFisicaRelatorio() =>
    TipoMovimentoEstoque.values
        .where(PoliticaMovimentoEstoque.alteraEstoqueFisico)
        .toList();
