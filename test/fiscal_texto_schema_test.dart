import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/fiscal_texto_schema.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  group('FiscalTextoSchema', () {
    test('limita logradouro a 60 caracteres', () {
      final longo =
          'Rua Professor Doutor Jose da Silva Santos Oliveira e Souza Filho';
      expect(longo.length, greaterThan(60));
      final cortado = FiscalTextoSchema.logradouro(longo);
      expect(cortado.length, 60);
      expect(cortado, longo.substring(0, 60).trimRight());
    });

    test('nao altera texto dentro do limite', () {
      expect(FiscalTextoSchema.logradouro('Rua A'), 'Rua A');
      expect(FiscalTextoSchema.nome('Maria'), 'Maria');
    });
  });

  group('Focus payload corta endereco longo', () {
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

    test('NF-e corta logradouro/nome/bairro acima de 60', () {
      final logradouroLongo =
          'Avenida Contorno Norte Industrial Comerciarios Unidos da Bahia Sul';
      expect(logradouroLongo.length, greaterThan(60));

      final dest = FocusNfeDestinatarioNfe(
        nome: 'Construtora Alpha Beta Gamma Delta Epsilon Zeta Eta Theta',
        documento: '12345678000199',
        inscricaoEstadual: '123456789',
        indicadorInscricaoEstadual: '1',
        logradouro: logradouroLongo,
        numero: '123456789012345678901234567890123456789012345678901234567890XXX',
        bairro: 'Bairro Industrial Comerciantes e Prestadores de Servico Extenso',
        municipio: 'Feira de Santana Municipio Com Nome Muito Extenso Para Schema',
        codigoMunicipioIbge: '2910800',
        uf: 'BA',
        cep: '44001000',
        complemento:
            'Proximo ao posto de gasolina e ao supermercado da esquina principal',
      );

      final venda = Venda()
        ..id = 901
        ..itens.add(item());

      final payload = service.montarPayloadNfe(
        venda,
        destinatario: dest,
      );

      expect(
        (payload['logradouro_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['nome_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['numero_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['bairro_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['municipio_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['complemento_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
    });

    test('NFC-e entrega corta logradouro longo', () {
      final logradouroLongo =
          'Rua Professor Doutor Jose da Silva Santos Oliveira e Souza Filho';
      final endereco = EnderecoCliente(
        tipo: 'entrega',
        padraoCarreto: true,
        cep: '44001-000',
        endereco: logradouroLongo,
        numero: '100',
        bairro: 'Centro',
        cidade: 'Feira de Santana',
        uf: 'BA',
        codigoIbge: '2910800',
        referencia:
            'Complemento muito longo para o schema fiscal da SEFAZ e Focus NFe API',
      );
      final cliente = Cliente(
        nomeRazao:
            'Cliente Com Nome Extremamente Longo Para Ultrapassar Sessenta Caracteres',
        documento: '52998224725',
      )..definirEnderecos([endereco]);

      final venda = Venda()
        ..id = 902
        ..total = 2
        ..tipoEntrega = 'entrega_loja'
        ..itens.add(item());

      final payload = service.montarPayloadNfce(
        venda,
        cliente: cliente,
        entregaDomicilio: true,
        enderecoEntrega: endereco,
        codigoMunicipioIbge: '2910800',
      );

      expect(
        (payload['logradouro_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['nome_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
      expect(
        (payload['complemento_destinatario'] as String).length,
        lessThanOrEqualTo(60),
      );
    });
  });
}
