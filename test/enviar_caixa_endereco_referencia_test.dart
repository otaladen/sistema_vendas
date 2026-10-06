import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/vendas/enviar_caixa_entrega_ui.dart';

void main() {
  group('Enviar ao caixa — ponto de referencia x observacao carreto', () {
    test('textoPontoReferenciaDiscreto formata Ref. ou retorna null', () {
      expect(
        EnviarCaixaEntregaUi.textoPontoReferenciaDiscreto(''),
        isNull,
      );
      expect(
        EnviarCaixaEntregaUi.textoPontoReferenciaDiscreto('  portao azul  '),
        '📌 Ref.: portao azul',
      );
    });

    testWidgets('ponto de referencia no bloco Onde em tom secundario', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnviarCaixaPontoReferenciaLinha(
              referencia: 'Esquina com farmacia',
            ),
          ),
        ),
      );

      final refFinder = find.text('📌 Ref.: Esquina com farmacia');
      expect(refFinder, findsOneWidget);

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      final style = tester.widget<Text>(refFinder).style;
      expect(style?.color, theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('ponto de referencia vazio nao renderiza linha', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EnviarCaixaPontoReferenciaLinha(referencia: ''),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets(
      'card observacoes carreto mostra so F8, nao ponto de referencia do cadastro',
      (tester) async {
        const obsCarreto = 'Ligar 10 min antes';
        const refCadastro = 'Portao de ferro preto';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnviarCaixaObservacoesCarretoResumo(
                observacaoGravada: obsCarreto,
              ),
            ),
          ),
        );

        expect(find.textContaining('LIGAR 10 MIN ANTES'), findsOneWidget);
        expect(find.textContaining(refCadastro), findsNothing);
        expect(find.textContaining('📌 Ref.'), findsNothing);
      },
    );

    testWidgets(
      'observacao gravada misturada com referencia antiga exibe so linhas digitadas',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnviarCaixaObservacoesCarretoResumo(
                observacaoGravada: 'Subir rampa\n[01/10/2026 08:00] SAIU',
              ),
            ),
          ),
        );

        expect(find.textContaining('SUBIR RAMPA'), findsOneWidget);
        expect(find.textContaining('01/10/2026'), findsNothing);
      },
    );
  });
}
