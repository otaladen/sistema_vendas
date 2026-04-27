import 'package:objectbox/objectbox.dart';

@Entity()
class Cliente {
  Cliente({
    this.id = 0,
    this.tipoPessoa = 'fisica',
    required this.nomeRazao,
    this.nomeFantasia = '',
    this.documento = '',
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
    this.referencia = '',
    this.limiteCredito = 0,
    this.observacoes = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  String tipoPessoa; // fisica | juridica
  String nomeRazao;
  String nomeFantasia;
  String documento; // CPF/CNPJ
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
  String referencia;
  double limiteCredito;
  String observacoes;
  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
