import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec.dart';
import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_cupom_builder.dart';

Produto _ravello() => Produto(
      id: 10,
      codigoInterno: 'RAV',
      nome: 'Piso Ravello',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 20,
      precoVenda: 32,
      preco1: 32,
      permiteQuantidadeFracionada: false,
    );

Produto _tabua() => Produto(
      id: 11,
      codigoInterno: 'TAB',
      nome: 'Tabua',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 5,
      precoVenda: 10,
      preco1: 10,
      permiteQuantidadeFracionada: false,
    );

Produto _gravilhao({String unidade = 'UN'}) => Produto(
      id: 12,
      codigoInterno: 'GRAV',
      nome: 'Gravilhao',
      unidade: unidade,
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 120,
      preco1: 120,
      permiteQuantidadeFracionada: false,
    );

Produto _laminaStarret() => Produto(
      id: 13,
      codigoInterno: 'LAM',
      nome: 'Lamina de Serra Starret',
      unidade: 'UN',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 10,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 4,
      precoVenda: 9.5,
      preco1: 9.5,
      permiteQuantidadeFracionada: false,
    );

/// Grava como o PDV: armazenamento + escala decidida no carrinho.
ItemVenda _itemPdv(
  Produto produto,
  double quantidadeVenda, {
  bool comProdutoVinculado = true,
}) {
  final arm = QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
    produto: produto,
    quantidadeVenda: quantidadeVenda,
    emUnidadeCompra: false,
  );
  final item = ItemVenda(
    nomeProduto: produto.nome,
    quantidade: arm.armazenado,
    precoUnitario: produto.preco1,
    precoCustoUnitario: produto.precoCusto,
    escalaQuantidade: ItemVenda.escalaDeFlag(arm.gravadoEmMilesimosPdv),
  );
  if (comProdutoVinculado) item.produto.target = produto;
  return item;
}

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

void main() {
  group('Impressao do cupom nao fiscal', () {
    test('4,2 M2 x R\$ 32,00 imprime 4,2 e subtotal R\$ 134,40', () {
      final item = _itemPdv(_ravello(), 4.2);
      expect(item.quantidade, 4200);
      expect(item.subtotal, closeTo(134.40, 0.001));

      final ascii = _ascii(
        EscPosCupomBuilder.montar(
          CupomBalcaoDados(
            venda: Venda(
              numeroOrcamento: 1,
              total: 134.40,
              formaPagamento: 'dinheiro',
            ),
            config: const EmpresaConfig(nomeLoja: 'Loja'),
            itens: [item],
            totalRecebido: 134.40,
          ),
          largura: EscPosLarguraBobina.mm80,
          abrirGaveta: false,
        ),
      );
      expect(ascii, contains('4,2 M2'));
      expect(ascii, contains('134,40'));
      expect(ascii, isNot(contains('4200')));
      expect(ascii, isNot(contains('134.400')));
    });

    test('item legado sem escala gravada em M2 nao multiplica por 1000', () {
      final item = ItemVenda(
        nomeProduto: 'Piso Ravello',
        quantidade: 4200,
        precoUnitario: 32,
        precoCustoUnitario: 20,
      )..produto.target = _ravello();
      expect(item.escalaQuantidade, ItemVenda.escalaQuantidadeLegado);
      expect(
        ProdutoEmbalagem.formatarQuantidadeItemImpressao(
          produto: item.produtoOuNull,
          quantidadeArmazenada: item.quantidade,
        ),
        '4,2',
      );
      expect(item.subtotal, closeTo(134.40, 0.001));
    });

    test('1400 UN inteiro continua 1400 (nao vira 1,4)', () {
      final item = _itemPdv(_tabua(), 1400);
      expect(item.quantidade, 1400);
      expect(item.quantidadeExibicaoVenda, '1400');
      expect(item.subtotal, closeTo(14000, 0.001));
    });
  });

  group('Listagem de vendas / modal Produtos — Controle', () {
    test('exibe 20 x Tabua, 1,5 x Gravilhao e 4,2 x Ravello', () {
      final itens = [
        _itemPdv(_tabua(), 20),
        _itemPdv(_gravilhao(), 1.5),
        _itemPdv(_ravello(), 4.2),
      ];
      expect(itens.map((i) => i.quantidade), [20000, 1500, 4200]);

      final linhas =
          itens.map((i) => '${i.quantidadeExibicaoVenda} x ${i.nomeProduto}');
      expect(linhas, [
        '20 x Tabua',
        '1,5 x Gravilhao',
        '4,2 x Piso Ravello',
      ]);
      expect(itens[1].subtotal, closeTo(180, 0.001));
    });

    test('Terminal Leve (produto nao resolvido) usa escala vinda da API', () {
      final servidor = [
        _itemPdv(_tabua(), 20),
        _itemPdv(_gravilhao(), 1.5),
        _itemPdv(_ravello(), 4.2),
      ];
      // Mesmo contrato de GET /api/vendas/<id>/itens e SyncEntityCodec.vendaParaMap.
      final itensMap = servidor
          .map(
            (i) => <String, dynamic>{
              'nomeProduto': i.nomeProduto,
              'quantidade': i.quantidade,
              'precoUnitario': i.precoUnitario,
              'precoCustoUnitario': i.precoCustoUnitario,
              'quantidadeEmMilesimos': i.quantidadeEmMilesimosResolvida,
            },
          )
          .toList();

      final cliente = itensMap.map(SyncEntityCodec.itemDeMap).toList();
      expect(cliente.every((i) => i.produtoOuNull == null), isTrue);
      expect(
        cliente.map((i) => '${i.quantidadeExibicaoVenda} x ${i.nomeProduto}'),
        ['20 x Tabua', '1,5 x Gravilhao', '4,2 x Piso Ravello'],
      );
      expect(cliente[2].subtotal, closeTo(134.40, 0.001));
    });

    test('Gravilhao legado em M3 le 1500 como 1,5', () {
      final item = ItemVenda(
        nomeProduto: 'Gravilhao',
        quantidade: 1500,
        precoUnitario: 120,
        precoCustoUnitario: 50,
      )..produto.target = _gravilhao(unidade: 'M3');
      expect(item.quantidadeExibicaoVenda, '1,5');
    });
  });

  group('Unidade de venda no carrinho / conferencia (sem caixa de compra)', () {
    test('Lamina Starret: 1 item exibe 1 UN, sem sufixo CX', () {
      final produto = _laminaStarret();
      final item = _itemPdv(produto, 1);
      expect(item.quantidade, 1);

      expect(item.quantidadeExibicaoVenda, '1');
      expect(item.quantidadeExibicaoVenda, isNot(contains('CX')));
      expect(item.subtotal, closeTo(9.5, 0.001));

      final carrinho = ProdutoEmbalagem.quantidadeCarrinhoDeItemPersistido(
        produto: produto,
        quantidadeArmazenada: item.quantidade,
      );
      expect(carrinho.emUnidadeCompra, isFalse);
      expect(carrinho.quantidadeDigitada, 1);

      final rotulo = ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: carrinho.quantidadeDigitada,
        emUnidadeCompra: carrinho.emUnidadeCompra,
      );
      expect(rotulo, '1 UN');
      expect(rotulo, isNot(contains('CX')));
    });

    test('passo +/- na conferencia de caixa e 1 UN, nao 1 CX (10 UN)', () {
      final produto = _laminaStarret();
      final item = _itemPdv(produto, 1);
      expect(
        ProdutoEmbalagem.passoQuantidadeArmazenada(
          produto: produto,
          quantidadeArmazenada: item.quantidade,
          emMilesimos: item.quantidadeEmMilesimosPersistida,
        ),
        1,
      );
    });

    test('linha do carrinho respeita milésimos do PDV (1,5 UN, nao 1500)', () {
      final produto = _gravilhao();
      final arm = QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
        produto: produto,
        quantidadeVenda: 1.5,
        emUnidadeCompra: false,
      );
      expect(
        ProdutoEmbalagem.rotuloQuantidadeCarrinho(
          produto: produto,
          quantidadeDigitada: arm.armazenado,
          emUnidadeCompra: false,
          emMilesimos: arm.gravadoEmMilesimosPdv,
        ),
        '1,5 UN',
      );
    });

    test('item legado de 1 UN em produto com embalagem nao vira CX', () {
      final produto = _laminaStarret();
      final texto = ProdutoEmbalagem.textoQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: 1,
      );
      expect(texto, '1');
      expect(texto, isNot(contains('CX')));
    });
  });
}
