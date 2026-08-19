import 'package:objectbox/objectbox.dart';

import 'produto.dart';

/// Lote de estoque com rastreio de validade (FEFO / Bota-Fora).
@Entity()
class LoteProduto {
  LoteProduto({
    this.id = 0,
    this.numeroLote = '',
    this.dataValidade,
    this.quantidadeEstoque = 0,
    DateTime? dataEntrada,
    this.ativo = true,
  }) : dataEntrada = dataEntrada ?? DateTime.now().toUtc();

  static const String numeroSemLote = 'SEM-LOTE';

  @Id(assignable: true)
  int id;

  @Index()
  String numeroLote;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataValidade;

  int quantidadeEstoque;

  @Property(type: PropertyType.dateUtc)
  DateTime dataEntrada;

  @Index()
  bool ativo;

  final produto = ToOne<Produto>();

  int get produtoId {
    try {
      return produto.targetId;
    } catch (_) {
      return 0;
    }
  }

  bool get semValidade => dataValidade == null;

  bool get vencido {
    final v = dataValidade;
    if (v == null) return false;
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final val = DateTime(v.year, v.month, v.day);
    return val.isBefore(dia);
  }

  /// Dias restantes ate a validade (negativo se vencido). Null = sem validade.
  int? get diasParaVencer {
    final v = dataValidade;
    if (v == null) return null;
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final val = DateTime(v.year, v.month, v.day);
    return val.difference(dia).inDays;
  }

  bool get vendavel =>
      ativo && quantidadeEstoque > 0 && !vencido;
}
