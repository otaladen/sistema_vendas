import 'package:objectbox/objectbox.dart';

import 'reajuste_preco_item.dart';

/// Cabecalho de um reajuste de precos em lote (auditoria e estorno).
@Entity()
class ReajustePreco {
  ReajustePreco({
    this.id = 0,
    this.usuarioLogin = '',
    this.usuarioNome = '',
    this.motivo = '',
    this.modo = 'percentual',
    this.percentualSobrePreco = 0,
    this.margemPercentual = 0,
    this.baseCusto = 'custo_digitado',
    this.arredondamento = 'centavos',
    this.tabelasCsv = 'preco1,preco2,preco3',
    this.somenteAtivos = true,
    this.protegerAbaixoCusto = true,
    this.margemMinimaPercentual = 0,
    this.totalEscopo = 0,
    this.totalAlterados = 0,
    this.totalIgnorados = 0,
    this.estornado = false,
    this.estornadoPorLogin = '',
    this.reajusteOrigemId = 0,
    DateTime? criadoEm,
    this.estornadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  String usuarioLogin;
  String usuarioNome;
  String motivo;

  /// percentual | margem
  String modo;
  double percentualSobrePreco;
  double margemPercentual;

  /// custo_digitado | custo_medio
  String baseCusto;

  /// centavos | dezena_90 | final_99
  String arredondamento;

  /// Ex.: preco1,preco2,preco3
  String tabelasCsv;

  bool somenteAtivos;
  bool protegerAbaixoCusto;
  double margemMinimaPercentual;

  int totalEscopo;
  int totalAlterados;
  int totalIgnorados;

  bool estornado;

  @Property(type: PropertyType.dateUtc)
  DateTime? estornadoEm;

  String estornadoPorLogin;

  /// Quando este registro e um estorno, aponta para o reajuste original.
  int reajusteOrigemId;

  @Backlink('reajuste')
  final itens = ToMany<ReajustePrecoItem>();
}
