import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/caixa_meio_pagamento_fechamento.dart';
import 'package:sistema_vendas/domain/venda_finalizacao_caixa_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('CaixaMeioPagamentoFechamento', () {
    test('somente dinheiro entra na gaveta', () {
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('dinheiro'), isTrue);
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('pix'), isFalse);
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('fiado'), isFalse);
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('transferencia'), isFalse);
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('outros'), isFalse);
      expect(CaixaMeioPagamentoFechamento.entraNaGaveta('desconhecido'), isFalse);
    });

    test('fiado e transferencia nao caem no bucket dinheiro', () {
      expect(CaixaMeioPagamentoFechamento.bucket('fiado'), isNull);
      expect(CaixaMeioPagamentoFechamento.bucket('transferencia'), isNull);
      expect(
        CaixaMeioPagamentoFechamento.bucket('dinheiro'),
        CaixaMeioPagamentoFechamento.bucketDinheiro,
      );
      expect(
        CaixaMeioPagamentoFechamento.bucket('pix'),
        CaixaMeioPagamentoFechamento.bucketPix,
      );
    });
  });

  group('VendaFinalizacaoCaixaHelper no periodo do caixa', () {
    test('orcamento antigo finalizado hoje usa finalizadaEm', () {
      final ontem = DateTime.utc(2026, 8, 10, 15, 0);
      final hoje = DateTime.utc(2026, 8, 11, 14, 30);
      final v = Venda(
        id: 1,
        data: ontem,
        status: 'finalizada',
        total: 100,
        formaPagamento: 'pix',
        finalizadaEm: hoje,
      );
      final momento = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
      expect(momento, hoje);

      final abertura = DateTime.utc(2026, 8, 11, 8, 0);
      final agora = DateTime.utc(2026, 8, 11, 18, 0);
      expect(momento.isBefore(abertura), isFalse);
      expect(momento.isAfter(agora), isFalse);
      // data do orcamento ficaria fora do turno se filtrasse por data:
      expect(v.data.isBefore(abertura), isTrue);
    });
  });
}
