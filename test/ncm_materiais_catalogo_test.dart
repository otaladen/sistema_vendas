import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/fiscal/ncm_materiais_catalogo.dart';

void main() {
  test('catalogo tem NCM de PVC e cimento', () {
    expect(NcmMateriaisCatalogo.porCodigo('39172300')?.descricao, contains('PVC'));
    expect(NcmMateriaisCatalogo.porCodigo('25232910')?.descricao, contains('CIMENTO'));
  });

  test('busca por descricao e por codigo', () {
    final porNome = NcmMateriaisCatalogo.buscar('areia');
    expect(porNome, isNotEmpty);
    expect(porNome.first.codigo, startsWith('2505'));

    final porCodigo = NcmMateriaisCatalogo.buscar('3917.23');
    expect(porCodigo.any((e) => e.codigo == '39172300'), isTrue);
  });
}
