import 'package:objectbox/objectbox.dart';

import 'promocao_combo_item.dart';
import 'promocao_item.dart';

/// Campanha promocional com vigencia (Fase 1).
@Entity()
class Promocao {
  Promocao({
    this.id = 0,
    required this.nome,
    this.descricao = '',
    required this.dataInicio,
    required this.dataFim,
    this.ativa = true,
    this.prioridade = 0,
    this.tipoRegra = 'preco_fixo',
    this.valorRegra = 0,
    this.segmentoCliente = '',
    this.tipoCampanha = 'produto',
    this.margemMinimaPercentual = 0,
    this.limiteQuantidadeTotal = 0,
    this.quantidadeVendidaPromo = 0,
    this.leveQuantidade = 0,
    this.pagueQuantidade = 0,
    this.precoCombo = 0,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  @Index()
  String nome;

  String descricao;

  @Property(type: PropertyType.dateUtc)
  DateTime dataInicio;

  @Property(type: PropertyType.dateUtc)
  DateTime dataFim;

  bool ativa;

  /// Maior valor vence em empate de escopo.
  int prioridade;

  /// [preco_fixo] | [desconto_percentual] (base sempre preco 1).
  String tipoRegra;

  double valorRegra;

  /// Vazio = todos os segmentos; senao [Cliente.segmento] (consumidor, construtor...).
  String segmentoCliente;

  /// [produto] | [leve_pague] | [combo_ab] — ver [PromocaoCadastro].
  String tipoCampanha;

  /// Margem minima sobre preco de venda (%). 0 = sem trava.
  double margemMinimaPercentual;

  /// Teto global de unidades vendidas com esta campanha (0 = ilimitado).
  int limiteQuantidadeTotal;

  /// Contador acumulado ao finalizar vendas.
  int quantidadeVendidaPromo;

  /// Leve X pague Y (ex.: 3 e 2).
  int leveQuantidade;
  int pagueQuantidade;

  /// Preco total do combo A+B quando [tipoCampanha] = combo_ab.
  double precoCombo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  @Backlink('promocao')
  final itens = ToMany<PromocaoItem>();

  @Backlink('promocao')
  final comboItens = ToMany<PromocaoComboItem>();
}
