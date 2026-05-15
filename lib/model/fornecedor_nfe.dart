import 'package:objectbox/objectbox.dart';

/// Emitente da NF-e (fornecedor) persistido para vinculos e historico.
@Entity()
class FornecedorNfe {
  FornecedorNfe({
    this.id = 0,
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia = '',
  });

  @Id()
  int id;

  /// CNPJ (14 digitos) ou CPF (11 digitos) do emitente, apenas numeros.
  @Unique()
  @Index()
  String cnpj;

  String razaoSocial;
  String nomeFantasia;
}
