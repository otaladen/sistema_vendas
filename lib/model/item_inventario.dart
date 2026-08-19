import 'package:objectbox/objectbox.dart';

import '../domain/inventario_constantes.dart';
import 'produto.dart';

/// Linha de contagem de uma [SessaoInventario], com snapshot do estoque.
@Entity()
class ItemInventario {
  ItemInventario({
    this.id = 0,
    this.sessaoId = 0,
    this.produtoId = 0,
    this.nomeSnapshot = '',
    this.codigoInterno = '',
    this.codigoBarras = '',
    this.unidade = 'UN',
    this.categoria = '',
    this.subcategoria = '',
    this.permiteQuantidadeFracionada = false,
    this.quantidadePorEmbalagem = 1,
    this.embalagemMultiplica = true,
    this.unidadeCompra = '',
    this.controlaLoteValidade = false,
    this.snapshotFisico = 0,
    this.snapshotLivre = 0,
    this.snapshotReservado = 0,
    this.quantidadeContada = 0,
    this.conferido = false,
    this.estado = InventarioItemEstado.pendente,
    this.conferidoPor = '',
    this.conferidoEm,
    this.custoUnitario = 0,
    this.aplicado = false,
  });

  @Id(assignable: true)
  int id;

  @Index()
  int sessaoId;

  @Index()
  int produtoId;

  String nomeSnapshot;
  String codigoInterno;
  String codigoBarras;
  String unidade;
  String categoria;
  String subcategoria;
  bool permiteQuantidadeFracionada;
  double quantidadePorEmbalagem;
  bool embalagemMultiplica;
  String unidadeCompra;
  bool controlaLoteValidade;

  /// [Produto.estoqueReal] no momento do snapshot.
  int snapshotFisico;

  /// [Produto.estoqueLivreParaVenda] no snapshot.
  int snapshotLivre;

  int snapshotReservado;

  /// Quantidade fisica contada na mesma escala de [Produto.estoqueReal].
  int quantidadeContada;

  bool conferido;

  @Index()
  String estado;

  String conferidoPor;

  @Property(type: PropertyType.dateUtc)
  DateTime? conferidoEm;

  /// Custo unitario (unidade de venda) no snapshot, para valor estimado.
  double custoUnitario;

  /// True apos gerar movimentacao de ajuste nesta sessao.
  bool aplicado;

  int get deltaArmazenado {
    if (!conferido) return 0;
    return quantidadeContada - snapshotFisico;
  }

  void aplicarEstadoDaContagem() {
    if (!conferido) {
      estado = InventarioItemEstado.pendente;
    } else if (quantidadeContada == snapshotFisico) {
      estado = InventarioItemEstado.conferidoOk;
    } else {
      estado = InventarioItemEstado.divergente;
    }
  }

  /// Contexto de escala quando o produto vivo nao esta disponivel.
  Produto comoProdutoStub() {
    return Produto(
      id: produtoId,
      codigoInterno: codigoInterno,
      nome: nomeSnapshot,
      unidade: unidade,
      categoria: categoria,
      subcategoria: subcategoria,
      codigoBarras: codigoBarras,
      permiteQuantidadeFracionada: permiteQuantidadeFracionada,
      quantidadePorEmbalagem: quantidadePorEmbalagem <= 0
          ? 1
          : quantidadePorEmbalagem,
      embalagemMultiplica: embalagemMultiplica,
      unidadeCompra: unidadeCompra,
      controlaLoteValidade: controlaLoteValidade,
      quantidadeMinima: 0,
      precoCusto: custoUnitario,
      custoMedio: custoUnitario,
      precoVenda: 0,
    );
  }
}
