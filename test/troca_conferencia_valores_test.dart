import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/troca_conferencia_valores.dart';
import 'package:sistema_vendas/domain/troca_diferenca_caixa.dart';

void main() {
  group('TrocaConferenciaValores', () {
    test('subtotal soma quantidade x preco praticado', () {
      expect(
        TrocaConferenciaValores.subtotalSaida(const [
          TrocaSaidaLinhaConferencia(
            quantidade: 2,
            precoUnitarioPraticado: 10.15,
          ),
          TrocaSaidaLinhaConferencia(
            quantidade: 1,
            precoUnitarioPraticado: 5,
          ),
        ]),
        25.30,
      );
    });

    test('diferenca considera preco unitario alterado na saida', () {
      const creditoDevolvido = 20.0;
      final diffPadrao = TrocaConferenciaValores.diferenca(
        linhasSaida: const [
          TrocaSaidaLinhaConferencia(
            quantidade: 2,
            precoUnitarioPraticado: 10,
          ),
        ],
        valorDevolvido: creditoDevolvido,
      );
      expect(diffPadrao, 0);
      expect(TrocaDiferencaCaixa.clientePaga(diffPadrao), isFalse);

      final diffComAcrescimo = TrocaConferenciaValores.diferenca(
        linhasSaida: const [
          TrocaSaidaLinhaConferencia(
            quantidade: 2,
            precoUnitarioPraticado: 10.15,
          ),
        ],
        valorDevolvido: creditoDevolvido,
      );
      expect(diffComAcrescimo, 0.30);
      expect(TrocaDiferencaCaixa.clientePaga(diffComAcrescimo), isTrue);

      final diffComDesconto = TrocaConferenciaValores.diferenca(
        linhasSaida: const [
          TrocaSaidaLinhaConferencia(
            quantidade: 2,
            precoUnitarioPraticado: 9,
          ),
        ],
        valorDevolvido: creditoDevolvido,
      );
      expect(diffComDesconto, -2);
      expect(TrocaDiferencaCaixa.lojaDevolve(diffComDesconto), isTrue);
    });

    test('ignora linhas com quantidade zero', () {
      expect(
        TrocaConferenciaValores.subtotalSaida(const [
          TrocaSaidaLinhaConferencia(
            quantidade: 0,
            precoUnitarioPraticado: 100,
          ),
          TrocaSaidaLinhaConferencia(
            quantidade: 1,
            precoUnitarioPraticado: 7.5,
          ),
        ]),
        7.5,
      );
    });
  });
}
