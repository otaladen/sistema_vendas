import 'package:objectbox/objectbox.dart';

/// Fechamento mensal de folha simplificada por funcionario.
@Entity()
class FechamentoRhFuncionario {
  FechamentoRhFuncionario({
    this.id = 0,
    required this.funcionarioId,
    required this.mesReferencia,
    this.salarioBase = 0,
    this.descontoFixo = 0,
    this.totalVales = 0,
    this.totalDescontosLancados = 0,
    this.totalBonus = 0,
    this.liquidoApagar = 0,
    this.qtdVales = 0,
    this.contaPagarId = 0,
    this.fechadoPorLogin = '',
    DateTime? fechadoEm,
  }) : fechadoEm = fechadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  int funcionarioId;

  /// Primeiro dia do mes de referencia (UTC).
  @Property(type: PropertyType.dateUtc)
  DateTime mesReferencia;

  double salarioBase;
  double descontoFixo;
  double totalVales;
  double totalDescontosLancados;
  double totalBonus;
  double liquidoApagar;
  int qtdVales;

  /// Titulo gerado em Contas a Pagar (0 = nenhum).
  int contaPagarId;

  String fechadoPorLogin;

  @Property(type: PropertyType.dateUtc)
  DateTime fechadoEm;
}
