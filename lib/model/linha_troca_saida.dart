import 'package:objectbox/objectbox.dart';

import 'produto.dart';
import 'registro_devolucao.dart';

@Entity()
class LinhaTrocaSaida {
  LinhaTrocaSaida({
    this.id = 0,
    this.quantidade = 0,
    this.precoUnitario = 0,
    this.precoCustoUnitario = 0,
    this.precoTipo = 'preco1',
    this.nomeProdutoSnapshot = '',
  });

  @Id()
  int id;

  int quantidade;

  double precoUnitario;

  double precoCustoUnitario;

  String precoTipo;

  String nomeProdutoSnapshot;

  final registro = ToOne<RegistroDevolucao>();

  final produto = ToOne<Produto>();
}
