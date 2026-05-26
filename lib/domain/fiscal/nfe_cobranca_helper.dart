import '../../model/venda.dart';
import '../limite_credito_helper.dart';
import '../pagamento_orcamento.dart';
import '../plano_fiado.dart';

/// Monta fatura/duplicatas da NF-e para vendas a prazo (Focus NFe).
abstract final class NfeCobrancaHelper {
  NfeCobrancaHelper._();

  static bool vendaExigeBlocoCobranca(Venda venda) {
    if (venda.formaPagamento == 'fiado') return true;
    if (venda.formaPagamento == 'boleto' && venda.quantidadeParcelas > 1) {
      return true;
    }
    if (PlanoFiadoCodec.parcelasDaVenda(venda).isNotEmpty) return true;
    if (venda.formaPagamento == 'misto') {
      final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
      if (linhas.any((l) => l.meio == 'fiado' && l.valor > 0)) return true;
      if (linhas.any((l) => l.meio == 'boleto' && l.parcelas > 1 && l.valor > 0)) {
        return true;
      }
    }
    return false;
  }

  /// Valor da cobranca a prazo (fiado / boleto parcelado) para o bloco `cobr`.
  static double valorCobrancaVenda(Venda venda) {
    if (venda.formaPagamento == 'fiado') {
      return venda.total;
    }
    if (venda.formaPagamento == 'boleto' && venda.quantidadeParcelas > 1) {
      return venda.total;
    }
    final fiado = LimiteCreditoHelper.valorFiadoNaVenda(venda);
    if (fiado > 0.001) return fiado;

    if (venda.formaPagamento == 'misto') {
      final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
      final boletoParcelado = linhas
          .where((l) => l.meio == 'boleto' && l.parcelas > 1)
          .fold<double>(0, (a, b) => a + b.valor);
      if (boletoParcelado > 0.001) return boletoParcelado;
    }
    return 0;
  }

  static List<PlanoFiadoParcela> resolverParcelas(
    Venda venda,
    double valorCobranca,
  ) {
    if (valorCobranca <= 0.001) return [];

    final doPlano = PlanoFiadoCodec.parcelasParaCupom(venda);
    if (PlanoFiadoCodec.validarContraValor(doPlano, valorCobranca)) {
      return List<PlanoFiadoParcela>.from(doPlano)
        ..sort((a, b) => a.vencimento.compareTo(b.vencimento));
    }
    if (doPlano.isNotEmpty) {
      return List<PlanoFiadoParcela>.from(doPlano)
        ..sort((a, b) => a.vencimento.compareTo(b.vencimento));
    }

    if (venda.formaPagamento == 'boleto' && venda.quantidadeParcelas > 1) {
      return PlanoFiadoCodec.gerarParcelasIguais(
        valorTotal: valorCobranca,
        quantidade: venda.quantidadeParcelas,
        primeiroVencimento: venda.data.toUtc().add(const Duration(days: 30)),
      );
    }

    if (venda.formaPagamento == 'misto') {
      final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
      final boleto = linhas.where((l) => l.meio == 'boleto' && l.parcelas > 1);
      if (boleto.isNotEmpty) {
        final qtd = boleto.map((l) => l.parcelas).reduce((a, b) => a > b ? a : b);
        return PlanoFiadoCodec.gerarParcelasIguais(
          valorTotal: valorCobranca,
          quantidade: qtd.clamp(1, 99),
          primeiroVencimento: venda.data.toUtc().add(const Duration(days: 30)),
        );
      }
    }

    return PlanoFiadoCodec.gerarParcelasIguais(
      valorTotal: valorCobranca,
      quantidade: 1,
      primeiroVencimento: venda.data.toUtc().add(const Duration(days: 30)),
    );
  }

  /// Campos Focus: `numero_fatura`, `valor_*_fatura`, `duplicatas`.
  static Map<String, dynamic> montarCamposFocus(Venda venda) {
    if (!vendaExigeBlocoCobranca(venda)) return {};
    final valorCobranca = valorCobrancaVenda(venda);
    final parcelas = resolverParcelas(venda, valorCobranca);
    if (parcelas.isEmpty || valorCobranca <= 0.001) return {};

    final numeroFatura = venda.numeroOrcamento > 0
        ? '${venda.numeroOrcamento}'
        : '${venda.id}';

    return {
      'numero_fatura': numeroFatura,
      'valor_original_fatura': _decimal(valorCobranca),
      'valor_desconto_fatura': '0.00',
      'valor_liquido_fatura': _decimal(valorCobranca),
      'duplicatas': parcelas
          .map(
            (p) => {
              'numero': p.numero.toString().padLeft(3, '0'),
              'data_vencimento': _dataIso(p.vencimento),
              'valor': _decimal(p.valor),
            },
          )
          .toList(),
    };
  }

  static String _decimal(double v) => v.toStringAsFixed(2);

  static String _dataIso(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
