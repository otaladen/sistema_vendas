import '../data/nfe_saida_fiscal_store.dart';
import '../data/venda_repository.dart';
import '../domain/fiscal/nfe_cce_reconciliacao.dart';
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

  String get _storePath => _historicoStore.storeDirectoryPath;

  Future<NfeReconciliacaoLote> reconsultarProcessando() async {
    final fila = NfePendenciasService.listarProcessando(_historicoStore);
    var autorizadas = 0;
    var atualizadas = 0;
    for (final reg in fila) {
      final antes = reg.statusFocus;
      final antesChave = reg.chaveNfe;
      final atualizado = await _reconsultarRegistro(reg);
      if (atualizado.statusFocus != antes ||
          atualizado.chaveNfe != antesChave ||
          atualizado.cartasCorrecaoProcessando != reg.cartasCorrecaoProcessando) {
        atualizadas++;
      }
      if (atualizado.autorizada) autorizadas++;
    }
    return NfeReconciliacaoLote(
      total: fila.length,
      autorizadas: autorizadas,
      atualizadas: atualizadas,
    );
  }

  Future<NfeSaidaFiscalRegistro> reconsultarRegistro(
    NfeSaidaFiscalRegistro reg,
  ) async {
    return _reconsultarRegistro(reg);
  }

  Future<NfeSaidaFiscalRegistro> _reconsultarRegistro(
    NfeSaidaFiscalRegistro reg,
  ) async {
    final r = await _focusNfe.consultarNfe(reg.referenciaFocus);
    var atualizado = mesclarRegistroComResultadoFocus(reg, r);
    atualizado = await reconsultarCartasCorrecaoPendentes(
      registro: atualizado,
      focusNfe: _focusNfe,
      storeDirectoryPath: _storePath,
    );
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
    return atualizado;
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
