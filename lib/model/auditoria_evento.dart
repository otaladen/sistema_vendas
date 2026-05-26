import 'package:objectbox/objectbox.dart';

/// Evento de auditoria central (log do sistema).
@Entity()
class AuditoriaEvento {
  AuditoriaEvento({
    this.id = 0,
    this.usuarioLogin = '',
    this.modulo = '',
    this.acao = '',
    this.entidade = '',
    this.entidadeId = '',
    this.resumo = '',
    this.detalhesJson = '',
    DateTime? dataHora,
  }) : dataHora = dataHora ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Property(type: PropertyType.dateUtc)
  DateTime dataHora;

  String usuarioLogin;
  String modulo;
  String acao;
  String entidade;
  String entidadeId;
  String resumo;

  /// JSON opcional com campos extras (motivo, caminho, etc.).
  String detalhesJson;
}
