import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/troca_diferenca_caixa.dart';

void main() {
  group('TrocaDiferencaCaixa', () {
    test('2 joelhos com 0,15 a mais: cliente paga', () {
      final d = TrocaDiferencaCaixa.diferenca(
        valorSaida: 10.15,
        valorDevolvido: 10,
      );
      expect(d, 0.15);
      expect(TrocaDiferencaCaixa.clientePaga(d), isTrue);
      expect(TrocaDiferencaCaixa.lojaDevolve(d), isFalse);
    });

    test('valores iguais nao geram orcamento', () {
      final d = TrocaDiferencaCaixa.diferenca(
        valorSaida: 8.90,
        valorDevolvido: 8.90,
      );
      expect(d, 0);
      expect(TrocaDiferencaCaixa.clientePaga(d), isFalse);
    });

    test('devolvido maior: loja devolve, nao manda ao caixa', () {
      final d = TrocaDiferencaCaixa.diferenca(
        valorSaida: 5,
        valorDevolvido: 8.50,
      );
      expect(d, -3.50);
      expect(TrocaDiferencaCaixa.lojaDevolve(d), isTrue);
      expect(TrocaDiferencaCaixa.clientePaga(d), isFalse);
    });

    test('cartao de credito gera NFC-e da diferenca', () {
      expect(TrocaDiferencaCaixa.geraNfce('cartao_credito'), isTrue);
      expect(TrocaDiferencaCaixa.geraNfce('pix'), isTrue);
      expect(TrocaDiferencaCaixa.geraNfce('dinheiro'), isFalse);
      expect(TrocaDiferencaCaixa.parcelasCredito('cartao_credito', 3), 3);
      expect(TrocaDiferencaCaixa.parcelasCredito('dinheiro', 3), 1);
      expect(TrocaDiferencaCaixa.normalizarMeio('boleto'), 'dinheiro');
    });
  });
}
