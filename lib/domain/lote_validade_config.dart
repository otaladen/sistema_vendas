import 'package:shared_preferences/shared_preferences.dart';

/// Parametros do semaforo de validade e Bota-Fora.
abstract final class LoteValidadeConfigStore {
  LoteValidadeConfigStore._();

  static const _kDiasAtencao = 'lote_validade_dias_atencao_v1';
  static const _kDiasCritico = 'lote_validade_dias_critico_v1';
  static const _kPctBotaFora = 'lote_validade_pct_bota_fora_v1';

  static const int diasAtencaoPadrao = 60;
  static const int diasCriticoPadrao = 30;
  static const double percentualBotaForaPadrao = 20;

  static int _diasAtencao = diasAtencaoPadrao;
  static int _diasCritico = diasCriticoPadrao;
  static double _pctBotaFora = percentualBotaForaPadrao;

  static int get diasAtencao => _diasAtencao;
  static int get diasCriticoBotaFora => _diasCritico;
  static double get percentualBotaForaPadraoEfetivo => _pctBotaFora;

  static Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    _diasAtencao = prefs.getInt(_kDiasAtencao) ?? diasAtencaoPadrao;
    _diasCritico = prefs.getInt(_kDiasCritico) ?? diasCriticoPadrao;
    _pctBotaFora =
        prefs.getDouble(_kPctBotaFora) ?? percentualBotaForaPadrao;
    if (_diasAtencao < 1) _diasAtencao = diasAtencaoPadrao;
    if (_diasCritico < 1) _diasCritico = diasCriticoPadrao;
    if (_diasCritico > _diasAtencao) _diasCritico = _diasAtencao;
    if (_pctBotaFora < 0) _pctBotaFora = 0;
    if (_pctBotaFora > 90) _pctBotaFora = 90;
  }

  static Future<void> salvar({
    int? diasAtencao,
    int? diasCriticoBotaFora,
    double? percentualBotaForaPadrao,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (diasAtencao != null) {
      _diasAtencao = diasAtencao.clamp(1, 3650);
      await prefs.setInt(_kDiasAtencao, _diasAtencao);
    }
    if (diasCriticoBotaFora != null) {
      _diasCritico = diasCriticoBotaFora.clamp(1, 3650);
      await prefs.setInt(_kDiasCritico, _diasCritico);
    }
    if (percentualBotaForaPadrao != null) {
      _pctBotaFora = percentualBotaForaPadrao.clamp(0, 90);
      await prefs.setDouble(_kPctBotaFora, _pctBotaFora);
    }
    if (_diasCritico > _diasAtencao) {
      _diasCritico = _diasAtencao;
      await prefs.setInt(_kDiasCritico, _diasCritico);
    }
  }
}

enum LoteValidadeSemaforo {
  verde,
  amarelo,
  laranja,
  vermelho,
  semValidade,
}

abstract final class LoteValidadeSemaforoUtil {
  LoteValidadeSemaforoUtil._();

  static LoteValidadeSemaforo deDiasRestantes(int? dias) {
    if (dias == null) return LoteValidadeSemaforo.semValidade;
    if (dias < 0) return LoteValidadeSemaforo.vermelho;
    if (dias <= LoteValidadeConfigStore.diasCriticoBotaFora) {
      return LoteValidadeSemaforo.laranja;
    }
    if (dias <= LoteValidadeConfigStore.diasAtencao) {
      return LoteValidadeSemaforo.amarelo;
    }
    return LoteValidadeSemaforo.verde;
  }

  static String rotulo(LoteValidadeSemaforo s) => switch (s) {
        LoteValidadeSemaforo.verde => 'Ok',
        LoteValidadeSemaforo.amarelo => 'Atencao',
        LoteValidadeSemaforo.laranja => 'Critico / Bota-fora',
        LoteValidadeSemaforo.vermelho => 'Vencido',
        LoteValidadeSemaforo.semValidade => 'Sem validade',
      };
}
