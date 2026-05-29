import '../../data/nfe_saida_fiscal_store.dart';
import '../../services/focus_nfe_service.dart';
import 'nfe_carta_correcao_registro.dart';

/// Mescla registro local com retorno da API Focus.
NfeSaidaFiscalRegistro mesclarRegistroComResultadoFocus(
  NfeSaidaFiscalRegistro base,
  FocusNfeEmissaoResultado resultado,
) {
  var reg = NfeSaidaFiscalRegistro(
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
    cartasCorrecao: base.cartasCorrecao,
  );
  return mesclarCartaCorrecaoDoPayload(reg, resultado.payloadBruto);
}

/// Atualiza CC-e a partir do JSON bruto da Focus (consulta NF-e / CC-e).
NfeSaidaFiscalRegistro mesclarCartaCorrecaoDoPayload(
  NfeSaidaFiscalRegistro base,
  Map<String, dynamic>? json,
) {
  if (json == null || json.isEmpty) return base;
  var reg = base;
  final cartasRaw = json['cartas_correcao'] ?? json['carta_correcao'];
  if (cartasRaw is List) {
    for (final item in cartasRaw) {
      if (item is! Map) continue;
      final cce = _cceFromFocusJson(item.map((k, v) => MapEntry(k.toString(), v)));
      if (cce != null) reg = _aplicarCceMesclada(reg, cce);
    }
  }
  final unica = _cceFromFocusJson(json);
  if (unica != null) reg = _aplicarCceMesclada(reg, unica);
  return reg;
}

NfeSaidaFiscalRegistro _aplicarCceMesclada(
  NfeSaidaFiscalRegistro base,
  NfeCartaCorrecaoRegistro cce,
) {
  NfeCartaCorrecaoRegistro? existente;
  for (final c in base.cartasCorrecao) {
    if (c.numeroSequencia == cce.numeroSequencia) {
      existente = c;
      break;
    }
  }
  return base.comNovaCartaCorrecao(
    cce.copyWith(
      textoCorrecao: cce.textoCorrecao.isNotEmpty
          ? cce.textoCorrecao
          : (existente?.textoCorrecao ?? ''),
      urlPdf: cce.urlPdf.isNotEmpty ? cce.urlPdf : (existente?.urlPdf ?? ''),
      urlXml: cce.urlXml.isNotEmpty ? cce.urlXml : (existente?.urlXml ?? ''),
      protocolo:
          cce.protocolo.isNotEmpty ? cce.protocolo : (existente?.protocolo ?? ''),
      statusFocus: cce.statusFocus.isNotEmpty
          ? cce.statusFocus
          : (existente?.statusFocus ?? 'autorizado'),
      emitidaEm: existente?.emitidaEm,
    ),
  );
}

/// Mescla resultado de consulta CC-e no registro (preserva texto local).
NfeSaidaFiscalRegistro mesclarCartaCorrecaoComResultado(
  NfeSaidaFiscalRegistro base,
  FocusNfeCartaCorrecaoResultado resultado, {
  String textoCorrecao = '',
}) {
  if (!resultado.sucesso) return base;
  final seq = resultado.numeroSequencia > 0 ? resultado.numeroSequencia : 1;
  NfeCartaCorrecaoRegistro? existente;
  for (final c in base.cartasCorrecao) {
    if (c.numeroSequencia == seq) {
      existente = c;
      break;
    }
  }
  return base.comNovaCartaCorrecao(
    NfeCartaCorrecaoRegistro(
      numeroSequencia: seq,
      textoCorrecao: textoCorrecao.isNotEmpty
          ? textoCorrecao
          : (existente?.textoCorrecao ?? ''),
      urlPdf: resultado.urlPdf.isNotEmpty
          ? resultado.urlPdf
          : (existente?.urlPdf ?? ''),
      urlXml: resultado.urlXml.isNotEmpty
          ? resultado.urlXml
          : (existente?.urlXml ?? ''),
      protocolo: resultado.protocolo.isNotEmpty
          ? resultado.protocolo
          : (existente?.protocolo ?? ''),
      statusFocus: resultado.statusFocus.isNotEmpty
          ? resultado.statusFocus
          : (existente?.statusFocus ?? 'autorizado'),
      emitidaEm: existente?.emitidaEm,
    ),
  );
}

NfeCartaCorrecaoRegistro? _cceFromFocusJson(Map<String, dynamic> json) {
  final numero = ((json['numero_carta_correcao'] as num?) ??
          (json['numero_sequencia'] as num?) ??
          (json['numeroSequencia'] as num?) ??
          0)
      .toInt();
  if (numero <= 0) return null;
  final pdf = (json['caminho_pdf_carta_correcao'] ??
          json['url_pdf_carta_correcao'] ??
          json['urlPdf'] ??
          '')
      .toString()
      .trim();
  final xml = (json['caminho_xml_carta_correcao'] ??
          json['url_xml_carta_correcao'] ??
          json['urlXml'] ??
          '')
      .toString()
      .trim();
  final protocolo = (json['protocolo'] ??
          json['numero_protocolo'] ??
          json['protocolo_sefaz'] ??
          '')
      .toString()
      .trim();
  final statusFocus = (json['status'] ?? json['status_sefaz'] ?? json['statusFocus'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  final texto = (json['correcao'] ?? json['textoCorrecao'] ?? '').toString();
  return NfeCartaCorrecaoRegistro(
    numeroSequencia: numero,
    textoCorrecao: texto,
    urlPdf: pdf,
    urlXml: xml,
    protocolo: protocolo,
    statusFocus: statusFocus.isEmpty ? 'autorizado' : statusFocus,
  );
}
