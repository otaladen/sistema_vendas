import 'package:objectbox/objectbox.dart';

import 'cliente.dart';
import 'registro_devolucao.dart';
import 'uso_vale_credito.dart';
import 'venda.dart';

/// Credito de devolucao que sobrevive ao cliente sair da loja.
///
/// Hibrido: o [codigo] impresso no comprovante vale por si (portador) e,
/// quando a venda tem cliente, o vale tambem fica amarrado ao cadastro para
/// ser recuperado sem o papel em maos.
@Entity()
class ValeCredito {
  ValeCredito({
    this.id = 0,
    this.codigo = '',
    this.valorOriginal = 0,
    this.valorUtilizado = 0,
    this.cancelado = false,
    this.motivoCancelamento = '',
    this.canceladoPor = '',
    this.emitidoPor = '',
    this.observacao = '',
    this.numeroVendaOrigem = 0,
    DateTime? dataEmissao,
    this.dataValidade,
    this.dataCancelamento,
  }) : dataEmissao = dataEmissao ?? DateTime.now();

  @Id(assignable: true)
  int id;

  /// Chave que o balconista digita no caixa, sem prefixo nem hifens.
  /// Unicidade garantida na emissao (ver ValeCreditoRepository.emitir).
  @Index()
  String codigo;

  double valorOriginal;

  /// Soma dos resgates ja feitos; o saldo e a diferenca para [valorOriginal].
  double valorUtilizado;

  bool cancelado;
  String motivoCancelamento;
  String canceladoPor;

  String emitidoPor;
  String observacao;

  /// Numero do orcamento que originou o vale, para o cliente conferir.
  int numeroVendaOrigem;

  @Property(type: PropertyType.dateUtc)
  DateTime dataEmissao;

  /// Nulo quando o vale nao vence.
  @Property(type: PropertyType.dateUtc)
  DateTime? dataValidade;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataCancelamento;

  /// Vazio quando a venda nao tinha cliente: ai o vale so vale pelo codigo.
  final cliente = ToOne<Cliente>();

  final vendaOrigem = ToOne<Venda>();

  final registroDevolucao = ToOne<RegistroDevolucao>();

  @Backlink('vale')
  final usos = ToMany<UsoValeCredito>();
}
