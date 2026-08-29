import 'package:objectbox/objectbox.dart';

import 'vale_credito.dart';
import 'venda.dart';

/// Um resgate do vale. Um vale pode ser gasto em varias compras, entao o
/// historico fica em linhas em vez de um unico campo "usado em".
@Entity()
class UsoValeCredito {
  UsoValeCredito({
    this.id = 0,
    this.valor = 0,
    this.registradoPor = '',
    this.numeroVenda = 0,
    DateTime? data,
  }) : data = data ?? DateTime.now();

  @Id(assignable: true)
  int id;

  double valor;

  String registradoPor;

  /// Numero do orcamento onde o vale foi gasto.
  int numeroVenda;

  @Property(type: PropertyType.dateUtc)
  DateTime data;

  final vale = ToOne<ValeCredito>();

  final venda = ToOne<Venda>();
}
