import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/obra_calculadora.dart';
import 'package:sistema_vendas/domain/obra_calculadora_projeto.dart';
import 'package:sistema_vendas/domain/pdv_obra_calculadora_insercao.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('tijolos 9x19x19 com junta 1cm ≈ 25 por m²', () {
    final n = ObraCalculadora.tijolosPorMetroQuadrado(
      TipoTijoloObra.ceramico8f_9x19x19,
    );
    expect(n, closeTo(25, 0.5));
  });

  test('parede 4x3 m gera quantidades coerentes', () {
    const entrada = ObraCalculadoraEntrada(
      larguraM: 4,
      alturaM: 3,
      perdaPct: 10,
    );
    final res = ObraCalculadora.calcularParedeAlvenaria(entrada)!;
    expect(res.areaM2, 12);
    final tijolos = res.materiais
        .firstWhere((m) => m.papel == ObraMaterialPapel.tijolo);
    expect(tijolos.quantidade, greaterThan(300));
    expect(tijolos.quantidade, lessThan(350));
  });

  test('parede desconta 1 porta padrao', () {
    final entrada = ObraCalculadoraEntrada(
      larguraM: 4,
      alturaM: 3,
      perdaPct: 0,
      aberturas: [ObraAberturaPadrao.porta()],
    );
    final res = ObraCalculadora.calcularParedeAlvenaria(entrada)!;
    expect(res.areaAberturasM2, closeTo(1.68, 0.01));
    expect(res.areaM2, closeTo(10.32, 0.05));
  });

  test('parseTextoLivre interpreta parede 4x3 tijolo 9x19x19', () {
    final e = ObraCalculadora.parseTextoLivre(
      'Parede de 4x3 metros com tijolo 9x19x19',
    );
    expect(e, isNotNull);
    expect(e!.tipo, ObraReceitaTipo.parede);
    expect(e.larguraM, 4);
    expect(e.alturaM, 3);
  });

  test('parseTextoLivre interpreta laje 20m2', () {
    final e = ObraCalculadora.parseTextoLivre('Laje 20m2');
    expect(e?.tipo, ObraReceitaTipo.laje);
    expect(e?.areaCalculadaM2, 20);
  });

  test('parseTextoLivre interpreta fundacao 10m', () {
    final e = ObraCalculadora.parseTextoLivre('Fundacao sapata 10 metros');
    expect(e?.tipo, ObraReceitaTipo.fundacao);
    expect(e?.comprimentoM, 10);
  });

  test('parseTextoLivre interpreta telhado 40m2', () {
    final e = ObraCalculadora.parseTextoLivre('Telhado ceramico 40m2');
    expect(e?.tipo, ObraReceitaTipo.telhado);
    expect(e?.areaCalculadaM2, 40);
  });

  test('calcularLaje gera cimento areia brita', () {
    final res = ObraCalculadora.calcularLaje(
      const ObraLajeEntrada(areaM2: 10, espessuraMm: 100, perdaPct: 0),
    )!;
    expect(res.materiais.length, 3);
    expect(
      res.materiais.any((m) => m.papel == ObraMaterialPapel.brita),
      isTrue,
    );
  });

  test('calcularTelhado estima telhas', () {
    final res = ObraCalculadora.calcularTelhado(
      const ObraTelhadoEntrada(
        areaM2: 10,
        perdaPct: 0,
        inclinacaoPct: 0,
        telhasPorM2: 16,
      ),
    )!;
    expect(res.materiais.first.quantidade, 160);
  });

  test('calcularReboco 12m2 gera cimento e areia', () {
    final res = ObraCalculadora.calcularReboco(
      const ObraArgamassaEntrada(areaM2: 12, espessuraMm: 20, perdaPct: 0),
    )!;
    expect(res.materiais.length, 2);
    expect(res.materiais.any((m) => m.papel == ObraMaterialPapel.cimento), isTrue);
    expect(res.materiais.any((m) => m.papel == ObraMaterialPapel.areia), isTrue);
  });

  test('calcularPiso arredonda caixas', () {
    final res = ObraCalculadora.calcularPiso(
      const ObraPisoEntrada(areaM2: 10, perdaPct: 0, m2PorCaixa: 2),
    )!;
    expect(res.materiais.single.quantidade, 5);
  });

  test('calcularFundacao volume sapata 10x0,4x0,5', () {
    final res = ObraCalculadora.calcularFundacao(
      const ObraFundacaoEntrada(
        comprimentoM: 10,
        larguraM: 0.40,
        profundidadeM: 0.50,
        perdaPct: 0,
      ),
    )!;
    expect(res.volumeM3, closeTo(2, 0.01));
    expect(res.materiais.any((m) => m.papel == ObraMaterialPapel.ferro), isTrue);
  });

  test('telhado inclinacao aumenta quantidade de telhas', () {
    final plano = ObraCalculadora.calcularTelhado(
      const ObraTelhadoEntrada(
        areaM2: 10,
        perdaPct: 0,
        inclinacaoPct: 0,
        telhasPorM2: 16,
      ),
    )!;
    final inclinado = ObraCalculadora.calcularTelhado(
      const ObraTelhadoEntrada(
        areaM2: 10,
        perdaPct: 0,
        inclinacaoPct: 30,
        telhasPorM2: 16,
      ),
    )!;
    expect(inclinado.materiais.first.quantidade,
        greaterThan(plano.materiais.first.quantidade));
  });

  test('projeto consolida linhas do mesmo produto', () {
    final p = Produto(
      id: 1,
      codigoInterno: 'C1',
      nome: 'Cimento',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    final mat = ObraCalculadoraMaterialCalculado(
      papel: ObraMaterialPapel.cimento,
      quantidade: 5,
      unidadeRotulo: 'SC',
      rotulo: 'Cimento',
      detalhe: 'a',
    );
    final linhas = [
      PdvObraCalculadoraLinhaInsercao(produto: p, quantidade: 5, material: mat),
      PdvObraCalculadoraLinhaInsercao(produto: p, quantidade: 3, material: mat),
    ];
    final out = ObraCalculadoraProjetoUtil.consolidarLinhas(linhas);
    expect(out.length, 1);
    expect(out.first.quantidade, 8);
  });
}