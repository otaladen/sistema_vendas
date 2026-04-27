import 'package:objectbox/objectbox.dart';

import 'produto.dart';
import 'venda.dart';

@Entity()
class ItemVenda {
  ItemVenda({
    this.id = 0,
    required this.nomeProduto,
    required this.quantidade,
    this.precoTipo = 'preco1',
    required this.precoUnitario,
    required this.precoCustoUnitario,
  });

  @Id()
  int id;

  String nomeProduto;
  int quantidade;
  String precoTipo;
  double precoUnitario;
  double precoCustoUnitario;

  final produto = ToOne<Produto>();
  final venda = ToOne<Venda>();

  double get subtotal => quantidade * precoUnitario;
  double get subtotalCusto => quantidade * precoCustoUnitario;
  double get lucro => subtotal - subtotalCusto;
}
