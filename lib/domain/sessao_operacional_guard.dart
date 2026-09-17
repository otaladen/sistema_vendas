/// Contadores de telas criticas que impedem operacoes pesadas (ex.: backup que
/// fecha o ObjectBox) enquanto o PDV esta em uso ou terminais estao na API.
class SessaoOperacionalGuard {
  SessaoOperacionalGuard._();

  static int _pdvAbertos = 0;
  static int _terminaisWs = 0;

  static bool get pdvEmUso => _pdvAbertos > 0;

  static bool get terminaisConectados => _terminaisWs > 0;

  /// PDV local ou terminal leve com WebSocket: nao fechar ObjectBox.
  static bool get operacaoCriticaAtiva => pdvEmUso || terminaisConectados;

  static void marcarPdvAberto() => _pdvAbertos++;

  static void marcarPdvFechado() {
    if (_pdvAbertos > 0) _pdvAbertos--;
  }

  static void atualizarTerminaisWs(int quantidade) {
    _terminaisWs = quantidade < 0 ? 0 : quantidade;
  }
}
