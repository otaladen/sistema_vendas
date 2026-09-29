import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/compras_preditivas_service.dart';
import 'package:sistema_vendas/services/resumo_diario_produto_service.dart';

import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  group('consultas de periodo no ObjectBox', () {
    late Directory tempDir;
    late ObjectBox db;
    late VendaRepository vendas;

    setUp(() {
      enterSyncApplySilencioso();
      tempDir = Directory.systemTemp.createTempSync('sv_periodo_obx_');
      db = ObjectBox.createForTest(tempDir);
      vendas = VendaRepository(db);
    });

    tearDown(() {
      leaveSyncApplySilencioso();
      db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Produto novoProduto(String codigo) {
      final p = Produto(
        codigoInterno: codigo,
        nome: 'Produto $codigo',
        quantidadeMinima: 0,
        precoCusto: 1,
        precoVenda: 2,
      );
      p.id = db.produtoBox.put(p);
      return p;
    }

    Cliente novoCliente(String nome) {
      final c = Cliente(nomeRazao: nome);
      c.id = db.clienteBox.put(c);
      return c;
    }

    void gravarVenda({
      required Cliente cliente,
      required Produto produto,
      required int quantidade,
      required DateTime quando,
      DateTime? finalizadaEm,
      bool semFinalizadaEm = false,
      bool cancelada = false,
      String status = 'finalizada',
      int quantidadeDevolvida = 0,
    }) {
      final venda = Venda(
        data: quando,
        status: status,
        cancelada: cancelada,
        total: quantidade.toDouble(),
        finalizadaEm: semFinalizadaEm ? null : (finalizadaEm ?? quando),
      );
      venda.cliente.target = cliente;
      venda.id = db.vendaBox.put(venda);
      final item = ItemVenda(
        nomeProduto: produto.nome,
        quantidade: quantidade,
        quantidadeDevolvida: quantidadeDevolvida,
        precoUnitario: 1,
        precoCustoUnitario: 1,
      );
      item.produto.target = produto;
      item.venda.target = venda;
      db.itemVendaBox.put(item);
    }

    test('media de 60 dias ignora venda antiga, cancelada e orcamento', () {
      final produto = novoProduto('60');
      final cliente = novoCliente('Obra');
      final agora = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      gravarVenda(
        cliente: cliente,
        produto: produto,
        quantidade: 4,
        quando: agora.subtract(const Duration(days: 10)),
      );
      gravarVenda(
        cliente: cliente,
        produto: produto,
        quantidade: 2,
        quantidadeDevolvida: 1,
        quando: agora.subtract(const Duration(days: 3)),
        semFinalizadaEm: true,
      );
      gravarVenda(
        cliente: cliente,
        produto: produto,
        quantidade: 9,
        quando: agora.subtract(const Duration(days: 90)),
      );
      gravarVenda(
        cliente: cliente,
        produto: produto,
        quantidade: 8,
        quando: agora.subtract(const Duration(days: 2)),
        cancelada: true,
      );
      gravarVenda(
        cliente: cliente,
        produto: produto,
        quantidade: 7,
        quando: agora.subtract(const Duration(days: 1)),
        status: 'orcamento',
        semFinalizadaEm: true,
      );

      ResumoDiarioProdutoService(db).backfillSeVazio();
      final consumo = ComprasPreditivasService(
        db,
      ).montarConsumoPorProdutoNoPeriodo(dias: 60);

      expect(consumo[produto.id], 5);
    });

    test('historico do cliente vem por finalizadaEm, com limite', () {
      final produto = novoProduto('H');
      final cliente = novoCliente('Cliente A');
      final outro = novoCliente('Cliente B');
      final agora = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      for (var i = 1; i <= 3; i++) {
        gravarVenda(
          cliente: cliente,
          produto: produto,
          quantidade: 1,
          quando: agora.subtract(Duration(days: 10 + i)),
          finalizadaEm: agora.subtract(Duration(days: i)),
        );
      }
      gravarVenda(
        cliente: outro,
        produto: produto,
        quantidade: 1,
        quando: agora,
      );

      final pagina = vendas.listarComprasFinalizadasPorCliente(cliente.id);
      expect(pagina, hasLength(3));
      expect(pagina.map((v) => v.finalizadaEm).toList(), [
        agora.subtract(const Duration(days: 1)),
        agora.subtract(const Duration(days: 2)),
        agora.subtract(const Duration(days: 3)),
      ]);

      final recente = vendas.listarComprasFinalizadasPorCliente(
        cliente.id,
        limit: 2,
      );
      expect(recente, hasLength(2));
      expect(
        recente.first.finalizadaEm,
        agora.subtract(const Duration(days: 1)),
      );
      expect(vendas.listarComprasFinalizadasPorCliente(outro.id), hasLength(1));
    });
  }, skip: skipObjectBox);
}
