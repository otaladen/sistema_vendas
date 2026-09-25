import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/api/lan_api_client.dart';
import 'package:sistema_vendas/domain/entrega_filtro_util.dart';
import 'package:sistema_vendas/domain/filtro_listagem_entregas.dart';
import 'package:sistema_vendas/model/motorista.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/entregas/entregas_barra_compacta.dart';
import 'package:sistema_vendas/ui/entregas_page.dart';

class _FakeVendaRepo {
  _FakeVendaRepo(this.entregas);
  final List<Venda> entregas;
  final List<FiltroListagemEntregas> filtrosLista = [];
  dynamic get objectBox => throw StateError('sem ObjectBox');

  ResultadoListagemEntregas carregarListagemEntregasComResumo({
    required FiltroListagemEntregas filtroLista,
    required FiltroListagemEntregas filtroContagem,
  }) {
    if (!identical(filtroLista, filtroContagem)) filtrosLista.add(filtroLista);
    final paraContagem =
        EntregaFiltroUtil.aplicarEmMemoria(entregas, filtroContagem);
    return ResultadoListagemEntregas(
      entregas: EntregaFiltroUtil.aplicarEmMemoria(entregas, filtroLista),
      atrasadas: paraContagem.where(EntregaFiltroUtil.ehAtrasada).length,
      pendentesHoje: paraContagem.where(EntregaFiltroUtil.ehAgendaHoje).length,
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

DateTime _diaRelativo(int deltaDias, {int hora = 10}) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + deltaDias, hora);
}

Venda _venda({
  required int n,
  required DateTime marcada,
  String statusEntrega = 'pendente',
}) {
  return LanApiClient.vendaCompletaDeMap({
    'id': n,
    'data': marcada.toUtc().toIso8601String(),
    'total': 100.0,
    'status': 'finalizada',
    'cancelada': false,
    'clienteId': 3,
    'vendedorId': 2,
    'tipoEntrega': 'entrega_loja',
    'statusEntrega': statusEntrega,
    'entregaPendente': statusEntrega != 'entregue',
    'numeroOrcamento': n,
    'enderecoEntrega': 'Rua A, Centro',
    'motoristaEntrega': 'Joao',
    'dataEntregaMarcada': marcada.toUtc().toIso8601String(),
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

/// 8 atrasadas (pendentes com data antes de hoje), 1 atrasada ja entregue,
/// 2 para hoje e 1 para amanha.
List<Venda> _cenario() {
  return [
    for (var i = 0; i < 8; i++)
      _venda(
        n: 101 + i,
        marcada: _diaRelativo(-(i + 1), hora: i.isEven ? 23 : 8),
        statusEntrega: i == 3 ? 'saiu_entrega' : 'pendente',
      ),
    _venda(n: 301, marcada: _diaRelativo(-2), statusEntrega: 'entregue'),
    _venda(n: 201, marcada: _diaRelativo(0, hora: 0)),
    _venda(n: 202, marcada: _diaRelativo(0, hora: 15)),
    _venda(n: 401, marcada: _diaRelativo(1)),
  ];
}

const _idsAtrasadas = [101, 102, 103, 104, 105, 106, 107, 108];
const _idsNaoAtrasadas = [301, 201, 202, 401];

FilterChip _chip(WidgetTester tester, Key key) =>
    tester.widget<FilterChip>(find.byKey(key));

Future<_FakeVendaRepo> _abrirVisaoAvancada(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'entregas_visao_simples': false,
    'entregas_dicas_visiveis': false,
  });
  final repo = _FakeVendaRepo(_cenario());
  await tester.pumpWidget(
    MaterialApp(
      home: EntregasPage(
        vendaRepository: repo,
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
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  expect(find.text('Visão avançada'), findsNothing);
  return repo;
}

void main() {
  group('EntregaFiltroUtil atrasadas', () {
    test('limite e o ultimo instante de ontem (data < hoje, sem horario)', () {
      final agora = DateTime(2026, 9, 24, 16, 9);
      final fim = EntregaFiltroUtil.fimDataMarcadaAtrasadas(agora);
      expect(fim.isBefore(DateTime(2026, 9, 24)), isTrue);
      expect(fim.isAfter(DateTime(2026, 9, 23, 23, 59, 59)), isTrue);
    });

    test('aplicarEmMemoria com filtro de atrasadas lista so as 8 atrasadas', () {
      final filtro = FiltroListagemEntregas(
        dataMarcadaFim: EntregaFiltroUtil.fimDataMarcadaAtrasadas(),
        dataMarcadaFiltradaNoBanco: true,
        apenasAtrasadas: true,
        incluirEntregasConcluidas: false,
      );
      final r = EntregaFiltroUtil.aplicarEmMemoria(_cenario(), filtro);
      expect(r.map((v) => v.id), unorderedEquals(_idsAtrasadas));
    });
  });

  testWidgets('chip Atr. X ativa o filtro e lista so as entregas atrasadas',
      (tester) async {
    final repo = await _abrirVisaoAvancada(tester);

    expect(find.text('Atr. 8'), findsOneWidget);
    expect(_chip(tester, EntregasBarraCompacta.chaveChipAtrasadas).selected,
        isFalse);
    // Visao padrao: dia de hoje no calendario.
    expect(find.textContaining('#201'), findsWidgets);
    expect(find.textContaining('#101'), findsNothing);

    await tester.tap(find.byKey(EntregasBarraCompacta.chaveChipAtrasadas));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    expect(_chip(tester, EntregasBarraCompacta.chaveChipAtrasadas).selected,
        isTrue);
    expect(repo.filtrosLista.last.apenasAtrasadas, isTrue);
    expect(repo.filtrosLista.last.apenasPendentesHoje, isFalse);
    expect(repo.filtrosLista.last.dataMarcadaInicio, isNull);

    for (final id in _idsAtrasadas) {
      expect(find.textContaining('#$id'), findsWidgets, reason: '#$id atrasada');
    }
    for (final id in _idsNaoAtrasadas) {
      expect(find.textContaining('#$id'), findsNothing, reason: '#$id');
    }
  });

  testWidgets('segundo clique no chip ativo volta para a visao do calendario',
      (tester) async {
    final repo = await _abrirVisaoAvancada(tester);
    final chip = find.byKey(EntregasBarraCompacta.chaveChipAtrasadas);

    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_chip(tester, EntregasBarraCompacta.chaveChipAtrasadas).selected,
        isFalse);
    expect(repo.filtrosLista.last.apenasAtrasadas, isFalse);
    expect(find.textContaining('#201'), findsWidgets);
    expect(find.textContaining('#101'), findsNothing);
  });

  testWidgets('Atrasadas, Pendentes hoje e Concluidas sao exclusivos',
      (tester) async {
    final repo = await _abrirVisaoAvancada(tester);

    await tester.tap(find.byKey(EntregasBarraCompacta.chaveChipAtrasadas));
    await tester.pump();
    await tester.tap(find.byKey(EntregasBarraCompacta.chaveChipPendentesHoje));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_chip(tester, EntregasBarraCompacta.chaveChipAtrasadas).selected,
        isFalse);
    expect(_chip(tester, EntregasBarraCompacta.chaveChipPendentesHoje).selected,
        isTrue);
    expect(repo.filtrosLista.last.apenasPendentesHoje, isTrue);
    expect(find.textContaining('#201'), findsWidgets);
    expect(find.textContaining('#101'), findsNothing);

    final concluidas = find.byKey(EntregasBarraCompacta.chaveChipConcluidas);
    if (concluidas.evaluate().isNotEmpty) {
      await tester.tap(concluidas);
      await tester.pump();
      expect(
        _chip(tester, EntregasBarraCompacta.chaveChipPendentesHoje).selected,
        isFalse,
      );
      expect(_chip(tester, EntregasBarraCompacta.chaveChipConcluidas).selected,
          isTrue);
    }
  });
}
