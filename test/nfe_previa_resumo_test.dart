import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_previa_resumo.dart';

void main() {
  test('NfePreviaResumoBuilder extrai totais e duplicatas', () {
    final payload = {
      'cnpj_emitente': '32662298000191',
      'nome_destinatario': 'Construtora',
      'cnpj_destinatario': '12345678000199',
      'uf_destinatario': 'BA',
      'consumidor_final': '0',
      'local_destino': '1',
      'natureza_operacao': 'Venda de mercadoria',
      'valor_produtos': '100.00',
      'valor_frete': '10.00',
      'valor_desconto': '5.00',
      'valor_total': '105.00',
      'modalidade_frete': '0',
      'items': [{}, {}],
      'duplicatas': [
        {'numero': '001', 'valor': '52.50'},
        {'numero': '002', 'valor': '52.50'},
      ],
    };

    final r = NfePreviaResumoBuilder.fromPayload(
      payload,
      referencia: 'venda_10_nfe',
    );

    expect(r.referencia, 'venda_10_nfe');
    expect(r.valorTotal, 105);
    expect(r.quantidadeItens, 2);
    expect(r.temDuplicatas, isTrue);
    expect(r.quantidadeDuplicatas, 2);
    expect(r.rotuloLocalDestino, 'Interna (BA)');
  });
}
