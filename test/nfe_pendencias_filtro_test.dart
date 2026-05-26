import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/fiscal/cliente_fiscal_helper.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_pendencias_filtro.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_pendencias_service.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('ClienteFiscalHelper detecta CNPJ', () {
    expect(ClienteFiscalHelper.documentoEhCnpj('32662298000191'), isTrue);
    expect(ClienteFiscalHelper.documentoEhCnpj('12345678901'), isFalse);
    expect(
      ClienteFiscalHelper.clienteExigeNfe55(
        Cliente(id: 1, nomeRazao: 'PJ', tipoPessoa: 'juridica'),
      ),
      isTrue,
    );
  });

  test('NfePendenciasFiltro somente CNPJ e valor minimo', () {
    final cnpj = Cliente(
      id: 1,
      nomeRazao: 'Construtora',
      tipoPessoa: 'juridica',
      documento: '32662298000191',
    );
    final pf = Cliente(id: 2, nomeRazao: 'Joao', documento: '12345678901');
    final vendaCnpj = Venda(id: 10, total: 1000)..cliente.target = cnpj;
    final vendaPf = Venda(id: 11, total: 1000)..cliente.target = pf;
    final lista = [
      NfePendenciaVenda(venda: vendaCnpj, clienteNome: 'Construtora'),
      NfePendenciaVenda(venda: vendaPf, clienteNome: 'Joao'),
    ];
    final soCnpj = const NfePendenciasFiltro(somenteCnpj: true).aplicar(lista);
    expect(soCnpj.length, 1);
    expect(soCnpj.first.venda.id, 10);

    final alto = const NfePendenciasFiltro(valorMinimo: 500).aplicar(lista);
    expect(alto.length, 2);

    final carreto = Venda(
      id: 12,
      total: 200,
      tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
    )..cliente.target = cnpj;
    final comEntrega = const NfePendenciasFiltro(somenteComEntrega: true)
        .aplicar([NfePendenciaVenda(venda: carreto, clienteNome: 'X')]);
    expect(comEntrega.length, 1);
  });
}
