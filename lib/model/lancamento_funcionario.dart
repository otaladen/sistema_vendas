import 'package:objectbox/objectbox.dart';

import 'funcionario.dart';

/// Lancamento financeiro estruturado (vale, desconto, bonus, observacao).
@Entity()
class LancamentoFuncionario {
  LancamentoFuncionario({
    this.id = 0,
    required this.tipo,
    this.valor = 0,
    this.observacao = '',
    this.estornado = false,
    DateTime? data,
    DateTime? criadoEm,
  })  : data = data ?? DateTime.now(),
        criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  /// Um de [LancamentoFuncionarioCatalogo] (vale, desconto, bonus, observacao).
  String tipo;

  double valor;

  String observacao;

  bool estornado;

  @Property(type: PropertyType.dateUtc)
  DateTime data;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  final funcionario = ToOne<Funcionario>();
}
