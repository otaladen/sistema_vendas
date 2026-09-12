import 'package:objectbox/objectbox.dart';

import '../domain/produto_embalagem.dart';
import 'historico_entrada.dart';

@Entity()
class Produto {
  Produto({
    this.id = 0,
    required this.codigoInterno,
    required this.nome,
    this.nomeImpressao = '',
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
    this.estoqueCd = 0,
    this.substitutosIds = '',
    this.ncm = '',
    this.cest = '',
    this.grupoTributario = 'tributado',
    this.cfopVenda = '',
    this.icmsOrigem = '',
    this.icmsSituacaoTributaria = '',
    this.pisCofinsSituacaoTributaria = '',
    int? estoque,
    int? estoqueReal,
    int? estoqueAtual,
    this.estoqueReservado = 0,
    this.estoqueVersao = 0,
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
    this.limiteDescontoPreco1 = 0,
    this.limiteDescontoPreco2 = 0,
    this.limiteDescontoPreco3 = 0,
    this.unidadeCompra = '',
    this.quantidadePorEmbalagem = 1,
    this.embalagemMultiplica = true,
    this.permiteQuantidadeFracionada = false,
    this.ultimaVendaEm,
    this.precoAlteradoEm,
    DateTime? criadoEm,
    this.ativo = true,
    this.controlaLoteValidade = false,
    this.percentualBotaFora = 0,
  }) : estoqueReal = estoqueReal ?? estoque ?? 0,
       estoqueAtual = estoqueAtual ?? estoqueReal ?? estoque ?? 0,
       criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  /// Buscas por SKU / codigo interno (NF-e, cadastro).
  @Index()
  String codigoInterno;

  /// Ordenacao em listas e busca textual no cadastro.
  @Index()
  String nome;

  /// Texto no cupom / DANFE / NF-e; vazio = usa [nome].
  String nomeImpressao;

  String descricao;
  String unidade;

  @Index()
  String categoria;

  @Index()
  String subcategoria;

  String marca;

  /// Texto livre preenchido por NF-e / vinculo de compra — nao editar na Classificacao.
  String fornecedor;

  /// Legado (Paradox/CSV). A UI usa so [marca]; gravacao espelha a marca.
  String fabricante;

  /// Resolucao por EAN na importacao de NF-e e no PDV.
  @Index()
  String codigoBarras;

  /// Apelidos de balcao, codigo fornecedor e GTIN alternativos (; ou quebra de linha).
  String apelidosBusca;

  String fotoPath;
  String localizacao;

  /// Estoque no deposito secundario (CD). Zero = nao controlado separadamente.
  int estoqueCd;

  /// IDs de produtos substitutos cadastrados (; ou ,).
  String substitutosIds;

  /// NCM — 8 digitos (obrigatorio para NFC-e).
  String ncm;
  /// CEST — 7 digitos (ST / material de construcao).
  String cest;
  /// tributado | isento | substituicao_tributaria
  String grupoTributario;
  /// CFOP fixo na venda (4 digitos); vazio = calculo automatico no [FiscalService].
  String cfopVenda;
  /// Origem ICMS (0-8); vazio = [FiscalConfig.icmsOrigemPadrao].
  String icmsOrigem;
  /// CST ICMS (2 digitos); vazio = grupo tributario / padrao da loja.
  String icmsSituacaoTributaria;
  /// CST PIS e COFINS (2 digitos); vazio = [FiscalConfig.pisCofinsSituacaoTributariaPadrao].
  String pisCofinsSituacaoTributaria;
  int estoqueReal;
  int estoqueReservado;

  /// Incrementado a cada mutacao local de estoque; usado no sync LAN.
  int estoqueVersao;

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

  /// Teto de desconto no PDV por tabela (%). Zero = usa teto geral da loja.
  double limiteDescontoPreco1;
  double limiteDescontoPreco2;
  double limiteDescontoPreco3;

  /// Unidade de compra/estoque (vazio = igual a [unidade] de venda).
  String unidadeCompra;

  /// Fator de conversao embalagem (ex.: 12 unidades por caixa).
  double quantidadePorEmbalagem;

  /// true: 1 CX com fator 12 = +12 UN no estoque; false: divide.
  bool embalagemMultiplica;

  /// Legado (ObjectBox/sync). O PDV aceita decimal na unidade de venda
  /// automaticamente; quando `true`, dados antigos em milésimos (ex.: 5 un. = 5000)
  /// continuam sendo lidos corretamente.
  bool permiteQuantidadeFracionada;

  /// Quantidade decimal na unidade de venda no PDV/orcamento (nao depende do cadastro).
  bool get pdvPermiteQuantidadeDecimal => true;

  @Property(type: PropertyType.dateUtc)
  DateTime? ultimaVendaEm;

  /// Ultima vez que preco de venda/custo foi alterado (cadastro ou reajuste).
  @Property(type: PropertyType.dateUtc)
  DateTime? precoAlteradoEm;

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

  /// Quando true, entradas/baixas usam [LoteProduto] com FEFO e Bota-Fora.
  bool controlaLoteValidade;

  /// % de desconto Bota-Fora (0 = usa padrao global da loja).
  double percentualBotaFora;

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
  /// Pode ser negativo quando a loja vende com estoque negativo.
  int get estoqueLivreParaVenda => estoqueReal - estoqueReservado;

  /// Estoque fisico em unidade de venda para exibicao (ex.: 144,62 m²).
  double get estoqueExibicao =>
      ProdutoEmbalagem.valorEstoqueExibicao(this, estoqueReal);

  /// Estoque livre em unidade de venda para exibicao e comparacao com o carrinho.
  double get estoqueLivreExibicao =>
      ProdutoEmbalagem.valorEstoqueExibicao(this, estoqueLivreParaVenda);

  /// Media diaria na unidade de venda (ex.: 2,41 m²/dia), nao em milésimos.
  double get vendaMediaDiariaExibicao =>
      ProdutoEmbalagem.valorMediaDiariaExibicao(this, vendaMediaDiaria);

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
