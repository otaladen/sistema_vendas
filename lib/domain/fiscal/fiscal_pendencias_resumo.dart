import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import 'nfe_pendencias_service.dart';

/// Contagem operacional de pendencias fiscais (badge no menu).
class FiscalPendenciasResumo {
  const FiscalPendenciasResumo({
    required this.nfceAguardandoSefaz,
    required this.nfeProcessando,
    required this.nfeRejeitadas,
  });

  final int nfceAguardandoSefaz;
  final int nfeProcessando;
  final int nfeRejeitadas;

  int get total =>
      nfceAguardandoSefaz + nfeProcessando + nfeRejeitadas;

  bool get temPendencias => total > 0;
}

abstract final class FiscalPendenciasResumoService {
  FiscalPendenciasResumoService._();

  static FiscalPendenciasResumo contar({
    required VendaRepository vendaRepository,
  }) {
    final nfce = vendaRepository.listarComNfcePendenteFocus().length;
    final storePath = vendaRepository.objectBox.storeDirectoryPath;
    final nfeStore = NfeSaidaFiscalStore(storePath);
    final nfeProc = NfePendenciasService.listarProcessando(
      nfeStore,
      vendaRepository: vendaRepository,
    ).length;
    final nfeRej = NfePendenciasService.listarRejeitadasRecentes(
      nfeStore,
      vendaRepository: vendaRepository,
    ).length;
    return FiscalPendenciasResumo(
      nfceAguardandoSefaz: nfce,
      nfeProcessando: nfeProc,
      nfeRejeitadas: nfeRej,
    );
  }
}
