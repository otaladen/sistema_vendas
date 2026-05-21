import 'package:objectbox/objectbox.dart';

import 'promocao.dart';

/// Escopo de uma [Promocao] sobre produtos.
@Entity()
class PromocaoItem {
  PromocaoItem({
    this.id = 0,
    this.produtoAlvoId = 0,
    this.categoria = '',
    this.subcategoria = '',
    this.quantidadeMinima = 1,
    this.quantidadeMaximaPromo = 0,
    this.ordem = 0,
  });

  @Id()
  int id;

  /// Produto especifico; 0 = usar [categoria]/[subcategoria].
  int produtoAlvoId;

  String categoria;
  String subcategoria;

  int quantidadeMinima;

  /// Maximo por venda nesta campanha (0 = sem limite por linha).
  int quantidadeMaximaPromo;

  int ordem;

  final promocao = ToOne<Promocao>();
}
