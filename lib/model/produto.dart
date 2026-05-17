import 'package:objectbox/objectbox.dart';

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
    this.fotoPath = '',
    this.localizacao = '',
    this.ncm = '',
    this.cest = '',
    this.grupoTributario = 'tributado',
    this.cfopVenda = '',
    int? estoque,
    int? estoqueReal,
    this.estoqueReservado = 0,
    required this.quantidadeMinima,
    required this.precoCusto,
    this.custoMedio = 0,
    this.preco1 = 0,
    this.preco2 = 0,
    this.preco3 = 0,
    required this.precoVenda,
    DateTime? criadoEm,
    this.ativo = true,
  }) : estoqueReal = estoqueReal ?? estoque ?? 0,
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
  int quantidadeMinima;
  double precoCusto;

  /// Custo medio ponderado pelas entradas de NF-e (importacao / sync).
  /// Sem movimentacao de entrada, permanece alinhado ao [precoCusto] para exibicao em relatorios.
  double custoMedio;
  double preco1;
  double preco2;
  double preco3;
  double precoVenda;
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
  set estoque(int value) => estoqueReal = value;

  /// Fisico menos comprometido em [estoqueReservado] (retirada futura, carreto ate sair).
  int get estoqueLivreParaVenda {
    final livre = estoqueReal - estoqueReservado;
    return livre < 0 ? 0 : livre;
  }

  @Backlink('produto')
  final historicoEntradas = ToMany<HistoricoEntrada>();
}
