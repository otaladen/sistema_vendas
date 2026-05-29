import '../data/nfe_saida_fiscal_store.dart';
import '../data/venda_repository.dart';
import '../domain/fiscal/nfe_pendencias_service.dart';
import '../domain/fiscal/nfe_registro_focus_merge.dart';
import '../domain/fiscal/nfe_venda_sync.dart';
import '../domain/fiscal/nfe_xml_local_service.dart';
import '../services/focus_nfe_service.dart';

/// Reconsulta NF-e modelo 55 em processamento (F9 / painel fiscal).
class NfeReconciliacaoService {
  NfeReconciliacaoService({
    required NfeSaidaFiscalStore historicoStore,
    required VendaRepository vendaRepository,
    required FocusNfeService focusNfe,
    NfeXmlLocalService? xmlLocal,
  })  : _historicoStore = historicoStore,
        _vendaRepository = vendaRepository,
        _focusNfe = focusNfe,
        _xmlLocal = xmlLocal;

  final NfeSaidaFiscalStore _historicoStore;
  final VendaRepository _vendaRepository;
  final FocusNfeService _focusNfe;
  final NfeXmlLocalService? _xmlLocal;

  Future<NfeReconciliacaoLote> reconsultarProcessando() async {
    final fila = NfePendenciasService.listarProcessando(_historicoStore);
    var autorizadas = 0;
    var atualizadas = 0;
    for (final reg in fila) {
      final r = await _focusNfe.consultarNfe(reg.referenciaFocus);
      final atualizado = mesclarRegistroComResultadoFocus(reg, r);
      if (atualizado.statusFocus != reg.statusFocus ||
          atualizado.chaveNfe != reg.chaveNfe) {
        atualizadas++;
      }
      _historicoStore.gravar(atualizado);
      NfeVendaSync.aplicarRegistroNoRepositorio(
        vendaRepository: _vendaRepository,
        registro: atualizado,
      );
      if (_xmlLocal != null && atualizado.urlXml.trim().isNotEmpty) {
        await _xmlLocal!.tentarArquivar(
          chaveAcesso: atualizado.chaveNfe,
          urlXml: atualizado.urlXml,
        );
      }
      if (atualizado.autorizada) autorizadas++;
    }
    return NfeReconciliacaoLote(
      total: fila.length,
      autorizadas: autorizadas,
      atualizadas: atualizadas,
    );
  }
}

class NfeReconciliacaoLote {
  const NfeReconciliacaoLote({
    required this.total,
    required this.autorizadas,
    required this.atualizadas,
  });

  final int total;
  final int autorizadas;
  final int atualizadas;
}
