import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_status_transicao.dart';

void main() {
  group('EntregaStatusTransicao', () {
    test('idempotente no mesmo status', () {
      expect(EntregaStatusTransicao.mensagemBloqueio('entregue', 'entregue'), isNull);
      expect(
        EntregaStatusTransicao.mensagemBloqueio('reagendada', 'reagendada'),
        isNull,
      );
    });

    test('nao sobrescreve entregue com reagendada', () {
      final msg = EntregaStatusTransicao.mensagemBloqueio(
        'entregue',
        'reagendada',
      );
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('entregue'));
      expect(
        () => EntregaStatusTransicao.garantirPermitida('entregue', 'reagendada'),
        throwsA(isA<EntregaStatusConflitoException>()),
      );
    });

    test('nao sobrescreve reagendada com entregue atrasado', () {
      final msg = EntregaStatusTransicao.mensagemBloqueio(
        'reagendada',
        'entregue',
      );
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('reagendada'));
    });

    test('ciclo real apos reagendar continua permitido', () {
      expect(
        EntregaStatusTransicao.mensagemBloqueio('reagendada', 'roteirizada'),
        isNull,
      );
      expect(
        EntregaStatusTransicao.mensagemBloqueio('saiu_entrega', 'entregue'),
        isNull,
      );
      expect(
        EntregaStatusTransicao.mensagemBloqueio('saiu_entrega', 'reagendada'),
        isNull,
      );
    });

    test('cancelada e terminal', () {
      expect(
        EntregaStatusTransicao.mensagemBloqueio('cancelada', 'entregue'),
        isNotNull,
      );
      expect(EntregaStatusTransicao.ehTerminal('entregue'), isTrue);
      expect(EntregaStatusTransicao.ehTerminal('saiu_entrega'), isFalse);
    });
  });
}
