import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/focus_nfe_referencia.dart';
import 'package:sistema_vendas/domain/listagem_vendas_dedupe.dart';
import 'package:sistema_vendas/model/venda.dart';

Venda _venda({
  required int id,
  int controle = 0,
  String nfceNumero = '',
  String nfceChave = '',
  String nfceProtocolo = '',
  String nfceStatus = 'autorizado',
  double total = 100,
}) {
  return Venda(
    id: id,
    status: 'finalizada',
    numeroControle: controle,
    nfceNumero: nfceNumero,
    nfceChaveAcesso: nfceChave,
    nfceProtocolo: nfceProtocolo,
    nfceStatusFocus: nfceStatus,
    total: total,
  );
}

/// Equivalente ao rotulo da Listagem de Vendas (Controle + NFC-e).
List<String> _rotulosListagem(Iterable<Venda> payload) {
  return ListagemVendasDedupe.sanitizar(payload)
      .map(
        (v) => 'Controle ${v.numeroControle} · NFC-e ${v.nfceNumero}',
      )
      .toList();
}

void main() {
  group('ListagemVendasDedupe', () {
    test('payload com o mesmo id vira um unico item na listagem', () {
      final a = _venda(
        id: 834,
        controle: 802,
        nfceNumero: '60456',
        nfceChave: '35250900000000000000650010000604561000000001',
      );

      expect(_rotulosListagem([a, a, a]), [
        'Controle 802 · NFC-e 60456',
      ]);
    });

    test(
      'varios registros fiscais do Controle 802 (NFC-e 60456) renderizam um item',
      () {
        final original = _venda(
          id: 834,
          controle: 802,
          nfceNumero: '60456',
          nfceChave: '35250900000000000000650010000604561000000001',
          nfceProtocolo: '123456789',
        );
        final sombraFiscal = _venda(
          id: 1902,
          controle: 802,
          nfceNumero: '60456',
          nfceChave: '35250900000000000000650010000604561000000001',
        );

        final itens = ListagemVendasDedupe.sanitizar([sombraFiscal, original]);

        expect(itens, hasLength(1));
        expect(itens.single.id, 834);
        expect(_rotulosListagem([sombraFiscal, original]), [
          'Controle 802 · NFC-e 60456',
        ]);
      },
    );

    test('ids distintos e NFC-e diferentes permanecem dois itens', () {
      final a = _venda(id: 10, controle: 801, nfceNumero: '100');
      final b = _venda(id: 11, controle: 803, nfceNumero: '101');

      expect(ListagemVendasDedupe.sanitizar([a, b]), hasLength(2));
    });
  });

  group('FocusNfeReferencia', () {
    test('extrai id de venda_834', () {
      expect(FocusNfeReferencia.idVenda('venda_834'), 834);
    });

    test('extrai id de venda_834_nfe', () {
      expect(FocusNfeReferencia.idVenda('venda_834_nfe'), 834);
    });

    test('ignora referencia temporaria', () {
      expect(FocusNfeReferencia.idVenda('venda_tmp_1710000000_nfce'), isNull);
    });
  });
}
