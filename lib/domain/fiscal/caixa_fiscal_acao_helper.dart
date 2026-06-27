import '../../model/cliente.dart';
import '../../model/venda.dart';
import '../pagamento_orcamento.dart';
import 'cliente_fiscal_helper.dart';
import 'venda_documento_fiscal_mutex.dart';

/// Define qual documento fiscal o caixa deve sugerir/disparar apos o pagamento.
abstract final class CaixaFiscalAcaoHelper {
  CaixaFiscalAcaoHelper._();

  /// `cupom` | `nfce` | `nfe55` | null
  static String? acaoAutomaticaPorPagamento({
    required Venda venda,
    Cliente? cliente,
  }) {
    final base = _acaoBasePorPagamento(venda);
    if (base == null) return null;
    if (base == 'nfce' && ClienteFiscalHelper.clienteExigeNfe55(cliente)) {
      return 'nfe55';
    }
    return base;
  }

  static String? _acaoBasePorPagamento(Venda venda) {
    switch (venda.formaPagamento) {
      case 'dinheiro':
      case 'fiado':
        return 'cupom';
      case 'pix':
      case 'cartao_credito':
      case 'cartao_debito':
      case 'transferencia':
        return 'nfce';
      case 'misto':
        return _acaoBasePagamentoMisto(venda);
      default:
        return 'nfce';
    }
  }

  static String? _acaoBasePagamentoMisto(Venda venda) {
    final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
    if (linhas.isEmpty) return null;
    const eletronicos = {
      'pix',
      'cartao_credito',
      'cartao_debito',
      'transferencia',
    };
    if (linhas.any((l) => eletronicos.contains(l.meio))) {
      return 'nfce';
    }
    if (linhas.any((l) => l.meio == 'fiado' || l.meio == 'dinheiro')) {
      return 'cupom';
    }
    return 'cupom';
  }

  /// Cliente CNPJ deve receber NF-e 55, nao NFC-e de consumidor.
  static String? mensagemBloqueioNfceClienteCnpj({
    required Cliente? cliente,
    required Venda venda,
  }) {
    if (!ClienteFiscalHelper.clienteExigeNfe55(cliente)) return null;
    if (venda.nfceEmitida) return null;
    return 'Cliente CNPJ: use NF-e modelo 55 nesta venda (NFC-e nao se aplica).';
  }

  static bool bloqueiaNovaNfceNoCaixa({
    required Venda venda,
    Cliente? cliente,
  }) {
    if (VendaDocumentoFiscalMutex.bloqueiaNovaNfce(venda)) return true;
    return mensagemBloqueioNfceClienteCnpj(cliente: cliente, venda: venda) !=
        null;
  }

  static bool documentoFiscalJaAtendido({
    required Venda venda,
    required String acao,
  }) {
    switch (acao) {
      case 'nfce':
        return venda.nfceEmitida || venda.nfceProcessandoPendenteFocus;
      case 'cupom':
        return venda.cupomNaoFiscalEmitidoEm != null;
      case 'nfe55':
        return venda.nfe55Autorizada || venda.nfe55Processando;
      default:
        return false;
    }
  }
}
