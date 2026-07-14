import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/importacao/categoria_importacao_mapper.dart';
import 'package:sistema_vendas/domain/produto_categorias_catalogo.dart';

void main() {
  group('CategoriaImportacaoMapper', () {
    test('mapeia grupo Hidraulica para categoria do catalogo', () {
      final r = CategoriaImportacaoMapper.resolver(
        grupo: 'HIDRAULICA',
        subgrupo: 'Tubos PVC',
      );
      expect(r.categoria, 'Hidraulica');
      expect(r.subcategoria, 'Tubos e Conexoes');
    });

    test('ignora DIVERSOS e usa palavras-chave do nome via subgrupo', () {
      final r = CategoriaImportacaoMapper.resolver(
        familia: 'DIVERSOS',
        grupo: 'DIVERSOS',
        subgrupo: 'Tinta acrilica branca',
      );
      expect(r.categoria, 'Tintas e Acessorios');
    });

    test('fallback para Outros com texto livre', () {
      final r = CategoriaImportacaoMapper.resolver(
        grupo: 'Linha Especial XYZ',
        subcategoriaFallback: 'Importacao Chacal',
      );
      expect(r.categoria, ProdutoCategoriasCatalogo.outros);
      expect(r.subcategoria, 'Linha Especial XYZ');
    });

    test('mapeia subgrupo exato do catalogo', () {
      final r = CategoriaImportacaoMapper.resolver(
        grupo: 'Eletrica',
        subgrupo: 'Disjuntores',
      );
      expect(r.categoria, 'Eletrica');
      expect(r.subcategoria, 'Disjuntores');
    });
  });
}
