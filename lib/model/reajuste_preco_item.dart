import 'package:objectbox/objectbox.dart';

import 'reajuste_preco.dart';

/// Snapshot de precos de um produto em um reajuste (permite estorno).
@Entity()
class ReajustePrecoItem {
  ReajustePrecoItem({
    this.id = 0,
    this.produtoId = 0,
    this.codigoInterno = '',
    this.nome = '',
    this.preco1Antes = 0,
    this.preco2Antes = 0,
    this.preco3Antes = 0,
    this.preco1Depois = 0,
    this.preco2Depois = 0,
    this.preco3Depois = 0,
    this.alterouPreco1 = false,
    this.alterouPreco2 = false,
    this.alterouPreco3 = false,
  });

  @Id(assignable: true)
  int id;

  int produtoId;
  String codigoInterno;
  String nome;

  double preco1Antes;
  double preco2Antes;
  double preco3Antes;
  double preco1Depois;
  double preco2Depois;
  double preco3Depois;

  bool alterouPreco1;
  bool alterouPreco2;
  bool alterouPreco3;

  final reajuste = ToOne<ReajustePreco>();
}
