import '../../data/app_config_repository.dart';

/// Regras de autorizacao de supervisor no fechamento/conferencia do caixa.
abstract final class CaixaDivergenciaAutorizacao {
  CaixaDivergenciaAutorizacao._();

  /// Limite configurado em Configuracoes (`limiteDivergenciaCaixa`), normalizado.
  static double limiteSemSupervisor(EmpresaConfig config) =>
      normalizarLimiteSemSupervisor(config.limiteDivergenciaCaixa);

  static double normalizarLimiteSemSupervisor(double valor) {
    if (valor.isNaN || valor.isInfinite) {
      return const EmpresaConfig().limiteDivergenciaCaixa;
    }
    return valor < 0 ? 0 : valor;
  }

  /// Diferenca total da conferencia: soma (declarado - esperado) por meio.
  static double divergenciaTotalConferencia({
    required double declaradoDinheiro,
    required double esperadoDinheiro,
    required double declaradoPix,
    required double esperadoPix,
    required double declaradoDebito,
    required double esperadoDebito,
    required double declaradoCredito,
    required double esperadoCredito,
  }) {
    return (declaradoDinheiro - esperadoDinheiro) +
        (declaradoPix - esperadoPix) +
        (declaradoDebito - esperadoDebito) +
        (declaradoCredito - esperadoCredito);
  }

  /// Magnitude usada na regra: sobra (+) e falta (-) tratadas igualmente.
  static double magnitudeDivergencia(double divergenciaTotal) =>
      divergenciaTotal.abs();

  /// Exige dialogo/senha de supervisor quando |divergencia| > limite.
  static bool exigeAutorizacaoSupervisor({
    required double divergenciaTotal,
    required double limiteSemSupervisor,
  }) {
    final limite = normalizarLimiteSemSupervisor(limiteSemSupervisor);
    return magnitudeDivergencia(divergenciaTotal) > limite;
  }

  static bool liberadoSemSupervisor({
    required double divergenciaTotal,
    required double limiteSemSupervisor,
  }) =>
      !exigeAutorizacaoSupervisor(
        divergenciaTotal: divergenciaTotal,
        limiteSemSupervisor: limiteSemSupervisor,
      );
}
