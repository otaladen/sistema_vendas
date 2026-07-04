import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/ui/widgets/mascaras_cadastro_input.dart';

void main() {
  test('cpfValidoOuVazio aceita vazio e CPF valido', () {
    expect(cpfValidoOuVazio(''), isTrue);
    expect(cpfValidoOuVazio('529.982.247-25'), isTrue);
    expect(cpfValidoOuVazio('111.111.111-11'), isFalse);
  });

  test('cnpjValidoOuVazio aceita vazio e CNPJ valido', () {
    expect(cnpjValidoOuVazio(''), isTrue);
    expect(cnpjValidoOuVazio('11.222.333/0001-81'), isTrue);
    expect(cnpjValidoOuVazio('11.111.111/1111-11'), isFalse);
  });

  test('documentoCpfCnpjValidoOuVazio respeita tipo pessoa', () {
    expect(
      documentoCpfCnpjValidoOuVazio('529.982.247-25', tipoPessoa: 'fisica'),
      isTrue,
    );
    expect(
      documentoCpfCnpjValidoOuVazio('11.222.333/0001-81', tipoPessoa: 'juridica'),
      isTrue,
    );
    expect(
      documentoCpfCnpjValidoOuVazio('529.982.247-25', tipoPessoa: 'juridica'),
      isFalse,
    );
  });
}
