import 'package:objectbox/objectbox.dart';

@Entity()
class Motorista {
  Motorista({
    this.id = 0,
    this.codigoInterno = '',
    this.nome = '',
    this.telefone = '',
    this.cpf = '',
    this.cnhNumero = '',
    this.cnhCategoria = '',
    this.cnhValidade,
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  String codigoInterno;
  String nome;
  String telefone;
  String cpf;
  String cnhNumero;
  String cnhCategoria;

  @Property(type: PropertyType.dateUtc)
  DateTime? cnhValidade;

  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
