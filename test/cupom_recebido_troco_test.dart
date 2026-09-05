import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/cupom_nao_fiscal_venda_pdf.dart';

void main() {
  group('CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom', () {
    test('usa valores gravados no caixa', () {
      final v = Venda(
        id: 19,
        total: 100,
        formaPagamento: 'misto',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(meio: 'pix', valor: 40),
          const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 60),
        ]),
        valorRecebidoCaixa: 110,
        valorTrocoCaixa: 10,
      );
      final r = CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom(v);
      expect(r.recebido, 110);
      expect(r.troco, 10);
    });

    test('inferencia misto quando troco nao foi gravado', () {
      final v = Venda(
        total: 100,
        formaPagamento: 'misto',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(meio: 'pix', valor: 50),
          const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 60),
        ]),
      );
      final r = CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom(v);
      expect(r.recebido, 110);
      expect(r.troco, 10);
    });

    test('pix sem troco', () {
      final v = Venda(total: 50, formaPagamento: 'pix');
      final r = CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom(v);
      expect(r.recebido, 50);
      expect(r.troco, 0);
    });
  });
}
