import 'fiscal_config.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../services/fiscal_config_store.dart';
import '../services/focus_nfe_service.dart';

/// Monta [FocusNfeConfig] a partir das configuracoes efetivas (UI ou [FiscalConfig]).
FocusNfeConfig criarFocusNfeConfigPadrao() {
  final cfg = FiscalConfigStore.efetivo;
  final token = cfg.apiToken.trim();
  final cnpj = cfg.cnpjEmitente.replaceAll(RegExp(r'\D'), '');
  final ie = cfg.inscricaoEstadualEmitente.replaceAll(RegExp(r'\D'), '');
  final regime = cfg.regimeTributarioEmitente.clamp(1, 3);

  final icmsPadrao = FiscalRegimePadrao.icmsSituacaoTributariaPadrao(cfg);
  final pisPadrao = FiscalRegimePadrao.pisCofinsSituacaoTributariaPadrao(cfg);

  if (cfg.homologacao) {
    return FocusNfeConfig(
      baseUrl: FocusNfeConfig.baseUrlHomologacao,
      apiToken: token,
      cnpjEmitente: cnpj.length == 14 ? cnpj : cfg.cnpjEmitente,
      inscricaoEstadualEmitente: ie,
      regimeTributarioEmitente: regime,
      ambiente: FocusNfeAmbiente.homologacao,
      naturezaOperacaoNfce: FiscalConfig.naturezaOperacaoNfce,
      naturezaOperacaoNfe: FiscalConfig.naturezaOperacaoNfe,
      icmsSituacaoTributariaPadrao: icmsPadrao,
      pisCofinsSituacaoPadrao: pisPadrao,
    );
  }
  return FocusNfeConfig(
    baseUrl: FocusNfeConfig.baseUrlProducao,
    apiToken: token,
    cnpjEmitente: cnpj.length == 14 ? cnpj : cfg.cnpjEmitente,
    inscricaoEstadualEmitente: ie,
    regimeTributarioEmitente: regime,
    ambiente: FocusNfeAmbiente.producao,
    naturezaOperacaoNfce: FiscalConfig.naturezaOperacaoNfce,
    naturezaOperacaoNfe: FiscalConfig.naturezaOperacaoNfe,
    icmsSituacaoTributariaPadrao: icmsPadrao,
    pisCofinsSituacaoPadrao: pisPadrao,
  );
}
