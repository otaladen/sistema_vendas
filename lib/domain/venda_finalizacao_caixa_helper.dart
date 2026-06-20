import '../model/venda.dart';

/// Momento em que a venda foi fechada no caixa (nao a data do orcamento).
abstract final class VendaFinalizacaoCaixaHelper {
  VendaFinalizacaoCaixaHelper._();

  static DateTime momentoFinalizacao(Venda venda) {
    final fe = venda.finalizadaEm;
    if (fe != null) return fe.toUtc();
    final cupom = venda.cupomNaoFiscalEmitidoEm;
    if (cupom != null) return cupom.toUtc();
    return venda.data.toUtc();
  }

  /// Remove [Venda.finalizadaEm] copiado da data do orcamento (backfill incorreto).
  static bool ehFinalizadaEmCopiaDaDataOrcamento(Venda venda) {
    final fe = venda.finalizadaEm;
    if (fe == null) return false;
    return fe.toUtc().millisecondsSinceEpoch ==
        venda.data.toUtc().millisecondsSinceEpoch;
  }
}
