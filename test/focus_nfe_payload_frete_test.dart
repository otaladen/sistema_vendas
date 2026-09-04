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

  Produto produto(String codigo, String nome, double preco) => Produto(
        codigoInterno: codigo,
        nome: nome,
        ncm: '69041000',
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: preco,
      );

  FocusNfeDestinatarioNfe destinatario() => FocusNfeDestinatarioNfe(
        nome: 'Cliente Teste',
        documento: '52998224725',
        inscricaoEstadual: '',
        indicadorInscricaoEstadual: '9',
        logradouro: 'Rua A',
        numero: '1',
        bairro: 'Centro',
        municipio: 'Feira de Santana',
        codigoMunicipioIbge: '2910800',
        uf: 'BA',
        cep: '44001000',
      );

  double somaFreteItens(List<Map<String, dynamic>> items) {
    var total = 0.0;
    for (final it in items) {
      total +=
          double.tryParse(it['valor_frete']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  test(
    'NFC-e com frete rateia valor_frete nos itens (rejeicao total frete)',
    () {
      final item1 = ItemVenda(
        nomeProduto: 'Tijolo',
        quantidade: 10,
        precoUnitario: 1.50,
        precoCustoUnitario: 1,
      )..produto.target = produto('1', 'Tijolo', 1.50);
      final item2 = ItemVenda(
        nomeProduto: 'Cimento',
        quantidade: 1,
        precoUnitario: 35.00,
        precoCustoUnitario: 20,
      )..produto.target = produto('2', 'Cimento', 35);

      final venda = Venda()
        ..id = 100
        ..valorFrete = 15.00
        ..total = 65.00 // 15 + 15 + 35
        ..tipoEntrega = 'entrega_loja'
        ..itens.add(item1)
        ..itens.add(item2);

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

      final payload = service.montarPayloadNfce(
        venda,
        cliente: cliente,
        entregaDomicilio: true,
        enderecoEntrega: endereco,
        codigoMunicipioIbge: '2910800',
      );
      final items = (payload['items'] as List).cast<Map<String, dynamic>>();

      expect(payload['valor_frete'], '15.00');
      expect(payload['valor_produtos'], '50.00');
      expect(payload['valor_total'], '65.00');
      expect(items.every((it) => it.containsKey('valor_frete')), isTrue);

      final somaItens = somaFreteItens(items);
      expect(somaItens, closeTo(15.00, 0.001));
      expect(
        somaItens,
        closeTo(double.parse(payload['valor_frete'] as String), 0.001),
      );
    },
  );

  test('NFC-e sem frete nao envia valor_frete nos itens', () {
    final item = ItemVenda(
      nomeProduto: 'Tijolo',
      quantidade: 1,
      precoUnitario: 2,
      precoCustoUnitario: 1,
    )..produto.target = produto('1', 'Tijolo', 2);

    final venda = Venda()
      ..id = 101
      ..total = 2
      ..itens.add(item);

    final payload = service.montarPayloadNfce(venda);
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;

    expect(payload['valor_frete'], '0.00');
    expect(itemPayload.containsKey('valor_frete'), isFalse);
  });

  test('NF-e com frete rateia valor_frete nos itens', () {
    final item1 = ItemVenda(
      nomeProduto: 'Telha',
      quantidade: 3,
      precoUnitario: 7.33,
      precoCustoUnitario: 4,
    )..produto.target = produto('T1', 'Telha', 7.33);
    final item2 = ItemVenda(
      nomeProduto: 'Argamassa',
      quantidade: 2,
      precoUnitario: 12.50,
      precoCustoUnitario: 8,
    )..produto.target = produto('A1', 'Argamassa', 12.50);

    final venda = Venda()
      ..id = 102
      ..valorFrete = 10.00
      ..total = 56.99 // 21.99 + 25 + 10
      ..itens.add(item1)
      ..itens.add(item2);

    final payload = service.montarPayloadNfe(
      venda,
      destinatario: destinatario(),
    );
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();

    expect(payload['valor_frete'], '10.00');
    expect(items.every((it) => it.containsKey('valor_frete')), isTrue);

    final somaItens = somaFreteItens(items);
    expect(somaItens, closeTo(10.00, 0.001));
    expect(
      somaItens,
      closeTo(double.parse(payload['valor_frete'] as String), 0.001),
    );
  });

  test('NFC-e frete com desconto mantem consistencia cabecalho x itens', () {
    final item1 = ItemVenda(
      nomeProduto: 'Obturador',
      quantidade: 1,
      precoUnitario: 14.90,
      precoCustoUnitario: 1,
    )..produto.target = produto('2081', 'Obturador', 14.90);
    final item2 = ItemVenda(
      nomeProduto: 'Bucha',
      quantidade: 2,
      precoUnitario: 0.70,
      precoCustoUnitario: 0.1,
    )..produto.target = produto('42', 'Bucha', 0.70);

    final venda = Venda()
      ..id = 103
      ..valorFrete = 12.50
      ..total = 28.00 // 16.30 + 12.50 - 0.80
      ..tipoEntrega = 'entrega_loja'
      ..itens.add(item1)
      ..itens.add(item2);

    final endereco = EnderecoCliente(
      tipo: 'entrega',
      padraoCarreto: true,
      cep: '44001-000',
      endereco: 'Rua B',
      numero: '50',
      bairro: 'Centro',
      cidade: 'Feira de Santana',
      uf: 'BA',
      codigoIbge: '2910800',
    );
    final cliente = Cliente(nomeRazao: 'Joao', documento: '52998224725')
      ..definirEnderecos([endereco]);

    final payload = service.montarPayloadNfce(
      venda,
      cliente: cliente,
      entregaDomicilio: true,
      enderecoEntrega: endereco,
      codigoMunicipioIbge: '2910800',
    );
    final items = (payload['items'] as List).cast<Map<String, dynamic>>();

    expect(venda.descontoImplicitoTotal, closeTo(0.80, 0.001));
    expect(payload['valor_desconto'], '0.80');
    expect(payload['valor_frete'], '12.50');
    expect(payload['valor_total'], '28.00');

    var somaFrete = 0.0;
    var somaDesc = 0.0;
    for (final it in items) {
      somaFrete +=
          double.tryParse(it['valor_frete']?.toString() ?? '') ?? 0;
      somaDesc +=
          double.tryParse(it['valor_desconto']?.toString() ?? '') ?? 0;
    }
    expect(somaFrete, closeTo(12.50, 0.001));
    expect(somaDesc, closeTo(0.80, 0.001));
  });
}
