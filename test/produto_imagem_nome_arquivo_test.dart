import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_imagem_nome_arquivo.dart';

void main() {
  test('prefixo remove acentos e caracteres invalidos', () {
    expect(
      ProdutoImagemNomeArquivo.prefixoDeIdentificador('Cola Branca Cascorez 500 GR'),
      'cola_branca_cascorez_500_gr',
    );
    expect(
      ProdutoImagemNomeArquivo.prefixoDeIdentificador('Solei Marmore BR 145X15'),
      'solei_marmore_br_145x15',
    );
  });

  test('gerarNomeArquivo usa nome do produto + hash curto', () {
    final nome = ProdutoImagemNomeArquivo.gerarNomeArquivo(
      productIdentifier: 'Cola Branca Cascorez 500 GR',
      hashCompleto: '0a392ecd401f9ddb4acae0825a204031ba6b651c',
    );
    expect(nome, 'cola_branca_cascorez_500_gr_0a392ecd.jpg');
    expect(ProdutoImagemNomeArquivo.valido(nome), isTrue);
    expect(ProdutoImagemNomeArquivo.validoParaLan(nome), isTrue);
  });

  test('sem identificador mantem formato shared_', () {
    final nome = ProdutoImagemNomeArquivo.gerarNomeArquivo(
      productIdentifier: '',
      hashCompleto: '0a392ecd401f9ddb4acae0825a204031ba6b651c',
    );
    expect(nome, 'shared_0a392ecd401f9ddb4acae0825a204031ba6b651c.jpg');
    expect(ProdutoImagemNomeArquivo.valido(nome), isTrue);
  });
}
