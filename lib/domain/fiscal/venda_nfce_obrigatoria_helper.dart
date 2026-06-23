import '../../domain/pagamento_orcamento.dart';
import '../../model/venda.dart';

/// Regras de quando a venda exige NFC-e (PIX, cartao, misto eletronico).
abstract final class VendaNfceObrigatoriaHelper {
  VendaNfceObrigatoriaHelper._();

  static const _meiosEletronicos = {
    'pix',
    'cartao_credito',
    'cartao_debito',
    'transferencia',
  };

  static bool pagamentoExigeNfce(Venda venda) {
    switch (venda.formaPagamento) {
      case 'pix':
      case 'cartao_credito':
      case 'cartao_debito':
      case 'transferencia':
        return true;
      case 'misto':
        return _mistoExigeNfce(venda);
      default:
        return false;
    }
  }

  static bool _mistoExigeNfce(Venda venda) {
    final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
    if (linhas.isEmpty) return false;
    return linhas.any((l) => _meiosEletronicos.contains(l.meio));
  }

  /// Venda finalizada que deveria ter NFC-e mas ainda nao tem documento valido.
  static bool ehPendenteEmissao(Venda venda) {
    if (venda.status != 'finalizada' || venda.cancelada) return false;
    if (!pagamentoExigeNfce(venda)) return false;
    if (venda.nfceEmitida || venda.nfe55Autorizada) return false;
    if (venda.nfceProcessandoPendenteFocus || venda.nfceEmissaoEmAndamento) {
      return false;
    }
    return true;
  }

  static String motivoPendenciaEmissao(Venda venda) {
    final st = venda.nfceStatusFocus.trim().toLowerCase();
    if (st == 'erro_autorizacao' || st == 'denegado') {
      return 'Rejeitada pela SEFAZ';
    }
    if (venda.cupomNaoFiscalEmitidoEm != null) {
      return 'Cupom impresso sem NFC-e';
    }
    return 'NFC-e nao emitida';
  }

  static String rotuloFormaPagamento(Venda venda) {
    if (venda.formaPagamento == 'misto') {
      final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
      if (linhas.isEmpty) return 'Misto';
      return linhas
          .map((l) => switch (l.meio) {
                'pix' => 'PIX',
                'cartao_credito' => 'Credito',
                'cartao_debito' => 'Debito',
                'dinheiro' => 'Dinheiro',
                'fiado' => 'Fiado',
                'transferencia' => 'Transferencia',
                _ => l.meio,
              })
          .join(' + ');
    }
    return switch (venda.formaPagamento) {
      'pix' => 'PIX',
      'cartao_credito' => 'Cartao credito',
      'cartao_debito' => 'Cartao debito',
      'transferencia' => 'Transferencia',
      'dinheiro' => 'Dinheiro',
      'fiado' => 'Fiado',
      _ => venda.formaPagamento,
    };
  }

  static double somaTotal(Iterable<Venda> vendas) =>
      vendas.fold<double>(0, (s, v) => s + v.total);
}
