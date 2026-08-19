import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/entregas/loja_origem_mercadoria.dart';

void main() {
  test('vazio nao e desta loja — padrao carreto e outra loja', () {
    expect(LojaOrigemMercadoria.ehLocal(null), isFalse);
    expect(LojaOrigemMercadoria.ehLocal(''), isFalse);
    expect(LojaOrigemMercadoria.ehLocal('local'), isTrue);
    expect(LojaOrigemMercadoria.ehLocal('loja_atual'), isTrue);
    expect(LojaOrigemMercadoria.ehLocal('Loja atual'), isTrue);
    expect(LojaOrigemMercadoria.ehLocal('Saída da loja atual'), isTrue);
    expect(LojaOrigemMercadoria.ehLocal('Desta loja'), isTrue);
  });

  test('outra loja nao e local', () {
    expect(LojaOrigemMercadoria.ehLocal('Loja B'), isFalse);
    expect(LojaOrigemMercadoria.ehLocal(LojaOrigemMercadoria.outraLoja), isFalse);
  });

  test('motivo kardex de transferencia nao inclui nome de loja', () {
    expect(
      LojaOrigemMercadoria.motivoKardex(
        origem: LojaOrigemMercadoria.outraLoja,
        vendaId: 12,
        numeroOrcamento: 88,
      ),
      'Entrega Efetuada via Transferência - Venda #88',
    );
  });

  test('origem efetiva vazia e outra loja antes da saida', () {
    expect(
      LojaOrigemMercadoria.origemEfetiva(
        origemItem: '',
        origemVenda: 'Loja B',
      ),
      LojaOrigemMercadoria.outraLoja,
    );
    expect(
      LojaOrigemMercadoria.origemEfetiva(
        origemItem: 'Depósito Central',
        origemVenda: '',
      ),
      LojaOrigemMercadoria.outraLoja,
    );
    expect(
      LojaOrigemMercadoria.origemEfetiva(
        origemItem: '',
        origemVenda: 'Misto',
      ),
      LojaOrigemMercadoria.outraLoja,
    );
  });

  test('origem efetiva vazia apos saida e legado desta loja', () {
    expect(
      LojaOrigemMercadoria.origemEfetiva(
        origemItem: '',
        origemVenda: '',
        cargaSaiu: true,
      ),
      LojaOrigemMercadoria.local,
    );
  });

  test('resumo misto quando ha loja local e transferencia na mesma nota', () {
    expect(
      LojaOrigemMercadoria.resumo(
        [LojaOrigemMercadoria.local, LojaOrigemMercadoria.outraLoja],
      ),
      LojaOrigemMercadoria.misto,
    );
    expect(
      LojaOrigemMercadoria.resumo(['', LojaOrigemMercadoria.outraLoja]),
      LojaOrigemMercadoria.outraLoja,
    );
    expect(
      LojaOrigemMercadoria.resumo(
        [LojaOrigemMercadoria.outraLoja, 'Loja B'],
      ),
      LojaOrigemMercadoria.outraLoja,
    );
    expect(
      LojaOrigemMercadoria.resumo(['', '']),
      LojaOrigemMercadoria.outraLoja,
    );
    expect(LojaOrigemMercadoria.ehMisto('Misto'), isTrue);
  });

  test('opcoes padrao colapsam transferencia em Outra loja', () {
    final opcoes = LojaOrigemMercadoria.opcoesPadrao(
      nomeLojaAtual: 'Loja A',
      extras: ['Loja B', 'Loja A'],
    );
    expect(opcoes, [LojaOrigemMercadoria.outraLoja]);
  });
}
