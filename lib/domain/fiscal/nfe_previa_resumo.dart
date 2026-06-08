import '../../config/fiscal_config.dart';

/// Resumo legivel do payload NF-e para conferencia antes do envio.
class NfePreviaResumo {
  const NfePreviaResumo({
    required this.referencia,
    required this.ambiente,
    required this.emitenteCnpj,
    required this.destinatarioNome,
    required this.destinatarioDocumento,
    required this.destinatarioUf,
    required this.consumidorFinal,
    required this.localDestino,
    required this.valorProdutos,
    required this.valorFrete,
    required this.valorDesconto,
    required this.valorTotal,
    required this.quantidadeItens,
    required this.temDuplicatas,
    required this.quantidadeDuplicatas,
    required this.naturezaOperacao,
    required this.modalidadeFrete,
  });

  final String referencia;
  final String ambiente;
  final String emitenteCnpj;
  final String destinatarioNome;
  final String destinatarioDocumento;
  final String destinatarioUf;
  final bool consumidorFinal;
  final String localDestino;
  final double valorProdutos;
  final double valorFrete;
  final double valorDesconto;
  final double valorTotal;
  final int quantidadeItens;
  final bool temDuplicatas;
  final int quantidadeDuplicatas;
  final String naturezaOperacao;
  final String modalidadeFrete;

  String get rotuloLocalDestino {
    switch (localDestino) {
      case '2':
        return 'Interestadual';
      case '3':
        return 'Exterior';
      default:
        return 'Interna (BA)';
    }
  }

  /// Rotulo SEFAZ da modalidade de frete (modFrete).
  String get rotuloModalidadeFrete {
    switch (modalidadeFrete) {
      case '0':
        return 'CIF — emitente (0)';
      case '1':
        return 'FOB — destinatario (1)';
      case '2':
        return 'Terceiros (2)';
      case '3':
        return 'Proprio remetente (3)';
      case '4':
        return 'Proprio destinatario (4)';
      case '9':
        return 'Sem ocorrencia de transporte (9)';
      default:
        return 'Modalidade $modalidadeFrete';
    }
  }
}

abstract final class NfePreviaResumoBuilder {
  NfePreviaResumoBuilder._();

  static NfePreviaResumo fromPayload(
    Map<String, dynamic> payload, {
    required String referencia,
  }) {
    final doc = (payload['cnpj_destinatario'] ?? payload['cpf_destinatario'] ?? '')
        .toString();
    final dups = payload['duplicatas'];
    final qtdDup = dups is List ? dups.length : 0;

    return NfePreviaResumo(
      referencia: referencia,
      ambiente: FiscalConfig.ambiente,
      emitenteCnpj: (payload['cnpj_emitente'] ?? FiscalConfig.cnpjEmitente)
          .toString(),
      destinatarioNome: (payload['nome_destinatario'] ?? '').toString(),
      destinatarioDocumento: doc,
      destinatarioUf: (payload['uf_destinatario'] ?? '').toString(),
      consumidorFinal: payload['consumidor_final']?.toString() == '1',
      localDestino: (payload['local_destino'] ?? '1').toString(),
      valorProdutos: _dbl(payload['valor_produtos']),
      valorFrete: _dbl(payload['valor_frete']),
      valorDesconto: _dbl(payload['valor_desconto']),
      valorTotal: _dbl(payload['valor_total']),
      quantidadeItens: payload['items'] is List
          ? (payload['items'] as List).length
          : 0,
      temDuplicatas: qtdDup > 0,
      quantidadeDuplicatas: qtdDup,
      naturezaOperacao: (payload['natureza_operacao'] ?? '').toString(),
      modalidadeFrete: (payload['modalidade_frete'] ?? '0').toString(),
    );
  }

  static double _dbl(Object? v) =>
      double.tryParse(v?.toString() ?? '') ?? 0;
}
