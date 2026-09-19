import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/listagem_vendas_busca_relevancia.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/vendas/listagem_venda_item_ui.dart';
import 'package:sistema_vendas/ui/vendas/listagem_vendas_ordenacao.dart';

Venda _venda({
  required int id,
  int controle = 0,
  String nfceNumero = '',
  String nfeNumero = '',
  required DateTime data,
}) {
  return Venda(
    id: id,
    status: 'finalizada',
    numeroControle: controle,
    nfceNumero: nfceNumero,
    nfeNumero: nfeNumero,
    data: data,
    finalizadaEm: data,
    total: 100,
  );
}

ListagemVendaItemUi _item(Venda v) {
  return ListagemVendaItemUi(
    venda: v,
    titulo: v.nfceNumero,
    status: 'Concluída',
    statusCor: const Color(0xFF000000),
    dataHora: '',
    cliente: '',
    vendedor: '',
    pagamento: '',
    entrega: '',
    badgeNumero: '${v.numeroControle > 0 ? v.numeroControle : v.id}',
    totalFormatado: '',
    cancelada: false,
  );
}

void main() {
  final antiga = DateTime.utc(2026, 1, 10);
  final recente = DateTime.utc(2026, 9, 18);
  final maisRecente = DateTime.utc(2026, 9, 19);

  group('ListagemVendasBuscaRelevancia', () {
    test('busca por ID exato posiciona a venda no indice 0', () {
      final id1320 = _venda(
        id: 1320,
        controle: 1320,
        nfceNumero: '1892',
        data: maisRecente,
      );
      final id1133 = _venda(
        id: 1133,
        controle: 1133,
        nfceNumero: '8920',
        data: recente,
      );
      final id892 = _venda(
        id: 892,
        controle: 892,
        nfceNumero: '100',
        data: antiga,
      );

      final resultado = ListagemVendasBuscaRelevancia.ordenar(
        [id1320, id1133, id892],
        textoBusca: '892',
      );

      expect(resultado, hasLength(3));
      expect(resultado[0].id, 892);
      expect(resultado.first.id, 892);
    });

    test('NFC-e exata fica apos o Controle e antes dos parciais', () {
      final parcialRecente = _venda(
        id: 1320,
        controle: 1320,
        nfceNumero: '1892',
        data: maisRecente,
      );
      final nfceExata = _venda(
        id: 1100,
        controle: 1100,
        nfceNumero: '892',
        data: recente,
      );
      final controleExato = _venda(
        id: 892,
        controle: 892,
        data: antiga,
      );

      final resultado = ListagemVendasBuscaRelevancia.ordenar(
        [parcialRecente, nfceExata, controleExato],
        textoBusca: '892',
      );

      expect(resultado.map((v) => v.id).toList(), [892, 1100, 1320]);
    });

    test('parciais numericos permanecem por data decrescente', () {
      final maisNova = _venda(
        id: 1320,
        nfceNumero: '1892',
        data: maisRecente,
      );
      final maisVelha = _venda(
        id: 1133,
        nfceNumero: '8920',
        data: recente,
      );
      final idExato = _venda(id: 892, controle: 892, data: antiga);

      final resultado = ListagemVendasBuscaRelevancia.ordenar(
        [maisVelha, idExato, maisNova],
        textoBusca: '892',
      );

      expect(resultado[0].id, 892);
      expect(resultado[1].id, 1320);
      expect(resultado[2].id, 1133);
    });

    test('busca nao numerica nao reordena a lista filtrada', () {
      final a = _venda(id: 2, data: maisRecente);
      final b = _venda(id: 1, data: antiga);
      final entrada = [a, b];

      expect(
        ListagemVendasBuscaRelevancia.ordenar(entrada, textoBusca: 'silva'),
        same(entrada),
      );
    });
  });

  group('ordenarItensListagemVendas', () {
    test('ID exato permanece no indice 0 mesmo ordenando data decrescente', () {
      final itens = [
        _item(_venda(
          id: 1320,
          controle: 1320,
          nfceNumero: '1892',
          data: maisRecente,
        )),
        _item(_venda(
          id: 1133,
          controle: 1133,
          nfceNumero: '8920',
          data: recente,
        )),
        _item(_venda(id: 892, controle: 892, data: antiga)),
      ];

      final ordenados = ordenarItensListagemVendas(
        itens,
        coluna: ListagemVendasColuna.data,
        ascendente: false,
        textoBusca: '892',
      );

      expect(ordenados[0].venda.id, 892);
    });
  });
}
