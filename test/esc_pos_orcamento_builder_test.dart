import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_orcamento_builder.dart';

void main() {
  test('montar orcamento ESC/POS gera bytes com init e texto', () {
    final produto = Produto(
      id: 1,
      codigoInterno: '39',
      nome: 'Cimento Poly 50kg',
      precoCusto: 40,
      precoVenda: 50,
      preco1: 50,
      quantidadeMinima: 0,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento Poly 50kg',
      quantidade: 1,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      precoTipo: 'preco1',
      tipoEntregaItem: 'retirada',
    )..produto.target = produto;

    final venda = Venda(
      numeroOrcamento: 1,
      total: 50,
      formaPagamento: 'dinheiro',
    );

    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(
          nomeLoja: 'Comprou Levou',
          telefone: '2136-8582',
          endereco: 'Rua Teste',
        ),
        itens: [item],
        validadeDias: 7,
        produtosPorItem: {0: produto},
      ),
      largura: EscPosLarguraBobina.mm80,
    );

    expect(bytes, isNotEmpty);
    expect(bytes[0], 0x1B); // ESC
    expect(bytes[1], 0x40); // @ init
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('ORCAMENTO'));
    expect(texto, contains('Cimento'));
    expect(texto, contains('VALOR TOTAL'));
    expect(texto, contains('COTACAO'));
    expect(texto, contains('FORMA DE PAGAMENTO'));
    expect(texto, contains('A vista'));
    expect(texto, contains('Dinheiro/PIX/Debito'));
    expect(texto, isNot(contains('2x de')));
    expect(texto, isNot(contains('12x')));
    expect(texto, isNot(contains('Condicoes de parcelamento')));
    expect(texto, isNot(contains('RETIRA LOGO')));
    expect(texto, isNot(contains('RETIRADA FUTURA')));
    expect(texto, isNot(contains('ENTREGA/CARRETO')));
  });

  test('montar orcamento ESC/POS imprime so o credito escolhido', () {
    final venda = Venda(
      numeroOrcamento: 2,
      total: 90,
      formaPagamento: 'cartao_credito',
      quantidadeParcelas: 3,
    );
    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Comprou Levou'),
        itens: const [],
        validadeDias: 7,
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('Cartao de credito'));
    expect(texto, contains('3x de'));
    expect(texto, isNot(contains('2x de')));
    expect(texto, isNot(contains('12x')));
    expect(texto, isNot(contains('A vista')));
  });
}
