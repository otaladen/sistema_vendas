import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/sugestao_venda_ranking.dart';
import 'package:sistema_vendas/model/sugestao_venda_metrica_evento.dart';

void main() {
  group('SugestaoVendaRankingUtil.agrupar', () {
    test('soma exibicoes aceites e ignorados por par origem/sugerido/fonte', () {
      final eventos = [
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 10,
          produtoSugeridoId: 20,
          tipoEvento: 'exibiu',
          canal: 'faixa_carrinho',
          fonte: 'cadastro',
        ),
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 10,
          produtoSugeridoId: 20,
          tipoEvento: 'aceitou',
          canal: 'faixa_carrinho',
          fonte: 'cadastro',
          quantidade: 2,
        ),
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 10,
          produtoSugeridoId: 20,
          tipoEvento: 'ignorou',
          canal: 'faixa_carrinho',
          fonte: 'cadastro',
        ),
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 10,
          produtoSugeridoId: 30,
          tipoEvento: 'aceitou',
          canal: 'insights',
          fonte: 'historico',
          quantidade: 1,
        ),
      ];

      final ranking = SugestaoVendaRankingUtil.agrupar(eventos);
      expect(ranking.length, 2);

      final cadastro = ranking.firstWhere((l) => l.produtoSugeridoId == 20);
      expect(cadastro.exibicoes, 1);
      expect(cadastro.aceites, 1);
      expect(cadastro.ignorados, 1);
      expect(cadastro.taxaAceite, closeTo(0.5, 0.001));

      final historico = ranking.firstWhere((l) => l.produtoSugeridoId == 30);
      expect(historico.aceites, 1);
      expect(historico.fonte, 'historico');
    });
  });
}
