import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/api/lan_api_client.dart';
import 'package:sistema_vendas/domain/entrega_filtro_util.dart';
import 'package:sistema_vendas/domain/filtro_listagem_entregas.dart';
import 'package:sistema_vendas/model/motorista.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/entregas_page.dart';

class _FakeVendaRepo {
  _FakeVendaRepo(this.entregas);
  final List<Venda> entregas;
  dynamic get objectBox => throw StateError('sem ObjectBox');

  ResultadoListagemEntregas carregarListagemEntregasComResumo({
    required FiltroListagemEntregas filtroLista,
    required FiltroListagemEntregas filtroContagem,
  }) {
    final lista = EntregaFiltroUtil.aplicarEmMemoria(entregas, filtroLista);
    return ResultadoListagemEntregas(
      entregas: lista,
      atrasadas: 0,
      pendentesHoje: lista.where(EntregaFiltroUtil.ehAgendaHoje).length,
    );
  }

  List listarItensPorVenda(int id) {
    try {
      return entregas.firstWhere((v) => v.id == id).itens.toList();
    } catch (_) {
      return const [];
    }
  }
}

class _FakeMotoristaRepo {
  List<Motorista> listarAtivos() => [
        Motorista(id: 1, nome: 'Joao', ativo: true),
      ];
}

class _FakeVendedorRepo {
  dynamic obterPorId(int id) => null;
}

Venda _venda({
  required int n,
  String tipo = 'entrega_loja',
  String mot = '',
  String statusEntrega = 'pendente',
}) {
  return LanApiClient.vendaCompletaDeMap({
    'id': n,
    'data': DateTime.now().toUtc().toIso8601String(),
    'total': 100.0,
    'status': 'finalizada',
    'cancelada': false,
    'clienteId': 3,
    'vendedorId': 2,
    'tipoEntrega': tipo,
    'statusEntrega': statusEntrega,
    'entregaPendente': statusEntrega != 'entregue',
    'numeroOrcamento': n,
    'enderecoEntrega': 'Rua A, Centro',
    'motoristaEntrega': mot,
    'dataEntregaMarcada': DateTime.now().toUtc().toIso8601String(),
    'itens': [
      {
        'id': n * 10,
        'produtoId': 1,
        'nomeProduto': 'Cimento',
        'quantidade': 2,
        'precoUnitario': 50.0,
        'precoCustoUnitario': 30.0,
        'tipoEntregaItem': 'entrega_loja',
      }
    ],
  });
}

void main() {
  testWidgets('EntregasPage simples opens with detached API vendas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntregasPage(
          vendaRepository: _FakeVendaRepo([_venda(n: 42)]),
          produtoRepository: Object(),
          motoristaRepository: _FakeMotoristaRepo(),
          vendedorRepository: _FakeVendedorRepo(),
          usuarioAtual: 'admin',
          podeGerenciarStatusEntrega: true,
          podeRegistrarPodEntrega: true,
          podeRegistrarDevolucaoTrocaSemSenha: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Entregas'), findsWidgets);
    expect(find.textContaining('#42'), findsWidgets);
  });

  testWidgets('EntregasPage advanced lista opens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntregasPage(
          vendaRepository: _FakeVendaRepo([_venda(n: 99, mot: 'Joao', tipo: 'misto')]),
          produtoRepository: Object(),
          motoristaRepository: _FakeMotoristaRepo(),
          vendedorRepository: _FakeVendedorRepo(),
          usuarioAtual: 'admin',
          podeGerenciarStatusEntrega: true,
          podeRegistrarPodEntrega: true,
          podeRegistrarDevolucaoTrocaSemSenha: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final avancada = find.text('Visão avançada');
    expect(avancada, findsOneWidget);
    await tester.tap(avancada);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('#99'), findsWidgets);
  });

  testWidgets('EntregasPage nao lista entrega ja concluida na agenda do dia',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EntregasPage(
          vendaRepository: _FakeVendaRepo([
            _venda(n: 100, mot: 'Joao'),
            _venda(n: 212, mot: 'Joao', statusEntrega: 'entregue'),
          ]),
          produtoRepository: Object(),
          motoristaRepository: _FakeMotoristaRepo(),
          vendedorRepository: _FakeVendedorRepo(),
          usuarioAtual: 'admin',
          podeGerenciarStatusEntrega: true,
          podeRegistrarPodEntrega: true,
          podeRegistrarDevolucaoTrocaSemSenha: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('#100'), findsWidgets);
    expect(find.textContaining('#212'), findsNothing);
  });
}
