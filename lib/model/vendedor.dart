import 'package:objectbox/objectbox.dart';

/// Cadastro voltado ao **time de vendas** da loja (orcamentos, PDV, comissao).
/// Para dados de RH (admissao, pis, cargo administrativo etc.), use futura tela Funcionarios.
@Entity()
class Vendedor {
  Vendedor({
    this.id = 0,
    required this.codigoInterno,
    required this.nomeCompleto,
    this.apelido = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',

    /// Percentual sobre o valor vendido (ex.: 2.5 para dois e meio por cento).
    this.percentualComissao = 0,

    /// Referencia opcional para metas simples em R\$ (mesmo formato que totais na loja).
    this.metaMensalValor = 0,

    /// Notas sobre area de loja que atende, cliente tipo etc.
    this.observacoesComerciais = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  /// Codigo curto para cupons e identificacao interna (ex.: V03).
  String codigoInterno;

  String nomeCompleto;

  /// Nome impresso/em telas onde cabe menos texto.
  String apelido;

  String telefone;
  String whatsapp;
  String email;

  double percentualComissao;

  double metaMensalValor;

  String observacoesComerciais;

  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
