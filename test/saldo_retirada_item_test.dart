import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/retirada_parcial_evento.dart';
import 'package:sistema_vendas/domain/saldo_retirada_item.dart';
import 'package:sistema_vendas/model/historico_entrega.dart';
import 'package:sistema_vendas/model/item_venda.dart';

void main() {
  group('SaldoRetiradaItem', () {
    test('comprou 10, retirou 3, pendente 7', () {
      expect(
        SaldoRetiradaItem.pendente(
          quantidade: 10,
          quantidadeJaRetirada: 3,
          quantidadeDevolvida: 0,
        ),
        7,
      );
    });

    test('baixa 3, depois 3, depois 4 esgota; 1 a mais e recusado', () {
      var ja = 0;
      const vendido = 10;
      const devolvida = 0;

      void baixa(int q) {
        SaldoRetiradaItem.validarRetirada(
          nomeProduto: 'Cimento',
          quantidade: vendido,
          quantidadeJaRetirada: ja,
          quantidadeDevolvida: devolvida,
          quantidadeSolicitada: q,
        );
        ja += q;
      }

      baixa(3);
      expect(ja, 3);
      baixa(3);
      expect(ja, 6);
      baixa(4);
      expect(ja, 10);
      expect(
        () => baixa(1),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ultrapassa'),
          ),
        ),
      );
    });

    test('devolucao reduz o pendente: 10 vendidos, 3 retirados, 2 devolvidos', () {
      expect(
        SaldoRetiradaItem.pendente(
          quantidade: 10,
          quantidadeJaRetirada: 3,
          quantidadeDevolvida: 2,
        ),
        5,
      );
    });

    test('nao permite retirar alem do vendido liquido apos devolucao', () {
      expect(
        () => SaldoRetiradaItem.validarRetirada(
          nomeProduto: 'Areia',
          quantidade: 10,
          quantidadeJaRetirada: 0,
          quantidadeDevolvida: 4,
          quantidadeSolicitada: 7,
        ),
        throwsA(isA<StateError>()),
      );
      SaldoRetiradaItem.validarRetirada(
        nomeProduto: 'Areia',
        quantidade: 10,
        quantidadeJaRetirada: 0,
        quantidadeDevolvida: 4,
        quantidadeSolicitada: 6,
      );
    });

    test('saldo corrompido (ja retirado > vendido) e limitado no cap', () {
      expect(
        SaldoRetiradaItem.jaRetiradaCapped(
          quantidadeJaRetirada: 15,
          quantidade: 10,
          quantidadeDevolvida: 0,
        ),
        10,
      );
      expect(
        SaldoRetiradaItem.pendente(
          quantidade: 10,
          quantidadeJaRetirada: 15,
          quantidadeDevolvida: 0,
        ),
        0,
      );
    });
  });

  group('ItemVenda.quantidadePendenteRetirada', () {
    test('desconta devolucao na retirada futura', () {
      final item = ItemVenda(
        nomeProduto: 'Saco',
        quantidade: 10,
        precoUnitario: 1,
        precoCustoUnitario: 0.5,
        quantidadeJaRetirada: 3,
        quantidadeDevolvida: 2,
        tipoEntregaItem: 'retirada_futura',
      );
      expect(item.quantidadePendenteRetirada, 5);
    });
  });

  group('RetiradaParcialEvento', () {
    test('roundtrip JSON com data, usuario, quantidade e documento', () {
      final original = RetiradaParcialEvento(
        vendaId: 12,
        numeroOrcamento: 431,
        documento: 'Orcamento #431',
        tipo: RetiradaParcialEvento.tipoFutura,
        usuario: 'maria',
        retiradoPor: 'Joao',
        dataHora: DateTime.utc(2026, 8, 26, 18, 30, 0),
        linhas: const [
          RetiradaParcialLinhaEvento(
            itemVendaId: 7,
            nomeProduto: 'Cimento',
            quantidade: 3,
            vendido: 10,
            jaRetiradaAntes: 0,
            quantidadeDevolvida: 0,
          ),
        ],
      );
      final parsed = RetiradaParcialEvento.tryParse(original.encode());
      expect(parsed, isNotNull);
      expect(parsed!.vendaId, 12);
      expect(parsed.documento, 'Orcamento #431');
      expect(parsed.usuario, 'maria');
      expect(parsed.retiradoPor, 'Joao');
      expect(parsed.linhas.single.quantidade, 3);
      expect(parsed.dataHora.toUtc(), DateTime.utc(2026, 8, 26, 18, 30, 0));
      expect(parsed.textoHumano, contains('Cimento x3'));
      expect(
        HistoricoEntregaEventos.textoDetalhe(
          HistoricoEntregaEventos.retiradaFutura,
          original.encode(),
        ),
        contains('Orcamento #431'),
      );
    });
  });
}
