import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/estoque/tipo_movimento_estoque.dart';
import 'package:sistema_vendas/domain/relatorios/movimentacao_estoque_relatorio.dart';
import 'package:sistema_vendas/model/movimento_estoque.dart';
import 'package:sistema_vendas/model/produto.dart';

MovimentoEstoque _mov({
  required int produtoId,
  required String tipo,
  required int deltaFisico,
  required int saldoAntes,
  required int saldoDepois,
  DateTime? quando,
}) {
  final m = MovimentoEstoque(
    tipoMovimento: tipo,
    deltaFisico: deltaFisico,
    saldoFisicoAntes: saldoAntes,
    saldoFisicoDepois: saldoDepois,
    registradoEm: quando ?? DateTime(2026, 6, 10, 12),
  );
  m.produto.targetId = produtoId;
  return m;
}

void main() {
  final produto = Produto(
    id: 1,
    codigoInterno: 'A1',
    nome: 'Tubo PVC',
    categoria: 'Hidraulica',
    marca: 'Tigre',
    quantidadeMinima: 0,
    precoCusto: 1,
    precoVenda: 2,
  );
  final Map<int, Produto> produtos = {1: produto};

  test('agrega entradas e saidas por produto', () {
    final movs = [
      _mov(
        produtoId: 1,
        tipo: TipoMovimentoEstoque.entradaNfeCompra.name,
        deltaFisico: 10,
        saldoAntes: 0,
        saldoDepois: 10,
        quando: DateTime(2026, 6, 1),
      ),
      _mov(
        produtoId: 1,
        tipo: TipoMovimentoEstoque.cupomNaoFiscalVenda.name,
        deltaFisico: -3,
        saldoAntes: 10,
        saldoDepois: 7,
        quando: DateTime(2026, 6, 2),
      ),
    ];

    final resumo = agregarMovimentacaoEstoque(
      movimentos: movs,
      produtosPorId: produtos,
      agrupamento: AgrupamentoMovimentacaoEstoque.produto,
      natureza: FiltroNaturezaMovimentacaoEstoque.todas,
    );

    expect(resumo, hasLength(1));
    expect(resumo.first.entradas, 10);
    expect(resumo.first.saidas, 3);
    expect(resumo.first.saldoInicial, 0);
    expect(resumo.first.saldoFinal, 7);
  });

  test('agrupa por categoria', () {
    final movs = [
      _mov(
        produtoId: 1,
        tipo: TipoMovimentoEstoque.ajusteManual.name,
        deltaFisico: 2,
        saldoAntes: 5,
        saldoDepois: 7,
      ),
    ];

    final resumo = agregarMovimentacaoEstoque(
      movimentos: movs,
      produtosPorId: produtos,
      agrupamento: AgrupamentoMovimentacaoEstoque.categoria,
      natureza: FiltroNaturezaMovimentacaoEstoque.todas,
    );

    expect(resumo.single.rotulo, 'Hidraulica');
    expect(resumo.single.entradas, 2);
  });

  test('filtro devolucoes ignora vendas', () {
    final movs = [
      _mov(
        produtoId: 1,
        tipo: TipoMovimentoEstoque.devolucaoCliente.name,
        deltaFisico: 1,
        saldoAntes: 4,
        saldoDepois: 5,
      ),
      _mov(
        produtoId: 1,
        tipo: TipoMovimentoEstoque.cupomNaoFiscalVenda.name,
        deltaFisico: -2,
        saldoAntes: 5,
        saldoDepois: 3,
      ),
    ];

    final resumo = agregarMovimentacaoEstoque(
      movimentos: movs,
      produtosPorId: produtos,
      agrupamento: AgrupamentoMovimentacaoEstoque.produto,
      natureza: FiltroNaturezaMovimentacaoEstoque.devolucoes,
    );

    expect(resumo, hasLength(1));
    expect(resumo.first.entradas, 1);
    expect(resumo.first.saidas, 0);
  });
}
