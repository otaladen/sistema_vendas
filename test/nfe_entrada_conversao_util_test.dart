import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/custo_medio_entrada_util.dart';
import 'package:sistema_vendas/domain/nfe_entrada_conversao_util.dart';
import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/model/item_nota_temporario.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('fator sugerido usa qTrib/qCom quando uCom difere de uTrib', () {
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'A1',
      descricao: 'Item teste',
      unidadeComercial: 'CX',
      quantidadeComercial: 5,
      valorUnitarioComercial: 120,
      unidadeTributavel: 'UN',
      quantidadeTributavel: 60,
      valorUnitarioTributavel: 10,
    );
    final produto = Produto(
      id: 1,
      codigoInterno: '001',
      nome: 'Produto UN',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    expect(item.fatorComercialParaTributavel, 12);
    expect(
      NfeEntradaConversaoUtil.fatorInicialConferencia(
        item: item,
        produto: produto,
      ),
      12,
    );
  });

  test('fator sugerido reconhece DZ para produto UN', () {
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'B1',
      descricao: 'Item duzia',
      unidadeComercial: 'DZ',
      quantidadeComercial: 3,
      valorUnitarioComercial: 24,
    );
    final produto = Produto(
      id: 2,
      codigoInterno: '002',
      nome: 'Produto UN',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    expect(
      NfeEntradaConversaoUtil.fatorInicialConferencia(
        item: item,
        produto: produto,
      ),
      12,
    );
  });

  test('custo unitario interno inclui IPI rateado e fator x', () {
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'C1',
      descricao: 'Com IPI',
      unidadeComercial: 'CX',
      quantidadeComercial: 2,
      valorUnitarioComercial: 100,
      ipiValor: 20,
    );
    final custo = NfeEntradaConversaoUtil.custoUnitarioInterno(
      item: item,
      fator: 12,
      embalagemMultiplica: true,
    );
    // (100 + 20/2) / 12 = 110/12
    expect(custo, closeTo(110 / 12, 0.0001));
  });

  test('entrada em produto existente nao exige confirmar conversao quando unidades batem', () {
    final produto = Produto(
      id: 3,
      codigoInterno: '003',
      nome: 'Produto UN',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'D1',
      descricao: 'UN na nota',
      unidadeComercial: 'UN',
      quantidadeComercial: 10,
      valorUnitarioComercial: 5,
    );
    expect(
      NfeEntradaConversaoUtil.precisaConfirmarConversaoEmbalagem(
        item: item,
        produto: produto,
        fator: 1,
      ),
      isFalse,
    );
  });

  test('nota CX com fator 6 exige opt-in para gravar conversao no cadastro', () {
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'CX1',
      descricao: 'Produto caixa',
      unidadeComercial: 'CX',
      quantidadeComercial: 5,
      valorUnitarioComercial: 30,
      unidadeTributavel: 'UN',
      quantidadeTributavel: 30,
      valorUnitarioTributavel: 5,
    );
    expect(
      NfeEntradaConversaoUtil.notaExigeConfirmacaoEmbalagem(
        item: item,
        unidadeInterna: 'UN',
        fator: 6,
      ),
      isTrue,
    );
    expect(
      NfeEntradaConversaoUtil.notaExigeConfirmacaoEmbalagem(
        item: item,
        unidadeInterna: 'UN',
        fator: 1,
      ),
      isFalse,
    );
  });

  test('quantidade nota para estoque soma corretamente ao saldo existente', () {
    final produto = Produto(
      id: 4,
      codigoInterno: '004',
      nome: 'Produto UN',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 45,
      precoVenda: 20,
      custoMedio: 45,
      estoqueReal: 49,
    );
    const item = ItemNotaTemporario(
      numeroItem: 1,
      codigo: 'E1',
      descricao: 'Entrada',
      unidadeComercial: 'UN',
      quantidadeComercial: 100,
      valorUnitarioComercial: 32.5,
    );
    final qtdEntrada = ProdutoEmbalagem.quantidadeNotaParaEstoque(
      quantidadeComercial: item.quantidadeComercial,
      fator: 1,
      embalagemMultiplica: true,
      produto: produto,
      unidadeComercial: item.unidadeComercial,
      unidadeInterna: produto.unidade,
    );
    expect(qtdEntrada, 100);
    expect(produto.estoqueReal + qtdEntrada, 149);

    final cm = CustoMedioEntradaUtil.custoMedioAposEntrada(
      estoqueAntes: produto.estoqueReal,
      custoMedioAntes: CustoMedioEntradaUtil.custoReferenciaSaldo(
        custoMedio: produto.custoMedio,
        precoCusto: produto.precoCusto,
      ),
      quantidadeEntrada: qtdEntrada,
      custoUnitarioEntrada: 32.5,
    );
    expect(cm, closeTo(36.61, 0.01));
  });
}
