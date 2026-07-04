import 'package:objectbox/objectbox.dart';

/// Sugestao manual de produto agregado para oferta no PDV.
@Entity()
class ProdutoSugestaoVenda {
  ProdutoSugestaoVenda({
    this.id = 0,
    required this.produtoOrigemId,
    required this.produtoSugeridoId,
    this.tipo = 'complementar',
    this.quantidadeSugerida = 1,
    this.prioridade = 0,
    this.observacao = '',
    this.ativo = true,
  });

  @Id(assignable: true)
  int id;

  @Index()
  int produtoOrigemId;

  @Index()
  int produtoSugeridoId;

  /// [SugestaoVendaTipo.codigo]
  String tipo;

  int quantidadeSugerida;
  int prioridade;
  String observacao;
  bool ativo;
}
