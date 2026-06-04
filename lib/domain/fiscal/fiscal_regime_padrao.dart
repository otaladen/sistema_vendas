import '../../config/fiscal_config.dart';
import '../../services/fiscal_config_store.dart';

/// Padroes fiscais conforme regime do emitente (configuracao da loja).
abstract final class FiscalRegimePadrao {
  FiscalRegimePadrao._();

  /// 1 = Simples Nacional | 3 = Regime Normal (Lucro Presumido/Real).
  static const int simplesNacional = 1;
  static const int regimeNormal = 3;

  static int regimeEfetivo([FiscalConfigDados? cfg]) {
    final r = (cfg ?? FiscalConfigStore.efetivo).regimeTributarioEmitente;
    return normalizarRegime(r);
  }

  static int normalizarRegime(int? valor) {
    if (valor == simplesNacional) return simplesNacional;
    if (valor == 2) return 2; // SN excesso sublimite (tratado como SN)
    return regimeNormal;
  }

  static bool ehSimplesNacional([FiscalConfigDados? cfg]) {
    final r = regimeEfetivo(cfg);
    return r == simplesNacional || r == 2;
  }

  /// CSOSN (3 digitos) no Simples; CST (2 digitos) no Regime Normal.
  static String icmsSituacaoTributariaPadrao([FiscalConfigDados? cfg]) {
    if (ehSimplesNacional(cfg)) {
      return FiscalConfig.icmsSituacaoTributariaSimples;
    }
    return FiscalConfig.icmsSituacaoTributariaPadrao;
  }

  static String pisCofinsSituacaoTributariaPadrao([FiscalConfigDados? cfg]) {
    if (ehSimplesNacional(cfg)) {
      return FiscalConfig.pisCofinsSituacaoTributariaSimples;
    }
    return FiscalConfig.pisCofinsSituacaoTributariaPadrao;
  }

  static String rotuloRegime(int regime) {
    if (normalizarRegime(regime) == simplesNacional || regime == 2) {
      return 'Simples Nacional';
    }
    return 'Regime Normal';
  }

  static String rotuloIcmsCampo([FiscalConfigDados? cfg]) =>
      ehSimplesNacional(cfg) ? 'CSOSN ICMS' : 'CST ICMS';

  static String resumoPadroesEmissao(int regime) {
    final icms = regime == simplesNacional || regime == 2
        ? FiscalConfig.icmsSituacaoTributariaSimples
        : FiscalConfig.icmsSituacaoTributariaPadrao;
    final pis = regime == simplesNacional || regime == 2
        ? FiscalConfig.pisCofinsSituacaoTributariaSimples
        : FiscalConfig.pisCofinsSituacaoTributariaPadrao;
    final campo = regime == simplesNacional || regime == 2 ? 'CSOSN' : 'CST';
    return '$campo $icms · PIS/COFINS $pis';
  }
}
