import 'package:objectbox/objectbox.dart';

import 'cliente.dart';

/// Baixa de fiado (pagamento do cliente apos a venda).
@Entity()
class RecebimentoFiado {
  RecebimentoFiado({
    this.id = 0,
    this.valorTotal = 0,
    this.formaPagamento = 'dinheiro',
    this.observacao = '',
    this.alocacoesJson = '',
    DateTime? data,
    DateTime? criadoEm,
  })  : data = data ?? DateTime.now(),
        criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  double valorTotal;

  /// dinheiro | pix | cartao_credito | cartao_debito | transferencia
  String formaPagamento;

  String observacao;

  /// JSON: [{ "tituloId": int, "valor": double }]
  String alocacoesJson;

  @Property(type: PropertyType.dateUtc)
  DateTime data;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  final cliente = ToOne<Cliente>();
}
