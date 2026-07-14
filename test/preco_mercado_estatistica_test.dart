import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/preco_mercado_estatistica.dart';
import 'package:sistema_vendas/domain/preco_mercado_resultado.dart';
import 'package:sistema_vendas/services/preco_mercado_service.dart';

void main() {
  group('PrecoMercadoParser', () {
    test('parseia R\$ com virgula e milhar', () {
      expect(PrecoMercadoParser.parseBrl('47,90'), 47.90);
      expect(PrecoMercadoParser.parseBrl('1.234,56'), 1234.56);
    });

    test('parseia R\$ 47 90 (centavos com espaco)', () {
      expect(PrecoMercadoParser.parseBrl('47 90'), 47.90);
    });

    test('extrai preco principal e ignora preco por kg quando ha ambos', () {
      const texto =
          'Argamassa Aciii 20kg Cinza R\$ 47 90 Preço por quilo: R\$ 2,39';
      expect(PrecoMercadoParser.extrairPrecoPrincipal(texto), 47.90);
    });
  });

  group('PrecoMercadoEstatistica', () {
    test('mediana e IQR removem outlier', () {
      final filtrados = PrecoMercadoEstatistica.filtrarOutliers([
        40,
        42,
        43,
        45,
        44,
        500,
      ]);
      expect(filtrados.contains(500), isFalse);
      expect(PrecoMercadoEstatistica.mediana(filtrados), closeTo(43, 0.01));
    });
  });

  test('query basica nao acrescenta UN e remove sufixo UN', () {
    expect(
      PrecoMercadoService.montarQueryBasica(
        nome: 'CIMENTO 50KG POTY',
        codigoBarras: '2890040270017',
        unidade: 'UN',
      ),
      'CIMENTO 50KG POTY',
    );
    expect(
      PrecoMercadoService.montarQueryBasica(
        nome: 'CIMENTO 50KG POTY UN',
        unidade: 'UN',
      ),
      'CIMENTO 50KG POTY',
    );
  });

  test('links externos priorizam Salvador e lojas-alvo', () {
    final svc = PrecoMercadoService();
    final links = svc.montarLinksExternos('CIMENTO 50KG POTY');
    expect(links.length, greaterThanOrEqualTo(4));
    expect(links.any((l) => l.rotulo.contains('Ferreira Costa')), isTrue);
    expect(links.any((l) => l.rotulo.contains('Leroy')), isTrue);
    expect(links.any((l) => l.rotulo.contains('Mercado Livre')), isTrue);
    expect(links.any((l) => l.rotulo.contains('Google Shopping')), isTrue);
    expect(links.any((l) => l.url.contains('tbm=shop')), isTrue);
  });

  test('extrai precos por loja de texto colado', () {
    const texto =
        'Ferreira Costa R\$ 34,90 / Leroy Merlin R\$ 36,50 e Mercado Livre R\$ 33,00';
    final mapa = PrecoMercadoParser.extrairPrecosPorLoja(texto);
    expect(mapa['Ferreira Costa'], 34.90);
    expect(mapa['Leroy Merlin'], 36.50);
    expect(mapa['Mercado Livre'], 33.00);
  });

  test('media manual usa precos informados', () {
    final svc = PrecoMercadoService();
    final r = svc.resumirPrecosManuais(
      queryUsada: 'CIMENTO 50KG POTY',
      precosPorLoja: {
        'Ferreira Costa': 34.9,
        'Leroy Merlin': 36.5,
        'Mercado Livre': 33.0,
      },
    );
    expect(r.precoSugerido, closeTo(34.9, 0.01));
    expect(r.amostrasPrioritarias, 3);
  });
}
