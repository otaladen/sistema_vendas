import 'package:objectbox/objectbox.dart';

/// Cabecalho da NF-e ja processada no estoque (evita duplicidade pela chave de 44 digitos).
@Entity()
class NfeImportadaRegistro {
  NfeImportadaRegistro({
    this.id = 0,
    required this.chaveAcesso,
    this.numeroNota = 0,
    required this.dataEmissao,
    this.nomeFornecedor = '',
    this.cnpjFornecedor = '',
    required this.dataHoraImportacao,
    this.quantidadeItens = 0,
  });

  @Id(assignable: true)
  int id;

  /// Chave de acesso da NF-e (44 digitos), unica.
  @Unique()
  @Index()
  String chaveAcesso;

  int numeroNota;

  @Property(type: PropertyType.dateUtc)
  DateTime dataEmissao;

  String nomeFornecedor;
  String cnpjFornecedor;

  @Property(type: PropertyType.dateUtc)
  DateTime dataHoraImportacao;

  int quantidadeItens;
}
