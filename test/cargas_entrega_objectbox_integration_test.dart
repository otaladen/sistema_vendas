import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/domain/complemento_entrega_codec.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/agenda_carreto_ocupacao.dart';
import 'package:sistema_vendas/domain/entregas/cargas_entrega.dart';
import 'package:sistema_vendas/domain/entregas/loja_origem_mercadoria.dart';
import 'package:sistema_vendas/domain/venda_documento_rotulo_helper.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  group(
    'cargas da entrega ObjectBox',
    () {
      late Directory tempDir;
      late ObjectBox db;
      late VendaRepository vendas;

      final d1 = DateTime(2030, 5, 10);
      final d2 = DateTime(2030, 5, 17);
      final d3 = DateTime(2030, 5, 24);

      setUp(() {
        enterSyncApplySilencioso();
        tempDir = Directory.systemTemp.createTempSync('sv_cargas_obx_');
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

      Produto cimento() {
        final p = Produto(
          codigoInterno: '500',
          nome: 'Cimento 50kg',
          unidade: 'SC',
          estoqueReal: 300,
          estoqueReservado: 0,
          estoqueAtual: 300,
          quantidadeMinima: 0,
          precoCusto: 30,
          precoVenda: 40,
          preco1: 40,
          preco2: 40,
          preco3: 40,
          ativo: true,
        );
        p.id = db.produtoBox.put(p);
        return p;
      }

      int real(Produto p) => db.produtoBox.get(p.id)!.estoqueReal;
      int reservado(Produto p) => db.produtoBox.get(p.id)!.estoqueReservado;
      Venda venda(int id) => vendas.obterPorId(id)!;

      LinhaCargaEntrega linha(Produto p, double q) => LinhaCargaEntrega(
            produtoId: p.id,
            nomeProduto: p.nome,
            quantidade: q,
          );

      int quantidadeNaCarga(int id) {
        final v = venda(id);
        final itens = vendas.listarItensPorVenda(id);
        return EntregaVendaHelper.quantidadeRomaneioCarga(
          v,
          itens.single,
          itens: itens,
        );
      }

      void sair(int id) => vendas.atualizarChecklistCargaEntrega(
            id,
            separado: true,
            carregado: true,
            saiu: true,
            lojaOrigemMercadoria: LojaOrigemMercadoria.local,
          );

      int vendaCarretoComCargas(Produto p, List<CargaEntrega> cargas) {
        final id = vendas.registrarOrcamento(
          [
            ItemVendaInput(
              produtoId: p.id,
              quantidade: 200,
              quantidadeEmMilesimos: false,
              precoUnitario: 40,
              tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
            ),
          ],
          pagamento: DadosPagamentoOrcamento(
            formaPagamento: 'pix',
            quantidadeParcelas: 1,
          ),
          entrega: DadosEntregaOrcamento(
            tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
            valorFrete: 80,
            enderecoEntrega: 'Rua da Obra 10',
            dataEntregaMarcada: d1,
            cargasEntregaJson: CargasEntregaCodec.encode(cargas),
          ),
        );
        vendas.converterOrcamentoParaVenda(id);
        return id;
      }

      test('duas cargas: cada saida baixa so a sua parte', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);
        expect(reservado(p), 200);
        expect(quantidadeNaCarga(id), 120);
        expect(
          VendaDocumentoRotuloHelper.rotuloPedidoEntrega(venda(id)),
          endsWith('Carga 1/2'),
        );
        final escopo1 =
            EntregaVendaHelper.escopoConferenciaCargaRomaneio([venda(id)]);

        sair(id);
        expect(real(p), 180);
        expect(reservado(p), 80);

        vendas.atualizarStatusEntrega(id, 'entregue');

        var v = venda(id);
        expect(v.statusEntrega, 'pendente');
        expect(v.cargaSaiu, isFalse);
        expect(v.cargaSeparada, isFalse);
        expect(CargasEntregaHelper.soDia(v.dataEntregaMarcada!), d2);
        expect(quantidadeNaCarga(id), 80);
        expect(
          EntregaVendaHelper.escopoConferenciaCargaRomaneio([v]),
          isNot(escopo1),
        );
        // Nada muda no estoque ao concluir a carga 1.
        expect(real(p), 180);
        expect(reservado(p), 80);

        sair(id);
        expect(real(p), 100);
        expect(reservado(p), 0);

        vendas.atualizarStatusEntrega(id, 'entregue');
        v = venda(id);
        expect(v.statusEntrega, 'entregue');
        expect(
          CargasEntregaCodec.decode(v.cargasEntregaJson)
              .every((c) => c.entregue),
          isTrue,
        );
        expect(real(p), 100);
        expect(reservado(p), 0);
      });

      test('desmarcar "Saiu" estorna so a carga atual', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);
        sair(id);
        vendas.atualizarChecklistCargaEntrega(id, saiu: false);
        expect(real(p), 300);
        expect(reservado(p), 200);
      });

      test('tres cargas e falta na ida da carga do meio', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 100)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 60)]),
          CargaEntrega(numero: 3, data: d3, linhas: [linha(p, 40)]),
        ]);
        sair(id);
        vendas.atualizarStatusEntrega(id, 'entregue');
        expect(real(p), 200);
        expect(reservado(p), 100);

        sair(id);
        expect(real(p), 140);
        expect(reservado(p), 40);
        final item = vendas.listarItensPorVenda(id).single;
        vendas.atualizarStatusEntrega(
          id,
          'entregue_complemento_pendente',
          complementoEntregaJson: ComplementoEntregaCodec.encode([
            LinhaComplementoEntrega(
              itemVendaId: item.id,
              quantidade: 10,
              nomeProduto: item.nomeProduto,
            ),
          ]),
        );
        expect(real(p), 150);
        expect(reservado(p), 50);

        vendas.atualizarStatusEntrega(id, 'entregue');
        var v = venda(id);
        expect(v.statusEntrega, 'pendente');
        expect(v.complementoEntregaJson, isEmpty);
        expect(CargasEntregaHelper.soDia(v.dataEntregaMarcada!), d3);
        expect(real(p), 140);
        expect(reservado(p), 40);

        sair(id);
        vendas.atualizarStatusEntrega(id, 'entregue');
        v = venda(id);
        expect(v.statusEntrega, 'entregue');
        expect(real(p), 100);
        expect(reservado(p), 0);
      });

      test('carga seguinte nao pode ser entregue sem sair', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 100)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 60)]),
          CargaEntrega(numero: 3, data: d3, linhas: [linha(p, 40)]),
        ]);
        sair(id);
        vendas.atualizarStatusEntrega(id, 'entregue');
        expect(
          () => vendas.atualizarStatusEntrega(id, 'entregue'),
          throwsStateError,
        );
      });

      test('baixa do motorista: POD fica na carga e reenvio e ignorado', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);
        sair(id);
        for (var i = 0; i < 2; i++) {
          vendas.baixarEntregaMotorista(
            vendaId: id,
            recebidoPor: 'Joao',
            usuarioLogin: 'motorista',
            statusAnterior: 'saiu_entrega',
          );
        }
        final v = venda(id);
        final cargas = CargasEntregaCodec.decode(v.cargasEntregaJson);
        expect(cargas.where((c) => c.entregue), hasLength(1));
        expect(cargas.first.recebidoPor, 'Joao');
        expect(v.podRecebidoPor, isEmpty);
        expect(v.statusEntrega, 'pendente');
        expect(real(p), 180);
      });

      test('cancelar depois da carga 1: volta o fisico e libera a reserva',
          () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);
        sair(id);
        vendas.atualizarStatusEntrega(id, 'entregue');
        vendas.cancelarVenda(id, motivo: 'teste');
        expect(real(p), 300);
        expect(reservado(p), 0);
      });

      test('origem outra loja: saida consome so a reserva da carga', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);
        vendas.atualizarChecklistCargaEntrega(
          id,
          separado: true,
          carregado: true,
          saiu: true,
        );
        expect(real(p), 300);
        expect(reservado(p), 80);
      });

      test('buscar nesta loja: recorte fisico limitado a carga atual', () {
        final p = cimento();
        final id = vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 20)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 180)]),
        ]);
        final item = vendas.listarItensPorVenda(id).single;
        for (final acao in ['solicitar', 'confirmar']) {
          vendas.atualizarBuscarNaLoja(
            id,
            acao: acao,
            itemIds: [item.id],
            usuario: 'patio',
            quantidadePorItem: {item.id: 30},
          );
        }
        vendas.atualizarChecklistCargaEntrega(
          id,
          separado: true,
          carregado: true,
          saiu: true,
        );
        // Pediu 30 desta loja, mas a carga 1 so leva 20.
        expect(real(p), 280);
        expect(reservado(p), 180);
      });

      test('agenda conta cada carga pendente no seu dia', () {
        final p = cimento();
        vendaCarretoComCargas(p, [
          CargaEntrega(numero: 1, data: d1, linhas: [linha(p, 120)]),
          CargaEntrega(numero: 2, data: d2, linhas: [linha(p, 80)]),
        ]);

        final mes = vendas.ocupacaoAgendaCarretoMes(DateTime(2030, 5));
        expect(mes.quantidadeDoDia(d1), 1);
        expect(mes.quantidadeDoDia(d2), 1);
        final dia2 = mes.itensDoDia(d2).single;
        expect(dia2.cargaRotulo, 'Carga 2/2');
        expect(dia2.produtos.single.quantidade, 80);
        expect(
          AgendaCarretoOcupacaoMes.deMap(mes.paraMap())
              .itensDoDia(d2)
              .single
              .cargaRotulo,
          'Carga 2/2',
        );
      });
    },
    skip: skipObjectBox,
  );
}
