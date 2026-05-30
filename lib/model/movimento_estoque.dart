import 'package:objectbox/objectbox.dart';

import 'produto.dart';

/// Linha do kardex (livro razao de estoque) por produto.
@Entity()
class MovimentoEstoque {
  MovimentoEstoque({
    this.id = 0,
    this.tipoMovimento = '',
    this.deltaFisico = 0,
    this.deltaReserva = 0,
    this.saldoFisicoAntes = 0,
    this.saldoFisicoDepois = 0,
    this.saldoReservaAntes = 0,
    this.saldoReservaDepois = 0,
    this.documentoReferencia = '',
    this.motivo = '',
    this.usuarioLogin = '',
    DateTime? registradoEm,
  }) : registradoEm = registradoEm ?? DateTime.now().toUtc();

  @Id(assignable: true)
  int id;

  /// Nome do [TipoMovimentoEstoque] (enum .name).
  @Index()
  String tipoMovimento;

  int deltaFisico;
  int deltaReserva;
  int saldoFisicoAntes;
  int saldoFisicoDepois;
  int saldoReservaAntes;
  int saldoReservaDepois;

  /// Venda #, chave NF-e, etc.
  String documentoReferencia;
  String motivo;
  String usuarioLogin;

  @Property(type: PropertyType.dateUtc)
  DateTime registradoEm;

  final produto = ToOne<Produto>();
}
