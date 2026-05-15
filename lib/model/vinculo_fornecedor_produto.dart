import 'package:objectbox/objectbox.dart';

import 'fornecedor_nfe.dart';
import 'produto.dart';

/// Lembra codigo do item na NF-e do fornecedor e o fator de conversao para o [Produto] interno.
@Entity()
class VinculoFornecedorProduto {
  VinculoFornecedorProduto({
    this.id = 0,
    required this.codigoProdutoFornecedor,
    required this.fatorConversao,
  });

  @Id()
  int id;

  /// [prod]/cProd na NF-e — busca junto com [fornecedor].
  @Index()
  String codigoProdutoFornecedor;

  /// Multiplicador: quantidade interna = qCom * fatorConversao.
  double fatorConversao;

  final fornecedor = ToOne<FornecedorNfe>();
  final produto = ToOne<Produto>();
}
