import 'package:objectbox/objectbox.dart';

/// Auditoria historica de caixa (ObjectBox). Independente do log central
/// ([AuditoriaEvento]), que pode ser expurgado por retencao.
@Entity()
class CaixaAuditoriaEvento {
  CaixaAuditoriaEvento({
    this.id = 0,
    DateTime? dataHora,
    this.data = '',
    this.hora = '',
    this.tipo = '',
    this.operador = '',
    this.usuario = '',
    this.valor = 0,
    this.detalhesJson = '',
  }) : dataHora = dataHora ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Property(type: PropertyType.dateUtc)
  @Index()
  DateTime dataHora;

  /// Data civil local no momento do registro (`yyyy-MM-dd`).
  String data;

  /// Hora local no momento do registro (`HH:mm:ss`).
  String hora;

  /// `suprimento`, `sangria` ou `fechamento_caixa`.
  @Index()
  String tipo;

  @Index()
  String operador;

  String usuario;
  double valor;

  /// JSON com campos extras (observacao, conferencia, etc.).
  String detalhesJson;
}
