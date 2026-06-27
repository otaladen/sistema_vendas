import 'package:objectbox/objectbox.dart';

import '../domain/lista_compra_item_constantes.dart';
import 'produto.dart';

/// Item da lista de compras (anotacao manual, sugestao aceita ou venda sem estoque).
@Entity()
class ItemListaCompra {
  ItemListaCompra({
    this.id = 0,
    this.descricaoLivre = '',
    this.quantidadeSugerida = 1,
    this.quantidadeRecebida = 0,
    this.unidade = 'UN',
    this.fornecedorTexto = '',
    this.prioridade = ListaCompraItemPrioridade.normal,
    this.observacao = '',
    this.origem = ListaCompraItemOrigem.manual,
    this.status = ListaCompraItemStatus.pendente,
    this.criadoPor = '',
    DateTime? criadoEm,
    this.resolvidoEm,
    this.nfeChaveResolucao = '',
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  final produto = ToOne<Produto>();

  /// Quando nao ha produto cadastrado (texto livre).
  String descricaoLivre;

  int quantidadeSugerida;
  int quantidadeRecebida;
  String unidade;
  String fornecedorTexto;
  String prioridade;
  String observacao;
  String origem;
  String status;

  String criadoPor;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  @Property(type: PropertyType.dateUtc)
  DateTime? resolvidoEm;

  /// NF-e de entrada que baixou (total ou parcialmente) este item.
  String nfeChaveResolucao;

  int get produtoId => produto.targetId;

  int get quantidadePendenteRecebimento {
    final falta = quantidadeSugerida - quantidadeRecebida;
    return falta < 0 ? 0 : falta;
  }

  bool get ativo =>
      ListaCompraItemStatus.ativos.contains(status);

  String nomeExibicao(Produto? produtoCarregado) {
    if (produtoCarregado != null && produtoCarregado.nome.trim().isNotEmpty) {
      return produtoCarregado.nome.trim();
    }
    final livre = descricaoLivre.trim();
    if (livre.isNotEmpty) return livre;
    return 'Item #${id > 0 ? id : '?'}';
  }
}
