import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/via_cep_endereco_similaridade.dart';
import 'package:sistema_vendas/services/viacep_endereco_service.dart';

void main() {
  group('ViaCepEnderecoResultado', () {
    test('fromMap preenche campos e IBGE', () {
      final r = ViaCepEnderecoResultado.fromMap({
        'cep': '01001-000',
        'logradouro': 'Praça da Sé',
        'bairro': 'Sé',
        'localidade': 'São Paulo',
        'uf': 'sp',
        'complemento': 'lado ímpar',
        'ibge': '3550308',
      });
      expect(r.cep, '01001000');
      expect(r.logradouro, 'Praça da Sé');
      expect(r.bairro, 'Sé');
      expect(r.cidade, 'São Paulo');
      expect(r.uf, 'SP');
      expect(r.codigoIbge, '3550308');
    });
  });

  group('via_cep_endereco_similaridade', () {
    test('extrai logradouro sem numero e tipo', () {
      expect(
        extrairLogradouroParaBuscaCep('Av. Sete de Setembro, 123'),
        'Sete de Setembro',
      );
      expect(
        extrairLogradouroParaBuscaCep('Rua das Flores nº 45'),
        'das Flores',
      );
    });

    test('ordena resultados mais parecidos primeiro', () {
      const a = ViaCepEnderecoResultado(
        cep: '40000000',
        logradouro: 'Rua Sete de Setembro',
        bairro: 'Centro',
        cidade: 'Salvador',
        uf: 'BA',
      );
      const b = ViaCepEnderecoResultado(
        cep: '40000001',
        logradouro: 'Rua Outra',
        bairro: 'Barra',
        cidade: 'Salvador',
        uf: 'BA',
      );
      final ord = ordenarEnderecosPorSimilaridade(
        lista: [b, a],
        logradouroReferencia: 'Sete de Setembro',
        bairroReferencia: 'Centro',
      );
      expect(ord.first.logradouro, contains('Sete de Setembro'));
    });
  });

  group('ViaCepEnderecoService.buscarPorLogradouro', () {
    test('valida UF, cidade e logradouro', () async {
      expect(
        () => ViaCepEnderecoService.buscarPorLogradouro(
          uf: 'B',
          cidade: 'Salvador',
          logradouro: 'Rua A',
        ),
        throwsArgumentError,
      );
      expect(
        () => ViaCepEnderecoService.buscarPorLogradouro(
          uf: 'BA',
          cidade: 'Sa',
          logradouro: 'Rua A',
        ),
        throwsArgumentError,
      );
      expect(
        () => ViaCepEnderecoService.buscarPorLogradouro(
          uf: 'BA',
          cidade: 'Salvador',
          logradouro: 'Ru',
        ),
        throwsArgumentError,
      );
    });
  });
}
