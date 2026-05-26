import 'package:objectbox/objectbox.dart';

import 'produto.dart';

/// Agrupamento de produtos para montagem rapida de orcamento (ex.: kit banheiro).
@Entity()
class KitOrcamento {
  KitOrcamento({
    this.id = 0,
    required this.nome,
    this.descricao = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Index()
  String nome;

  String descricao;
  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  @Backlink('kit')
  final itens = ToMany<KitOrcamentoItem>();
}

/// Linha de um [KitOrcamento]: produto base e quantidade por aplicacao do kit.
@Entity()
class KitOrcamentoItem {
  KitOrcamentoItem({
    this.id = 0,
    this.quantidade = 1,
    this.ordem = 0,
  });

  @Id(assignable: true)
  int id;

  /// Quantidade deste produto por "1 kit" inserido no orcamento.
  int quantidade;

  /// Ordem de exibicao / aplicacao no PDV.
  int ordem;

  final kit = ToOne<KitOrcamento>();
  final produto = ToOne<Produto>();
}
