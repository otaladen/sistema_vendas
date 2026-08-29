import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/caixa_meio_pagamento_fechamento.dart';
import 'package:sistema_vendas/domain/leitura_parcial_caixa.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';

void main() {
  group('LeituraParcialCaixaSnapshot', () {
    test('gaveta = fundo + dinheiro de vendas + quitacao - sangria', () {
      final s = LeituraParcialCaixaSnapshot.montar(
        fundoTroco: 100,
        suprimentos: 50,
        sangrias: 20,
        vendasDinheiro: 80,
        vendasPix: 30,
        vendasDebito: 10,
        vendasCredito: 5,
        recDinheiro: 15,
        recPix: 7,
        totalVendas: 200,
        quantidadeVendas: 4,
      );
      expect(s.dinheiroGaveta, 225);
      expect(s.pix, 37);
      expect(s.debito, 10);
      expect(s.credito, 5);
      expect(s.vale, 0);
    });

    test('vale nao entra na gaveta nem nos cartoes', () {
      final s = LeituraParcialCaixaSnapshot.montar(
        fundoTroco: 100,
        suprimentos: 0,
        sangrias: 0,
        vendasDinheiro: 40,
        vendasPix: 0,
        vendasDebito: 0,
        vendasCredito: 0,
        vendasVale: 68,
        totalVendas: 108,
        quantidadeVendas: 2,
      );
      expect(s.dinheiroGaveta, 140);
      expect(s.vale, 68);
      expect(s.pix, 0);
      expect(s.totalVendas, 108);
    });

    test('sangria maior que o saldo zera a gaveta, nao fica negativa', () {
      final s = LeituraParcialCaixaSnapshot.montar(
        fundoTroco: 10,
        suprimentos: 0,
        sangrias: 999,
        vendasDinheiro: 0,
        vendasPix: 0,
        vendasDebito: 0,
        vendasCredito: 0,
        totalVendas: 0,
        quantidadeVendas: 0,
      );
      expect(s.dinheiroGaveta, 0);
    });

    test('NaN e Infinity viram zero e o JSON serializa', () {
      final s = LeituraParcialCaixaSnapshot.montar(
        fundoTroco: double.nan,
        suprimentos: double.infinity,
        sangrias: double.negativeInfinity,
        vendasDinheiro: double.nan,
        vendasPix: 12,
        vendasDebito: 0,
        vendasCredito: 0,
        vendasVale: double.infinity,
        totalVendas: 12,
        quantidadeVendas: 1,
      );
      expect(s.dinheiroGaveta, 0);
      expect(s.fundoTroco, 0);
      expect(s.suprimentos, 0);
      expect(s.sangrias, 0);
      expect(s.vale, 0);
      expect(s.pix, 12);
      expect(() => jsonEncode(s.toJson()), returnsNormally);
      expect(() => jsonEncode(s.toAuditoriaDetalhes()), returnsNormally);
    });

    test('fromJson rejeita resposta com error', () {
      expect(
        LeituraParcialCaixaSnapshot.fromJson({'error': 'caixa nao aberto'}),
        isNull,
      );
      expect(
        LeituraParcialCaixaSnapshot.respostaValida({
          'error': 'caixa nao aberto',
        }),
        isFalse,
      );
    });

    test('fromJson reconstroi totais da API', () {
      final s = LeituraParcialCaixaSnapshot.fromJson({
        'dinheiroGaveta': 140,
        'pix': 30,
        'debito': 10,
        'credito': 5,
        'vale': 68,
        'fundoTroco': 100,
        'suprimentos': 0,
        'sangrias': 0,
        'totalVendas': 213,
        'quantidadeVendas': 3,
        'recebimentosFiadoTotal': 0,
        'recebimentosFiadoQuantidade': 0,
        'aberturaEm': '2026-08-12T20:46:00.000Z',
        'operador': 'admin',
      });
      expect(s, isNotNull);
      expect(s!.dinheiroGaveta, 140);
      expect(s.pix, 30);
      expect(s.vale, 68);
      expect(s.operador, 'admin');
      expect(s.aberturaEm, isNotNull);
    });
  });

  group('vale no bucket do caixa', () {
    test('vale nao cai no dinheiro da gaveta', () {
      expect(
        CaixaMeioPagamentoFechamento.bucket('vale'),
        CaixaMeioPagamentoFechamento.bucketVale,
      );
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('vale'), isFalse);
    });

    test('pagamento misto com vale so soma a parcela em dinheiro', () {
      final linhas = PagamentoOrcamentoCodec.decode(
        PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 40),
          const PagamentoOrcamentoLinha(
            meio: 'vale',
            valor: 68,
            valeId: 1,
            codigoVale: 'A3K92PQ7',
          ),
        ]),
      );
      var dinheiro = 0.0;
      var vale = 0.0;
      for (final l in linhas) {
        switch (CaixaMeioPagamentoFechamento.bucket(l.meio)) {
          case CaixaMeioPagamentoFechamento.bucketDinheiro:
            dinheiro += l.valor;
            break;
          case CaixaMeioPagamentoFechamento.bucketVale:
            vale += l.valor;
            break;
        }
      }
      expect(dinheiro, 40);
      expect(vale, 68);
    });
  });
}
