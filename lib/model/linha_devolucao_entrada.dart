import 'package:objectbox/objectbox.dart';

import 'produto.dart';
import 'registro_devolucao.dart';

@Entity()
class LinhaDevolucaoEntrada {
  LinhaDevolucaoEntrada({
    this.id = 0,
    this.itemVendaId = 0,
    this.quantidade = 0,
    this.precoUnitarioReferencia = 0,
    this.nomeProdutoSnapshot = '',
  });

  @Id()
  int id;

  int itemVendaId;

  int quantidade;

  double precoUnitarioReferencia;

  String nomeProdutoSnapshot;

  final registro = ToOne<RegistroDevolucao>();

  final produto = ToOne<Produto>();
}
