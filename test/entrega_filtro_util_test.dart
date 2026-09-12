import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_filtro_util.dart';
import 'package:sistema_vendas/domain/entregas/agenda_carreto_ocupacao.dart';
import 'package:sistema_vendas/domain/filtro_listagem_entregas.dart';
import 'package:sistema_vendas/ui/entregas/planejamento_entrega_dia.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('ehAtrasada ignora entregue e cancelada mas nao complemento pendente', () {
    final ontem = DateTime.now().subtract(const Duration(days: 1));
    final v = Venda(
      status: 'finalizada',
      statusEntrega: 'entregue_complemento_pendente',
      dataEntregaMarcada: ontem,
    );
    expect(EntregaFiltroUtil.ehAtrasada(v), isTrue);

    v.statusEntrega = 'entregue';
    expect(EntregaFiltroUtil.ehAtrasada(v), isFalse);
  });

  test('filtrarPorNumeroNota aceita hash e id', () {
    final v1 = Venda(id: 42, numeroOrcamento: 100);
    final v2 = Venda(id: 99, numeroOrcamento: 0);
    final r = EntregaFiltroUtil.filtrarPorNumeroNota([v1, v2], '#100');
    expect(r, hasLength(1));
    expect(r.first.id, 42);
  });

  test('filtrarPorNumeroNota encontra numero de controle', () {
    final v = Venda()
      ..id = 647
      ..status = 'finalizada'
      ..numeroOrcamento = 452
      ..numeroControle = 712;
    final r = EntregaFiltroUtil.filtrarPorNumeroNota([v], '712');
    expect(r, hasLength(1));
    expect(r.first.id, 647);
  });

  test('filtro Pendente inclui roteirizada (mesmo balde do patio)', () {
    expect(EntregaFiltroUtil.atendeStatusFiltro('pendente', 'pendente'), isTrue);
    expect(
      EntregaFiltroUtil.atendeStatusFiltro('roteirizada', 'pendente'),
      isTrue,
    );
    expect(
      EntregaFiltroUtil.atendeStatusFiltro('saiu_entrega', 'pendente'),
      isFalse,
    );
    expect(EntregaFiltroUtil.atendeStatusFiltro('roteirizada', 'todos'), isTrue);
  });

  group('agenda do dia', () {
    final dia = DateTime(2026, 9, 14);
    Venda venda({
      required int id,
      required String statusEntrega,
      DateTime? marcada,
    }) {
      return Venda(
        id: id,
        status: 'finalizada',
        statusEntrega: statusEntrega,
        tipoEntrega: 'entrega_loja',
        dataEntregaMarcada: marcada ?? dia,
      );
    }

    test('nao retorna pedido ja entregue na consulta de agenda do dia', () {
      final candidatas = [
        venda(id: 212, statusEntrega: 'entregue'),
        venda(id: 100, statusEntrega: 'pendente'),
        venda(id: 101, statusEntrega: 'roteirizada'),
        venda(id: 102, statusEntrega: 'saiu_entrega'),
        venda(id: 103, statusEntrega: 'reagendada'),
      ];

      final agenda = EntregaFiltroUtil.agendaDoDia(candidatas, dia);

      expect(agenda.map((v) => v.id), [100, 101, 102, 103]);
      expect(agenda.any((v) => v.statusEntrega == 'entregue'), isFalse);
    });

    test('nao retorna cancelada e ignora outro dia', () {
      final candidatas = [
        venda(id: 1, statusEntrega: 'cancelada'),
        venda(
          id: 2,
          statusEntrega: 'pendente',
          marcada: DateTime(2026, 9, 15),
        ),
        venda(id: 3, statusEntrega: 'entregue_complemento_pendente'),
      ];

      final agenda = EntregaFiltroUtil.agendaDoDia(candidatas, dia);

      expect(agenda.map((v) => v.id), [3]);
    });

    test('inclui concluidas apenas quando o filtro pede', () {
      final candidatas = [
        venda(id: 212, statusEntrega: 'entregue'),
        venda(id: 100, statusEntrega: 'pendente'),
      ];

      final comHistorico = EntregaFiltroUtil.agendaDoDia(
        candidatas,
        dia,
        incluirConcluidas: true,
      );

      expect(comHistorico.map((v) => v.id), [212, 100]);
    });

    test('aplicarEmMemoria com agenda do dia exclui entregue', () {
      final candidatas = [
        venda(id: 212, statusEntrega: 'entregue'),
        venda(id: 100, statusEntrega: 'pendente'),
        venda(id: 101, statusEntrega: 'saiu_entrega'),
      ];
      final filtro = FiltroListagemEntregas(
        statusEntrega: 'todos',
        dataMarcadaInicio: dia,
        dataMarcadaFim: DateTime(2026, 9, 14, 23, 59, 59, 999),
        incluirEntregasConcluidas: false,
      );

      final r = EntregaFiltroUtil.aplicarEmMemoria(candidatas, filtro);

      expect(r.map((v) => v.id), [100, 101]);
    });

    test('resumo dos badges do dia conta so pendentes', () {
      final entregas = [
        venda(id: 212, statusEntrega: 'entregue'),
        venda(id: 100, statusEntrega: 'pendente'),
        venda(id: 101, statusEntrega: 'saiu_entrega'),
        venda(id: 102, statusEntrega: 'cancelada'),
      ];

      final resumo = PlanejamentoEntregaDia.resumoDeEntregas(entregas);

      expect(resumo[PlanejamentoEntregaDia.chaveDeDateTime(dia)], 2);
    });

    test('contaNaAgenda nao ocupa o dia com entrega ja finalizada', () {
      final entregue = venda(id: 212, statusEntrega: 'entregue');
      final pendente = venda(id: 100, statusEntrega: 'pendente');

      expect(AgendaCarretoOcupacaoHelper.contaNaAgenda(entregue), isFalse);
      expect(AgendaCarretoOcupacaoHelper.contaNaAgenda(pendente), isTrue);
    });
  });
}
