import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/caixa_auditoria_repository.dart';
import 'package:sistema_vendas/domain/sessao_caixa_referencia.dart';

void main() {
  test('monta sessao fechada pareando abertura e fechamento', () {
    final abertura = DateTime.utc(2026, 3, 10, 12);
    final fechamento = DateTime.utc(2026, 3, 10, 20);
    final eventos = [
      CaixaAuditoriaRegistro(
        em: abertura,
        evento: 'abertura_caixa',
        usuario: 'admin',
        operadorCaixa: 'Maria',
        detalhes: {'operador': 'Maria', 'fundoTroco': 100},
      ),
      CaixaAuditoriaRegistro(
        em: fechamento,
        evento: 'fechamento_caixa',
        usuario: 'admin',
        operadorCaixa: 'Maria',
        detalhes: {
          'operador': 'Maria',
          'aberturaEm': abertura.toIso8601String(),
          'fundoTroco': 100,
          'suprimentos': 50,
          'sangrias': 20,
        },
      ),
    ];
    final lista = SessaoCaixaCatalogo.montarDeAuditoria(eventos);
    expect(lista.length, 1);
    expect(lista.first.operador, 'Maria');
    expect(lista.first.aberturaEm, abertura);
    expect(lista.first.fechamentoEm, fechamento);
    expect(lista.first.suprimentos, 50);
  });

  test('segundo turno no mesmo dia comeca apos fechamento anterior', () {
    final manha = DateTime(2026, 9, 8, 12, 43);
    final tarde = DateTime(2026, 9, 8, 13, 6);
    final ctx = [
      CaixaAuditoriaRegistro(
        em: manha,
        evento: 'fechamento_caixa',
        usuario: 'u',
        operadorCaixa: 'tavinho',
        detalhes: {'operador': 'tavinho'},
      ),
      CaixaAuditoriaRegistro(
        em: tarde,
        evento: 'fechamento_caixa',
        usuario: 'u',
        operadorCaixa: 'Mayrena',
        detalhes: {'operador': 'Mayrena'},
      ),
    ];
    final tardeSessao = SessaoCaixaReferencia.montarSessaoFechamento(
      fechamento: ctx[1],
      numero: 1,
      fechamentosContexto: ctx,
    );
    expect(
      tardeSessao.aberturaEm.isAfter(manha),
      isTrue,
      reason: 'nao pode incluir vendas do caixa da manha',
    );
    final (ini, fim) = tardeSessao.intervaloFiltroVendasUtc();
    expect(ini.isAfter(manha.toUtc()), isTrue);
    expect(fim.isAfter(ini), isTrue);
  });
}
