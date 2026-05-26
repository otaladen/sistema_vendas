import 'package:objectbox/objectbox.dart';

import 'linha_devolucao_entrada.dart';
import 'linha_troca_saida.dart';
import 'venda.dart';

@Entity()
class RegistroDevolucao {
  RegistroDevolucao({
    this.id = 0,
    this.tipo = 'devolucao',
    this.motivo = '',
    this.observacaoFinanceira = '',
    this.registradoPor = '',
    DateTime? data,
  }) : data = data ?? DateTime.now();

  @Id(assignable: true)
  int id;

  /// `devolucao` ou `troca`.
  String tipo;

  String motivo;

  /// Ex.: valor devolvido em dinheiro, complemento pago, vale-troca.
  String observacaoFinanceira;

  String registradoPor;

  @Property(type: PropertyType.dateUtc)
  DateTime data;

  final vendaOrigem = ToOne<Venda>();

  @Backlink('registro')
  final linhasEntrada = ToMany<LinhaDevolucaoEntrada>();

  @Backlink('registro')
  final linhasSaidaTroca = ToMany<LinhaTrocaSaida>();
}
