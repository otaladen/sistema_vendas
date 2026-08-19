import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_consulta_insights_service.dart';
import 'package:sistema_vendas/domain/pdv_consulta_similares_util.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produto({
  int id = 1,
  String nome = 'Cimento CP II',
  String categoria = 'Cimento',
  String subcategoria = 'CP II',
  String marca = 'Poty',
  String descricao = 'Uso em lajes e fundacoes',
  String apelidosBusca = 'laje;fundacao',
  String localizacao = 'A-12',
  double precoCusto = 30,
  double preco1 = 50,
  int estoqueReal = 10,
}) =>
    Produto(
      id: id,
      codigoInterno: '004025',
      nome: nome,
      descricao: descricao,
      apelidosBusca: apelidosBusca,
      categoria: categoria,
      subcategoria: subcategoria,
      marca: marca,
      localizacao: localizacao,
      unidade: 'SC',
      precoCusto: precoCusto,
      precoVenda: preco1,
      preco1: preco1,
      preco2: 48,
      preco3: 45,
      quantidadeMinima: 2,
      estoqueReal: estoqueReal,
    );

void main() {
  test('alerta margem abaixo do minimo padrao', () {
    final alerta = PdvConsultaInsightsService.calcularAlertaMargem(
      produto: _produto(precoCusto: 45, preco1: 50),
      precoVenda: 50,
      margemMinimaPadrao: 20,
    );
    expect(alerta.abaixoMargemMinima, isTrue);
    expect(alerta.margemPercentual, closeTo(10, 0.1));
  });

  test('alerta margem abaixo do custo', () {
    final alerta = PdvConsultaInsightsService.calcularAlertaMargem(
      produto: _produto(precoCusto: 55),
      precoVenda: 50,
    );
    expect(alerta.abaixoCusto, isTrue);
  });

  test('filtro aplicacao usa descricao e apelidos', () {
    final p = _produto();
    expect(
      PdvConsultaInsightsService.produtoCombinaAplicacao(p, 'laje'),
      isTrue,
    );
    expect(
      PdvConsultaInsightsService.produtoCombinaAplicacao(p, 'fundacao'),
      isTrue,
    );
    expect(
      PdvConsultaInsightsService.produtoCombinaAplicacao(p, 'tinta'),
      isFalse,
    );
  });

  test('filtro aplicacao aceita curingas %', () {
    final p = _produto(
      descricao: 'Indicada para impermeabilizacao de lajes e fundacoes.',
    );
    expect(
      PdvConsultaInsightsService.produtoCombinaAplicacao(p, 'imper%laje'),
      isTrue,
    );
    expect(
      PdvConsultaInsightsService.produtoCombinaAplicacao(p, 'imper%tinta'),
      isFalse,
    );
  });

  test('extrai trecho da descricao para o termo', () {
    final p = _produto(
      descricao:
          'Indicado para impermeabilizacao de lajes expostas e areas molhadas.',
    );
    final trecho = PdvConsultaInsightsService.extrairTrechoAplicacao(
      p,
      'lajes',
    );
    expect(trecho, isNotNull);
    expect(trecho!.toLowerCase(), contains('lajes'));
  });

  test('categoria generica nao gera similares', () {
    final ref = _produto(categoria: 'Geral', subcategoria: '');
    expect(PdvConsultaSimilaresUtil.referenciaElegivel(ref), isFalse);
  });

  test('exige mesma subcategoria quando cadastrada', () {
    final ref = _produto(subcategoria: 'CP II');
    final outroCp = _produto(
      id: 2,
      nome: 'Cimento CP III',
      subcategoria: 'CP III',
      estoqueReal: 50,
    );
    final mesmoCp = _produto(
      id: 3,
      nome: 'Cimento CP II Votoran',
      subcategoria: 'CP II',
      estoqueReal: 30,
    );
    expect(
      PdvConsultaSimilaresUtil.candidatoCompativel(ref, outroCp),
      isFalse,
    );
    expect(
      PdvConsultaSimilaresUtil.candidatoCompativel(ref, mesmoCp),
      isTrue,
    );
  });

  test('similares ignoram candidato sem estoque', () {
    final ref = _produto(subcategoria: 'CP II');
    final semEstoque = _produto(
      id: 2,
      subcategoria: 'CP II',
      estoqueReal: 0,
    );
    expect(
      PdvConsultaSimilaresUtil.candidatoCompativel(ref, semEstoque),
      isFalse,
    );
  });
}
