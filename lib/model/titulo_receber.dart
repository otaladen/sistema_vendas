import 'package:objectbox/objectbox.dart';

import 'cliente.dart';
import 'venda.dart';

/// Parcela a receber gerada na finalizacao de venda fiado no caixa.
@Entity()
class TituloReceber {
  TituloReceber({
    this.id = 0,
    this.numeroParcela = 1,
    this.totalParcelas = 1,
    this.valorOriginal = 0,
    this.saldo = 0,
    this.status = TituloReceberStatusDefault.aberto,
    DateTime? vencimento,
    this.dataQuitacao,
    DateTime? criadoEm,
  })  : vencimento = vencimento ?? DateTime.now(),
        criadoEm = criadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  int numeroParcela;
  int totalParcelas;
  double valorOriginal;
  double saldo;

  /// [TituloReceberCatalogo]: aberto | quitado | cancelado
  String status;

  @Property(type: PropertyType.dateUtc)
  DateTime vencimento;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataQuitacao;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  final cliente = ToOne<Cliente>();
  final venda = ToOne<Venda>();

  bool get emAberto => status == TituloReceberStatusDefault.aberto && saldo > 0.001;

  bool get vencido =>
      emAberto && vencimento.isBefore(DateTime.now().toUtc().subtract(const Duration(days: 1)));
}

/// Evita import circular no model; espelha [TituloReceberCatalogo].
abstract final class TituloReceberStatusDefault {
  static const aberto = 'aberto';
  static const quitado = 'quitado';
  static const cancelado = 'cancelado';
}
