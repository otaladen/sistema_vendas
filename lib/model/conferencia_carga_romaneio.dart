import 'package:objectbox/objectbox.dart';

/// Conferencia de item na carga consolidada de uma viagem (escopo logistica).
@Entity()
class ConferenciaCargaRomaneio {
  ConferenciaCargaRomaneio({
    this.id = 0,
    this.escopoViagem = '',
    this.chaveProduto = '',
    this.conferido = false,
    this.usuarioLogin = '',
    DateTime? atualizadoEm,
  }) : atualizadoEm = atualizadoEm ?? DateTime.now();

  @Id()
  int id;

  /// `g:{grupoEntregaFreteId}` ou `s:{vendaId}` (mesmo [MontagemEntregaViagem.chave]).
  @Index()
  String escopoViagem;

  /// Chave do produto na carga (`p:produtoId` ou `n:nome`).
  @Index()
  String chaveProduto;

  bool conferido;
  String usuarioLogin;

  @Property(type: PropertyType.dateUtc)
  DateTime atualizadoEm;
}
