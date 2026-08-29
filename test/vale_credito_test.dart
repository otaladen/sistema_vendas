import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/vale_credito.dart';

void main() {
  group('codigo', () {
    test('gera codigo do tamanho certo e so com o alfabeto permitido', () {
      final rnd = Random(7);
      for (var i = 0; i < 200; i++) {
        final c = ValeCreditoCodigo.gerar(random: rnd);
        expect(c.length, ValeCreditoCodigo.tamanho);
        expect(
          c.split('').every(ValeCreditoCodigo.alfabeto.contains),
          isTrue,
          reason: 'codigo $c saiu do alfabeto',
        );
      }
    });

    test('alfabeto nao tem as letras que confundem no cupom', () {
      for (final proibida in ['I', 'L', 'O', 'U']) {
        expect(ValeCreditoCodigo.alfabeto.contains(proibida), isFalse);
      }
    });

    test('aceita o codigo do jeito que o balconista digita', () {
      const canonico = 'A3K92PQ7';
      for (final digitado in [
        'A3K92PQ7',
        'a3k92pq7',
        'VL-A3K9-2PQ7',
        'vl a3k9 2pq7',
        '  A3K9-2PQ7  ',
      ]) {
        expect(ValeCreditoCodigo.normalizar(digitado), canonico);
      }
    });

    test('corrige as trocas classicas de O por 0 e de I ou L por 1', () {
      expect(ValeCreditoCodigo.normalizar('OI2345L7'), '01234517');
      expect(ValeCreditoCodigo.normalizar('O123456L'), '01234561');
      expect(ValeCreditoCodigo.normalizar('UBCDEFGH'), 'VBCDEFGH');
    });

    test('formata para leitura no comprovante', () {
      expect(ValeCreditoCodigo.formatar('a3k92pq7'), 'VL-A3K9-2PQ7');
    });

    test('valida tamanho', () {
      expect(ValeCreditoCodigo.valido('VL-A3K9-2PQ7'), isTrue);
      expect(ValeCreditoCodigo.valido('A3K9'), isFalse);
      expect(ValeCreditoCodigo.valido('A3K92PQ7X'), isFalse);
      expect(ValeCreditoCodigo.valido(''), isFalse);
    });
  });

  group('saldo', () {
    test('desconta o que ja foi usado', () {
      expect(
        ValeCreditoRegras.saldo(valorOriginal: 68, valorUtilizado: 20),
        48,
      );
    });

    test('nao fica negativo', () {
      expect(
        ValeCreditoRegras.saldo(valorOriginal: 68, valorUtilizado: 100),
        0,
      );
    });

    test('somar resgates quebrados nao deixa centavo fantasma', () {
      var usado = 0.0;
      for (var i = 0; i < 3; i++) {
        usado += 0.1;
      }
      expect(ValeCreditoRegras.saldo(valorOriginal: 0.3, valorUtilizado: usado),
          0);
    });
  });

  group('situacao', () {
    test('novo em folha fica aberto', () {
      expect(
        ValeCreditoRegras.situacao(
          valorOriginal: 68,
          valorUtilizado: 0,
          cancelado: false,
        ),
        ValeCreditoSituacao.aberto,
      );
    });

    test('usado em parte continua gastavel', () {
      final s = ValeCreditoRegras.situacao(
        valorOriginal: 68,
        valorUtilizado: 20,
        cancelado: false,
      );
      expect(s, ValeCreditoSituacao.parcial);
      expect(s.gastavel, isTrue);
    });

    test('gasto por completo vira usado', () {
      expect(
        ValeCreditoRegras.situacao(
          valorOriginal: 68,
          valorUtilizado: 68,
          cancelado: false,
        ),
        ValeCreditoSituacao.usado,
      );
    });

    test('cancelado ganha de tudo', () {
      expect(
        ValeCreditoRegras.situacao(
          valorOriginal: 68,
          valorUtilizado: 0,
          cancelado: true,
          validade: DateTime(2020, 1, 1),
        ),
        ValeCreditoSituacao.cancelado,
      );
    });

    test('vale gasto que venceu depois continua usado, nao vencido', () {
      expect(
        ValeCreditoRegras.situacao(
          valorOriginal: 68,
          valorUtilizado: 68,
          cancelado: false,
          validade: DateTime(2020, 1, 1),
          agora: DateTime(2026, 1, 1),
        ),
        ValeCreditoSituacao.usado,
      );
    });

    test('sem validade nunca vence', () {
      expect(
        ValeCreditoRegras.situacao(
          valorOriginal: 68,
          valorUtilizado: 0,
          cancelado: false,
          agora: DateTime(2099, 1, 1),
        ),
        ValeCreditoSituacao.aberto,
      );
    });
  });

  group('validade', () {
    test('vale ate o fim do dia da validade', () {
      final validade = DateTime(2026, 8, 19);
      expect(
        ValeCreditoRegras.vencido(
          validade: validade,
          agora: DateTime(2026, 8, 19, 23, 59, 58),
        ),
        isFalse,
      );
      expect(
        ValeCreditoRegras.vencido(
          validade: validade,
          agora: DateTime(2026, 8, 20, 0, 0, 1),
        ),
        isTrue,
      );
    });
  });

  group('resgate', () {
    ValeCreditoAvaliacao avaliar({
      double original = 68,
      double utilizado = 0,
      bool cancelado = false,
      double total = 100,
      DateTime? validade,
      DateTime? agora,
    }) =>
        ValeCreditoRegras.avaliarResgate(
          valorOriginal: original,
          valorUtilizado: utilizado,
          cancelado: cancelado,
          totalAPagar: total,
          validade: validade,
          agora: agora,
        );

    test('compra maior que o vale gasta o vale inteiro', () {
      final a = avaliar(original: 68, total: 100);
      expect(a.podeUsar, isTrue);
      expect(a.valorAplicavel, 68);
    });

    test('compra menor que o vale gasta so o que cabe e guarda o resto', () {
      final a = avaliar(original: 68, total: 25);
      expect(a.podeUsar, isTrue);
      expect(a.valorAplicavel, 25);
      expect(ValeCreditoRegras.saldo(valorOriginal: 68, valorUtilizado: 25),
          43);
    });

    test('usa apenas o saldo que sobrou', () {
      final a = avaliar(original: 68, utilizado: 50, total: 100);
      expect(a.valorAplicavel, 18);
    });

    test('cancelado nao passa', () {
      final a = avaliar(cancelado: true);
      expect(a.podeUsar, isFalse);
      expect(a.motivo, contains('cancelado'));
      expect(a.valorAplicavel, 0);
    });

    test('vencido nao passa', () {
      final a = avaliar(
        validade: DateTime(2026, 1, 1),
        agora: DateTime(2026, 8, 19),
      );
      expect(a.podeUsar, isFalse);
      expect(a.motivo, contains('vencido'));
    });

    test('ja gasto nao passa', () {
      final a = avaliar(original: 68, utilizado: 68);
      expect(a.podeUsar, isFalse);
      expect(a.motivo, contains('usado'));
    });

    test('venda sem valor a pagar nao consome o vale', () {
      final a = avaliar(total: 0);
      expect(a.podeUsar, isFalse);
      expect(a.valorAplicavel, 0);
    });
  });
}
