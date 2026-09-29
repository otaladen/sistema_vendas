import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/movimento_estoque_repository.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/domain/estoque/tipo_movimento_estoque.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/resumo_diario_produto_service.dart';

import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  group('resumo diario de produto', () {
    late Directory tempDir;
    late ObjectBox db;
    late ResumoDiarioProdutoService service;

    setUp(() {
      enterSyncApplySilencioso();
      tempDir = Directory.systemTemp.createTempSync('sv_resumo_diario_obx_');
      db = ObjectBox.createForTest(tempDir);
      service = ResumoDiarioProdutoService(db);
    });

    tearDown(() {
      leaveSyncApplySilencioso();
      db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Produto novoProduto() {
      final produto = Produto(
        codigoInterno: 'P1',
        nome: 'Cimento',
        quantidadeMinima: 0,
        precoCusto: 1,
        precoVenda: 10,
      );
      produto.id = db.produtoBox.put(produto);
      return produto;
    }

    ItemVenda itemDe(Produto produto, int quantidade) {
      final item = ItemVenda(
        nomeProduto: produto.nome,
        quantidade: quantidade,
        precoUnitario: 10,
        precoCustoUnitario: 1,
      );
      item.produto.target = produto;
      item.id = db.itemVendaBox.put(item);
      return item;
    }

    test('acumula vendas do mesmo dia e ignora a saida fisica da venda', () {
      final produto = novoProduto();
      final quando = DateTime.utc(2026, 9, 28, 15);
      final venda = Venda(status: 'finalizada', finalizadaEm: quando);
      service.registrarVendaFinalizada(venda, [itemDe(produto, 4)]);
      service.registrarVendaFinalizada(venda, [itemDe(produto, 2)]);

      MovimentoEstoqueRepository(db).registrar(
        produto: produto,
        tipo: TipoMovimentoEstoque.cupomNaoFiscalVenda,
        saldoFisicoAntes: 10,
        saldoReservaAntes: 0,
        saldoFisicoDepois: 4,
        saldoReservaDepois: 0,
      );

      final linhas = db.resumoDiarioProdutoBox.getAll();
      expect(linhas, hasLength(1));
      expect(linhas.single.quantidadeVendida, 6);
      expect(linhas.single.valorTotalVendido, 60);
      expect(linhas.single.quantidadeEntrada, 0);
      expect(linhas.single.chaveDia, '${produto.id}|2026-09-28');
    });

    test('entrada e devolucao atualizam o dia do movimento', () {
      final produto = novoProduto();
      final movimentos = MovimentoEstoqueRepository(db);
      movimentos.registrar(
        produto: produto,
        tipo: TipoMovimentoEstoque.entradaNfeCompra,
        saldoFisicoAntes: 0,
        saldoReservaAntes: 0,
        saldoFisicoDepois: 20,
        saldoReservaDepois: 0,
      );
      movimentos.registrar(
        produto: produto,
        tipo: TipoMovimentoEstoque.devolucaoCliente,
        saldoFisicoAntes: 20,
        saldoReservaAntes: 0,
        saldoFisicoDepois: 22,
        saldoReservaDepois: 0,
      );

      final linha = db.resumoDiarioProdutoBox.getAll().single;
      expect(linha.quantidadeEntrada, 20);
      expect(linha.quantidadeDevolvida, 2);
      expect(linha.quantidadeVendida, 0);
    });

    test('estorno da venda zera a linha do dia', () {
      final produto = novoProduto();
      final venda = Venda(
        status: 'finalizada',
        finalizadaEm: DateTime.utc(2026, 9, 28, 12),
      );
      final itens = [itemDe(produto, 3)];
      service.registrarVendaFinalizada(venda, itens);
      service.estornarVendaFinalizada(venda, itens);
      expect(db.resumoDiarioProdutoBox.count(), 0);
    });

    test('backfill roda uma vez e a segunda chamada nao duplica', () {
      final produto = novoProduto();
      final venda = Venda(
        status: 'finalizada',
        cancelada: false,
        data: DateTime.utc(2026, 9, 20, 10),
        finalizadaEm: DateTime.utc(2026, 9, 20, 10),
      );
      venda.id = db.vendaBox.put(venda);
      final item = itemDe(produto, 5);
      item.quantidadeDevolvida = 1;
      item.venda.target = venda;
      db.itemVendaBox.put(item);

      expect(service.backfillSeVazio(), 1);
      expect(service.backfillSeVazio(), 0);

      final linha = db.resumoDiarioProdutoBox.getAll().single;
      expect(linha.quantidadeVendida, 5);
      expect(linha.quantidadeDevolvida, 1);
      final consumo = service.consumoLiquidoEntre(
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 9, 28),
      );
      expect(consumo[produto.id], 4);
    });
  }, skip: skipObjectBox);
}
