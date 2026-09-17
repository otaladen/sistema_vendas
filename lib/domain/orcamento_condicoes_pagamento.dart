import '../model/venda.dart';
import 'pagamento_orcamento.dart';

/// Texto da forma/condicao de pagamento escolhida no orcamento impresso.
///
/// Nao gera tabela generica de parcelas: so a condicao salva na venda.
abstract final class OrcamentoCondicoesPagamento {
  OrcamentoCondicoesPagamento._();

  static const String tituloSecao = 'CONDIÇÕES DE PAGAMENTO';

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
        return 'Cartão de débito';
      case PagamentoMeio.cartaoCredito:
        return 'Cartão de crédito';
      case PagamentoMeio.transferencia:
        return 'Transferência';
      case PagamentoMeio.fiado:
        return 'Fiado';
      case PagamentoMeio.vale:
        return 'Vale';
      case PagamentoMeio.misto:
        return 'Misto';
      default:
        return meio.isEmpty ? 'À vista' : meio;
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
    return linhasColunasDaVenda(
      venda,
      total: total,
      formatarMoeda: formatarMoeda,
    ).map((l) => l.descricao).toList();
  }

  /// Rotulo e valor em colunas (evita quebra do valor monetario na impressao).
  static List<({String rotulo, String valor, String descricao})> linhasColunasDaVenda(
    Venda venda, {
    required double total,
    required String Function(double) formatarMoeda,
  }) {
    return linhasColunas(
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
    return linhasColunas(
      total: total,
      formatarMoeda: formatarMoeda,
      formaPagamento: formaPagamento,
      quantidadeParcelas: quantidadeParcelas,
      pagamentosJson: pagamentosJson,
    ).map((l) => l.descricao).toList();
  }

  static List<({String rotulo, String valor, String descricao})> linhasColunas({
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
              (l) => _colunasMeio(
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
      _colunasMeio(
        meio: formaPagamento,
        valor: t,
        parcelas: quantidadeParcelas,
        formatarMoeda: formatarMoeda,
      ),
    ];
  }

  static ({String rotulo, String valor, String descricao}) _colunasMeio({
    required String meio,
    required double valor,
    required int parcelas,
    required String Function(double) formatarMoeda,
  }) {
    final rotuloMeioTxt = rotuloMeio(meio);
    if (meio == PagamentoMeio.cartaoCredito) {
      final n = parcelas < 1 ? 1 : parcelas;
      if (n > 1) {
        final valorParcela = formatarMoeda(valor / n);
        final rotulo = '$rotuloMeioTxt ${n}x de';
        return (
          rotulo: rotulo,
          valor: valorParcela,
          descricao: '$rotulo $valorParcela',
        );
      }
      final valorFmt = formatarMoeda(valor);
      final rotulo = '$rotuloMeioTxt à vista';
      return (
        rotulo: rotulo,
        valor: valorFmt,
        descricao: '$rotulo - Total: $valorFmt',
      );
    }
    if (meioAVista(meio)) {
      final valorFmt = formatarMoeda(valor);
      final rotulo = '$rotuloMeioTxt à vista';
      return (
        rotulo: rotulo,
        valor: valorFmt,
        descricao: '$rotulo - Total: $valorFmt',
      );
    }
    final valorFmt = formatarMoeda(valor);
    return (
      rotulo: rotuloMeioTxt,
      valor: valorFmt,
      descricao: '$rotuloMeioTxt - Total: $valorFmt',
    );
  }

  static double _valorSeguro(double total) {
    if (total.isNaN || total.isInfinite || total < 0) return 0;
    return total;
  }
}
