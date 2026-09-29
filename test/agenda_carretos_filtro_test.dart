import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/agenda_carreto_ocupacao.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/venda.dart';

import 'helpers/objectbox_dll_for_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  final dia = DateTime(2026, 9, 29);

  Venda carreto({
    required String status,
    int numeroOrcamento = 0,
    bool cancelada = false,
    String statusEntrega = 'pendente',
    String tipoEntrega = EntregaVendaHelper.tipoEntregaLoja,
  }) {
    return Venda(
      status: status,
      numeroOrcamento: numeroOrcamento,
      cancelada: cancelada,
      tipoEntrega: tipoEntrega,
      statusEntrega: statusEntrega,
      dataEntregaMarcada: dia,
      enderecoEntrega: 'Rua A | Centro',
    );
  }

  AgendaCarretoOcupacaoItem item({
    required int vendaId,
    required int numero,
    required bool ehOrcamento,
    required String status,
  }) {
    return AgendaCarretoOcupacaoItem(
      dataChave: AgendaCarretoOcupacaoMes.chaveDia(dia),
      vendaId: vendaId,
      numero: numero,
      clienteNome: ehOrcamento ? 'Joselvado dos Santos' : 'Cliente pago',
      bairro: 'Centro',
      janela: 'manha',
      status: status,
      ehOrcamento: ehOrcamento,
    );
  }

  group('filtro da agenda', () {
    test('orcamento com pagamento pendente nao ocupa o dia', () {
      final orcamento = carreto(status: 'orcamento', numeroOrcamento: 2028);
      final faturada = carreto(status: 'finalizada', numeroOrcamento: 2027);

      expect(AgendaCarretoOcupacaoHelper.contaNaAgenda(orcamento), isFalse);
      expect(AgendaCarretoOcupacaoHelper.contaNaAgenda(faturada), isTrue);
    });

    test('cancelada e estornada nao ocupam o dia', () {
      expect(
        AgendaCarretoOcupacaoHelper.contaNaAgenda(
          carreto(status: 'finalizada', cancelada: true),
        ),
        isFalse,
      );
      expect(
        AgendaCarretoOcupacaoHelper.contaNaAgenda(
          carreto(status: 'estornada'),
        ),
        isFalse,
      );
      expect(
        AgendaCarretoOcupacaoHelper.contaNaAgenda(
          carreto(status: 'finalizada', statusEntrega: 'cancelada'),
        ),
        isFalse,
      );
    });

    test('orcamento no payload nao altera o totalizador do dia', () {
      final chave = AgendaCarretoOcupacaoMes.chaveDia(dia);
      final mes = AgendaCarretoOcupacaoMes(
        ano: 2026,
        mes: 9,
        quantidadePorDia: {chave: 2},
        itens: [
          item(
            vendaId: 10,
            numero: 2027,
            ehOrcamento: false,
            status: 'pendente',
          ),
          item(
            vendaId: 2028,
            numero: 2028,
            ehOrcamento: true,
            status: 'orcamento',
          ),
        ],
      );

      final filtrada = mes.somenteVendasFaturadas();

      expect(filtrada.quantidadeDoDia(dia), 1);
      expect(filtrada.itensDoDia(dia), hasLength(1));
      expect(filtrada.itensDoDia(dia).single.numero, 2027);
      expect(
        filtrada.itens.any((e) => e.numero == 2028 || e.ehOrcamento),
        isFalse,
      );
    });
  });

  group('consulta da agenda no ObjectBox', () {
    late Directory tempDir;
    late ObjectBox db;
    late VendaRepository vendas;

    setUp(() {
      enterSyncApplySilencioso();
      tempDir = Directory.systemTemp.createTempSync('sv_agenda_filtro_');
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

    int gravar({
      required String status,
      required int numeroOrcamento,
      required String clienteNome,
      bool cancelada = false,
      String statusEntrega = 'pendente',
    }) {
      final cliente = Cliente(nomeRazao: clienteNome);
      cliente.id = db.clienteBox.put(cliente);
      final venda = Venda(
        data: dia,
        status: status,
        numeroOrcamento: numeroOrcamento,
        numeroControle: status == 'finalizada' ? numeroOrcamento : 0,
        cancelada: cancelada,
        tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
        statusEntrega: statusEntrega,
        dataEntregaMarcada: dia,
        enderecoEntrega: 'Rua da Obra | Centro',
        finalizadaEm: status == 'finalizada' ? dia : null,
      );
      venda.cliente.target = cliente;
      return db.vendaBox.put(venda);
    }

    test(
      'orcamento nao faturado nao entra na consulta nem no total do dia',
      () {
        gravar(
          status: 'finalizada',
          numeroOrcamento: 2027,
          clienteNome: 'Cliente pago',
        );
        gravar(
          status: 'orcamento',
          numeroOrcamento: 2028,
          clienteNome: 'Joselvado dos Santos',
        );
        gravar(
          status: 'finalizada',
          numeroOrcamento: 2029,
          clienteNome: 'Venda estornada',
          cancelada: true,
        );

        final mes = vendas.ocupacaoAgendaCarretoMes(
          DateTime(2026, 9),
          incluirProdutos: false,
        );

        expect(mes.quantidadeDoDia(dia), 1);
        final doDia = mes.itensDoDia(dia);
        expect(doDia, hasLength(1));
        expect(doDia.single.numero, 2027);
        expect(doDia.single.ehOrcamento, isFalse);
        expect(
          doDia.any(
            (e) =>
                e.numero == 2028 ||
                e.clienteNome.contains('Joselvado'),
          ),
          isFalse,
        );
      },
    );
  }, skip: skipObjectBox);
}
