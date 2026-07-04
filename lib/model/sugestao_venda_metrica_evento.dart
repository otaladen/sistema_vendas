import 'package:objectbox/objectbox.dart';

/// Evento de metrica: exibicao, aceite ou ignorar sugestao agregada no PDV.
@Entity()
class SugestaoVendaMetricaEvento {
  SugestaoVendaMetricaEvento({
    this.id = 0,
    required this.produtoOrigemId,
    required this.produtoSugeridoId,
    required this.tipoEvento,
    required this.canal,
    required this.fonte,
    this.quantidade = 0,
    this.usuarioLogin = '',
    DateTime? dataHora,
  }) : dataHora = dataHora ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Index()
  int produtoOrigemId;

  @Index()
  int produtoSugeridoId;

  /// [SugestaoVendaMetricaTipo]
  String tipoEvento;

  /// [SugestaoVendaMetricaCanal]
  String canal;

  /// [SugestaoVendaMetricaFonte]
  String fonte;

  int quantidade;
  String usuarioLogin;

  @Property(type: PropertyType.dateUtc)
  DateTime dataHora;
}
