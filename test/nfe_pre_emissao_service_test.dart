import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/endereco_fiscal_ibge_resolver.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_pre_emissao_service.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  Cliente clienteContribuinte() => Cliente(
        nomeRazao: 'Construtora SA',
        documento: '12345678000199',
        inscricaoEstadual: '987654321',
        indicadorIe: 'contribuinte',
      )..enderecosJson = '''
[{"tipo":"entrega","cep":"40000000","endereco":"Rua A","numero":"1","bairro":"Centro","cidade":"Salvador","uf":"BA","codigoIbge":"2927408"}]
''';

  test('bloqueia NF-e duplicada e item sem NCM', () {
    final produto = Produto(
      codigoInterno: 'X',
      nome: 'Sem NCM',
      ncm: '',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 10,
    );
    final item = ItemVenda(
      nomeProduto: 'Sem NCM',
      quantidade: 1,
      precoUnitario: 10,
      precoCustoUnitario: 1,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 1
      ..total = 10
      ..itens.add(item);

    final ibge = const EnderecoIbgeResolvido(
      sucesso: true,
      codigoIbge: '2927408',
      origem: 'teste',
    );

    final nfeAuth = NfeSaidaFiscalRegistro(
      id: '1',
      vendaId: 1,
      numeroOrcamento: 1,
      clienteNome: 'C',
      referenciaFocus: 'venda_1_nfe',
      statusFocus: 'autorizado',
      emitidaEm: DateTime.now(),
      statusSefaz: '100',
    );

    final r = NfePreEmissaoService.avaliar(
      venda: venda,
      cliente: clienteContribuinte(),
      ibge: ibge,
      nfeAutorizada: nfeAuth,
    );

    expect(r.podeEmitir, isFalse);
    expect(
      r.checklist.any((c) => c.titulo.contains('NF-e ja autorizada')),
      isTrue,
    );
    expect(r.linhasFiscais.first.bloqueiaEmissao, isTrue);
  });

  test('libera emissao com item e IBGE ok', () {
    final produto = Produto(
      codigoInterno: 'CIM',
      nome: 'Cimento',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 20,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 20,
      precoCustoUnitario: 1,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 2
      ..total = 20
      ..itens.add(item);

    final ibge = const EnderecoIbgeResolvido(
      sucesso: true,
      codigoIbge: '2927408',
      origem: 'cadastro',
    );

    // Sem FiscalConfigStore local: mesmo caminho do terminal (emissao no PC1).
    final r = NfePreEmissaoService.avaliar(
      venda: venda,
      cliente: clienteContribuinte(),
      ibge: ibge,
      emissaoNoServidor: true,
    );

    expect(r.podeEmitir, isTrue);
    expect(r.linhasFiscais.first.cfop, '5101');
    expect(r.consumidorFinal, isFalse);
  });
}
