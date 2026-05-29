import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_estoque_sync.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  group('ProdutoEstoqueSync.mergeProdutoRemoto', () {
    Produto localBase() => Produto(
          id: 5,
          codigoInterno: 'A1',
          nome: 'Cimento',
          quantidadeMinima: 0,
          precoCusto: 10,
          precoVenda: 20,
          estoqueReal: 100,
          estoqueReservado: 10,
          estoqueVersao: 3,
        );

    Map<String, dynamic> payload({
      int versao = 2,
      int real = 50,
      int reservado = 5,
    }) =>
        {
          'id': 5,
          'codigoInterno': 'A1',
          'nome': 'Cimento remoto',
          'quantidadeMinima': 0,
          'precoCusto': 11,
          'precoVenda': 21,
          'estoqueReal': real,
          'estoqueReservado': reservado,
          'estoqueVersao': versao,
        };

    test('preserva estoque local quando versao local e maior', () {
      final local = localBase();
      final merged = ProdutoEstoqueSync.mergeProdutoRemoto(
        local: local,
        payload: payload(versao: 2, real: 50, reservado: 5),
      );
      expect(merged.produto.estoqueReal, 100);
      expect(merged.produto.estoqueReservado, 10);
      expect(merged.produto.estoqueVersao, 3);
      expect(merged.produto.nome, 'Cimento remoto');
      expect(merged.produto.precoVenda, 21);
      expect(merged.estoqueLocalPreservado, isTrue);
    });

    test('aplica estoque remoto quando versao remota e maior', () {
      final local = localBase()..estoqueVersao = 1;
      final merged = ProdutoEstoqueSync.mergeProdutoRemoto(
        local: local,
        payload: payload(versao: 4, real: 50, reservado: 5),
      );
      expect(merged.produto.estoqueReal, 50);
      expect(merged.produto.estoqueReservado, 5);
      expect(merged.produto.estoqueVersao, 4);
    });

    test('produto novo usa payload integral', () {
      final merged = ProdutoEstoqueSync.mergeProdutoRemoto(
        local: null,
        payload: payload(versao: 1, real: 7, reservado: 2),
      );
      expect(merged.produto.estoqueReal, 7);
      expect(merged.produto.estoqueReservado, 2);
      expect(merged.produto.estoqueVersao, 1);
    });
  });

  test('marcarEstoqueAlterado incrementa versao', () {
    final p = Produto(
      codigoInterno: 'X',
      nome: 'X',
      quantidadeMinima: 0,
      precoCusto: 1,
      precoVenda: 2,
      estoqueReal: 5,
    );
    expect(p.estoqueVersao, 0);
    ProdutoEstoqueSync.marcarEstoqueAlterado(p);
    expect(p.estoqueVersao, 1);
    expect(p.estoqueAtual, 5);
  });
}
