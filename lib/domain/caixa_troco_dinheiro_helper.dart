import 'pagamento_orcamento.dart';

/// Troco e conferencia de dinheiro no checkout do caixa.
abstract final class CaixaTrocoDinheiroHelper {
  CaixaTrocoDinheiroHelper._();

  static const double toleranciaPadrao = 0.05;

  static double troco({
    required double valorEntregue,
    required double saldoPendente,
  }) {
    if (valorEntregue <= saldoPendente + 1e-9) return 0;
    return valorEntregue - saldoPendente;
  }

  static bool recebidoSuficiente({
    required double valorEntregue,
    required double saldoPendente,
    double tolerancia = toleranciaPadrao,
  }) {
    return valorEntregue >= saldoPendente - tolerancia;
  }

  /// Pagamento misto: dinheiro pode exceder o saldo; demais meios devem bater.
  static String? validarLinhasMisto({
    required List<PagamentoOrcamentoLinha> informado,
    required List<PagamentoOrcamentoLinha> esperado,
    required double totalVenda,
    double tolerancia = toleranciaPadrao,
    required String Function(String meio) rotuloMeio,
    required String Function(double valor) formatarMoeda,
  }) {
    if (informado.length != esperado.length) {
      return 'Pagamento misto invalido para conferencia no caixa.';
    }

    var fiado = 0.0;
    var recebidoCaixa = 0.0;
    for (var i = 0; i < informado.length; i++) {
      final inf = informado[i];
      if (inf.meio == 'fiado') {
        fiado += inf.valor;
        continue;
      }
      recebidoCaixa += inf.valor;
      final esp = esperado[i];
      if (esp.meio == 'dinheiro') {
        if (inf.valor + tolerancia < esp.valor) {
          return 'Dinheiro abaixo do saldo pendente '
              '(${formatarMoeda(esp.valor)}).';
        }
        continue;
      }
      if ((inf.valor - esp.valor).abs() > tolerancia) {
        final sufixoParcelas = esp.meio == 'cartao_credito'
            ? ' (${esp.parcelas}x)'
            : '';
        return 'Valor divergente em ${rotuloMeio(esp.meio)}$sufixoParcelas. '
            'Esperado: ${formatarMoeda(esp.valor)}.';
      }
    }

    final aPagarAgora =
        (totalVenda - fiado).clamp(0, double.infinity).toDouble();
    if (recebidoCaixa < aPagarAgora - tolerancia) {
      return 'Recebido agora (${formatarMoeda(recebidoCaixa)}) menor que '
          '${formatarMoeda(aPagarAgora)} (total menos fiado).';
    }
    return null;
  }
}
