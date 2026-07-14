/// Contadores de telas criticas que impedem operacoes pesadas (ex.: backup que
/// fecha o ObjectBox) enquanto o PDV esta em uso.
class SessaoOperacionalGuard {
  SessaoOperacionalGuard._();

  static int _pdvAbertos = 0;

  static bool get pdvEmUso => _pdvAbertos > 0;

  static void marcarPdvAberto() => _pdvAbertos++;

  static void marcarPdvFechado() {
    if (_pdvAbertos > 0) _pdvAbertos--;
  }
}
