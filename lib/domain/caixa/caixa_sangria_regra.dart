/// Regras de sangria: teto sem supervisor e teto fisico da gaveta.
abstract final class CaixaSangriaRegra {
  CaixaSangriaRegra._();

  /// Default de fabrica (R$). 0 = toda sangria pede supervisor.
  static const double limitePadraoSemSupervisor = 200;

  static const double _toleranciaCentavos = 0.009;

  static double normalizarLimiteSemSupervisor(double valor) {
    if (valor.isNaN || valor.isInfinite) return limitePadraoSemSupervisor;
    if (valor < 0) return 0;
    return valor;
  }

  /// True quando o valor passa do teto (0 = sempre pede senha).
  static bool exigeSupervisor({
    required double valor,
    required double limiteSemSupervisor,
  }) {
    if (valor <= 0) return false;
    final limite = normalizarLimiteSemSupervisor(limiteSemSupervisor);
    return valor > limite + _toleranciaCentavos;
  }

  /// True se a sangria e maior que o dinheiro esperado na gaveta.
  static bool excedeSaldoGaveta({
    required double valor,
    required double dinheiroGaveta,
  }) {
    if (valor <= 0) return false;
    final saldo = dinheiroGaveta.isFinite ? dinheiroGaveta : 0.0;
    return valor > saldo + _toleranciaCentavos;
  }

  static String? mensagemSaldoInsuficiente({
    required double valor,
    required double dinheiroGaveta,
  }) {
    if (!excedeSaldoGaveta(valor: valor, dinheiroGaveta: dinheiroGaveta)) {
      return null;
    }
    final saldo = dinheiroGaveta.isFinite && dinheiroGaveta > 0
        ? dinheiroGaveta
        : 0.0;
    return 'Sangria maior que o dinheiro na gaveta '
        '(disponivel: ${_fmt(saldo)}).';
  }

  static String _fmt(double v) {
    final n = v.abs().toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $n';
  }
}
