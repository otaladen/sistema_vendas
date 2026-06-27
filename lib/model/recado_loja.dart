import 'package:objectbox/objectbox.dart';

/// Recado interno para a equipe da loja (avisos operacionais).
@Entity()
class RecadoLoja {
  RecadoLoja({
    this.id = 0,
    this.texto = '',
    this.prioridade = 'normal',
    this.destinoTipo = 'todos',
    this.destinoPerfil = '',
    this.criadoPorLogin = '',
    this.criadoPorNome = '',
    this.leiturasJson = '[]',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  String texto;
  String prioridade;

  /// [RecadoLojaDestino.todos] ou [RecadoLojaDestino.perfil].
  String destinoTipo;

  /// Perfil alvo quando [destinoTipo] == perfil (id de [PerfilUsuarioPreset]).
  String destinoPerfil;

  String criadoPorLogin;
  String criadoPorNome;

  /// JSON array de logins que marcaram como lido.
  String leiturasJson;

  /// false = arquivado (nao exibe na faixa nem na lista ativa).
  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
