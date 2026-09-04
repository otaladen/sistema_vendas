import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  final config = FocusNfeConfig.homologacao(
    apiToken: 'token-teste',
    cnpjEmitente: '32662298000191',
    inscricaoEstadualEmitente: '123456789',
  );
  final service = FocusNfeService(config: config);

  Produto produto() => Produto(
        codigoInterno: '1',
        nome: 'Tijolo',
        ncm: '69041000',
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 2,
      );

  ItemVenda item() => ItemVenda(
        nomeProduto: 'Tijolo',
        quantidade: 1,
        precoUnitario: 2,
        precoCustoUnitario: 1,
      )..produto.target = produto();

  test('NFC-e entrega a domicilio inclui endereco do destinatario', () {
    final endereco = EnderecoCliente(
      tipo: 'entrega',
      padraoCarreto: true,
      cep: '44001-000',
      endereco: 'Rua das Flores',
      numero: '100',
      bairro: 'Centro',
      cidade: 'Feira de Santana',
      uf: 'BA',
      codigoIbge: '2910800',
    );
    final cliente = Cliente(nomeRazao: 'Maria Silva', documento: '52998224725')
      ..definirEnderecos([endereco]);

    final venda = Venda()
      ..id = 77
      ..total = 2
      ..tipoEntrega = 'entrega_loja'
      ..enderecoEntrega = endereco.resumo()
      ..itens.add(item());

    final payload = service.montarPayloadNfce(
      venda,
      cliente: cliente,
      entregaDomicilio: true,
      enderecoEntrega: endereco,
      codigoMunicipioIbge: '2910800',
    );

    expect(payload['presenca_comprador'], '4');
    expect(payload['modalidade_frete'], '0');
    expect(payload['cpf_destinatario'], '52998224725');
    expect(payload['nome_destinatario'], 'Maria Silva');
    expect(payload['logradouro_destinatario'], 'Rua das Flores');
    expect(payload['numero_destinatario'], '100');
    expect(payload['bairro_destinatario'], 'Centro');
    expect(payload['municipio_destinatario'], 'Feira de Santana');
    expect(payload['codigo_municipio_destinatario'], '2910800');
    expect(payload['uf_destinatario'], 'BA');
    expect(payload['cep_destinatario'], '44001000');
  });

  test('NFC-e entrega a domicilio sem endereco lanca validacao', () {
    final cliente = Cliente(nomeRazao: 'Sem Endereco', documento: '52998224725');
    final venda = Venda()
      ..id = 78
      ..total = 2
      ..tipoEntrega = 'entrega_loja'
      ..itens.add(item());

    expect(
      () => service.montarPayloadNfce(
        venda,
        cliente: cliente,
        entregaDomicilio: true,
      ),
      throwsA(
        isA<FocusNfeValidacaoException>().having(
          (e) => e.message,
          'message',
          contains('endereco'),
        ),
      ),
    );
  });

  test('NFC-e presencial nao exige endereco', () {
    final venda = Venda()
      ..id = 79
      ..total = 2
      ..itens.add(item());

    final payload = service.montarPayloadNfce(venda);
    expect(payload['presenca_comprador'], '1');
    expect(payload.containsKey('logradouro_destinatario'), isFalse);
  });
}
