import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/caixa_troco_dinheiro_helper.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';

void main() {
  group('CaixaTrocoDinheiroHelper.troco', () {
    test('calcula troco quando entregue excede saldo', () {
      expect(
        CaixaTrocoDinheiroHelper.troco(
          valorEntregue: 50,
          saldoPendente: 43.5,
        ),
        closeTo(6.5, 0.001),
      );
    });

    test('sem troco quando entregue igual ao saldo', () {
      expect(
        CaixaTrocoDinheiroHelper.troco(
          valorEntregue: 43.5,
          saldoPendente: 43.5,
        ),
        0,
      );
    });
  });

  group('CaixaTrocoDinheiroHelper.validarLinhasMisto', () {
    test('permite dinheiro acima do saldo e calcula conferencia pelo total', () {
      final esperado = [
        PagamentoOrcamentoLinha(meio: 'pix', valor: 20, parcelas: 1),
        PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 23.5, parcelas: 1),
      ];
      final informado = [
        PagamentoOrcamentoLinha(meio: 'pix', valor: 20, parcelas: 1),
        PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 50, parcelas: 1),
      ];
      expect(
        CaixaTrocoDinheiroHelper.validarLinhasMisto(
          informado: informado,
          esperado: esperado,
          totalVenda: 43.5,
          rotuloMeio: (m) => m,
          formatarMoeda: (v) => 'R\$ $v',
        ),
        isNull,
      );
    });

    test('rejeita pix divergente do saldo', () {
      final linha = PagamentoOrcamentoLinha(meio: 'pix', valor: 20, parcelas: 1);
      expect(
        CaixaTrocoDinheiroHelper.validarLinhasMisto(
          informado: [
            PagamentoOrcamentoLinha(meio: 'pix', valor: 25, parcelas: 1),
          ],
          esperado: [linha],
          totalVenda: 20,
          rotuloMeio: (m) => m,
          formatarMoeda: (v) => 'R\$ $v',
        ),
        isNotNull,
      );
    });

    test('rejeita dinheiro abaixo do saldo pendente', () {
      final linha =
          PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 43.5, parcelas: 1);
      expect(
        CaixaTrocoDinheiroHelper.validarLinhasMisto(
          informado: [
            PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 40, parcelas: 1),
          ],
          esperado: [linha],
          totalVenda: 43.5,
          rotuloMeio: (m) => m,
          formatarMoeda: (v) => 'R\$ $v',
        ),
        isNotNull,
      );
    });
  });
}
