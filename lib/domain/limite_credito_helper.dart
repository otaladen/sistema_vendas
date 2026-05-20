import '../model/venda.dart';
import 'pagamento_orcamento.dart';

/// Calculo de fiado em aberto (vendas finalizadas) vs [Cliente.limiteCredito].
abstract final class LimiteCreditoHelper {
  /// Valor da venda que entra no saldo em aberto (fiado).
  static double valorFiadoNaVenda(Venda venda) {
    if (venda.cancelada) return 0;
    if (venda.formaPagamento == 'fiado') {
      return venda.total;
    }
    if (venda.formaPagamento == 'misto') {
      return PagamentoOrcamentoCodec.somaPorMeio(
        PagamentoOrcamentoCodec.decode(venda.pagamentosJson),
        'fiado',
      );
    }
    return 0;
  }

  /// Fiado previsto antes de gravar orcamento/venda.
  static double valorFiadoNoPagamento({
    required String formaPagamento,
    required double totalVendaLiquido,
    List<PagamentoOrcamentoLinha>? linhasMisto,
  }) {
    if (formaPagamento == 'fiado') {
      return totalVendaLiquido;
    }
    if (formaPagamento == 'misto' && linhasMisto != null) {
      return PagamentoOrcamentoCodec.somaPorMeio(linhasMisto, 'fiado');
    }
    return 0;
  }

  static String formatarMoedaBr(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
}

/// Resultado da checagem de limite de credito.
class ValidacaoLimiteCredito {
  const ValidacaoLimiteCredito({
    required this.permitido,
    this.mensagem,
    this.saldoEmAberto = 0,
    this.limite = 0,
    this.valorFiadoOperacao = 0,
    this.saldoAposOperacao = 0,
    this.nomeCliente = '',
  });

  final bool permitido;
  final String? mensagem;
  final double saldoEmAberto;
  final double limite;
  final double valorFiadoOperacao;
  final double saldoAposOperacao;
  final String nomeCliente;

  factory ValidacaoLimiteCredito.semLimiteConfigurado() =>
      const ValidacaoLimiteCredito(permitido: true);

  factory ValidacaoLimiteCredito.semFiado() =>
      const ValidacaoLimiteCredito(permitido: true);
}
