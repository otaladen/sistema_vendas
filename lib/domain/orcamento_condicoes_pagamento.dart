import '../model/venda.dart';
import 'pagamento_orcamento.dart';

/// Texto da forma/condicao de pagamento escolhida no orcamento impresso.
///
/// Nao gera tabela generica de parcelas: so a condicao salva na venda.
abstract final class OrcamentoCondicoesPagamento {
  OrcamentoCondicoesPagamento._();

  static const String tituloSecao = 'CONDICOES DE PAGAMENTO / FORMA SUGERIDA';

  static bool meioAVista(String meio) {
    switch (meio) {
      case PagamentoMeio.dinheiro:
      case PagamentoMeio.pix:
      case PagamentoMeio.cartaoDebito:
      case '':
        return true;
      default:
        return false;
    }
  }

  static String rotuloMeio(String meio) {
    switch (meio) {
      case PagamentoMeio.dinheiro:
        return 'Dinheiro';
      case PagamentoMeio.pix:
        return 'PIX';
      case PagamentoMeio.cartaoDebito:
        return 'Cartao de debito';
      case PagamentoMeio.cartaoCredito:
        return 'Cartao de credito';
      case PagamentoMeio.transferencia:
        return 'Transferencia';
      case PagamentoMeio.fiado:
        return 'Fiado';
      case PagamentoMeio.vale:
        return 'Vale';
      case PagamentoMeio.misto:
        return 'Misto';
      default:
        return meio.isEmpty ? 'A vista' : meio;
    }
  }

  static int quantidadeLinhasLayout({
    String formaPagamento = PagamentoMeio.dinheiro,
    int quantidadeParcelas = 1,
    String pagamentosJson = '',
  }) {
    return linhas(
      total: 1,
      formatarMoeda: (_) => '',
      formaPagamento: formaPagamento,
      quantidadeParcelas: quantidadeParcelas,
      pagamentosJson: pagamentosJson,
    ).length;
  }

  static List<String> linhasDaVenda(
    Venda venda, {
    required double total,
    required String Function(double) formatarMoeda,
  }) {
    return linhas(
      total: total,
      formatarMoeda: formatarMoeda,
      formaPagamento: venda.formaPagamento,
      quantidadeParcelas: venda.quantidadeParcelas,
      pagamentosJson: venda.pagamentosJson,
    );
  }

  /// Linha curta para o resumo financeiro (PDF e ESC/POS).
  static String resumoFinanceiroDaVenda(
    Venda venda, {
    required double total,
    required String Function(double) formatarMoeda,
  }) {
    final detalhe = linhasDaVenda(
      venda,
      total: total,
      formatarMoeda: formatarMoeda,
    ).join(' | ');
    return 'Pagamento: $detalhe';
  }

  /// Linhas da condicao escolhida (sem titulo de secao).
  static List<String> linhas({
    required double total,
    required String Function(double) formatarMoeda,
    String formaPagamento = PagamentoMeio.dinheiro,
    int quantidadeParcelas = 1,
    String pagamentosJson = '',
  }) {
    final t = _valorSeguro(total);
    if (formaPagamento == PagamentoMeio.misto) {
      final mistos = PagamentoOrcamentoCodec.decode(pagamentosJson);
      if (mistos.isNotEmpty) {
        return mistos
            .map(
              (l) => _linhaMeio(
                meio: l.meio,
                valor: _valorSeguro(l.valor),
                parcelas: l.parcelas,
                formatarMoeda: formatarMoeda,
              ),
            )
            .toList();
      }
    }
    return [
      _linhaMeio(
        meio: formaPagamento,
        valor: t,
        parcelas: quantidadeParcelas,
        formatarMoeda: formatarMoeda,
      ),
    ];
  }

  static String _linhaMeio({
    required String meio,
    required double valor,
    required int parcelas,
    required String Function(double) formatarMoeda,
  }) {
    final rotulo = rotuloMeio(meio);
    if (meio == PagamentoMeio.cartaoCredito) {
      final n = parcelas < 1 ? 1 : parcelas;
      if (n > 1) {
        return '$rotulo ${n}x de ${formatarMoeda(valor / n)}';
      }
      return '$rotulo a vista - Total: ${formatarMoeda(valor)}';
    }
    if (meioAVista(meio)) {
      return '$rotulo a vista - Total: ${formatarMoeda(valor)}';
    }
    return '$rotulo - Total: ${formatarMoeda(valor)}';
  }

  static double _valorSeguro(double total) {
    if (total.isNaN || total.isInfinite || total < 0) return 0;
    return total;
  }
}
