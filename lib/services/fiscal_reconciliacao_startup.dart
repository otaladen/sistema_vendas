import '../config/focus_nfe_runtime.dart';
import '../data/nfe_saida_fiscal_store.dart';
import '../data/nfe_saida_xml_store.dart';
import '../data/objectbox.dart';
import '../data/venda_repository.dart';
import '../domain/fiscal/nfce_xml_local_service.dart';
import '../domain/fiscal/nfe_xml_local_service.dart';
import '../services/fiscal_config_store.dart';
import '../services/focus_nfe_service.dart';
import '../services/nfce_reconciliacao_service.dart';
import '../services/nfe_reconciliacao_service.dart';

/// Reconciliacao fiscal silenciosa na abertura do app (F9).
abstract final class FiscalReconciliacaoStartup {
  FiscalReconciliacaoStartup._();

  static Future<void> executarSeConfigurado({
    required ObjectBox objectBox,
  }) async {
    if (!FiscalConfigStore.configurado) return;

    final vendaRepository = VendaRepository(objectBox);
    final focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
    final storePath = objectBox.storeDirectoryPath;

    try {
      await NfceReconciliacaoService(
        vendaRepository: vendaRepository,
        focusNfe: focus,
      ).reconsultarTodasPendentes();
    } catch (_) {}

    try {
      final xmlNfe = NfeXmlLocalService(NfeSaidaXmlStore(storePath));
      await NfeReconciliacaoService(
        historicoStore: NfeSaidaFiscalStore(storePath),
        vendaRepository: vendaRepository,
        focusNfe: focus,
        xmlLocal: xmlNfe,
      ).reconsultarProcessando();
    } catch (_) {}

    try {
      await NfceXmlLocalService.processarFilaRetry(storePath);
    } catch (_) {}

    try {
      await NfeXmlLocalService.processarFilaRetry(storePath);
    } catch (_) {}
  }
}
