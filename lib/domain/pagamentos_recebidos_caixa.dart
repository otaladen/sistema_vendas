import '../model/venda.dart';
import 'pagamento_orcamento.dart';

/// Pagamentos efetivamente entregues pelo cliente no caixa.
///
/// [Venda.pagamentosJson] do misto e gravado somando o total da venda (extrato,
/// fiado e relatorios dependem disso); o excesso entregue em dinheiro fica so
/// em [Venda.valorTrocoCaixa]. NFC-e (vPag - vTroco = vNF) e o bloco
/// "FORMA DE PAGAMENTO" do cupom precisam do valor entregue, entao o troco
/// volta para a linha de dinheiro aqui.
abstract final class PagamentosRecebidosCaixa {
  PagamentosRecebidosCaixa._();

  static const double _tol = 0.009;

  /// Linhas do misto com o troco somado ao dinheiro.
  ///
  /// [totalNota] padrao [Venda.total]; [troco] padrao [Venda.valorTrocoCaixa].
  /// Idempotente: se as linhas ja cobrem total + troco, nada muda.
  static List<PagamentoOrcamentoLinha> linhasMisto(
    Venda venda, {
    double? totalNota,
    double? troco,
  }) {
    final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
    if (linhas.isEmpty) return linhas;

    final t = troco ?? venda.valorTrocoCaixa;
    if (t <= _tol) return linhas;

    final alvo = (totalNota ?? venda.total) + t;
    final falta = alvo - PagamentoOrcamentoCodec.soma(linhas);
    if (falta <= _tol) return linhas;

    var i = linhas.lastIndexWhere((l) => l.meio == PagamentoMeio.dinheiro);
    if (i < 0) {
      i = linhas.lastIndexWhere(
        (l) => l.meio != PagamentoMeio.fiado && l.meio != PagamentoMeio.vale,
      );
    }
    if (i < 0) i = linhas.length - 1;

    final l = linhas[i];
    linhas[i] = PagamentoOrcamentoLinha(
      meio: l.meio,
      valor: _arredondar(l.valor + falta),
      parcelas: l.parcelas,
      valeId: l.valeId,
      codigoVale: l.codigoVale,
    );
    return linhas;
  }

  static double _arredondar(double v) => (v * 100).round() / 100;
}
