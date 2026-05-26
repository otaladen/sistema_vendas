import 'fechamento_tributos_xml.dart';

/// Linha de nota fiscal de saida (NFC-e / NF-e) para fechamento contabil.
class NotaFiscalFechamentoItem {
  const NotaFiscalFechamentoItem({
    required this.modelo,
    required this.dataEmissao,
    required this.numero,
    required this.serie,
    required this.chaveAcesso,
    required this.documentoDestinatario,
    required this.valorTotal,
    required this.status,
    required this.statusFocus,
    required this.urlXml,
    this.referenciaFocus = '',
    this.vendaId = 0,
    this.razaoSocialDestinatario = '',
    this.protocoloSefaz = '',
    this.mensagemSefaz = '',
    this.urlXmlEventoCancelamento = '',
    this.tributos = FechamentoTributosXml.vazio,
    this.vendaOperacionalCancelada = false,
    this.incluirNoZip = true,
  });

  /// `65` (NFC-e) ou `55` (NF-e).
  final String modelo;
  final DateTime dataEmissao;
  final String numero;
  final String serie;
  final String chaveAcesso;
  final String documentoDestinatario;
  final double valorTotal;
  final String status;
  final String statusFocus;
  final String urlXml;
  final String referenciaFocus;
  final int vendaId;
  final String razaoSocialDestinatario;
  final String protocoloSefaz;
  final String mensagemSefaz;
  final String urlXmlEventoCancelamento;
  final FechamentoTributosXml tributos;
  final bool vendaOperacionalCancelada;
  final bool incluirNoZip;

  bool get autorizada =>
      statusFocus == 'autorizado' ||
      status.toLowerCase() == 'autorizada';

  bool get cancelada {
    final s = statusFocus.toLowerCase();
    final st = status.toLowerCase();
    return s == 'cancelado' ||
        st.contains('cancelad') ||
        mensagemSefaz.toLowerCase().contains('cancelad');
  }

  bool get rejeitada {
    final s = statusFocus.toLowerCase();
    return s == 'erro_autorizacao' ||
        s == 'denegado' ||
        status.toLowerCase() == 'rejeitada';
  }

  String get cfopExibicao => tributos.cfopPredominante.isNotEmpty
      ? tributos.cfopPredominante
      : '';

  String get alertaVendaOperacional =>
      vendaOperacionalCancelada ? 'SIM — venda cancelada no ERP' : '';

  String nomeArquivoXml({bool canceladaSuffix = false}) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final prefixo = modelo == '65' ? 'NFCe' : 'NFe';
    final sufixo = canceladaSuffix ? '_cancelada' : '';
    if (chave.length >= 44) {
      return '${prefixo}_$chave$sufixo.xml';
    }
    final num = numero.replaceAll(RegExp(r'\D'), '');
    if (num.isNotEmpty) {
      return '${prefixo}_${num}_$modelo$sufixo.xml';
    }
    return '${prefixo}_${referenciaFocus.isNotEmpty ? referenciaFocus : vendaId}$sufixo.xml';
  }

  String get nomeArquivoEventoCancelamento {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length >= 44) return 'evento_cancelamento_$chave.xml';
    return 'evento_cancelamento_${referenciaFocus.isNotEmpty ? referenciaFocus : vendaId}.xml';
  }
}
