import '../../data/nfe_saida_fiscal_store.dart';
import '../../services/focus_nfe_service.dart';

/// Mescla registro local com retorno da API Focus.
NfeSaidaFiscalRegistro mesclarRegistroComResultadoFocus(
  NfeSaidaFiscalRegistro base,
  FocusNfeEmissaoResultado resultado,
) {
  return NfeSaidaFiscalRegistro(
    id: base.id,
    vendaId: base.vendaId,
    numeroOrcamento: base.numeroOrcamento,
    clienteNome: base.clienteNome,
    referenciaFocus: resultado.referencia.isNotEmpty
        ? resultado.referencia
        : base.referenciaFocus,
    statusFocus: resultado.statusFocus.isNotEmpty
        ? resultado.statusFocus
        : base.statusFocus,
    emitidaEm: base.emitidaEm,
    statusSefaz: resultado.statusSefaz.isNotEmpty
        ? resultado.statusSefaz
        : base.statusSefaz,
    chaveNfe: resultado.chaveNfe.isNotEmpty ? resultado.chaveNfe : base.chaveNfe,
    numero: resultado.numero.isNotEmpty ? resultado.numero : base.numero,
    serie: resultado.serie.isNotEmpty ? resultado.serie : base.serie,
    protocolo:
        resultado.protocolo.isNotEmpty ? resultado.protocolo : base.protocolo,
    urlDanfe: resultado.urlDanfe.isNotEmpty ? resultado.urlDanfe : base.urlDanfe,
    urlXml: resultado.urlXml.isNotEmpty ? resultado.urlXml : base.urlXml,
    urlXmlEventoCancelamento: resultado.urlXmlCancelamento.isNotEmpty
        ? resultado.urlXmlCancelamento
        : base.urlXmlEventoCancelamento,
    mensagemSefaz:
        resultado.mensagem.isNotEmpty ? resultado.mensagem : base.mensagemSefaz,
    modalidadeFrete: base.modalidadeFrete,
    placaVeiculo: base.placaVeiculo,
    volumes: base.volumes,
    pesoBrutoKg: base.pesoBrutoKg,
    valorTotal: base.valorTotal,
    urlPdfCartaCorrecao: base.urlPdfCartaCorrecao,
    urlXmlCartaCorrecao: base.urlXmlCartaCorrecao,
    numeroCartaCorrecao: base.numeroCartaCorrecao,
  );
}
