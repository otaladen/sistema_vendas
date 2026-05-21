import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/promocao_cadastro.dart';
import 'package:sistema_vendas/domain/promocao_preco_service.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/promocao.dart';

void main() {
  test('desconto percentual usa preco1 como base', () {
    final preco = PromocaoPrecoService.calcularPrecoRegra(
      tipoRegra: 'desconto_percentual',
      valorRegra: 10,
      precoBasePreco1: 100,
    );
    expect(preco, closeTo(90, 0.01));
  });

  test('preco fixo retorna valor da regra', () {
    final preco = PromocaoPrecoService.calcularPrecoRegra(
      tipoRegra: 'preco_fixo',
      valorRegra: 42.5,
      precoBasePreco1: 100,
    );
    expect(preco, 42.5);
  });

  test('sem promocao lista ativa usa preco2', () {
    final p = Produto(
      codigoInterno: 'X',
      nome: 'X',
      quantidadeMinima: 0,
      precoCusto: 1,
      preco1: 100,
      preco2: 88,
      precoVenda: 100,
    );
    expect(PromocaoPrecoService.precoLista(p, 'preco2'), 88);
    expect(PromocaoPrecoService.preco1Base(p), 100);
  });

  test('tipo promo identificado no cadastro', () {
    expect(PromocaoCadastro.precoTipoPromo, 'promo');
  });

  test('segmento vazio aceita qualquer cliente', () {
    final p = Promocao(
      nome: 'T',
      dataInicio: DateTime.utc(2026, 1, 1),
      dataFim: DateTime.utc(2026, 12, 31),
    );
    expect(PromocaoCadastro.promocaoAceitaSegmento(p, 'construtor'), isTrue);
    expect(PromocaoCadastro.promocaoAceitaSegmento(p, null), isTrue);
  });

  test('preview cadastro igual ao motor de preco', () {
    final p1 = 100.0;
    expect(
      PromocaoCadastro.calcularPrecoUnitarioEfetivo(
        tipoCampanha: PromocaoCadastro.tipoProduto,
        tipoRegra: 'desconto_percentual',
        valorRegra: 10,
        precoBasePreco1: p1,
      ),
      closeTo(90, 0.01),
    );
    expect(
      PromocaoCadastro.calcularPrecoUnitarioEfetivo(
        tipoCampanha: PromocaoCadastro.tipoLevePague,
        tipoRegra: 'desconto_percentual',
        valorRegra: 10,
        precoBasePreco1: p1,
        quantidade: 3,
        leveQuantidade: 3,
        pagueQuantidade: 2,
      ),
      closeTo(60, 0.01),
    );
  });

  test('leve 3 pague 2 com preco fixo 300 totaliza 600', () {
    const precoFixo = 300.0;
    const qtd = 3;
    final unit = PromocaoCadastro.calcularPrecoUnitarioEfetivo(
      tipoCampanha: PromocaoCadastro.tipoLevePague,
      tipoRegra: 'preco_fixo',
      valorRegra: precoFixo,
      precoBasePreco1: 500,
      quantidade: qtd,
      leveQuantidade: 3,
      pagueQuantidade: 2,
    );
    expect(unit, closeTo(200, 0.01));
    expect(unit * qtd, closeTo(600, 0.01));
    expect(precoFixo * 2, closeTo(600, 0.01));
  });

  test('validacao leve pague exige pague menor que leve', () {
    final erros = PromocaoCadastro.validarFormulario(
      nome: 'T',
      tipoCampanha: PromocaoCadastro.tipoLevePague,
      tipoRegra: 'desconto_percentual',
      valorRegra: 10,
      precoCombo: 0,
      leveQuantidade: 2,
      pagueQuantidade: 2,
      qtdItensProduto: 1,
      qtdItensCombo: 0,
      margemMinima: 0,
      limiteGlobal: 0,
    );
    expect(erros, isNotEmpty);
  });

  test('segmento restrito so construtor', () {
    final p = Promocao(
      nome: 'Obra',
      dataInicio: DateTime.utc(2026, 1, 1),
      dataFim: DateTime.utc(2026, 12, 31),
      segmentoCliente: 'construtor',
    );
    expect(PromocaoCadastro.promocaoAceitaSegmento(p, 'construtor'), isTrue);
    expect(PromocaoCadastro.promocaoAceitaSegmento(p, 'consumidor'), isFalse);
  });
}
