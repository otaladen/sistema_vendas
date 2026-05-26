import 'package:objectbox/objectbox.dart';

import '../../model/fornecedor_nfe.dart';

/// Valores persistidos em [ContaPagar.status].
abstract final class ContaPagarStatus {
  static const pendente = 'PENDENTE';
  static const pago = 'PAGO';
  static const atrasado = 'ATRASADO';
}

/// Parcela / título a pagar (NF-e ou lançamento manual).
///
/// O vínculo com emitente usa [FornecedorNfe] (cadastro de fornecedor NF-e do sistema).
@Entity()
class ContaPagar {
  ContaPagar({
    this.id = 0,
    this.nfeChave,
    this.numeroNota,
    required this.numeroParcela,
    required this.dataEmissao,
    required this.dataVencimento,
    required this.valorParcela,
    this.status = ContaPagarStatus.pendente,
    this.dataPagamento,
    this.valorPago,
  });

  @Id(assignable: true)
  int id;

  /// Chave da NF-e (44 dígitos); nulo quando conta manual.
  String? nfeChave;

  String? numeroNota;

  /// Ex.: `001/003`.
  String numeroParcela;

  @Property(type: PropertyType.dateUtc)
  DateTime dataEmissao;

  @Property(type: PropertyType.dateUtc)
  DateTime dataVencimento;

  double valorParcela;

  /// Um de [ContaPagarStatus].
  String status;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataPagamento;

  double? valorPago;

  /// Fornecedor / emitente (persistência: [FornecedorNfe]).
  final fornecedor = ToOne<FornecedorNfe>();
}
