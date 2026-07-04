import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_consulta_insights_service.dart';
import 'package:sistema_vendas/domain/sugestao_venda_tipo.dart';

void main() {
  group('PdvConsultaAgregadoVenda.detalheLinha', () {
    String moeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

    test('cadastro manual mostra Sugestao e tipo', () {
      const ag = PdvConsultaAgregadoVenda(
        produtoId: 1,
        nome: 'Rolo',
        estoqueDisponivel: 10,
        precoReferencia: 19.99,
        tipo: SugestaoVendaTipo.acessorio,
        quantidadeSugerida: 2,
        cadastrado: true,
      );
      expect(
        ag.detalheLinha(moeda),
        'Sugestao · Acessorio · 10 · R\$ 19.99 · 2 un.',
      );
    });

    test('historico mostra vendas juntas', () {
      const ag = PdvConsultaAgregadoVenda(
        produtoId: 2,
        nome: 'Fita',
        estoqueDisponivel: 5,
        precoReferencia: 8.5,
        tipo: SugestaoVendaTipo.complementar,
        quantidadeSugerida: 1,
        historico: true,
        vendasJuntasHistorico: 7,
      );
      expect(
        ag.detalheLinha(moeda),
        'Historico · 7 vendas juntas · 5 · R\$ 8.50 · 1 un.',
      );
    });
  });
}
