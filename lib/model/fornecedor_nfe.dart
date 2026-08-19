import 'package:objectbox/objectbox.dart';

/// Fornecedor / emitente de NF-e (compra) e credor de contas a pagar.
///
/// Criado automaticamente na importacao de NF-e e no lancamento manual de
/// contas a pagar; tambem editavel pelo cadastro de Fornecedores.
@Entity()
class FornecedorNfe {
  FornecedorNfe({
    this.id = 0,
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia = '',
    this.inscricaoEstadual = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',
    this.cep = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.observacoes = '',
    this.ativo = true,
    DateTime? atualizadoEm,
  }) : atualizadoEm = atualizadoEm ?? DateTime.now().toUtc();

  @Id(assignable: true)
  int id;

  /// CNPJ (14 digitos), CPF (11) ou chave sintetica `MANUAL_…` (despesa sem doc).
  @Unique()
  @Index()
  String cnpj;

  String razaoSocial;
  String nomeFantasia;
  String inscricaoEstadual;
  String telefone;
  String whatsapp;
  String email;
  String cep;
  String endereco;
  String numero;
  String bairro;
  String cidade;
  String uf;
  String observacoes;
  bool ativo;

  @Property(type: PropertyType.dateNano)
  DateTime atualizadoEm;

  String get nomeExibicao {
    final f = nomeFantasia.trim();
    if (f.isNotEmpty) return f;
    final r = razaoSocial.trim();
    return r.isEmpty ? 'Fornecedor' : r;
  }

  bool get ehManualSemDocumento => cnpj.startsWith('MANUAL_');
}
