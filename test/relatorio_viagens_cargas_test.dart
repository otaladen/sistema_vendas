import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/cargas_entrega.dart';
import 'package:sistema_vendas/domain/relatorio_performance_entregas.dart';
import 'package:sistema_vendas/domain/relatorios/pendencia_entrega_relatorio.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/relatorios/relatorio_entregas_helper.dart';

void main() {
  const cimento = 1;
  final ini = DateTime(2030, 5, 1);
  final fim = DateTime(2030, 5, 31);

  LinhaCargaEntrega linha(double q) => LinhaCargaEntrega(
        produtoId: cimento,
        nomeProduto: 'Cimento',
        quantidade: q,
      );

  Venda vendaComPlano(
    List<CargaEntrega> cargas, {
    String status = 'pendente',
    String motorista = 'Atual',
    String obs = '',
  }) {
    return Venda(
      id: 7,
      numeroOrcamento: 70,
      status: 'finalizada',
      tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
      entregaPendente: true,
      statusEntrega: status,
      motoristaEntrega: motorista,
      caminhaoEntrega: 'HR',
      observacaoEntrega: obs,
      dataEntregaMarcada: DateTime(2030, 5, 17),
      cargasEntregaJson: CargasEntregaCodec.encode(cargas),
    );
  }

  group('performance por viagem', () {
    test('cada carga entregue conta para quem levou', () {
      final v = vendaComPlano([
        CargaEntrega(
          numero: 1,
          data: DateTime(2030, 5, 10),
          status: CargaEntrega.statusEntregue,
          entregueEm: DateTime(2030, 5, 10, 15),
          motorista: 'Joao',
          linhas: [linha(100)],
        ),
        CargaEntrega(
          numero: 2,
          data: DateTime(2030, 5, 12),
          status: CargaEntrega.statusEntregue,
          entregueEm: DateTime(2030, 5, 12, 9),
          motorista: 'Maria',
          linhas: [linha(60)],
        ),
        CargaEntrega(
          numero: 3,
          data: DateTime(2030, 5, 17),
          linhas: [linha(40)],
        ),
      ]);
      final lista = RelatorioPerformanceEntregas.agregar(
        entregas: [v],
        inicio: ini,
        fim: fim,
        dimensao: 'motorista',
      );
      expect(lista.map((e) => e.nome), containsAll(['Joao', 'Maria']));
      expect(lista.fold<int>(0, (s, e) => s + e.entregues), 2);
      expect(lista.any((e) => e.nome == 'Atual'), isFalse);
    });

    test('venda concluida nao conta a ultima carga duas vezes', () {
      final v = vendaComPlano(
        [
          for (var n = 1; n <= 2; n++)
            CargaEntrega(
              numero: n,
              data: DateTime(2030, 5, 10 + n),
              status: CargaEntrega.statusEntregue,
              motorista: 'Joao',
              linhas: [linha(100)],
            ),
        ],
        status: 'entregue',
      );
      final lista = RelatorioPerformanceEntregas.agregar(
        entregas: [v],
        inicio: ini,
        fim: fim,
        dimensao: 'motorista',
      );
      expect(lista.single.entregues, 2);
      expect(lista.single.insucessos, 0);
    });

    test('nao entregue na carga atual vira insucesso', () {
      final v = vendaComPlano(
        [
          CargaEntrega(
            numero: 1,
            data: DateTime(2030, 5, 10),
            status: CargaEntrega.statusEntregue,
            motorista: 'Atual',
            linhas: [linha(100)],
          ),
          CargaEntrega(
            numero: 2,
            data: DateTime(2030, 5, 17),
            linhas: [linha(100)],
          ),
        ],
        status: 'reagendada',
        obs: '[17/05/2030 10:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: '
            'Cliente ausente.',
      );
      final linhaAtual = RelatorioPerformanceEntregas.agregar(
        entregas: [v],
        inicio: ini,
        fim: fim,
        dimensao: 'motorista',
      ).single;
      expect(linhaAtual.entregues, 1);
      expect(linhaAtual.insucessos, 1);
    });
  });

  group('contagem de viagens', () {
    test('com plano conta cargas; sem plano conta 1', () {
      final v = vendaComPlano([
        CargaEntrega(
          numero: 1,
          data: DateTime(2030, 5, 10),
          status: CargaEntrega.statusEntregue,
          linhas: [linha(100)],
        ),
        CargaEntrega(numero: 2, data: DateTime(2030, 5, 17), linhas: [linha(100)]),
      ]);
      expect(relatorioViagensTotal(v), 2);
      expect(relatorioViagensFeitas(v), 1);
      expect(relatorioRotuloCargas(v), 'Carga 2/2');

      final simples = Venda(statusEntrega: 'entregue');
      expect(relatorioViagensTotal(simples), 1);
      expect(relatorioViagensFeitas(simples), 1);
      expect(relatorioRotuloCargas(simples), isEmpty);
    });
  });

  test('pendencia mostra so o que falta levar nas cargas pendentes', () {
    final v = vendaComPlano([
      CargaEntrega(
        numero: 1,
        data: DateTime(2030, 5, 10),
        status: CargaEntrega.statusEntregue,
        linhas: [linha(120)],
      ),
      CargaEntrega(numero: 2, data: DateTime(2030, 5, 17), linhas: [linha(80)]),
    ]);
    final item = ItemVenda(
      id: 5,
      nomeProduto: 'Cimento',
      quantidade: 200,
      escalaQuantidade: ItemVenda.escalaQuantidadeLiteral,
      precoUnitario: 40,
      precoCustoUnitario: 30,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    );
    item.produto.targetId = cimento;
    v.itens.add(item);

    final linhas = montarLinhasPendenciaEntrega(
      [v],
      filtroTipo: TipoPendenciaEntregaRelatorio.carreto,
    );
    expect(linhas.single.quantidadePendente, 80);
    expect(linhas.single.cargaRotulo, 'Carga 2/2');
  });
}
