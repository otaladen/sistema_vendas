import 'package:objectbox/objectbox.dart';

@Entity()
class Funcionario {
  Funcionario({
    this.id = 0,
    required this.codigoInterno,
    required this.nomeCompleto,
    this.cargo = '',
    this.setor = '',
    this.funcao = '',
    this.funcaoOutro = '',
    this.cpf = '',
    this.rg = '',
    this.pis = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',
    this.contatoEmergenciaNome = '',
    this.contatoEmergenciaTelefone = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.cep = '',
    this.observacoes = '',
    this.salario = 0,
    this.descontoAtual = 0,
    this.adiantamentoAtual = 0,
    this.historicoFinanceiro = '',
    this.valesJson = '[]',
    this.diaPagamento = 5,
    this.ativo = true,
    this.motivoDemissao = '',
    this.motivoDemissaoOutro = '',
    this.vendedorId = 0,
    this.motoristaId = 0,
    this.usuarioSistemaId = '',
    this.tipoVinculo = 'clt',
    this.cnhNumero = '',
    this.cnhCategoria = '',
    this.tamanhoUniforme = '',
    this.epiObservacoes = '',
    this.podeOperarEmpilhadeira = false,
    this.podeOperarTranspalete = false,
    this.fotoPath = '',
    DateTime? dataNascimento,
    DateTime? cnhValidade,
    DateTime? asoData,
    DateTime? asoValidade,
    DateTime? dataAdmissao,
    DateTime? dataDemissao,
    DateTime? criadoEm,
  }) : dataNascimento = dataNascimento ?? DateTime(2000, 1, 1),
       dataAdmissao = dataAdmissao ?? DateTime.now(),
       criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Index()
  String codigoInterno;

  @Index()
  String nomeCompleto;

  /// Campo legado (texto livre). Preferir [setor] + [funcao].
  String cargo;
  String setor;
  String funcao;
  String funcaoOutro;

  @Index()
  String cpf;
  String rg;
  String pis;
  String telefone;
  String whatsapp;
  String email;
  String contatoEmergenciaNome;
  String contatoEmergenciaTelefone;
  String endereco;
  String numero;
  String bairro;
  String cidade;
  String uf;
  String cep;
  String observacoes;
  double salario;
  double descontoAtual;
  double adiantamentoAtual;
  String historicoFinanceiro;
  String valesJson;
  int diaPagamento;

  @Index()
  bool ativo;
  String motivoDemissao;
  String motivoDemissaoOutro;

  /// Vinculo opcional com [Vendedor] no PDV (0 = sem vinculo).
  int vendedorId;

  /// Vinculo opcional com [Motorista] nas entregas (0 = sem vinculo).
  int motoristaId;

  /// Vinculo opcional com [UsuarioSistema] (id string; vazio = sem login).
  String usuarioSistemaId;

  /// clt, pj, temporario, aprendiz.
  String tipoVinculo;

  String cnhNumero;
  String cnhCategoria;
  String tamanhoUniforme;
  String epiObservacoes;
  bool podeOperarEmpilhadeira;
  bool podeOperarTranspalete;

  /// Caminho local da foto (arquivo em `funcionario_images`).
  String fotoPath;

  @Property(type: PropertyType.dateUtc)
  DateTime? cnhValidade;

  @Property(type: PropertyType.dateUtc)
  DateTime? asoData;

  @Property(type: PropertyType.dateUtc)
  DateTime? asoValidade;

  @Property(type: PropertyType.dateUtc)
  DateTime dataNascimento;

  @Property(type: PropertyType.dateUtc)
  DateTime dataAdmissao;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataDemissao;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
