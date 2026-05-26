import 'fiscal_config.dart';
import '../services/fiscal_config_store.dart';
import '../services/focus_nfe_service.dart';

/// Monta [FocusNfeConfig] a partir das configuracoes efetivas (UI ou [FiscalConfig]).
FocusNfeConfig criarFocusNfeConfigPadrao() {
  final cfg = FiscalConfigStore.efetivo;
  final token = cfg.apiToken.trim();
  final cnpj = cfg.cnpjEmitente.replaceAll(RegExp(r'\D'), '');
  final ie = cfg.inscricaoEstadualEmitente.replaceAll(RegExp(r'\D'), '');
  final regime = cfg.regimeTributarioEmitente.clamp(1, 3);

  if (cfg.homologacao) {
    return FocusNfeConfig.homologacao(
      apiToken: token,
      cnpjEmitente: cnpj.length == 14 ? cnpj : cfg.cnpjEmitente,
      inscricaoEstadualEmitente: ie,
      regimeTributarioEmitente: regime,
      naturezaOperacaoNfce: FiscalConfig.naturezaOperacaoNfce,
      naturezaOperacaoNfe: FiscalConfig.naturezaOperacaoNfe,
    );
  }
  return FocusNfeConfig.producao(
    apiToken: token,
    cnpjEmitente: cnpj.length == 14 ? cnpj : cfg.cnpjEmitente,
    inscricaoEstadualEmitente: ie,
    regimeTributarioEmitente: regime,
    naturezaOperacaoNfce: FiscalConfig.naturezaOperacaoNfce,
    naturezaOperacaoNfe: FiscalConfig.naturezaOperacaoNfe,
  );
}
