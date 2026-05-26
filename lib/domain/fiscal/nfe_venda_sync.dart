import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import '../../model/venda.dart';

/// Replica status NF-e 55 no [Venda] para sync LAN entre PCs.
abstract final class NfeVendaSync {
  NfeVendaSync._();

  static void aplicarRegistroNoRepositorio({
    required VendaRepository vendaRepository,
    required NfeSaidaFiscalRegistro registro,
  }) {
    if (registro.vendaId <= 0) return;
    vendaRepository.registrarNfe55Situacao(
      vendaId: registro.vendaId,
      referenciaFocus: registro.referenciaFocus,
      chaveAcesso: registro.chaveNfe,
      numero: registro.numero,
      serie: registro.serie,
      protocolo: registro.protocolo,
      urlDanfe: registro.urlDanfe,
      urlXml: registro.urlXml,
      statusFocus: registro.statusFocus,
      urlXmlCancelamento: registro.urlXmlEventoCancelamento,
      emitidaEm: registro.emitidaEm,
    );
  }

  static NfeSaidaFiscalRegistro registroFromVenda(Venda venda) {
    return NfeSaidaFiscalRegistro(
      id: 'venda_sync_${venda.id}_${venda.nfeReferenciaFocus}',
      vendaId: venda.id,
      numeroOrcamento: venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id,
      clienteNome: venda.cliente.target?.nomeRazao ?? '',
      referenciaFocus: venda.nfeReferenciaFocus,
      statusFocus: venda.nfeStatusFocus,
      emitidaEm: venda.nfeEmitidaEm ?? venda.data,
      chaveNfe: venda.nfeChaveAcesso,
      numero: venda.nfeNumero,
      serie: venda.nfeSerie,
      protocolo: venda.nfeProtocolo,
      urlDanfe: venda.nfeUrlDanfe,
      urlXml: venda.nfeUrlXml,
      urlXmlEventoCancelamento: venda.nfeUrlXmlCancelamento,
      valorTotal: venda.total,
    );
  }

  /// Historico local + registros vindos das vendas sincronizadas.
  static List<NfeSaidaFiscalRegistro> listarHistoricoUnificado({
    required NfeSaidaFiscalStore store,
    required VendaRepository vendaRepository,
    int limiteVendas = 200,
  }) {
    final porRef = <String, NfeSaidaFiscalRegistro>{};
    for (final r in store.listar()) {
      final ref = r.referenciaFocus.trim();
      if (ref.isEmpty) continue;
      porRef[ref] = r;
    }

    for (final v in vendaRepository.listarVendasComDadosNfe55(
      limit: limiteVendas,
    )) {
      final ref = v.nfeReferenciaFocus.trim();
      if (ref.isEmpty) continue;
      final local = porRef[ref];
      if (local == null || local.emitidaEm.isBefore(v.nfeEmitidaEm ?? v.data)) {
        porRef[ref] = registroFromVenda(v);
      }
    }

    final lista = porRef.values.toList()
      ..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
    return lista;
  }
}
