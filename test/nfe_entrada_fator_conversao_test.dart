import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/nfe_entrada_conversao_util.dart';
import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('41.9 na nota com fator 1 permanece 41.9 unidades (nao 41900)', () {
    const qNota = 41.9;
    const fator = 1.0;

    final entrada = NfeEntradaConversaoUtil.quantidadeEntradaUnidadeVenda(
      quantidadeNota: qNota,
      fatorConversao: fator,
      embalagemMultiplica: true,
    );
    expect(entrada, closeTo(41.9, 0.0001));

    final produto = Produto(
      id: 1,
      codigoInterno: 'UN01',
      nome: 'Produto UN',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    final armazenado = ProdutoEmbalagem.quantidadeNotaParaEstoque(
      quantidadeComercial: qNota,
      fator: fator,
      embalagemMultiplica: true,
      produto: produto,
      unidadeComercial: 'UN',
      unidadeInterna: 'UN',
    );
    expect(armazenado, 42);

    final rotulo = ProdutoEmbalagem.formatarQuantidadeNotaEstoque(
      estoqueArmazenado: armazenado,
      quantidadeUnidadeVenda: entrada,
      produto: produto,
      unidadeInterna: 'UN',
      comUnidade: true,
    );
    expect(rotulo, '41,9 UN');
  });

  test('parseDecimalTexto aceita virgula e ponto', () {
    expect(NfeEntradaConversaoUtil.parseDecimalTexto('41,9'), 41.9);
    expect(NfeEntradaConversaoUtil.parseDecimalTexto('41.9'), 41.9);
    expect(NfeEntradaConversaoUtil.parseDecimalTexto('  12,5  '), 12.5);
  });

  test('fator de embalagem com decimais calcula entrada corretamente', () {
    final entrada = NfeEntradaConversaoUtil.quantidadeEntradaUnidadeVenda(
      quantidadeNota: 4,
      fatorConversao: 2.63,
      embalagemMultiplica: true,
    );
    expect(entrada, closeTo(10.52, 0.001));
  });

  test('discrepancia grave detecta escala errada tipo 41900 para 41.9', () {
    final d = NfeEntradaConversaoUtil.avaliarDiscrepanciaQuantidadeEntrada(
      quantidadeNota: 41.9,
      quantidadeEntradaUnidadeVenda: 41900,
      fatorConversao: 1,
    );
    expect(d.nivel, NfeEntradaNivelDiscrepancia.grave);
    expect(d.bloqueiaConfirmacao, isTrue);
  });

  test('conversao CX fator 12 nao gera falso positivo grave', () {
    final d = NfeEntradaConversaoUtil.avaliarDiscrepanciaQuantidadeEntrada(
      quantidadeNota: 5,
      quantidadeEntradaUnidadeVenda: 60,
      fatorConversao: 12,
    );
    expect(d.nivel, NfeEntradaNivelDiscrepancia.nenhum);
  });
}
