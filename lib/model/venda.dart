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
    this.planoFiadoJson = '',
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
    this.carretoReservaAteSaida = false,
    this.entregaPendente = false,
    this.cancelada = false,
    this.motivoCancelamento = '',
    this.canceladaPor = '',
    this.canceladaEm,
    this.vendaOrigemFreteRetiradaId = 0,
    this.idOrcamentoFreteRetiradaAberto = 0,
    this.grupoEntregaFreteId = 0,
    this.ordemEntrega = 0,
    this.caminhaoEntrega = '',
    this.complementoEntregaJson = '',
    this.nfceChaveAcesso = '',
    this.nfceNumero = '',
    this.nfceSerie = '',
    this.nfceProtocolo = '',
    this.nfceUrlDanfe = '',
    this.nfceEmitidaEm,
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

  /// JSON lista [PlanoFiadoParcela]; plano de quitação definido no PDV.
  String planoFiadoJson;

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

  /// Carreto com estoque reservado na finalizacao; baixa fisica ao marcar [cargaSaiu].
  /// `false` em vendas antigas (baixa no caixa) e em migracoes retirada futura > carreto.
  bool carretoReservaAteSaida;

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

  /// Sequencia de parada no mesmo carro (1 = primeira entrega). 0 fora de grupo.
  int ordemEntrega;

  /// Legado (nao usado na UI). Expedicao identifica o veiculo pelo [motoristaEntrega].
  String caminhaoEntrega;

  /// JSON: lista de itens em falta na ida (`ComplementoEntregaCodec`).
  /// Usado com [statusEntrega] `entregue_complemento_pendente` ou pendencia em aberto.
  String complementoEntregaJson;

  /// Chave de acesso da NFC-e emitida para esta venda (apos pagamento no caixa).
  String nfceChaveAcesso;
  String nfceNumero;
  String nfceSerie;
  String nfceProtocolo;
  /// URL do PDF DANFE retornada pela API fiscal.
  String nfceUrlDanfe;
  @Property(type: PropertyType.dateUtc)
  DateTime? nfceEmitidaEm;

  final cliente = ToOne<Cliente>();
  final vendedor = ToOne<Vendedor>();

  @Backlink('venda')
  final itens = ToMany<ItemVenda>();

  @Backlink('venda')
  final historicoEntrega = ToMany<HistoricoEntrega>();

  /// Soma dos subtotais das linhas (precos nas linhas do pedido).
  double get somaSubtotalItens =>
      itens.fold<double>(0, (s, ItemVenda i) => s + i.subtotal);

  /// NFC-e ja autorizada e registrada nesta venda.
  bool get nfceEmitida =>
      nfceChaveAcesso.trim().isNotEmpty || nfceUrlDanfe.trim().isNotEmpty;

  /// Desconto aplicado sobre o bruto (itens + frete) ate chegar em [total], quando
  /// [total] foi reduzido sem alterar [precoUnitario] nas linhas (ex.: PDV e caixa).
  double get descontoImplicitoTotal {
    final bruto = somaSubtotalItens + valorFrete;
    final d = bruto - total;
    if (d <= 0.009) {
      return 0;
    }
    return d;
  }
}
