import 'package:objectbox/objectbox.dart';

import '../domain/produto_embalagem.dart';
import 'historico_entrada.dart';

@Entity()
class Produto {
  Produto({
    this.id = 0,
    required this.codigoInterno,
    required this.nome,
    this.descricao = '',
    this.unidade = 'UN',
    this.categoria = '',
    this.subcategoria = '',
    this.marca = '',
    this.fornecedor = '',
    this.fabricante = '',
    this.codigoBarras = '',
    this.apelidosBusca = '',
    this.fotoPath = '',
    this.localizacao = '',
    this.ncm = '',
    this.cest = '',
    this.grupoTributario = 'tributado',
    this.cfopVenda = '',
    int? estoque,
    int? estoqueReal,
    int? estoqueAtual,
    this.estoqueReservado = 0,
    this.leadTimeDias = 7,
    this.vendaMediaDiaria = 0,
    this.estoqueSeguranca = 0,
    required this.quantidadeMinima,
    required this.precoCusto,
    this.custoMedio = 0,
    this.preco1 = 0,
    this.preco2 = 0,
    this.preco3 = 0,
    required this.precoVenda,
    this.unidadeCompra = '',
    this.quantidadePorEmbalagem = 1,
    this.embalagemMultiplica = true,
    this.permiteQuantidadeFracionada = false,
    this.ultimaVendaEm,
    DateTime? criadoEm,
    this.ativo = true,
  }) : estoqueReal = estoqueReal ?? estoque ?? 0,
       estoqueAtual = estoqueAtual ?? estoqueReal ?? estoque ?? 0,
       criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  /// Buscas por SKU / codigo interno (NF-e, cadastro).
  @Index()
  String codigoInterno;

  /// Ordenacao em listas e busca textual no cadastro.
  @Index()
  String nome;

  String descricao;
  String unidade;
  String categoria;
  String subcategoria;
  String marca;
  String fornecedor;
  String fabricante;

  /// Resolucao por EAN na importacao de NF-e e no PDV.
  @Index()
  String codigoBarras;

  /// Apelidos de balcao, codigo fornecedor e GTIN alternativos (; ou quebra de linha).
  String apelidosBusca;

  String fotoPath;
  String localizacao;
  /// NCM — 8 digitos (obrigatorio para NFC-e).
  String ncm;
  /// CEST — 7 digitos (ST / material de construcao).
  String cest;
  /// tributado | isento | substituicao_tributaria
  String grupoTributario;
  /// CFOP fixo na venda (4 digitos); vazio = calculo automatico no [FiscalService].
  String cfopVenda;
  int estoqueReal;
  int estoqueReservado;

  /// Estoque atual para compras preditivas (mantido alinhado a [estoqueReal]).
  int estoqueAtual;

  /// Dias entre pedir ao fornecedor e receber mercadoria.
  int leadTimeDias;

  /// Media de unidades vendidas por dia (recalculada apos cada venda).
  double vendaMediaDiaria;

  /// Colchao extra no ponto de pedido (unidades).
  int estoqueSeguranca;

  int quantidadeMinima;
  double precoCusto;

  /// Custo medio ponderado pelas entradas de NF-e (importacao / sync).
  /// Sem movimentacao de entrada, permanece alinhado ao [precoCusto] para exibicao em relatorios.
  double custoMedio;
  double preco1;
  double preco2;
  double preco3;
  double precoVenda;

  /// Unidade de compra/estoque (vazio = igual a [unidade] de venda).
  String unidadeCompra;

  /// Fator de conversao embalagem (ex.: 12 unidades por caixa).
  double quantidadePorEmbalagem;

  /// true: 1 CX com fator 12 = +12 UN no estoque; false: divide.
  bool embalagemMultiplica;

  /// Permite quantidade decimal no PDV (m, m², kg, etc.).
  bool permiteQuantidadeFracionada;

  @Property(type: PropertyType.dateUtc)
  DateTime? ultimaVendaEm;

  double get lucroValor => precoVenda - precoCusto;
  double get markupPercentual {
    if (precoCusto <= 0) {
      return 0;
    }
    return ((precoVenda - precoCusto) / precoCusto) * 100;
  }

  double get margemLucroPercentual {
    if (precoVenda <= 0) {
      return 0;
    }
    return ((precoVenda - precoCusto) / precoVenda) * 100;
  }

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  /// Quando `false`, o produto nao aparece no PDV/pesquisa de venda, mas permanece no cadastro e no historico.
  @Index()
  bool ativo;

  // Mantem compatibilidade com o codigo legado enquanto a migracao
  // para estoqueReal/estoqueReservado e finalizada.
  int get estoque => estoqueReal;
  set estoque(int value) {
    estoqueReal = value;
    estoqueAtual = value;
  }

  /// PP = (vendaMediaDiaria * leadTimeDias) + estoqueSeguranca
  double get pontoPedido =>
      (vendaMediaDiaria * leadTimeDias) + estoqueSeguranca;

  /// Estoque atual atingiu ou ficou abaixo do PP (formula simples).
  /// Para produtos novos, use [ComprasPreditivasService.verificarEstoqueCritico].
  bool get estoqueCritico => estoqueAtual <= pontoPedido;

  /// Fisico menos comprometido em [estoqueReservado] (retirada futura, carreto ate sair).
  int get estoqueLivreParaVenda {
    final livre = estoqueReal - estoqueReservado;
    return livre < 0 ? 0 : livre;
  }

  String get unidadeCompraEfetiva {
    final u = unidadeCompra.trim();
    return u.isEmpty ? unidade : u;
  }

  bool get temConversaoEmbalagem => ProdutoEmbalagem.temConversao(this);

  bool get pdvPodeVenderEmUnidadeCompra =>
      ProdutoEmbalagem.vendaPodeUsarUnidadeCompra(this);

  /// Texto curto para UI (ex.: "1 CX = 12 UN").
  String get rotuloConversaoEmbalagem => ProdutoEmbalagem.rotuloConversao(this);

  @Backlink('produto')
  final historicoEntradas = ToMany<HistoricoEntrada>();
}
