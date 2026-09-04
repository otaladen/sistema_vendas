import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_exclusao_guard.dart';

void main() {
  group('ProdutoExclusaoBloqueio', () {
    test('mensagem lista controles e orienta desativar', () {
      const bloqueio = ProdutoExclusaoBloqueio(
        quantidadeVendas: 2,
        rotulosVendas: ['Controle 8', 'Controle 6'],
      );

      expect(
        bloqueio.mensagem,
        contains('NFC-e pendente'),
      );
      expect(bloqueio.mensagem, contains('Controle 8'));
      expect(bloqueio.mensagem, contains('desative o produto'));
    });

    test('mensagem resume quando ha muitas vendas', () {
      const bloqueio = ProdutoExclusaoBloqueio(
        quantidadeVendas: 5,
        rotulosVendas: ['Controle 8', 'Controle 6', 'Controle 4'],
      );

      expect(bloqueio.mensagem, contains('e mais 2'));
    });
  });
}
