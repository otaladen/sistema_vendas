import 'package:objectbox/objectbox.dart';

import 'cliente.dart';
import 'historico_entrega.dart';
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
    this.pagamentosJson = '',
    this.tipoEntrega = 'retirada',
    this.valorFrete = 0,
    this.enderecoEntrega = '',
    this.observacaoEntrega = '',
    this.motoristaEntrega = '',
    this.statusEntrega = 'nao_aplicavel',
    this.prioridadeEntrega = 'normal',
    this.janelaEntrega = 'nao_definida',
    this.dataEntregaMarcada,
    this.cargaSeparada = false,
    this.cargaCarregada = false,
    this.cargaSaiu = false,
    this.entregaPendente = false,
    this.cancelada = false,
    this.motivoCancelamento = '',
    this.canceladaPor = '',
    this.canceladaEm,
    this.vendaOrigemFreteRetiradaId = 0,
    this.idOrcamentoFreteRetiradaAberto = 0,
    this.grupoEntregaFreteId = 0,
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
  /// JSON lista [PagamentoOrcamentoLinha]; vazio se pagamento unico (legado).
  String pagamentosJson;
  String tipoEntrega;
  double valorFrete;
  String enderecoEntrega;
  String observacaoEntrega;
  String motoristaEntrega;
  String statusEntrega;
  String prioridadeEntrega;
  String janelaEntrega;
  @Property(type: PropertyType.dateUtc)
  DateTime? dataEntregaMarcada;
  bool cargaSeparada;
  bool cargaCarregada;
  bool cargaSaiu;
  bool entregaPendente;
  bool cancelada;
  String motivoCancelamento;
  String canceladaPor;
  @Property(type: PropertyType.dateUtc)
  DateTime? canceladaEm;

  /// Orcamento filho (somente frete) pendente no caixa; zerado apos pagamento.
  int idOrcamentoFreteRetiradaAberto;

  /// Na venda filha: ID da venda mae (retirada futura) que contratou o carreto.
  int vendaOrigemFreteRetiradaId;

  /// ID comum do grupo logistico na aba Entregas (mesmo valor = mesmo carro).
  /// Define-se manualmente ao agrupar notas; 0 = sem grupo.
  int grupoEntregaFreteId;

  final cliente = ToOne<Cliente>();
  final vendedor = ToOne<Vendedor>();

  @Backlink('venda')
  final itens = ToMany<ItemVenda>();

  @Backlink('venda')
  final historicoEntrega = ToMany<HistoricoEntrega>();
}
