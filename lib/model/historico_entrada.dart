import 'package:objectbox/objectbox.dart';

import 'produto.dart';

/// Registro de uma entrada de estoque via NF-e (importacao XML).
@Entity()
class HistoricoEntrada {
  HistoricoEntrada({
    this.id = 0,
    this.numeroNota = 0,
    this.chaveAcesso = '',
    required this.dataEmissao,
    this.nomeFornecedor = '',
    this.cnpjFornecedor = '',
    this.unidadeFornecedor = '',
    this.quantidadeFornecedor = 0,
    this.fatorConversaoUtilizado = 1,
    this.quantidadeEntradaEstoque = 0,
    this.precoCustoUnitarioNota = 0,
  });

  @Id(assignable: true)
  int id;

  /// ide/nNF
  int numeroNota;

  String chaveAcesso;

  @Property(type: PropertyType.dateUtc)
  DateTime dataEmissao;

  String nomeFornecedor;
  String cnpjFornecedor;
  String unidadeFornecedor;
  double quantidadeFornecedor;
  double fatorConversaoUtilizado;
  int quantidadeEntradaEstoque;
  double precoCustoUnitarioNota;

  final produto = ToOne<Produto>();
}
