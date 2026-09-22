import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/caixa/caixa_divergencia_autorizacao.dart';

void main() {
  group('CaixaDivergenciaAutorizacao', () {
    test('limite vem de EmpresaConfig.limiteDivergenciaCaixa (nao zero fixo)', () {
      const config = EmpresaConfig(limiteDivergenciaCaixa: 100);
      expect(CaixaDivergenciaAutorizacao.limiteSemSupervisor(config), 100);
    });

    test('divergencia R\$ 27 com limite R\$ 100 libera sem supervisor', () {
      expect(
        CaixaDivergenciaAutorizacao.liberadoSemSupervisor(
          divergenciaTotal: 27,
          limiteSemSupervisor: 100,
        ),
        isTrue,
      );
      expect(
        CaixaDivergenciaAutorizacao.exigeAutorizacaoSupervisor(
          divergenciaTotal: 27,
          limiteSemSupervisor: 100,
        ),
        isFalse,
      );
    });

    test('falta R\$ 27 (negativo) com limite R\$ 100 libera sem supervisor', () {
      expect(
        CaixaDivergenciaAutorizacao.liberadoSemSupervisor(
          divergenciaTotal: -27,
          limiteSemSupervisor: 100,
        ),
        isTrue,
      );
    });

    test('divergencia R\$ 150 com limite R\$ 100 exige supervisor', () {
      expect(
        CaixaDivergenciaAutorizacao.exigeAutorizacaoSupervisor(
          divergenciaTotal: 150,
          limiteSemSupervisor: 100,
        ),
        isTrue,
      );
    });

    test('divergencia exatamente no limite libera sem supervisor', () {
      expect(
        CaixaDivergenciaAutorizacao.liberadoSemSupervisor(
          divergenciaTotal: 100,
          limiteSemSupervisor: 100,
        ),
        isTrue,
      );
      expect(
        CaixaDivergenciaAutorizacao.liberadoSemSupervisor(
          divergenciaTotal: -100,
          limiteSemSupervisor: 100,
        ),
        isTrue,
      );
    });

    test('divergenciaTotalConferencia soma por meio de pagamento', () {
      expect(
        CaixaDivergenciaAutorizacao.divergenciaTotalConferencia(
          declaradoDinheiro: 127,
          esperadoDinheiro: 100,
          declaradoPix: 50,
          esperadoPix: 50,
          declaradoDebito: 0,
          esperadoDebito: 0,
          declaradoCredito: 0,
          esperadoCredito: 0,
        ),
        closeTo(27, 0.001),
      );
    });
  });
}
