import 'fiscal_config.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../services/configuracoes_service.dart';
import '../services/fiscal_config_store.dart';
import '../services/focus_nfe_service.dart';

/// Monta [FocusNfeConfig] a partir de [FiscalConfigDados] (global da loja).
FocusNfeConfig criarFocusNfeConfigDe(FiscalConfigDados cfg) {
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

/// Usa cache atual ([FiscalConfigStore.efetivo]) — chame [ConfiguracoesService.carregarFiscalGlobal] antes.
FocusNfeConfig criarFocusNfeConfigPadrao() =>
    criarFocusNfeConfigDe(FiscalConfigStore.efetivo);

/// Carrega fiscal global e monta config Focus (PDV, caixa, NF-e).
Future<FocusNfeConfig> criarFocusNfeConfigGlobal(
  ConfiguracoesService configuracoes,
) async {
  final cfg = await configuracoes.carregarFiscalGlobal();
  return criarFocusNfeConfigDe(cfg);
}
