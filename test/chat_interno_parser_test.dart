import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/chat_interno_parser.dart';

void main() {
  test('parseia @setor e #pedido', () {
    final p = ChatInternoParser.parse(
      '@caixa @pátio falta cimento no #1842',
    );
    expect(p.mencoes, containsAll(['caixa', 'separador']));
    expect(p.pedidoNumero, 1842);
    expect(p.temMencaoDirecionada, isTrue);
  });

  test('@patio e @expedicao viram separador', () {
    final p = ChatInternoParser.parse('@patio @expedicao conferir carga');
    expect(p.mencoes, equals({'separador'}));
  });

  test('mencao para o perfil da pessoa', () {
    expect(
      ChatInternoParser.mencionadaPara('caixa', ['caixa']),
      isTrue,
    );
    expect(
      ChatInternoParser.mencionadaPara('motorista', ['caixa']),
      isFalse,
    );
    expect(
      ChatInternoParser.mencionadaPara('caixa', ['todos']),
      isFalse,
    );
    expect(
      ChatInternoParser.mencionadaPara('separador', ['separador']),
      isTrue,
    );
  });

  test('sem @ nem # fica mural geral', () {
    final p = ChatInternoParser.parse('cafe na copa');
    expect(p.mencoes, isEmpty);
    expect(p.pedidoNumero, isNull);
    expect(p.temMencaoDirecionada, isFalse);
  });
}
