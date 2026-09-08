import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/carreto_saida_produto_orfao.dart';
import 'package:sistema_vendas/domain/entregas/romaneio_carga_merge.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('RomaneioProdutoOrfaoHelper', () {
    test('monta linha com snapshot quando produto foi excluido', () {
      final venda = Venda()
        ..id = 1
        ..status = 'finalizada'
        ..carretoReservaAteSaida = true;
      final item = ItemVenda(
        nomeProduto: 'Areia 1/2m3',
        quantidade: 2,
        precoUnitario: 10,
        precoCustoUnitario: 5,
        tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      )..produto.targetId = 99;

      venda.itens.add(item);

      final linhas = RomaneioCargaMerge.montarLinhas(
        [venda],
        obterProduto: (_) => null,
      );

      expect(linhas, hasLength(1));
      expect(linhas.first.nomeProduto, 'Areia 1/2m3');
      expect(linhas.first.quantidadeTotal, 2);
      expect(linhas.first.unidade, 'UN');
      expect(linhas.first.produtoNaoEncontradoNoCadastro, isTrue);
    });

    test('item com produto valido nao marca orfao', () {
      final produto = Produto(
        id: 5,
        codigoInterno: 'A1',
        nome: 'Areia',
        unidade: 'M3',
        quantidadeMinima: 0,
        precoCusto: 1,
        precoVenda: 2,
      );
      final venda = Venda()
        ..id = 2
        ..status = 'finalizada'
        ..carretoReservaAteSaida = true;
      final item = ItemVenda(
        nomeProduto: 'Areia',
        quantidade: 1,
        precoUnitario: 10,
        precoCustoUnitario: 5,
        tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      )..produto.target = produto;
      venda.itens.add(item);

      final linhas = RomaneioCargaMerge.montarLinhas(
        [venda],
        obterProduto: (id) => id == 5 ? produto : null,
      );

      expect(linhas, hasLength(1));
      expect(linhas.first.produtoNaoEncontradoNoCadastro, isFalse);
      expect(linhas.first.unidade, 'M3');
    });
  });

  group('CarretoSaidaProdutoOrfaoEvento', () {
    test('encode e parse preservam linhas', () {
      final ev = CarretoSaidaProdutoOrfaoEvento(
        vendaId: 10,
        numeroOrcamento: 100,
        documento: 'Pedido #100',
        dataHora: DateTime.utc(2026, 3, 8, 12),
        linhas: const [
          CarretoSaidaProdutoOrfaoLinha(
            itemVendaId: 7,
            nomeProduto: 'Tinta velha',
            quantidade: 3,
            unidade: 'UN',
          ),
        ],
      );
      final round = CarretoSaidaProdutoOrfaoEvento.tryParse(ev.encode());
      expect(round, isNotNull);
      expect(round!.linhas.single.nomeProduto, 'Tinta velha');
      expect(round.textoHumano, contains('cadastro excluido'));
    });
  });
}
