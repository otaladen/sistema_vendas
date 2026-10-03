import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/observacao_carreto.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/cupom_nao_fiscal_venda_pdf.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_cupom_builder.dart';
import 'package:sistema_vendas/ui/entregas/romaneio_pdf.dart';
import 'package:sistema_vendas/ui/entregas/romaneio_relatorios.dart';
import 'package:sistema_vendas/ui/vendas/carreto_observacao_dialog.dart';

const _logPatio =
    '[24/09/2026 16:10] RETIRADA_FUTURA por 1 - Mayara: '
    'Patio separou nesta loja (baixa estoque): Areia';

Venda _vendaCarreto({String observacao = ''}) => Venda(
  id: 900,
  numeroControle: 900,
  status: 'finalizada',
  tipoEntrega: 'entrega_loja',
  enderecoEntrega: 'Rua A, 10 | Iolanda | Lauro de Freitas - BA',
  observacaoEntrega: observacao,
  motoristaEntrega: 'Carlos',
  total: 100,
  formaPagamento: 'dinheiro',
);

List<ItemVenda> _itensCarreto() => [
  ItemVenda(
    nomeProduto: 'Cimento 50kg',
    quantidade: 2,
    precoUnitario: 50,
    precoCustoUnitario: 40,
    tipoEntregaItem: 'entrega_loja',
  ),
];

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

/// Abre o modal como o PDV faz; [aoFechar] recebe o texto salvo ou `null`.
Future<void> _abrirModal(
  WidgetTester tester, {
  required String observacaoInicial,
  required void Function(String?) aoFechar,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                aoFechar(
                  await mostrarCarretoObservacaoDialog(
                    context,
                    observacaoInicial: observacaoInicial,
                    clienteNome: 'Maria',
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  expect(find.text('Observações do carreto'), findsOneWidget);
}

void main() {
  group('ObservacaoCarreto (estrutura da venda)', () {
    test('textoEditavel mostra so o digitado, sem historico do patio', () {
      final gravada = 'Portao azul\n$_logPatio\nMotorista: Carlos';
      expect(ObservacaoCarreto.textoEditavel(gravada), 'Portao azul');
    });

    test('mesclar grava o digitado e preserva o historico interno', () {
      final gravada = 'Portao azul\n$_logPatio\nMotorista: Carlos';
      final nova = ObservacaoCarreto.mesclar(
        gravada,
        '  Descarregar na calçada \n\nLigar antes de sair ',
      );
      expect(
        nova,
        'Descarregar na calçada\nLigar antes de sair\n'
        '$_logPatio\nMotorista: Carlos',
      );
      expect(
        ObservacaoCarreto.textoEditavel(nova),
        'Descarregar na calçada\nLigar antes de sair',
      );
    });

    test('mesclar sem alteracao devolve o valor gravado intacto', () {
      final gravada = 'Portao azul [24/09/2026 15:54] RETIRADA_LOJA por 1';
      expect(ObservacaoCarreto.mesclar(gravada, 'Portao azul'), gravada);
    });

    test('mesclar com texto vazio remove so as observacoes digitadas', () {
      final gravada = 'Portao azul\n$_logPatio';
      expect(ObservacaoCarreto.mesclar(gravada, '   '), _logPatio);
    });

    test('linhasImpressao sai em caixa alta, sem log nem motorista', () {
      final venda = _vendaCarreto(
        observacao: 'Descarregar na calçada\n$_logPatio\nMotorista: Carlos',
      );
      expect(ObservacaoCarreto.linhasImpressao(venda), [
        'DESCARREGAR NA CALÇADA',
      ]);
      expect(ObservacaoCarreto.linhasHistoricoInterno(venda), [_logPatio]);
    });

    test('comprovante nao imprime observacoes em cotacao sem endereco', () {
      final venda = Venda(
        tipoEntrega: 'entrega_loja',
        statusEntrega: 'cotacao',
        observacaoEntrega: 'Ligar antes',
      );
      expect(ObservacaoCarreto.linhasImpressaoComprovante(venda), isEmpty);
    });

    test('observacao sobrevive a ida e volta do codec de sincronizacao', () {
      final venda = _vendaCarreto(
        observacao: ObservacaoCarreto.mesclar('', 'Subir escada'),
      );
      final copia = SyncEntityCodec.vendaCabecaDeMap(
        SyncEntityCodec.vendaParaMap(venda),
      );
      expect(ObservacaoCarreto.linhasImpressao(copia), ['SUBIR ESCADA']);
    });
  });

  group('CarretoObservacaoDialog', () {
    testWidgets('digitar + sugestao rapida + salvar grava na venda', (
      tester,
    ) async {
      String? salvo;
      var fechou = false;
      await _abrirModal(
        tester,
        observacaoInicial: '',
        aoFechar: (r) {
          salvo = r;
          fechou = true;
        },
      );

      await tester.enterText(
        find.byKey(CarretoObservacaoDialog.keyCampo),
        'Portao azul',
      );
      await tester.pump();
      await tester.tap(find.text('Descarregar na calçada'));
      await tester.pump();

      final preview = find.byKey(CarretoObservacaoDialog.keyPreview);
      expect(
        find.descendant(
          of: preview,
          matching: find.text(ObservacaoCarreto.tituloImpressao),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('> PORTAO AZUL')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.text('> DESCARREGAR NA CALÇADA'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(CarretoObservacaoDialog.keySalvar));
      await tester.pumpAndSettle();

      expect(fechou, isTrue);
      expect(salvo, 'Portao azul\nDescarregar na calçada');

      final venda = _vendaCarreto(observacao: 'Antiga\n$_logPatio');
      venda.observacaoEntrega = ObservacaoCarreto.mesclar(
        venda.observacaoEntrega,
        salvo!,
      );
      expect(
        venda.observacaoEntrega,
        'Portao azul\nDescarregar na calçada\n$_logPatio',
      );
      expect(ObservacaoCarreto.linhasImpressao(venda), [
        'PORTAO AZUL',
        'DESCARREGAR NA CALÇADA',
      ]);
    });

    testWidgets('sugestao ja presente e removida ao tocar de novo', (
      tester,
    ) async {
      String? salvo;
      await _abrirModal(
        tester,
        observacaoInicial: 'Portao azul\nDescarregar na calçada',
        aoFechar: (r) => salvo = r,
      );
      await tester.tap(find.text('Descarregar na calçada'));
      await tester.pump();
      await tester.tap(find.byKey(CarretoObservacaoDialog.keySalvar));
      await tester.pumpAndSettle();
      expect(salvo, 'Portao azul');
    });

    testWidgets('Ctrl+Enter salva e Esc cancela', (tester) async {
      String? salvo;
      var chamadas = 0;
      void aoFechar(String? r) {
        salvo = r;
        chamadas++;
      }

      await _abrirModal(
        tester,
        observacaoInicial: 'Ligar antes de sair',
        aoFechar: aoFechar,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(chamadas, 1);
      expect(salvo, 'Ligar antes de sair');

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(CarretoObservacaoDialog.keyCampo),
        'Nao deve gravar',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(chamadas, 2);
      expect(salvo, isNull);
      expect(find.text('Observações do carreto'), findsNothing);
    });
  });

  group('Impressao das observacoes do carreto', () {
    final venda = _vendaCarreto(
      observacao: 'Portao azul\nDescarregar na calçada\n$_logPatio',
    );

    test('comprovante ESC/POS imprime bloco proprio em negrito', () {
      final bytes = EscPosCupomBuilder.montar(
        CupomBalcaoDados(
          venda: venda,
          config: const EmpresaConfig(nomeLoja: 'Loja'),
          itens: _itensCarreto(),
          cliente: Cliente(nomeRazao: 'Maria', telefone: '71982250887'),
          totalRecebido: 100,
        ),
        largura: EscPosLarguraBobina.mm80,
        abrirGaveta: false,
      );
      final ascii = _ascii(bytes);

      // Ç e Õ saem em CP850 (bytes > 127), filtrados aqui.
      expect(ascii, contains('OBSERVAES DO CARRETO'));
      expect(ascii, contains('> PORTAO AZUL'));
      expect(ascii, contains('> DESCARREGAR NA CAL'));
      expect(ascii, isNot(contains('RETIRADA_FUTURA')));
      expect(ascii, isNot(contains('OBS/REFERENCIA')));

      final inicioBloco = _indexOfAscii(bytes, 'OBSERVA');
      final linhaObs = _indexOfAscii(bytes, '> PORTAO AZUL');
      final boldOn = _lastIndexOfSeq(bytes, [0x1B, 0x45, 1], before: linhaObs);
      final boldOff = _lastIndexOfSeq(bytes, [0x1B, 0x45, 0], before: linhaObs);
      expect(boldOn, lessThan(inicioBloco));
      expect(boldOn, greaterThan(boldOff), reason: 'Linha sai em negrito');
    });

    test('bloco de entrega do comprovante nao repete as observacoes', () {
      final linhas = EntregaVendaHelper.linhasBlocoEntregaImpressaoDetalhadas(
        venda: venda,
        itens: _itensCarreto(),
        incluirObservacoes: false,
      );
      expect(
        linhas.map((l) => l.texto).where((t) => t.contains('Portao azul')),
        isEmpty,
      );
    });

    test('cupom PDF gera com o bloco de observacoes', () async {
      final pdf = await CupomNaoFiscalVendaPdf.gerar(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Loja', modeloPdf: 'cupom'),
        itens: _itensCarreto(),
        totalRecebido: 100,
        troco: 0,
      );
      expect(pdf.bytes, isNotEmpty);
    });

    test('romaneio do motorista e separacao do patio usam o bloco', () async {
      expect(
        pwBlocoObservacoesCarreto(venda: venda, bobina: false),
        hasLength(1),
      );
      expect(
        pwBlocoObservacoesCarreto(venda: _vendaCarreto(), bobina: true),
        isEmpty,
      );
      expect(
        pwObservacoesCarretoDosPedidos(
          vendas: [venda, _vendaCarreto()],
          bobina: false,
        ),
        hasLength(1),
      );

      for (final tipo in [
        RelatorioEntregaTipo.romaneioMotoristaDia,
        RelatorioEntregaTipo.separacaoTotalDia,
      ]) {
        final bytes = await gerarRelatorioEntregaPdfBytes(
          tipo: tipo,
          entregasPeriodo: [venda],
          tituloPeriodo: '03/10/2026',
          emissao: DateTime(2026, 10, 3),
          motorista: 'Carlos',
          pdfUmaEntrega: (v, {parada}) =>
              pwBlocoObservacoesCarreto(venda: v, bobina: false).first,
          quantidadeEntrega: (_, item) => item.quantidade,
        );
        expect(bytes, isNotEmpty, reason: tipo.name);
      }
    });
  });
}

int _indexOfAscii(List<int> bytes, String texto) {
  final alvo = texto.codeUnits;
  for (var i = 0; i + alvo.length <= bytes.length; i++) {
    var ok = true;
    for (var j = 0; j < alvo.length; j++) {
      if (bytes[i + j] != alvo[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

int _lastIndexOfSeq(List<int> bytes, List<int> seq, {required int before}) {
  for (var i = before - seq.length; i >= 0; i--) {
    var ok = true;
    for (var j = 0; j < seq.length; j++) {
      if (bytes[i + j] != seq[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
