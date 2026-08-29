import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/importacao/produto_importacao_linha.dart';
import 'package:sistema_vendas/domain/produto_marca.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('marca prevalece sobre fabricante legado', () {
    expect(
      ProdutoMarca.efetiva(marca: 'Tigre', fabricante: 'Outra'),
      'Tigre',
    );
  });

  test('fabricante legado preenche marca vazia', () {
    expect(
      ProdutoMarca.efetiva(marca: '  ', fabricante: 'Votoran'),
      'Votoran',
    );
  });

  test('importacao CSV usa fabricante quando marca vem vazia', () {
    final p = const ProdutoImportacaoLinha(
      codigoInterno: '1',
      nome: 'Cimento',
      marca: '',
      fabricante: 'Votoran',
    ).paraProduto();
    expect(p.marca, 'Votoran');
    expect(p.fabricante, 'Votoran');
  });

  test('importacao nao apaga fornecedor ja gravado pela NF-e', () {
    final existente = Produto(
      codigoInterno: '1',
      nome: 'Cimento',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 1,
      fornecedor: 'Distribuidora X',
    );
    final p = const ProdutoImportacaoLinha(
      codigoInterno: '1',
      nome: 'Cimento',
    ).paraProduto(existente: existente);
    expect(p.fornecedor, 'Distribuidora X');
  });
}
