import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_nome_titulo_normalizer.dart';

void main() {
  test('converte MAIUSCULO para titulo como no exemplo', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar(
        'ABRACADEIRA NYLON 100MM X 2.5MM',
      ),
      'Abracadeira Nylon 100mm X 2.5mm',
    );
  });

  test('mantem conectores em minusculo', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar(
        'ABRACADEIRA DE NYLON 100MM X 2.5MM',
      ),
      'Abracadeira de Nylon 100mm X 2.5mm',
    );
  });

  test('exemplo ja formatado permanece coerente', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar(
        'Abraçadeira de Nylon 100mm X 2.5mm',
      ),
      'Abraçadeira de Nylon 100mm X 2.5mm',
    );
  });

  test('PVC e unidades', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar('TUBO PVC ESG 100MM'),
      'Tubo PVC ESG 100mm',
    );
  });

  test('dimensao 450X7.0MM', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar('ABRACADEIRA NYLON 450X7.0MM'),
      'Abracadeira Nylon 450X7.0mm',
    );
  });

  test('espacos extras', () {
    expect(
      ProdutoNomeTituloNormalizer.normalizar('  CIMENTO   CPII  50KG  '),
      'Cimento Cpii 50kg',
    );
  });
}
