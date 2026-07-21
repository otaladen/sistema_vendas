import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/fiscal/ncm_cest_sugestao.dart';

void main() {
  group('NcmCestSugestao', () {
    test('sugere CEST de cimento por prefixo 2523', () {
      expect(NcmCestSugestao.sugerirCest('25232910'), '1000100');
    });

    test('sugere CEST de tinta por prefixo 3208', () {
      expect(NcmCestSugestao.sugerirCest('3208.10.00'), '1001000');
    });

    test('sugere CEST de tubo PVC 3917', () {
      expect(NcmCestSugestao.sugerirCest('39172300'), '1000600');
    });

    test('retorna null para NCM incompleto ou desconhecido', () {
      expect(NcmCestSugestao.sugerirCest('12'), isNull);
      expect(NcmCestSugestao.sugerirCest('99999999'), isNull);
    });

    test('preencherSeVazio nao sobrescreve CEST ja informado', () {
      expect(
        NcmCestSugestao.preencherSeVazio(
          ncm: '25232910',
          cestAtual: '10.001.00',
        ),
        '1000100',
      );
      expect(
        NcmCestSugestao.preencherSeVazio(
          ncm: '25232910',
          cestAtual: '2100200',
        ),
        '2100200',
      );
    });

    test('formatarCestExibicao', () {
      expect(NcmCestSugestao.formatarCestExibicao('1000100'), '10.001.00');
    });
  });
}
