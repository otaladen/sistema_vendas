import 'package:objectbox/objectbox.dart';

@Entity()
class Motorista {
  Motorista({
    this.id = 0,
    this.nome = '',
    this.telefone = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  String nome;
  String telefone;
  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
