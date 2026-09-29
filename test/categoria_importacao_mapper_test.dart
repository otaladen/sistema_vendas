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

    test('mapeia nome curto de categoria nova', () {
      final r = CategoriaImportacaoMapper.resolver(
        grupo: 'Portas',
        subgrupo: 'Janela',
      );
      expect(r.categoria, 'Portas, Janelas e Vidros');
      expect(r.subcategoria, 'Janela');
    });

    test('nao confunde gesso de forro com gesso em po', () {
      final r = CategoriaImportacaoMapper.resolver(subgrupo: 'Gesso');
      expect(r.categoria, 'Forros e Divisorias');
    });
  });

  group('ProdutoCategoriasCatalogo', () {
    test('setores cobrem cada categoria uma vez', () {
      final vistas = <String>[];
      for (final setor in ProdutoCategoriasCatalogo.setores) {
        expect(setor.nome.trim(), isNotEmpty);
        for (final categoria in setor.categorias) {
          expect(
            ProdutoCategoriasCatalogo.materiaisConstrucao.containsKey(
              categoria,
            ),
            isTrue,
            reason: categoria,
          );
          expect(vistas, isNot(contains(categoria)));
          vistas.add(categoria);
          final subs = ProdutoCategoriasCatalogo.subcategoriasDe(categoria);
          expect(subs.toSet().length, subs.length, reason: categoria);
        }
      }
      expect(
        vistas.toSet(),
        ProdutoCategoriasCatalogo.materiaisConstrucao.keys.toSet(),
      );
    });

    test('resolve acento e apelido para o nome do catalogo', () {
      expect(
        ProdutoCategoriasCatalogo.resolverCategoria('Hidráulica'),
        'Hidraulica',
      );
      expect(
        ProdutoCategoriasCatalogo.resolverCategoria('Tintas'),
        'Tintas e Acessorios',
      );
      expect(
        ProdutoCategoriasCatalogo.setorDe('Iluminacao'),
        'Instalacoes',
      );
    });
  });
}
