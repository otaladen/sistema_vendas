import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/caixa_fiscal_acao_helper.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('CaixaFiscalAcaoHelper', () {
    test('cartao com cliente CNPJ sugere NF-e 55', () {
      final venda = Venda(formaPagamento: 'cartao_credito', status: 'finalizada');
      final cliente = Cliente(
        id: 1,
        nomeRazao: 'Construtora LTDA',
        documento: '12345678000199',
        tipoPessoa: 'juridica',
      );
      expect(
        CaixaFiscalAcaoHelper.acaoAutomaticaPorPagamento(
          venda: venda,
          cliente: cliente,
        ),
        'nfe55',
      );
    });

    test('cartao com consumidor sugere NFC-e', () {
      final venda = Venda(formaPagamento: 'cartao_credito', status: 'finalizada');
      expect(
        CaixaFiscalAcaoHelper.acaoAutomaticaPorPagamento(venda: venda),
        'nfce',
      );
    });

    test('fiado com CNPJ continua cupom interno', () {
      final venda = Venda(formaPagamento: 'fiado', status: 'finalizada');
      final cliente = Cliente(
        id: 1,
        nomeRazao: 'Construtora LTDA',
        documento: '12345678000199',
        tipoPessoa: 'juridica',
      );
      expect(
        CaixaFiscalAcaoHelper.acaoAutomaticaPorPagamento(
          venda: venda,
          cliente: cliente,
        ),
        'cupom',
      );
    });

    test('bloqueia NFC-e nova para cliente CNPJ', () {
      final venda = Venda(formaPagamento: 'pix', status: 'finalizada');
      final cliente = Cliente(
        id: 1,
        nomeRazao: 'Loja XYZ',
        documento: '12345678000199',
        tipoPessoa: 'juridica',
      );
      expect(
        CaixaFiscalAcaoHelper.bloqueiaNovaNfceNoCaixa(
          venda: venda,
          cliente: cliente,
        ),
        isTrue,
      );
    });

    test('misto com cartao e CNPJ sugere NF-e 55', () {
      final venda = Venda(
        formaPagamento: 'misto',
        status: 'finalizada',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          PagamentoOrcamentoLinha(meio: 'cartao_credito', valor: 100),
        ]),
      );
      final cliente = Cliente(
        id: 1,
        nomeRazao: 'Empresa',
        documento: '12345678000199',
        tipoPessoa: 'juridica',
      );
      expect(
        CaixaFiscalAcaoHelper.acaoAutomaticaPorPagamento(
          venda: venda,
          cliente: cliente,
        ),
        'nfe55',
      );
    });
  });
}
