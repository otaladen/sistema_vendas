import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/sessao_operacional_guard.dart';

void main() {
  tearDown(() {
    while (SessaoOperacionalGuard.fechamentoCaixaEmAndamento) {
      SessaoOperacionalGuard.marcarFechamentoCaixaConcluido();
    }
  });

  test('fechamento de caixa em andamento bloqueia operacao critica', () {
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);

    SessaoOperacionalGuard.marcarFechamentoCaixaIniciado();
    expect(SessaoOperacionalGuard.fechamentoCaixaEmAndamento, isTrue);
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isTrue);

    SessaoOperacionalGuard.marcarFechamentoCaixaConcluido();
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);
  });

  test('fechamentos aninhados (tentar novamente) liberam so no ultimo', () {
    SessaoOperacionalGuard.marcarFechamentoCaixaIniciado();
    SessaoOperacionalGuard.marcarFechamentoCaixaIniciado();
    SessaoOperacionalGuard.marcarFechamentoCaixaConcluido();
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isTrue);

    SessaoOperacionalGuard.marcarFechamentoCaixaConcluido();
    SessaoOperacionalGuard.marcarFechamentoCaixaConcluido();
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);
  });
}
