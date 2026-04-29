import 'package:objectbox/objectbox.dart';

import 'cliente.dart';
import 'item_venda.dart';
import 'vendedor.dart';

@Entity()
class Venda {
  Venda({
    this.id = 0,
    DateTime? data,
    this.total = 0,
    this.custoTotal = 0,
    this.lucroTotal = 0,
    this.status = 'orcamento',
    this.numeroOrcamento = 0,
    this.formaPagamento = 'dinheiro',
    this.quantidadeParcelas = 1,
    this.tipoEntrega = 'retirada',
    this.valorFrete = 0,
    this.enderecoEntrega = '',
    this.observacaoEntrega = '',
    this.statusEntrega = 'nao_aplicavel',
    this.entregaPendente = false,
    this.cancelada = false,
  }) : data = data ?? DateTime.now();

  @Id()
  int id;

  @Property(type: PropertyType.dateUtc)
  DateTime data;
  double total;
  double custoTotal;
  double lucroTotal;
  String status;
  int numeroOrcamento;
  String formaPagamento;
  int quantidadeParcelas;
  String tipoEntrega;
  double valorFrete;
  String enderecoEntrega;
  String observacaoEntrega;
  String statusEntrega;
  bool entregaPendente;
  bool cancelada;

  final cliente = ToOne<Cliente>();
  final vendedor = ToOne<Vendedor>();

  @Backlink('venda')
  final itens = ToMany<ItemVenda>();
}
